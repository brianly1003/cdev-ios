import Foundation

/// Connection information for pairing with agent
/// Matches cdev-agent's PairingInfo struct from internal/pairing/qrcode.go
struct ConnectionInfo: Codable, Equatable {
    let webSocketURL: URL
    let httpURL: URL
    let sessionId: String
    let repoName: String
    let token: String?

    /// JSON keys match cdev-agent's PairingInfo:
    /// - ws: WebSocket URL
    /// - http: HTTP API URL
    /// - session: Session ID
    /// - repo: Repository name
    /// - token: Optional pairing token
    enum CodingKeys: String, CodingKey {
        case webSocketURL = "ws"
        case httpURL = "http"
        case sessionId = "session"
        case repoName = "repo"
        case token
    }

    init(webSocketURL: URL, httpURL: URL, sessionId: String, repoName: String, token: String? = nil) {
        self.webSocketURL = webSocketURL
        self.httpURL = httpURL
        self.sessionId = sessionId
        self.repoName = repoName
        self.token = token
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
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
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

    var statusText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .reconnecting(let attempt):
            return "Reconnecting (\(attempt))..."
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}
