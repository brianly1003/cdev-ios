import Foundation

/// Protocol for agent connection management
protocol AgentConnectionProtocol: AnyObject {
    /// Current connection state
    var connectionState: ConnectionState { get }

    /// Stream of connection state changes
    var connectionStateStream: AsyncStream<ConnectionState> { get }

    /// Stream of incoming events
    var eventStream: AsyncStream<AgentEvent> { get }

    /// Connect to agent using connection info
    func connect(to connectionInfo: ConnectionInfo) async throws

    /// Disconnect from agent
    func disconnect()

    /// Send command to agent
    func send(command: AgentCommand) async throws

    /// Check if currently connected
    var isConnected: Bool { get }
}

/// Protocol for WebSocket-specific operations
protocol WebSocketServiceProtocol: AgentConnectionProtocol {
    /// Reconnect with exponential backoff
    func reconnect() async throws

    /// Ping server to check connection health
    func ping() async throws -> Bool
}

/// Protocol for HTTP API operations
protocol HTTPServiceProtocol: AnyObject {
    /// Base URL for HTTP requests
    var baseURL: URL? { get set }

    /// GET request
    func get<T: Decodable>(path: String, queryItems: [URLQueryItem]?) async throws -> T

    /// POST request
    func post<T: Decodable, B: Encodable>(path: String, body: B?) async throws -> T

    /// POST request without response
    func post<B: Encodable>(path: String, body: B?) async throws

    /// DELETE request
    func delete<T: Decodable>(path: String, queryItems: [URLQueryItem]?) async throws -> T

    /// Health check
    func healthCheck() async throws -> Bool
}
