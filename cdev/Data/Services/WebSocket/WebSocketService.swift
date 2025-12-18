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
    private var isReconnecting = false

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
    private let timerQueue = DispatchQueue(label: "com.cdev.websocket.timers", qos: .utility)

    /// Track if we should attempt reconnection
    private var shouldAutoReconnect = true

    // MARK: - Streams

    private var stateStreamContinuation: AsyncStream<ConnectionState>.Continuation?
    private(set) lazy var connectionStateStream: AsyncStream<ConnectionState> = {
        AsyncStream { continuation in
            self.stateStreamContinuation = continuation
            continuation.yield(self.connectionState)
        }
    }()

    private var eventStreamContinuation: AsyncStream<AgentEvent>.Continuation?
    private(set) lazy var eventStream: AsyncStream<AgentEvent> = {
        AsyncStream { continuation in
            self.eventStreamContinuation = continuation
        }
    }()

    // MARK: - Init

    override init() {
        super.init()
        setupNetworkMonitor()
    }

    deinit {
        stopNetworkMonitor()
        stopTimers()
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
        reconnectAttempts = 0
        shouldAutoReconnect = true

        updateState(.connecting)

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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Start receiving messages
            self.receiveMessage()

            // Check connection with a ping
            self.webSocket?.sendPing { [weak self] error in
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
        case -1009: // kCFURLErrorNotConnectedToInternet
            return "No internet connection"
        case 61: // Connection refused
            return "Connection refused - is the server running?"
        default:
            return nsError.localizedDescription
        }
    }

    func disconnect() {
        AppLogger.webSocket("Disconnecting")
        shouldAutoReconnect = false
        stopTimers()
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
        guard let connectionInfo = connectionInfo,
              !isReconnecting,
              shouldAutoReconnect else { return }

        isReconnecting = true

        reconnectAttempts += 1

        guard reconnectAttempts <= Constants.Network.maxReconnectAttempts else {
            isReconnecting = false
            updateState(.failed(reason: "Max reconnect attempts reached"))
            throw AppError.connectionFailed(underlying: nil)
        }

        updateState(.reconnecting(attempt: reconnectAttempts))

        // Clean up old connection first
        stopTimers()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil

        // Exponential backoff with max cap
        let delay = min(
            Constants.Network.reconnectDelay * pow(2, Double(reconnectAttempts - 1)),
            Constants.Network.maxReconnectDelay
        )
        AppLogger.webSocket("Reconnect attempt \(reconnectAttempts) in \(String(format: "%.1f", delay))s")
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        do {
            try await connect(to: connectionInfo)
            isReconnecting = false
            reconnectAttempts = 0
            AppLogger.webSocket("Reconnection successful", type: .success)
        } catch {
            isReconnecting = false
            throw error
        }
    }

    func ping() async throws -> Bool {
        guard let webSocket = webSocket else { return false }

        return await withCheckedContinuation { continuation in
            webSocket.sendPing { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    // MARK: - Send

    func send(command: AgentCommand) async throws {
        guard let webSocket = webSocket else {
            throw AppError.webSocketDisconnected
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(command)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw AppError.encodingFailed(underlying: NSError(domain: "WebSocket", code: -1))
        }

        AppLogger.webSocket("Sending command: \(command.command.rawValue)")

        do {
            try await webSocket.send(.string(jsonString))
        } catch {
            AppLogger.webSocket("Send failed: \(error)", type: .error)
            throw AppError.webSocketMessageFailed(underlying: error)
        }
    }

    // MARK: - Private

    private func updateState(_ state: ConnectionState) {
        _connectionState = state
        stateStreamContinuation?.yield(state)
        AppLogger.webSocket("State: \(state.statusText)")
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessage() // Continue receiving

            case .failure(let error):
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

        let decoder = JSONDecoder()

        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }

            do {
                let event = try decoder.decode(AgentEvent.self, from: data)

                // Handle heartbeat events - don't forward to event stream
                if event.type == .heartbeat {
                    AppLogger.webSocket("Heartbeat received")
                    continue
                }

                eventStreamContinuation?.yield(event)
                AppLogger.webSocket("Received event: \(event.type.rawValue)")
            } catch {
                AppLogger.webSocket("Parse error for line: \(error)", type: .warning)
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

        switch connectionState {
        case .connected:
            updateState(.failed(reason: errorMessage))
            // Attempt reconnect only if was connected and auto-reconnect is enabled
            if shouldAutoReconnect {
                Task {
                    try? await reconnect()
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

        Task {
            switch connectionState {
            case .connected:
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

    /// Called when app enters background - prepare for potential disconnection
    func handleAppWillResignActive() {
        AppLogger.webSocket("App will resign active")
        // Note: iOS will keep the connection alive briefly, but we should be
        // prepared to reconnect when foregrounding
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        AppLogger.webSocket("WebSocket opened", type: .success)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        // Ignore callbacks from old sessions during reconnection
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
