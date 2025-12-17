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
            throw AppError.connectionFailed(underlying: nil)
        }

        webSocket = session.webSocketTask(with: connectionInfo.webSocketURL)
        webSocket?.resume()

        // Wait for connection or timeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                // Start receiving messages
                self.receiveMessage()

                // Check connection with a ping
                do {
                    webSocket?.sendPing { error in
                        if let error = error {
                            continuation.resume(throwing: AppError.connectionFailed(underlying: error))
                        } else {
                            self.updateState(.connected(connectionInfo))
                            continuation.resume()
                        }
                    }
                }
            }
        }

        startPingTimer()
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
        defer { isReconnecting = false }

        reconnectAttempts += 1

        guard reconnectAttempts <= Constants.Network.maxReconnectAttempts else {
            updateState(.failed(reason: "Max reconnect attempts reached"))
            throw AppError.connectionFailed(underlying: nil)
        }

        updateState(.reconnecting(attempt: reconnectAttempts))

        // Exponential backoff
        let delay = Constants.Network.reconnectDelay * pow(2, Double(reconnectAttempts - 1))
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        try await connect(to: connectionInfo)
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
        guard let data = text.data(using: .utf8) else { return }

        do {
            let decoder = JSONDecoder()
            let event = try decoder.decode(AgentEvent.self, from: data)
            eventStreamContinuation?.yield(event)
            AppLogger.webSocket("Received event: \(event.type.rawValue)")
        } catch {
            AppLogger.webSocket("Parse error: \(error)", type: .warning)
        }
    }

    private func handleDisconnect(error: Error) {
        if case .connected = connectionState {
            updateState(.failed(reason: error.localizedDescription))

            // Attempt reconnect
            Task {
                try? await reconnect()
            }
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
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        AppLogger.webSocket("WebSocket closed: \(closeCode.rawValue)")
        updateState(.connectionClosed(reason: reasonString))
    }
}
