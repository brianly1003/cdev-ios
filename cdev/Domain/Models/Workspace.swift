import Foundation

// MARK: - Workspace Model

/// Represents a cdev-agent workspace connection
/// Stores connection details for quick reconnection
struct Workspace: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String                    // Repository name
    let webSocketURL: URL               // ws://host:port
    let httpURL: URL                    // http://host:port
    var lastConnected: Date             // For sorting recent
    var sessionId: String?              // Last Claude session
    var branch: String?                 // Last known branch

    init(
        id: UUID = UUID(),
        name: String,
        webSocketURL: URL,
        httpURL: URL,
        lastConnected: Date = Date(),
        sessionId: String? = nil,
        branch: String? = nil
    ) {
        self.id = id
        self.name = name
        self.webSocketURL = webSocketURL
        self.httpURL = httpURL
        self.lastConnected = lastConnected
        self.sessionId = sessionId
        self.branch = branch
    }

    /// Create from ConnectionInfo
    static func from(connectionInfo: ConnectionInfo, repoName: String) -> Workspace {
        Workspace(
            name: repoName,
            webSocketURL: connectionInfo.webSocketURL,
            httpURL: connectionInfo.httpURL,
            sessionId: connectionInfo.sessionId
        )
    }

    /// Short display name
    var displayName: String {
        name.isEmpty ? "Unknown" : name
    }

    /// Host for display (e.g., "192.168.1.100")
    var hostDisplay: String {
        webSocketURL.host ?? "localhost"
    }

    /// Time since last connected
    var timeSinceConnected: String {
        let interval = Date().timeIntervalSince(lastConnected)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Workspace Connection State

/// Extended workspace with live connection state
struct WorkspaceState: Identifiable, Equatable {
    let workspace: Workspace
    var isConnected: Bool
    var claudeState: ClaudeState

    var id: UUID { workspace.id }

    init(workspace: Workspace, isConnected: Bool = false, claudeState: ClaudeState = .idle) {
        self.workspace = workspace
        self.isConnected = isConnected
        self.claudeState = claudeState
    }
}
