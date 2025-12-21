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

    /// Check if currently connected
    var isConnected: Bool { get }
}

/// Protocol for WebSocket-specific operations
protocol WebSocketServiceProtocol: AgentConnectionProtocol {
    /// Reconnect with exponential backoff
    func reconnect() async throws

    /// Ping server to check connection health
    func ping() async throws -> Bool

    /// Send raw data (for JSON-RPC messages)
    func send(data: Data) async throws

    /// Handle app becoming active (foreground)
    func handleAppDidBecomeActive()

    /// Handle app resigning active (background)
    func handleAppWillResignActive()

    // MARK: - Session Watching

    /// Currently watched session ID (nil if not watching)
    var watchedSessionId: String? { get }

    /// Watch a session for real-time updates
    /// Sends watch_session command and tracks the watched session
    func watchSession(_ sessionId: String) async throws

    /// Stop watching the current session
    /// Sends unwatch_session command
    func unwatchSession() async throws
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
