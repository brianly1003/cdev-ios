import Foundation

/// Use case for connecting to agent
protocol ConnectToAgentUseCase {
    func execute(connectionInfo: ConnectionInfo) async throws
    func disconnect()
}

final class DefaultConnectToAgentUseCase: ConnectToAgentUseCase {
    private let webSocketService: WebSocketServiceProtocol
    private let sessionStorage: SessionStorageProtocol

    init(
        webSocketService: WebSocketServiceProtocol,
        sessionStorage: SessionStorageProtocol
    ) {
        self.webSocketService = webSocketService
        self.sessionStorage = sessionStorage
    }

    func execute(connectionInfo: ConnectionInfo) async throws {
        AppLogger.log("Connecting to agent at \(connectionInfo.host)")

        // Connect via WebSocket
        try await webSocketService.connect(to: connectionInfo)

        // Save connection for auto-reconnect
        try await sessionStorage.saveConnection(connectionInfo)

        AppLogger.log("Connected to agent", type: .success)
    }

    func disconnect() {
        AppLogger.log("Disconnecting from agent")
        webSocketService.disconnect()
    }
}
