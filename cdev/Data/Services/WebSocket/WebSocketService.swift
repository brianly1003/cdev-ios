import Foundation
import Network

/// WebSocket service for real-time communication with agent
/// Enhanced with mobile-optimized stability features per WEBSOCKET-STABILITY.md
final class WebSocketService: NSObject, WebSocketServiceProtocol {
    // MARK: - Properties

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var connectionInfo: ConnectionInfo?
    private var reconnectAttempts = 0
    @Atomic private var isReconnecting = false
    private let reconnectLock = NSLock()

    @Atomic private var _connectionState: ConnectionState = .disconnected
    var connectionState: ConnectionState {
        _connectionState
    }

    var isConnected: Bool {
        connectionState.isConnected
    }

    // MARK: - Stability Properties

    /// Last received message timestamp for connection health monitoring
    /// Updated on ANY received message (not just heartbeats)
    private var lastActivityTime: Date?

    /// Network path monitor for detecting network changes
    private var networkMonitor: NWPathMonitor?
    private var networkMonitorQueue: DispatchQueue?
    private var isNetworkAvailable = true

    /// DispatchSource timers for reliable timing (not affected by run loop)
    private var pingTimer: DispatchSourceTimer?
    private var heartbeatCheckTimer: DispatchSourceTimer?
    private var failedRetryTimer: DispatchSourceTimer?  // Periodic retry when in failed state
    private var tokenExpiryWarningTimer: DispatchSourceTimer?  // Token expiry warning
    private let timerQueue = DispatchQueue(label: "com.cdev.websocket.timers", qos: .utility)

    /// Callback for token expiry warning (called ~5 minutes before token expires)
    /// Parameter: time remaining in seconds
    var onTokenExpiryWarning: ((TimeInterval) -> Void)?

    /// Track if we should attempt reconnection
    private var shouldAutoReconnect = true

    /// Flag to indicate external retry loop is in progress (e.g., WorkspaceManagerViewModel)
    /// When true, connect() won't update to .failed state on failure
    @Atomic var isExternalRetryInProgress = false

    /// Cached JSON decoder/encoder to avoid repeated allocations
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    // MARK: - JSON-RPC Support

    /// JSON-RPC client for request/response correlation
    private var rpcClient: JSONRPCClient?

    /// Flag to enable JSON-RPC mode (set after successful initialize handshake)
    @Atomic private var useJSONRPC = false

    /// Client ID assigned by server during initialize (for multi-device awareness)
    @Atomic private var _clientId: String?

    /// Client ID assigned by server (nil if not connected or not assigned)
    var clientId: String? { _clientId }

    /// Check if a viewer/client ID matches this client (for multi-device awareness)
    /// - Parameter id: The client ID to check
    /// - Returns: true if the ID matches this client's ID
    func isMe(_ id: String?) -> Bool {
        guard let myId = _clientId, let checkId = id else { return false }
        return myId == checkId
    }

    /// Track pending request IDs to method names for response correlation (with timestamp for cleanup)
    private var pendingRequestMethods: [String: (method: String, timestamp: Date)] = [:]
    private let pendingRequestMethodsLock = NSLock()
    private static let pendingRequestTimeout: TimeInterval = 60  // Clean up after 60 seconds

    // MARK: - Session Watching State

    /// Currently watched session ID (publicly accessible)
    @Atomic private var _watchedSessionId: String?
    var watchedSessionId: String? { _watchedSessionId }

    /// Runtime of the currently watched session (claude/codex)
    @Atomic private var _watchedRuntime: AgentRuntime?

    // MARK: - Pending Trust Folder Permission

    /// Stores pending trust_folder permission that arrives before Dashboard is ready
    /// Dashboard should check this on init and clear after handling
    private var _pendingTrustFolderEvent: AgentEvent?
    private let pendingTrustFolderLock = NSLock()

    /// Get and clear pending trust_folder permission (atomic operation)
    /// Returns the event if one was pending, nil otherwise
    func consumePendingTrustFolderPermission() -> AgentEvent? {
        pendingTrustFolderLock.withLock {
            let event = _pendingTrustFolderEvent
            _pendingTrustFolderEvent = nil
            AppLogger.log("[WebSocket] consumePendingTrustFolderPermission - found=\(event != nil)")
            return event
        }
    }

    /// Store a pending trust_folder permission event
    func setPendingTrustFolderPermission(_ event: AgentEvent) {
        pendingTrustFolderLock.withLock {
            _pendingTrustFolderEvent = event
            AppLogger.log("[WebSocket] Stored pending trust_folder permission for Dashboard")
        }
    }

    /// Check if there's a pending trust_folder permission (without consuming)
    var hasPendingTrustFolderPermission: Bool {
        pendingTrustFolderLock.withLock {
            _pendingTrustFolderEvent != nil
        }
    }

    // MARK: - Streams (Broadcast Pattern)

    /// Thread-safe storage for multiple state stream subscribers
    private var stateStreamContinuations: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]
    private let continuationsLock = NSLock()

    /// Creates a NEW stream for each subscriber (broadcast pattern)
    /// Each subscriber receives ALL state updates independently
    var connectionStateStream: AsyncStream<ConnectionState> {
        let id = UUID()
        return AsyncStream { continuation in
            // Register this continuation
            self.continuationsLock.withLock {
                self.stateStreamContinuations[id] = continuation
            }

            // Yield current state immediately to new subscriber
            continuation.yield(self.connectionState)

            // Clean up when stream terminates
            continuation.onTermination = { [weak self] _ in
                self?.continuationsLock.withLock {
                    _ = self?.stateStreamContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Thread-safe storage for multiple event stream subscribers
    private var eventStreamContinuations: [UUID: AsyncStream<AgentEvent>.Continuation] = [:]
    private let eventContinuationsLock = NSLock()

    /// Creates a NEW stream for each subscriber (broadcast pattern)
    var eventStream: AsyncStream<AgentEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            // Register this continuation
            self.eventContinuationsLock.withLock {
                self.eventStreamContinuations[id] = continuation
            }

            // Clean up when stream terminates
            continuation.onTermination = { [weak self] _ in
                self?.eventContinuationsLock.withLock {
                    _ = self?.eventStreamContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - Init

    override init() {
        super.init()
        setupNetworkMonitor()
    }

    deinit {
        cleanupAllResources()
    }

    // MARK: - Resource Cleanup

    /// Complete cleanup of all resources to prevent memory leaks
    private func cleanupAllResources() {
        // Stop all timers
        stopTimers()

        // Stop network monitoring
        stopNetworkMonitor()

        // Cancel pending RPC requests
        if let client = rpcClient {
            Task {
                await client.cancelAllPending()
            }
        }
        rpcClient = nil
        useJSONRPC = false
        _clientId = nil
        RuntimeCapabilityRegistryStore.shared.resetToDefaults()

        // Cancel WebSocket and session
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil

        // Finish all stream continuations to release subscribers
        finishAllContinuations()

        // Clear state
        connectionInfo = nil
        shouldAutoReconnect = false
        isReconnecting = false
    }

    /// Finish all async stream continuations to allow subscribers to be released
    private func finishAllContinuations() {
        // Copy continuations out of locks first to avoid holding lock during finish()
        // finish() can trigger code that might try to acquire the same lock

        // State stream continuations
        let stateContinuations = continuationsLock.withLock {
            let copy = Array(stateStreamContinuations.values)
            stateStreamContinuations.removeAll()
            return copy
        }
        AppLogger.webSocket("Finishing \(stateContinuations.count) state continuations")
        for continuation in stateContinuations {
            continuation.finish()
        }

        // Event stream continuations
        let eventContinuations = eventContinuationsLock.withLock {
            let copy = Array(eventStreamContinuations.values)
            eventStreamContinuations.removeAll()
            return copy
        }
        AppLogger.webSocket("Finishing \(eventContinuations.count) event continuations")
        for continuation in eventContinuations {
            continuation.finish()
        }
    }

    // MARK: - Network Monitoring

    /// Setup NWPathMonitor to detect network changes (WiFi ↔ Cellular transitions)
    private func setupNetworkMonitor() {
        networkMonitorQueue = DispatchQueue(label: "com.cdev.networkmonitor", qos: .utility)
        networkMonitor = NWPathMonitor()

        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let wasAvailable = self.isNetworkAvailable
            self.isNetworkAvailable = path.status == .satisfied

            AppLogger.webSocket("Network status: \(path.status == .satisfied ? "available" : "unavailable")")

            // If network was lost and is now available, and we were connected, reconnect
            if !wasAvailable && self.isNetworkAvailable {
                AppLogger.webSocket("Network restored - checking connection", type: .info)
                self.handleNetworkRestored()
            }

            // If network was lost while connected, prepare for reconnection
            if wasAvailable && !self.isNetworkAvailable {
                AppLogger.webSocket("Network lost", type: .warning)
            }
        }

        networkMonitor?.start(queue: networkMonitorQueue!)
    }

    private func stopNetworkMonitor() {
        networkMonitor?.cancel()
        networkMonitor = nil
        networkMonitorQueue = nil
    }

    /// Handle network restoration - attempt reconnection if needed
    private func handleNetworkRestored() {
        Task { @MainActor in
            switch self.connectionState {
            case .failed, .disconnected:
                // Attempt to reconnect if we have connection info
                if self.connectionInfo != nil && self.shouldAutoReconnect {
                    AppLogger.webSocket("Attempting reconnection after network restore")
                    try? await self.reconnect()
                }
            case .connected:
                // Already connected, verify with ping
                let success = try? await self.ping()
                if success != true {
                    AppLogger.webSocket("Connection stale after network change - reconnecting")
                    try? await self.reconnect()
                }
            default:
                break
            }
        }
    }

    // MARK: - Timer Management

    private func startTimers() {
        startPingTimer()
        startHeartbeatCheckTimer()
    }

    private func stopTimers() {
        pingTimer?.cancel()
        pingTimer = nil
        heartbeatCheckTimer?.cancel()
        heartbeatCheckTimer = nil
        stopFailedRetryTimer()
        stopTokenExpiryWarningTimer()
    }

    /// Stop the token expiry warning timer
    private func stopTokenExpiryWarningTimer() {
        tokenExpiryWarningTimer?.cancel()
        tokenExpiryWarningTimer = nil
    }

    /// Schedule a warning before token expires
    /// Warns 5 minutes before expiry (or immediately if less than 5 minutes remaining)
    private func scheduleTokenExpiryWarning() {
        stopTokenExpiryWarningTimer()

        guard let connectionInfo = connectionInfo,
              let expiresAt = connectionInfo.tokenExpiresAt else {
            return
        }

        let warningTime: TimeInterval = 5 * 60  // Warn 5 minutes before expiry
        let timeUntilExpiry = expiresAt.timeIntervalSinceNow

        // If already expired or about to expire, warn immediately
        if timeUntilExpiry <= warningTime {
            AppLogger.webSocket("Token expires soon (in \(Int(timeUntilExpiry))s) - warning immediately")
            onTokenExpiryWarning?(timeUntilExpiry > 0 ? timeUntilExpiry : 0)
            return
        }

        // Schedule warning for 5 minutes before expiry
        let delayUntilWarning = timeUntilExpiry - warningTime
        AppLogger.webSocket("Token expires in \(Int(timeUntilExpiry))s - scheduling warning in \(Int(delayUntilWarning))s")

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + delayUntilWarning)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.stopTokenExpiryWarningTimer()

            // Calculate remaining time (should be ~5 minutes)
            let remaining = expiresAt.timeIntervalSinceNow
            AppLogger.webSocket("Token expiry warning - \(Int(remaining))s remaining", type: .warning)
            self.onTokenExpiryWarning?(remaining > 0 ? remaining : 0)
        }
        timer.resume()
        tokenExpiryWarningTimer = timer
    }

    /// Stop the failed retry timer
    private func stopFailedRetryTimer() {
        failedRetryTimer?.cancel()
        failedRetryTimer = nil
    }

    /// Schedule a single retry after cooldown period
    /// Called when max reconnect attempts reached - waits then tries again
    private func scheduleFailedRetry() {
        stopFailedRetryTimer()

        guard connectionInfo != nil, shouldAutoReconnect else { return }

        // Wait 60 seconds before trying again (gives server time to restart)
        let cooldownInterval: TimeInterval = 60

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + cooldownInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.handleFailedRetryTick()
            }
        }
        timer.resume()
        failedRetryTimer = timer
        AppLogger.webSocket("Scheduled retry in \(Int(cooldownInterval))s")
    }

    /// Handle failed retry - reset counter and try reconnecting
    private func handleFailedRetryTick() async {
        stopFailedRetryTimer()

        guard case .failed = connectionState,
              connectionInfo != nil,
              shouldAutoReconnect,
              isNetworkAvailable else {
            return
        }

        AppLogger.webSocket("Cooldown complete - attempting reconnection")

        // Reset counter to allow fresh 10 attempts
        reconnectAttempts = 0

        do {
            try await reconnect()
        } catch {
            // reconnect() will call scheduleFailedRetry() again if max attempts reached
            AppLogger.webSocket("Retry cycle failed, will retry after cooldown", type: .warning)
        }
    }

    /// Start ping timer using DispatchSourceTimer for reliability
    private func startPingTimer() {
        pingTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(
            deadline: .now() + Constants.Network.pingInterval,
            repeating: Constants.Network.pingInterval
        )
        timer.setEventHandler { [weak self] in
            Task {
                await self?.handlePingTick()
            }
        }
        timer.resume()
        pingTimer = timer
    }

    /// Handle ping timer tick - send ping and handle failures
    private func handlePingTick() async {
        guard isConnected else { return }

        let success = try? await ping()
        if success != true {
            AppLogger.webSocket("Ping failed - connection may be stale", type: .warning)

            // Trigger reconnection on ping failure
            await MainActor.run {
                self.triggerReconnection(reason: "Ping failed")
            }
        }
    }

    /// Start activity check timer
    private func startHeartbeatCheckTimer() {
        heartbeatCheckTimer?.cancel()

        // Initialize last activity time on connection
        lastActivityTime = Date()

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        // Check every 5 seconds if connection is stale (no messages received)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            Task {
                await self?.checkActivity()
            }
        }
        timer.resume()
        heartbeatCheckTimer = timer
    }

    /// Check if connection is stale (no messages received) and trigger reconnection
    private func checkActivity() async {
        guard isConnected else { return }

        guard let lastActivity = lastActivityTime else { return }

        let elapsed = Date().timeIntervalSince(lastActivity)

        if elapsed > Constants.Network.heartbeatTimeout {
            AppLogger.webSocket("Connection stale - no messages for \(Int(elapsed))s", type: .warning)

            await MainActor.run {
                self.triggerReconnection(reason: "No activity timeout")
            }
        }
    }

    /// Update last activity timestamp (called on any received message)
    func updateLastActivity() {
        lastActivityTime = Date()
    }

    // MARK: - Connection

    func connect(to connectionInfo: ConnectionInfo) async throws {
        // Guard against duplicate connection attempts (race condition prevention)
        if isConnected {
            AppLogger.webSocket("Already connected, skipping duplicate connect request")
            return
        }

        self.connectionInfo = connectionInfo
        // Only reset reconnect attempts for fresh connections, not during reconnection loop
        if !isReconnecting {
            reconnectAttempts = 0
            // Only update to .connecting for fresh connections
            // During reconnection, keep the .reconnecting(attempt:) state
            updateState(.connecting)
        }
        shouldAutoReconnect = true

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.Network.connectionTimeout
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        guard let session = session else {
            updateState(.failed(reason: "Failed to create session"))
            throw AppError.connectionFailed(underlying: nil)
        }

        let wsURL = connectionInfo.webSocketURL
        var request = URLRequest(url: wsURL)
        request.timeoutInterval = Constants.Network.connectionTimeout
        if let token = connectionInfo.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            AppLogger.webSocket("Auth token set on WebSocket request")
        } else {
            AppLogger.webSocket("WARNING: No auth token in connection info!")
        }

        AppLogger.webSocket("Connecting to: \(wsURL.absoluteString)")
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()

        // Wait for connection with timeout
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(Constants.Network.connectionTimeout * 1_000_000_000))
                    throw AppError.connectionTimeout
                }

                // Connection task
                group.addTask {
                    try await self.waitForConnection()
                }

                // Wait for first to complete (connection success or timeout)
                try await group.next()
                group.cancelAll()
            }
        } catch {
            // Clean up on failure
            webSocket?.cancel(with: .abnormalClosure, reason: nil)
            webSocket = nil
            self.session?.invalidateAndCancel()
            self.session = nil

            let errorMessage = Self.friendlyErrorMessage(from: error)
            // Only update to failed state if NOT in any retry loop (internal or external)
            // During retry loops, the caller handles state transitions to avoid flickering
            if !isReconnecting && !isExternalRetryInProgress {
                updateState(.failed(reason: errorMessage))
            }
            AppLogger.webSocket("Connection failed: \(errorMessage)", type: .error)
            throw error
        }

        // Start stability timers on successful connection
        startTimers()

        // JSON-RPC initialization is REQUIRED
        RuntimeCapabilityRegistryStore.shared.resetToDefaults()
        let supported = await tryJSONRPCInitialize()
        if !supported {
            // Clean up on JSON-RPC init failure
            webSocket?.cancel(with: .abnormalClosure, reason: nil)
            webSocket = nil
            self.session?.invalidateAndCancel()
            self.session = nil
            stopTimers()

            let errorMessage = "Server does not support JSON-RPC 2.0"
            // Only update to failed state if NOT in any retry loop
            if !isReconnecting && !isExternalRetryInProgress {
                updateState(.failed(reason: errorMessage))
            }
            throw AppError.connectionFailed(underlying: NSError(
                domain: "WebSocketService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            ))
        }

        // Mark connection as fully ready only after JSON-RPC initialize succeeds.
        updateState(.connected(connectionInfo))
        AppLogger.webSocket("JSON-RPC mode enabled")

        // Schedule token expiry warning if token has an expiry time
        scheduleTokenExpiryWarning()
    }

    private func waitForConnection() async throws {
        guard let currentSocket = webSocket else {
            throw AppError.connectionFailed(underlying: nil)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Thread-safe wrapper to ensure continuation is only resumed once
            // This prevents crashes during reconnection when callback may fire multiple times
            final class ThrowingContinuationBox: @unchecked Sendable {
                private var continuation: CheckedContinuation<Void, Error>?
                private let lock = NSLock()

                init(_ c: CheckedContinuation<Void, Error>) { continuation = c }

                func resume() {
                    let c = lock.withLock {
                        let temp = continuation
                        continuation = nil
                        return temp
                    }
                    c?.resume()
                }

                func resume(throwing error: Error) {
                    let c = lock.withLock {
                        let temp = continuation
                        continuation = nil
                        return temp
                    }
                    c?.resume(throwing: error)
                }
            }

            let box = ThrowingContinuationBox(continuation)

            // Start receiving messages
            self.receiveMessage()

            // Check connection with a ping
            currentSocket.sendPing { [weak self] error in
                // Verify socket is still the current one
                // If socket changed, just return silently - the new connection will handle things
                guard self?.webSocket === currentSocket else {
                    AppLogger.webSocket("Ping callback from old socket - ignoring (new connection in progress)")
                    // Don't throw error - just complete without error
                    // The new connection will set up its own state
                    box.resume()
                    return
                }

                if let error = error {
                    box.resume(throwing: AppError.connectionFailed(underlying: error))
                } else {
                    box.resume()
                }
            }
        }
    }

    private static func friendlyErrorMessage(from error: Error) -> String {
        if let appError = error as? AppError {
            switch appError {
            case .connectionTimeout:
                return "Connection timed out"
            case .connectionFailed:
                return "Could not connect to server"
            default:
                return appError.localizedDescription
            }
        }

        let nsError = error as NSError
        switch nsError.code {
        case -1004: // kCFURLErrorCannotConnectToHost
            return "Server not reachable"
        case -1001: // kCFURLErrorTimedOut
            return "Connection timed out"
        case -1005: // kCFURLErrorNetworkConnectionLost / Connection interrupted
            return "Connection interrupted"
        case -1009: // kCFURLErrorNotConnectedToInternet
            return "No internet connection"
        case -1018: // kCFURLErrorInternationalRoamingOff
            return "Roaming disabled"
        case -1020: // kCFURLErrorDataNotAllowed
            return "Data not allowed"
        case 53: // ECONNABORTED - Software caused connection abort
            return "Connection aborted"
        case 54: // ECONNRESET - Connection reset by peer
            return "Connection reset"
        case 57: // ENOTCONN - Socket is not connected
            return "Socket disconnected"
        case 61: // ECONNREFUSED - Connection refused
            return "Connection refused - is the server running?"
        default:
            return nsError.localizedDescription
        }
    }

    /// Check if error is a transient connection issue that should trigger silent reconnection
    private static func isTransientConnectionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let transientCodes = [
            -1005, // Connection interrupted
            -1001, // Timed out
            53,    // Connection aborted
            54,    // Connection reset
            57,    // Socket disconnected
        ]
        return transientCodes.contains(nsError.code)
    }

    func disconnect() {
        AppLogger.webSocket("Disconnecting - start")
        shouldAutoReconnect = false
        stopTimers()
        stopNetworkMonitor()
        AppLogger.webSocket("Disconnecting - timers stopped")

        // Clear watched session state (both session and workspace IDs)
        _watchedSessionId = nil
        _watchedWorkspaceId = nil

        // Clear pending request tracking to prevent memory buildup
        AppLogger.webSocket("Disconnecting - clearing pending requests")
        pendingRequestMethodsLock.withLock {
            pendingRequestMethods.removeAll()
        }
        AppLogger.webSocket("Disconnecting - pending requests cleared")

        // Cancel pending RPC requests and clear client
        if let client = rpcClient {
            Task {
                await client.cancelAllPending()
            }
        }
        rpcClient = nil
        useJSONRPC = false
        _clientId = nil
        RuntimeCapabilityRegistryStore.shared.resetToDefaults()

        // Clear connection info to prevent reconnection to old server
        connectionInfo = nil

        AppLogger.webSocket("Disconnecting - cancelling websocket")
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        AppLogger.webSocket("Disconnecting - websocket cancelled")

        // Finish all stream continuations to release subscribers
        AppLogger.webSocket("Disconnecting - finishing continuations")
        finishAllContinuations()
        AppLogger.webSocket("Disconnecting - continuations finished")

        AppLogger.webSocket("Disconnecting - updating state")
        updateState(.disconnected)
        AppLogger.webSocket("Disconnecting - complete")
    }

    /// Trigger reconnection from stability checks (ping/heartbeat failures)
    private func triggerReconnection(reason: String) {
        guard !isReconnecting else { return }

        switch connectionState {
        case .connected, .failed:
            AppLogger.webSocket("Triggering reconnection: \(reason)")
            Task {
                try? await reconnect()
            }
        default:
            break
        }
    }

    func reconnect() async throws {
        // Atomic check-and-set to prevent race conditions
        // Also capture connectionInfo to use after the lock
        let savedConnectionInfo: ConnectionInfo? = reconnectLock.withLock {
            guard let info = connectionInfo,
                  !isReconnecting,
                  shouldAutoReconnect else { return nil }
            isReconnecting = true
            return info
        }
        guard let connectionInfo = savedConnectionInfo else { return }

        defer {
            reconnectLock.withLock { isReconnecting = false }
        }

        // Loop through all attempts (fixes bug where only 1 attempt was made per call)
        while reconnectAttempts < Constants.Network.maxReconnectAttempts && shouldAutoReconnect {
            reconnectAttempts += 1
            updateState(.reconnecting(attempt: reconnectAttempts))

            // Clean up old connection first
            stopTimers()
            webSocket?.cancel(with: .goingAway, reason: nil)
            webSocket = nil
            session?.invalidateAndCancel()
            session = nil

            // CRITICAL: Clear watched session state on reconnect
            // This ensures watch can be re-established after server restart
            _watchedSessionId = nil
            _watchedWorkspaceId = nil
            AppLogger.webSocket("Cleared watch state during reconnection cleanup")

            // Exponential backoff with max cap
            // Attempts: 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s, 30s, 30s = ~127s total
            let delay = min(
                Constants.Network.reconnectDelay * pow(2, Double(reconnectAttempts - 1)),
                Constants.Network.maxReconnectDelay
            )
            AppLogger.webSocket("Reconnect attempt \(reconnectAttempts)/\(Constants.Network.maxReconnectAttempts) in \(String(format: "%.1f", delay))s")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            // Check if we should stop (app went to background, user disconnected)
            guard shouldAutoReconnect else {
                AppLogger.webSocket("Reconnection cancelled")
                return
            }

            do {
                // Refresh token from TokenManager before each reconnection attempt
                // This ensures we have a valid token even if the original connectionInfo didn't have one
                var connectionInfoWithToken = connectionInfo
                if let host = connectionInfo.webSocketURL.host,
                   let storedHost = TokenManager.shared.getStoredHost(),
                   storedHost == host {
                    if let freshToken = await TokenManager.shared.getValidAccessToken() {
                        connectionInfoWithToken = ConnectionInfo(
                            webSocketURL: connectionInfo.webSocketURL,
                            httpURL: connectionInfo.httpURL,
                            sessionId: connectionInfo.sessionId,
                            repoName: connectionInfo.repoName,
                            token: freshToken
                        )
                        AppLogger.webSocket("Refreshed token for reconnection attempt")
                    } else {
                        AppLogger.webSocket("WARNING: No valid token available for reconnection", type: .warning)
                    }
                }

                try await connect(to: connectionInfoWithToken)
                reconnectAttempts = 0
                AppLogger.webSocket("Reconnection successful", type: .success)
                return  // Success - exit loop
            } catch {
                AppLogger.webSocket("Attempt \(reconnectAttempts) failed: \(Self.friendlyErrorMessage(from: error))", type: .warning)
                // Continue to next attempt
            }
        }

        // All attempts exhausted
        updateState(.failed(reason: "Max reconnect attempts reached"))
        scheduleFailedRetry()
        throw AppError.connectionFailed(underlying: nil)
    }

    func ping() async throws -> Bool {
        guard let currentSocket = webSocket else { return false }

        return await withCheckedContinuation { [weak self] continuation in
            // Thread-safe wrapper to ensure continuation is only resumed once
            // This prevents crashes during reconnection when callback may fire multiple times
            final class ContinuationBox: @unchecked Sendable {
                private var continuation: CheckedContinuation<Bool, Never>?
                private let lock = NSLock()

                init(_ c: CheckedContinuation<Bool, Never>) { continuation = c }

                func resume(returning value: Bool) {
                    let c = lock.withLock {
                        let temp = continuation
                        continuation = nil  // Clear to prevent reuse
                        return temp
                    }
                    c?.resume(returning: value)
                }
            }

            let box = ContinuationBox(continuation)

            currentSocket.sendPing { error in
                // Verify socket is still the current one before resuming
                guard self?.webSocket === currentSocket else {
                    // Socket changed, treat as failure but don't crash
                    box.resume(returning: false)
                    return
                }
                box.resume(returning: error == nil)
            }
        }
    }

    // MARK: - Send

    /// Send raw data (for JSON-RPC messages)
    func send(data: Data) async throws {
        guard let webSocket = webSocket else {
            throw AppError.webSocketDisconnected
        }

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw AppError.encodingFailed(underlying: NSError(domain: "WebSocket", code: -1))
        }

        // Extract method name and request ID for logging (single JSON parse)
        let (method, requestId) = extractJSONRPCMethodAndId(data: data)
        let displayMethod = method ?? "request"

        // Track request ID -> method for response correlation
        if let requestId = requestId, let method = method {
            pendingRequestMethodsLock.withLock {
                pendingRequestMethods[requestId] = (method: method, timestamp: Date())
                // Periodic cleanup of stale entries (only if dictionary is getting large)
                if pendingRequestMethods.count > 50 {
                    cleanupStaleRequests()
                }
            }
        }

        AppLogger.webSocket("Sending JSON-RPC \(displayMethod)")

        do {
            try await webSocket.send(.string(jsonString))

            // Log outgoing data to debug store
            Task { @MainActor in
                DebugLogStore.shared.logWebSocket(
                    direction: .outgoing,
                    title: "→ \(displayMethod)",
                    eventType: "jsonrpc_\(displayMethod.replacingOccurrences(of: "/", with: "_"))",
                    // payload: jsonString.count < 2000 ? jsonString : String(jsonString.prefix(2000)) + "..."
                    payload: jsonString  // Full payload for copy support
                )
            }
        } catch {
            AppLogger.webSocket("Send raw data failed: \(error)", type: .error)
            throw AppError.webSocketMessageFailed(underlying: error)
        }
    }

    // MARK: - JSON-RPC Support

    /// Get the JSON-RPC client (creates if needed)
    func getJSONRPCClient() -> JSONRPCClient {
        if let client = rpcClient {
            return client
        }
        let client = JSONRPCClient(webSocket: self, requestTimeout: 30.0)
        rpcClient = client
        return client
    }

    /// Check if JSON-RPC mode is enabled
    var isJSONRPCEnabled: Bool {
        useJSONRPC
    }

    /// Attempt JSON-RPC initialize handshake
    /// Returns true if server supports JSON-RPC, false otherwise
    func tryJSONRPCInitialize() async -> Bool {
        let client = getJSONRPCClient()

        do {
            let params = InitializeParams(
                clientInfo: .cdevIOS,
                capabilities: nil
            )

            let result: InitializeResult = try await client.request(
                method: JSONRPCMethod.initialize,
                params: params
            )

            // Success - server supports JSON-RPC
            useJSONRPC = true
            _clientId = result.clientId
            AppLogger.webSocket("JSON-RPC initialized: server=\(result.serverInfo?.name ?? "unknown") v\(result.serverInfo?.version ?? "?"), clientId=\(result.clientId ?? "none")")

            if let capabilities = result.capabilities {
                RuntimeCapabilityRegistryStore.shared.apply(
                    supportedAgentIDs: capabilities.declaredAgentIDs,
                    runtimeRegistry: capabilities.runtimeRegistry
                )

                if let agents = capabilities.agents {
                    AppLogger.webSocket("Available agents: \(agents.joined(separator: ", "))")
                }
                if let supportedAgents = capabilities.supportedAgents {
                    AppLogger.webSocket("Supported agents: \(supportedAgents.joined(separator: ", "))")
                }
                if let runtimeRegistry = capabilities.runtimeRegistry {
                    let runtimeIDs = runtimeRegistry.runtimes.map(\.id)
                    AppLogger.webSocket("Runtime registry \(runtimeRegistry.schemaVersion ?? "unknown"): \(runtimeIDs.joined(separator: ", "))")
                }
                if let features = capabilities.features {
                    AppLogger.webSocket("Features: \(features.joined(separator: ", "))")
                }
            } else {
                RuntimeCapabilityRegistryStore.shared.resetToDefaults()
            }

            // Send 'initialized' notification to confirm we've processed the response
            try? await client.notify(method: JSONRPCMethod.initialized, params: nil as EmptyParams?)

            return true
        } catch {
            // Server doesn't support JSON-RPC or error occurred
            // Fall back to legacy protocol
            AppLogger.webSocket("JSON-RPC initialize failed (using legacy protocol): \(error.localizedDescription)", type: .info)
            useJSONRPC = false
            RuntimeCapabilityRegistryStore.shared.resetToDefaults()
            return false
        }
    }

    // MARK: - Private

    private func updateState(_ state: ConnectionState) {
        _connectionState = state

        // Stop failed retry timer when leaving failed state (connecting/connected)
        if case .failed = state {
            // Keep timer running (managed by reconnect/scheduleFailedRetry)
        } else {
            stopFailedRetryTimer()
        }

        // Broadcast to ALL subscribers (copy to Array to avoid holding lock during yield)
        let continuations = continuationsLock.withLock {
            Array(stateStreamContinuations.values)
        }

        for continuation in continuations {
            continuation.yield(state)
        }

        AppLogger.webSocket("State: \(state.statusText)")

        // Log to debug store
        let level: DebugLogLevel = {
            switch state {
            case .connected: return .success
            case .failed: return .error
            case .disconnected: return .warning
            default: return .info
            }
        }()
        Task { @MainActor in
            DebugLogStore.shared.logWebSocket(
                direction: .status,
                title: state.statusText,
                level: level
            )
        }
    }

    private func receiveMessage() {
        // Capture the current webSocket to compare in callback
        guard let currentSocket = webSocket else { return }

        currentSocket.receive { [weak self] result in
            guard let self = self else { return }

            // Ignore callbacks from old/stale websocket tasks
            guard self.webSocket === currentSocket else {
                AppLogger.webSocket("Ignoring callback from stale WebSocket task")
                return
            }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessage() // Continue receiving

            case .failure(let error):
                // Double-check we're not in the middle of cleanup
                guard self.webSocket != nil, !self.isReconnecting else {
                    AppLogger.webSocket("Ignoring receive error during cleanup/reconnection")
                    return
                }
                AppLogger.webSocket("Receive error: \(error)", type: .error)
                self.handleDisconnect(error: error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        // Any received message proves connection is alive - update last activity time
        updateLastActivity()

        switch message {
        case .string(let text):
            parseEvent(from: text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseEvent(from: text)
            }
        @unknown default:
            break
        }
    }

    private func parseEvent(from text: String) {
        // Handle newline-delimited JSON (NDJSON) - server may send multiple events
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }

            // Check if this is a JSON-RPC message
            let messageType = JSONRPCMessageType.detect(from: data)
            if messageType != .unknown {
                handleJSONRPCMessage(data: data, messageType: messageType, rawLine: line)
                continue
            }

            // Legacy event format
            do {
                let event = try jsonDecoder.decode(AgentEvent.self, from: data)

                // Handle heartbeat events - don't forward to event stream
                if event.type == .heartbeat {
                    AppLogger.webSocket("Heartbeat received")
                    // Log heartbeat to debug store but don't clutter main log
                    Task { @MainActor in
                        DebugLogStore.shared.logWebSocket(
                            direction: .incoming,
                            title: "heartbeat",
                            eventType: "heartbeat",
                            payload: nil
                        )
                    }
                    continue
                }

                // Handle deprecation warnings - log but don't forward to event stream
                if event.type == .deprecationWarning {
                    if case .deprecationWarning(let payload) = event.payload {
                        AppLogger.webSocket("⚠️ DEPRECATION: \(payload.message ?? "Unknown")", type: .warning)
                        if let migration = payload.migration {
                            for (oldCmd, newCmd) in migration {
                                AppLogger.webSocket("  Migration: \(oldCmd) → \(newCmd)", type: .info)
                            }
                        }
                    }
                    continue
                }

                // Store trust_folder permission for Dashboard to pick up
                // (Dashboard may not be listening yet when this arrives after session/start)
                if event.type == .ptyPermission {
                    if case .ptyPermission(let payload) = event.payload {
                        AppLogger.log("[WebSocket] pty_permission event - type=\(payload.type?.rawValue ?? "nil"), options=\(payload.options?.count ?? 0)")
                        if payload.type == .trustFolder {
                            setPendingTrustFolderPermission(event)
                        }
                    } else {
                        AppLogger.log("[WebSocket] pty_permission event - failed to decode payload")
                    }
                }

                // Broadcast to ALL event stream subscribers (copy to Array for thread safety)
                let eventContinuations = eventContinuationsLock.withLock {
                    Array(eventStreamContinuations.values)
                }

                for continuation in eventContinuations {
                    continuation.yield(event)
                }

                AppLogger.webSocket("Received event: \(event.type.rawValue)")

                // Log to debug store with payload for inspection
                Task { @MainActor in
                    DebugLogStore.shared.logWebSocket(
                        direction: .incoming,
                        title: event.type.rawValue,
                        eventType: event.type.rawValue,
                        // payload: line.count < 2000 ? line : String(line.prefix(2000)) + "..."
                        payload: line  // Full payload for copy support
                    )
                }
            } catch {
                AppLogger.webSocket("Parse error for line: \(error)", type: .warning)

                // Log parse errors to debug store
                Task { @MainActor in
                    DebugLogStore.shared.logWebSocket(
                        direction: .incoming,
                        title: "Parse error",
                        eventType: nil,
                        // payload: "\(error)\n\nRaw: \(line.prefix(500))",
                        payload: "\(error)\n\nRaw: \(line)",  // Full payload for copy support
                        level: .error
                    )
                }
            }
        }
    }

    /// Handle JSON-RPC messages (responses and notifications)
    private func handleJSONRPCMessage(data: Data, messageType: JSONRPCMessageType, rawLine: String) {
        switch messageType {
        case .response:
            // Route to RPC client for request correlation
            if let client = rpcClient {
                Task {
                    await client.handleMessage(data)
                }
            }

            // Parse response once and extract all needed info
            let responseInfo = parseJSONRPCResponse(data: data)

            // Look up the method name from tracked requests
            var methodName: String?
            if let responseId = responseInfo.id {
                methodName = pendingRequestMethodsLock.withLock {
                    pendingRequestMethods.removeValue(forKey: responseId)?.method
                }
            }
            let displayMethod = methodName ?? "response"

            if responseInfo.isError {
                AppLogger.webSocket("JSON-RPC error for \(displayMethod): \(responseInfo.errorMessage ?? "Unknown error")", type: .error)
            } else {
                AppLogger.webSocket("JSON-RPC response: \(displayMethod)")
            }

            // Log to debug store with appropriate level (capture values to avoid retain cycles)
            let title = responseInfo.isError
                ? "⚠️ \(displayMethod): \(responseInfo.errorMessage ?? "Error")"
                : "← \(displayMethod)"
            let eventType = responseInfo.isError ? "jsonrpc_error" : "jsonrpc_response"
            let level: DebugLogLevel = responseInfo.isError ? .error : .info
            // let payload = rawLine.count < 2000 ? rawLine : String(rawLine.prefix(2000)) + "..."
            let payload = rawLine  // Full payload for copy support

            Task { @MainActor in
                DebugLogStore.shared.logWebSocket(
                    direction: .incoming,
                    title: title,
                    eventType: eventType,
                    payload: payload,
                    level: level
                )
            }

        case .notification:
            // Parse notification and convert to AgentEvent if possible
            handleJSONRPCNotification(data: data, rawLine: rawLine)

        case .request:
            // Server-to-client requests not expected in current protocol
            AppLogger.webSocket("Unexpected JSON-RPC request from server", type: .warning)

        case .unknown:
            break
        }
    }

    /// Handle JSON-RPC notification - convert to AgentEvent if applicable
    private func handleJSONRPCNotification(data: Data, rawLine: String) {
        do {
            let notification = try jsonDecoder.decode(JSONRPCRawNotification.self, from: data)
            let method = notification.method

            AppLogger.webSocket("JSON-RPC notification: \(method)")

            // Log to debug store
            Task { @MainActor in
                DebugLogStore.shared.logWebSocket(
                    direction: .incoming,
                    title: method,
                    eventType: method,
                    // payload: rawLine.count < 2000 ? rawLine : String(rawLine.prefix(2000)) + "..."
                    payload: rawLine  // Full payload for copy support
                )
            }

            // Try to convert known notification methods to AgentEvent
            // This allows existing event handling code to work with JSON-RPC notifications
            if let event = convertNotificationToEvent(method: method, params: notification.params) {
                // Handle heartbeat events - don't forward to event stream
                if event.type == .heartbeat {
                    return
                }

                // Store trust_folder permission for Dashboard to pick up
                // (Dashboard may not be listening yet when this arrives after session/start)
                if event.type == .ptyPermission {
                    if case .ptyPermission(let payload) = event.payload {
                        AppLogger.log("[WS] pty_permission event - type=\(payload.type?.rawValue ?? "nil"), options=\(payload.options?.count ?? 0)")
                        if payload.type == .trustFolder {
                            setPendingTrustFolderPermission(event)
                        }
                    } else {
                        AppLogger.log("[WS] pty_permission event - failed to decode payload")
                    }
                }

                // Debug logging for session lifecycle and stream events
                if event.type == .sessionIdFailed || event.type == .sessionIdResolved || event.type == .streamReadComplete {
                    AppLogger.log("[WS] Special event: \(event.type.rawValue), payload type: \(type(of: event.payload))")
                }

                AppLogger.log("[WS] Broadcasting event: \(event.type.rawValue) to \(eventStreamContinuations.count) subscribers")

                // Broadcast to event stream subscribers
                let eventContinuations = eventContinuationsLock.withLock {
                    Array(eventStreamContinuations.values)
                }

                for continuation in eventContinuations {
                    continuation.yield(event)
                }
            } else {
                AppLogger.log("[WS] Failed to convert notification: \(method)", type: .warning)
            }
        } catch {
            AppLogger.webSocket("JSON-RPC notification parse error: \(error)", type: .warning)
        }
    }

    /// Convert JSON-RPC notification to AgentEvent
    /// Server sends events with workspace_id and session_id at top level for filtering
    private func convertNotificationToEvent(method: String, params: AnyCodable?) -> AgentEvent? {
        // Map notification methods to event types
        // This bridges the JSON-RPC format to existing event handling
        guard let paramsDict = params?.dictionaryValue else {
            AppLogger.log("[WS] convertNotification: params?.dictionaryValue is nil for method=\(method)", type: .warning)
            return nil
        }

        // Strip "event/" prefix from method name if present
        // JSON-RPC uses "event/claude_message" but AgentEventType expects "claude_message"
        let eventType = method.hasPrefix("event/") ? String(method.dropFirst(6)) : method
        AppLogger.log("[WS] convertNotification: eventType=\(eventType), paramsKeys=\(paramsDict.keys.sorted())")

        // Extract workspace_id and session_id from params for event filtering
        // Server sends these at the top level of the event for multi-device filtering
        let workspaceId = paramsDict["workspace_id"] as? String
        let sessionId = paramsDict["session_id"] as? String
        let topLevelAgentType = paramsDict["agent_type"] as? String

        // Extract payload - could be nested in "payload" key or params itself contains the payload
        let payload: [String: Any]
        if let nestedPayload = paramsDict["payload"] as? [String: Any] {
            payload = nestedPayload
        } else {
            // Params IS the payload (minus workspace_id/session_id)
            payload = paramsDict
        }

        // Re-encode params to Data for AgentEvent decoding
        // AgentEvent expects: { "event": "...", "payload": {...}, "workspace_id": "...", "session_id": "...", "id": "...", "timestamp": "..." }
        do {
            var eventDict: [String: Any] = [:]
            eventDict["event"] = eventType  // Add event type (without "event/" prefix)
            eventDict["payload"] = payload  // Payload content
            eventDict["id"] = UUID().uuidString
            eventDict["timestamp"] = paramsDict["timestamp"] as? String ?? ISO8601DateFormatter().string(from: Date())

            // Add workspace_id and session_id at top level for filtering
            if let workspaceId = workspaceId {
                eventDict["workspace_id"] = workspaceId
            }
            if let sessionId = sessionId {
                eventDict["session_id"] = sessionId
            }
            // Add agent_type for runtime routing; support both top-level and payload-provided forms.
            if let agentType = topLevelAgentType ?? (payload["agent_type"] as? String) {
                eventDict["agent_type"] = agentType
            }

            let eventData = try JSONSerialization.data(withJSONObject: eventDict)
            let event = try jsonDecoder.decode(AgentEvent.self, from: eventData)
            AppLogger.log("[WS] convertNotification: decoded event type=\(event.type.rawValue), payload=\(type(of: event.payload))")
            return event
        } catch {
            // Only log to console - avoid DebugLogStore for high-frequency errors
            AppLogger.webSocket("Failed to convert notification '\(eventType)': \(error)", type: .warning)
            return nil
        }
    }

    // MARK: - JSON-RPC Parsing Helpers (Optimized - single parse)

    /// Parsed JSON-RPC response info
    private struct JSONRPCResponseInfo {
        let id: String?
        let isError: Bool
        let errorMessage: String?
    }

    /// Parse JSON-RPC response once and extract all needed info
    private func parseJSONRPCResponse(data: Data) -> JSONRPCResponseInfo {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return JSONRPCResponseInfo(id: nil, isError: false, errorMessage: nil)
        }

        // Extract ID
        let id: String?
        if let idString = json["id"] as? String {
            id = idString
        } else if let idInt = json["id"] as? Int {
            id = String(idInt)
        } else {
            id = nil
        }

        // Check for error
        let isError = json["error"] != nil
        var errorMessage: String?
        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int
            let message = error["message"] as? String
            if let code = code, let message = message {
                errorMessage = "[\(code)] \(message)"
            } else {
                errorMessage = message
            }
        }

        return JSONRPCResponseInfo(id: id, isError: isError, errorMessage: errorMessage)
    }

    /// Extract method name and request ID from JSON-RPC request (single parse)
    private func extractJSONRPCMethodAndId(data: Data) -> (method: String?, id: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        let method = json["method"] as? String
        let id: String?
        if let idString = json["id"] as? String {
            id = idString
        } else if let idInt = json["id"] as? Int {
            id = String(idInt)
        } else {
            id = nil
        }
        return (method, id)
    }

    /// Clean up stale pending request entries (called with lock held)
    private func cleanupStaleRequests() {
        let now = Date()
        let timeout = Self.pendingRequestTimeout
        pendingRequestMethods = pendingRequestMethods.filter { _, value in
            now.timeIntervalSince(value.timestamp) < timeout
        }
    }

    private func handleDisconnect(error: Error) {
        // Ignore disconnect callbacks during reconnection - old socket cleanup
        guard !isReconnecting else {
            AppLogger.webSocket("Ignoring disconnect during reconnection")
            return
        }

        let errorMessage = Self.friendlyErrorMessage(from: error)
        let isTransient = Self.isTransientConnectionError(error)

        switch connectionState {
        case .connected:
            // For transient errors, go directly to reconnecting state (less alarming to user)
            if isTransient && shouldAutoReconnect {
                AppLogger.webSocket("Transient disconnect: \(errorMessage) - reconnecting silently")
                Task {
                    try? await reconnect()
                }
            } else {
                updateState(.failed(reason: errorMessage))
                if shouldAutoReconnect {
                    Task {
                        try? await reconnect()
                    }
                }
            }
        case .connecting:
            // Connection failed during initial connect - update state
            updateState(.failed(reason: errorMessage))
        case .reconnecting:
            // Ignore during reconnection - will be handled by reconnect flow
            break
        case .disconnected, .failed:
            // Already in terminal state, ignore
            break
        }
    }

    // MARK: - App Lifecycle Support

    /// Called when app enters foreground - verify connection and reconnect if needed
    func handleAppDidBecomeActive() {
        AppLogger.webSocket("App became active - checking connection")

        // Re-enable auto-reconnect when app becomes active
        if connectionInfo != nil {
            shouldAutoReconnect = true
            // Reset attempts to give fresh chances after returning to app
            reconnectAttempts = 0
        }

        Task {
            switch connectionState {
            case .connected:
                // Restart timers that were stopped on background
                startTimers()

                // Verify connection is still alive
                let success = try? await ping()
                if success != true {
                    AppLogger.webSocket("Connection stale after foregrounding - reconnecting")
                    try? await reconnect()
                } else {
                    // Reset activity timer since we just verified connection
                    updateLastActivity()
                }
            case .failed, .disconnected:
                // Attempt reconnection if we have connection info
                if connectionInfo != nil && shouldAutoReconnect {
                    AppLogger.webSocket("Reconnecting after foregrounding")
                    try? await reconnect()
                }
            default:
                break
            }
        }
    }

    /// Called when app enters background - stop reconnection attempts to save resources
    /// - Parameter preserveWatch: If true, keeps session watch active (for Dashboard persistence)
    func handleAppWillResignActive(preserveWatch: Bool) {
        AppLogger.webSocket("App will resign active - pausing reconnection (preserveWatch=\(preserveWatch))")

        // Stop reconnection attempts when app goes to background
        shouldAutoReconnect = false

        // Cancel any pending reconnection
        isReconnecting = false

        // Stop timers to save CPU/battery
        stopTimers()

        // Only unwatch if NOT preserving watch (Dashboard persistence)
        // When preserveWatch is true, we want to resume watching on reconnect
        if !preserveWatch && _watchedSessionId != nil {
            Task {
                try? await unwatchSession()
            }
        }
    }

    // MARK: - Session Watching

    /// Currently watched workspace ID (for workspace-aware unwatch)
    @Atomic private var _watchedWorkspaceId: String?

    /// Watch a session for real-time updates
    /// - Parameters:
    ///   - sessionId: The session ID to watch
    ///   - workspaceId: The workspace ID (required for workspaceScoped watch APIs)
    ///   - runtime: Runtime selector for watch routing
    /// - Throws: Connection or encoding errors
    func watchSession(_ sessionId: String, workspaceId: String?, runtime: AgentRuntime) async throws {
        // Already watching this session/runtime? Skip
        if _watchedSessionId == sessionId && _watchedRuntime == runtime {
            AppLogger.webSocket("Already watching session: \(sessionId) (runtime: \(runtime.rawValue))")
            return
        }

        // If watching a different session, unwatch first
        if _watchedSessionId != nil {
            try await unwatchSession()
        }

        // Must be connected
        guard isConnected else {
            AppLogger.webSocket("Cannot watch session - not connected", type: .warning)
            throw AppError.webSocketDisconnected
        }

        let client = getJSONRPCClient()

        let watchMethod = runtime.watchMethodName
        if runtime.usesWorkspaceScopedWatchMethod {
            // Workspace ID is required for workspace-scoped watch methods.
            guard let workspaceId = workspaceId else {
                AppLogger.webSocket("Cannot watch \(runtime.rawValue) session - workspaceId is required", type: .error)
                throw AppError.workspaceIdRequired
            }
            AppLogger.webSocket("Starting workspace watch for session: \(sessionId) in workspace: \(workspaceId) (runtime: \(runtime.rawValue), method: \(watchMethod))")
            let params = WorkspaceSessionWatchParams(
                workspaceId: workspaceId,
                sessionId: sessionId,
                agentType: runtime.rawValue
            )
            let _: WorkspaceSessionWatchResult = try await client.request(
                method: watchMethod,
                params: params
            )
            _watchedWorkspaceId = workspaceId
        } else {
            AppLogger.webSocket("Starting runtime watch for session: \(sessionId) (runtime: \(runtime.rawValue), method: \(watchMethod))")
            let params = SessionWatchParams(sessionId: sessionId, agentType: runtime.rawValue)
            let _: SessionWatchResult = try await client.request(
                method: watchMethod,
                params: params
            )
            _watchedWorkspaceId = nil
        }

        _watchedSessionId = sessionId
        _watchedRuntime = runtime
    }

    /// Stop watching the current session
    /// - Throws: Connection or encoding errors
    func unwatchSession() async throws {
        guard _watchedSessionId != nil else {
            AppLogger.webSocket("Not watching any session")
            return
        }

        // Clear watched session ID immediately to prevent race conditions
        let previousSessionId = _watchedSessionId
        let previousRuntime = _watchedRuntime
        _watchedSessionId = nil
        _watchedWorkspaceId = nil
        _watchedRuntime = nil

        // Only send unwatch if connected
        guard isConnected else {
            AppLogger.webSocket("Cleared local watch state (disconnected)")
            return
        }

        let client = getJSONRPCClient()
        let runtime = previousRuntime ?? AgentRuntime.defaultRuntime
        let unwatchMethod = runtime.unwatchMethodName

        if runtime.usesWorkspaceScopedUnwatchMethod {
            AppLogger.webSocket("Stopping workspace watch for session: \(previousSessionId ?? "unknown") (runtime: \(runtime.rawValue), method: \(unwatchMethod))")
            let params = WorkspaceSessionUnwatchParams(agentType: runtime.rawValue)
            let _: WorkspaceSessionUnwatchResult = try await client.request(
                method: unwatchMethod,
                params: params
            )
        } else {
            AppLogger.webSocket("Stopping runtime watch for session: \(previousSessionId ?? "unknown") (runtime: \(runtime.rawValue), method: \(unwatchMethod))")
            let _: SessionUnwatchResult = try await client.request(
                method: unwatchMethod,
                params: SessionUnwatchParams(agentType: runtime.rawValue)
            )
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        // Ignore callbacks from old/stale sessions
        guard self.session === session, self.webSocket === webSocketTask else {
            AppLogger.webSocket("Ignoring didOpen from stale session")
            return
        }
        AppLogger.webSocket("WebSocket opened", type: .success)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        // Ignore callbacks from old/stale sessions or during reconnection
        guard self.session === session, self.webSocket === webSocketTask else {
            AppLogger.webSocket("Ignoring didClose from stale session")
            return
        }
        guard !isReconnecting else { return }

        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        AppLogger.webSocket("WebSocket closed: code=\(closeCode.rawValue), reason=\(reasonString ?? "none")")

        // Handle specific close codes
        switch closeCode.rawValue {
        case 1008:  // Policy Violation - authentication failed
            AppLogger.webSocket("Authentication failed (close code 1008)", type: .error)
            updateState(.failed(reason: "Authentication failed - token may be expired"))
        case 1001:  // Going Away - server shutting down
            AppLogger.webSocket("Server going away", type: .warning)
            updateState(.failed(reason: "Server shutting down"))
        case 1006:  // Abnormal Closure - connection lost without close frame
            AppLogger.webSocket("Connection lost abnormally", type: .warning)
            updateState(.failed(reason: "Connection lost"))
        default:
            // Use reason string if provided, otherwise generic message
            if let reason = reasonString, !reason.isEmpty {
                updateState(.failed(reason: reason))
            } else {
                updateState(.disconnected)
            }
        }
    }
}
