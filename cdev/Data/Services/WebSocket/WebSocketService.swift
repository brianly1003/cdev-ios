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
    private let timerQueue = DispatchQueue(label: "com.cdev.websocket.timers", qos: .utility)

    /// Track if we should attempt reconnection
    private var shouldAutoReconnect = true

    /// Cached JSON decoder/encoder to avoid repeated allocations
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    // MARK: - Session Watching State

    /// Currently watched session ID (publicly accessible)
    @Atomic private var _watchedSessionId: String?
    var watchedSessionId: String? { _watchedSessionId }

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
            self.continuationsLock.lock()
            self.stateStreamContinuations[id] = continuation
            self.continuationsLock.unlock()

            // Yield current state immediately to new subscriber
            continuation.yield(self.connectionState)

            // Clean up when stream terminates
            continuation.onTermination = { [weak self] _ in
                self?.continuationsLock.lock()
                self?.stateStreamContinuations.removeValue(forKey: id)
                self?.continuationsLock.unlock()
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
            self.eventContinuationsLock.lock()
            self.eventStreamContinuations[id] = continuation
            self.eventContinuationsLock.unlock()

            // Clean up when stream terminates
            continuation.onTermination = { [weak self] _ in
                self?.eventContinuationsLock.lock()
                self?.eventStreamContinuations.removeValue(forKey: id)
                self?.eventContinuationsLock.unlock()
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
        // Finish state stream continuations
        continuationsLock.lock()
        for continuation in stateStreamContinuations.values {
            continuation.finish()
        }
        stateStreamContinuations.removeAll()
        continuationsLock.unlock()

        // Finish event stream continuations
        eventContinuationsLock.lock()
        for continuation in eventStreamContinuations.values {
            continuation.finish()
        }
        eventStreamContinuations.removeAll()
        eventContinuationsLock.unlock()
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

        webSocket = session.webSocketTask(with: connectionInfo.webSocketURL)
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
                    try await self.waitForConnection(connectionInfo: connectionInfo)
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
            updateState(.failed(reason: errorMessage))
            AppLogger.webSocket("Connection failed: \(errorMessage)", type: .error)
            throw error
        }

        // Start stability timers on successful connection
        startTimers()
    }

    private func waitForConnection(connectionInfo: ConnectionInfo) async throws {
        guard let currentSocket = webSocket else {
            throw AppError.connectionFailed(underlying: nil)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Start receiving messages
            self.receiveMessage()

            // Check connection with a ping
            currentSocket.sendPing { [weak self] error in
                // Verify socket is still the current one
                guard self?.webSocket === currentSocket else {
                    continuation.resume(throwing: AppError.connectionFailed(underlying: nil))
                    return
                }

                if let error = error {
                    continuation.resume(throwing: AppError.connectionFailed(underlying: error))
                } else {
                    self?.updateState(.connected(connectionInfo))
                    continuation.resume()
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
        AppLogger.webSocket("Disconnecting")
        shouldAutoReconnect = false
        stopTimers()

        // Clear watched session state
        _watchedSessionId = nil

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        updateState(.disconnected)
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
                try await connect(to: connectionInfo)
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
            currentSocket.sendPing { error in
                // Verify socket is still the current one before resuming
                guard self?.webSocket === currentSocket else {
                    // Socket changed, treat as failure but don't crash
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: error == nil)
            }
        }
    }

    // MARK: - Send

    func send(command: AgentCommand) async throws {
        guard let webSocket = webSocket else {
            throw AppError.webSocketDisconnected
        }

        let data = try jsonEncoder.encode(command)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw AppError.encodingFailed(underlying: NSError(domain: "WebSocket", code: -1))
        }

        AppLogger.webSocket("Sending command: \(command.command.rawValue)")

        do {
            try await webSocket.send(.string(jsonString))

            // Log outgoing command to debug store
            Task { @MainActor in
                DebugLogStore.shared.logWebSocket(
                    direction: .outgoing,
                    title: command.command.rawValue,
                    eventType: command.command.rawValue,
                    payload: jsonString
                )
            }
        } catch {
            AppLogger.webSocket("Send failed: \(error)", type: .error)

            // Log send error to debug store
            Task { @MainActor in
                DebugLogStore.shared.logWebSocket(
                    direction: .outgoing,
                    title: "Send failed: \(command.command.rawValue)",
                    eventType: command.command.rawValue,
                    payload: "\(error)",
                    level: .error
                )
            }

            throw AppError.webSocketMessageFailed(underlying: error)
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
        continuationsLock.lock()
        let continuations = Array(stateStreamContinuations.values)
        continuationsLock.unlock()

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

                // Broadcast to ALL event stream subscribers (copy to Array for thread safety)
                eventContinuationsLock.lock()
                let eventContinuations = Array(eventStreamContinuations.values)
                eventContinuationsLock.unlock()

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
                        payload: line.count < 2000 ? line : String(line.prefix(2000)) + "..."
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
                        payload: "\(error)\n\nRaw: \(line.prefix(500))",
                        level: .error
                    )
                }
            }
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
    func handleAppWillResignActive() {
        AppLogger.webSocket("App will resign active - pausing reconnection")

        // Stop reconnection attempts when app goes to background
        shouldAutoReconnect = false

        // Cancel any pending reconnection
        isReconnecting = false

        // Stop timers to save CPU/battery
        stopTimers()

        // Unwatch session when going to background to reduce server load
        if _watchedSessionId != nil {
            Task {
                try? await unwatchSession()
            }
        }
    }

    // MARK: - Session Watching

    /// Watch a session for real-time updates
    /// - Parameter sessionId: The session ID to watch
    /// - Throws: Connection or encoding errors
    func watchSession(_ sessionId: String) async throws {
        // Already watching this session? Skip
        guard _watchedSessionId != sessionId else {
            AppLogger.webSocket("Already watching session: \(sessionId)")
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

        AppLogger.webSocket("Starting watch for session: \(sessionId)")
        let command = AgentCommand.watchSession(sessionId: sessionId)
        try await send(command: command)

        // Optimistically set watched session ID
        // Server will confirm with session_watch_started event
        _watchedSessionId = sessionId
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
        _watchedSessionId = nil

        // Only send unwatch if connected
        guard isConnected else {
            AppLogger.webSocket("Cleared local watch state (disconnected)")
            return
        }

        AppLogger.webSocket("Stopping watch for session: \(previousSessionId ?? "unknown")")
        let command = AgentCommand.unwatchSession()
        try await send(command: command)
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
        AppLogger.webSocket("WebSocket closed: \(closeCode.rawValue)")

        // Only update state if not empty reason
        if let reason = reasonString, !reason.isEmpty {
            updateState(.failed(reason: reason))
        } else {
            updateState(.disconnected)
        }
    }
}
