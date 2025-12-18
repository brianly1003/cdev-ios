import Foundation

/// WebSocket service for real-time communication with agent
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

    // MARK: - Connection

    func connect(to connectionInfo: ConnectionInfo) async throws {
        self.connectionInfo = connectionInfo
        reconnectAttempts = 0

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

        startPingTimer()
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
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        updateState(.disconnected)
    }

    func reconnect() async throws {
        guard let connectionInfo = connectionInfo,
              !isReconnecting else { return }

        isReconnecting = true

        reconnectAttempts += 1

        guard reconnectAttempts <= Constants.Network.maxReconnectAttempts else {
            isReconnecting = false
            updateState(.failed(reason: "Max reconnect attempts reached"))
            throw AppError.connectionFailed(underlying: nil)
        }

        updateState(.reconnecting(attempt: reconnectAttempts))

        // Clean up old connection first
        pingTimer?.invalidate()
        pingTimer = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil

        // Exponential backoff
        let delay = Constants.Network.reconnectDelay * pow(2, Double(reconnectAttempts - 1))
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        do {
            try await connect(to: connectionInfo)
            isReconnecting = false
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
            // Attempt reconnect only if was connected
            Task {
                try? await reconnect()
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

    private var pingTimer: Timer?

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: Constants.Network.pingInterval, repeats: true) { [weak self] _ in
            Task {
                let success = try? await self?.ping()
                if success != true {
                    AppLogger.webSocket("Ping failed", type: .warning)
                }
            }
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
