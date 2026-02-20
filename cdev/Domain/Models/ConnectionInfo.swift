import Foundation

/// Connection information for pairing with agent
/// Matches cdev-agent's PairingInfo struct from internal/pairing/qrcode.go
struct ConnectionInfo: Codable, Equatable {
    let webSocketURL: URL
    let httpURL: URL
    let sessionId: String
    let repoName: String
    let authRequired: Bool?
    let token: String?  // Access token for HTTP/WebSocket auth
    let tokenExpiresAtString: String?  // ISO8601 expiry time from server

    /// JSON keys match cdev-agent's PairingInfo:
    /// - ws: WebSocket URL
    /// - http: HTTP API URL
    /// - session: Session ID
    /// - repo: Repository name
    /// - auth_required: Whether authentication is required
    /// - token: Optional pairing token
    /// - token_expires_at: Optional ISO8601 expiry time
    enum CodingKeys: String, CodingKey {
        case webSocketURL = "ws"
        case httpURL = "http"
        case sessionId = "session"
        case repoName = "repo"
        case authRequired = "auth_required"
        case token
        case tokenExpiresAtString = "token_expires_at"
    }

    init(webSocketURL: URL, httpURL: URL, sessionId: String, repoName: String, authRequired: Bool? = nil, token: String? = nil, tokenExpiresAt: String? = nil) {
        self.webSocketURL = webSocketURL
        self.httpURL = httpURL
        self.sessionId = sessionId
        self.repoName = repoName
        self.authRequired = authRequired
        self.token = token
        self.tokenExpiresAtString = tokenExpiresAt
    }

    /// Parsed token expiry date
    var tokenExpiresAt: Date? {
        guard let expiryString = tokenExpiresAtString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiryString) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiryString)
    }

    /// Check if token is expired
    var isTokenExpired: Bool {
        guard let expiresAt = tokenExpiresAt else { return false }
        return Date() > expiresAt
    }

    /// Time until token expires (nil if no expiry or already expired)
    var tokenTimeRemaining: TimeInterval? {
        guard let expiresAt = tokenExpiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let wsURLString = try container.decode(String.self, forKey: .webSocketURL)
        guard let wsURL = URL(string: wsURLString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .webSocketURL,
                in: container,
                debugDescription: "Invalid WebSocket URL"
            )
        }
        self.webSocketURL = wsURL

        let httpURLString = try container.decode(String.self, forKey: .httpURL)
        guard let httpURL = URL(string: httpURLString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .httpURL,
                in: container,
                debugDescription: "Invalid HTTP URL"
            )
        }
        self.httpURL = httpURL

        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.repoName = try container.decode(String.self, forKey: .repoName)
        self.authRequired = try container.decodeIfPresent(Bool.self, forKey: .authRequired)
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
        self.tokenExpiresAtString = try container.decodeIfPresent(String.self, forKey: .tokenExpiresAtString)
    }

    /// Host address (for display)
    var host: String {
        webSocketURL.host ?? "unknown"
    }

    /// Check if connection is local (same network)
    var isLocal: Bool {
        guard let host = webSocketURL.host else { return false }
        return host == "localhost" ||
               host == "127.0.0.1" ||
               host.hasPrefix("192.168.") ||
               host.hasPrefix("10.") ||
               host.hasPrefix("172.")
    }
}

/// Connection state
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(ConnectionInfo)
    case reconnecting(attempt: Int)
    case failed(reason: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        if case .reconnecting = self { return true }
        return false
    }

    var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .reconnecting(let attempt):
            return "Retrying to connect (\(attempt))..."
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}
