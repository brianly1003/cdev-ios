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
    /// Flag to indicate external retry loop is in progress (e.g., WorkspaceManagerViewModel)
    /// When true, connect() won't update to .failed state on failure
    var isExternalRetryInProgress: Bool { get set }

    /// Reconnect with exponential backoff
    func reconnect() async throws

    /// Ping server to check connection health
    func ping() async throws -> Bool

    /// Send raw data (for JSON-RPC messages)
    func send(data: Data) async throws

    /// Handle app becoming active (foreground)
    func handleAppDidBecomeActive()

    /// Handle app resigning active (background)
    /// - Parameter preserveWatch: If true, keeps session watch active for Dashboard persistence
    func handleAppWillResignActive(preserveWatch: Bool)

    // MARK: - Multi-Device Awareness

    /// Client ID assigned by server (nil if not connected or not assigned)
    var clientId: String? { get }

    // MARK: - JSON-RPC

    /// Get JSON-RPC client for making requests
    func getJSONRPCClient() -> JSONRPCClient

    // MARK: - Session Watching

    /// Currently watched session ID (nil if not watching)
    var watchedSessionId: String? { get }

    /// Watch a session for real-time updates using workspace/session/watch API
    /// - Parameters:
    ///   - sessionId: The session ID to watch
    ///   - workspaceId: The workspace ID (required for workspace/session/watch)
    /// - Throws: AppError.workspaceIdRequired if workspaceId is nil
    func watchSession(_ sessionId: String, workspaceId: String?) async throws

    /// Stop watching the current session
    /// Sends unwatch_session command
    func unwatchSession() async throws

    // MARK: - Pending Trust Folder Permission

    /// Get and clear pending trust_folder permission (atomic operation)
    /// Returns the event if one was pending, nil otherwise
    /// Used by Dashboard to pick up permissions that arrived before it was ready
    func consumePendingTrustFolderPermission() -> AgentEvent?

    // MARK: - Token Expiry Warning

    /// Callback for token expiry warning (called ~5 minutes before token expires)
    /// Parameter: time remaining in seconds until token expires
    var onTokenExpiryWarning: ((TimeInterval) -> Void)? { get set }
}

/// Protocol for HTTP API operations
protocol HTTPServiceProtocol: AnyObject {
    /// Base URL for HTTP requests
    var baseURL: URL? { get set }

    /// Authentication token for API requests (access token)
    /// When set, adds `Authorization: Bearer <token>` header to all requests
    var authToken: String? { get set }

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

    // MARK: - Token Authentication

    /// Exchange pairing token for access/refresh token pair
    /// - Parameter pairingToken: The pairing token from QR code
    /// - Returns: TokenPair with access and refresh tokens
    func exchangePairingToken(_ pairingToken: String) async throws -> TokenPair

    /// Refresh access token using refresh token
    /// - Parameter refreshToken: The refresh token from previous token pair
    /// - Returns: New TokenPair with fresh access and refresh tokens
    func refreshTokenPair(_ refreshToken: String) async throws -> TokenPair
}
