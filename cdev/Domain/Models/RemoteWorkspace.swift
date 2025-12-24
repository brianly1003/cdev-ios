import Foundation

// MARK: - Remote Workspace

/// Remote workspace from cdev server
/// Represents a git repository configured on the server
/// Single-port architecture: all workspaces share port 8766
struct RemoteWorkspace: Codable, Identifiable, Equatable, Hashable {
    let id: String              // "ws-abc123" - unique identifier
    let name: String            // "Backend API" - display name
    let path: String            // "/Users/dev/backend" - full path
    let autoStart: Bool         // Auto-start session on server launch
    let createdAt: Date?        // When workspace was registered
    var sessions: [Session]     // Active Claude sessions for this workspace

    enum CodingKeys: String, CodingKey {
        case id, name, path, sessions
        case autoStart = "auto_start"
        case createdAt = "created_at"
    }

    // MARK: - Init with defaults

    init(
        id: String,
        name: String,
        path: String,
        autoStart: Bool = false,
        createdAt: Date? = nil,
        sessions: [Session] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.autoStart = autoStart
        self.createdAt = createdAt
        self.sessions = sessions
    }

    // MARK: - Custom Decoder (handles missing sessions from workspace/add response)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        // Sessions may be missing from workspace/add response - default to empty array
        sessions = try container.decodeIfPresent([Session].self, forKey: .sessions) ?? []
    }

    // MARK: - Computed Properties

    /// Number of active sessions
    var activeSessionCount: Int {
        sessions.filter { $0.status == .running }.count
    }

    /// Whether this workspace has at least one active session
    var hasActiveSession: Bool {
        activeSessionCount > 0
    }

    /// Short path for display (just the folder name)
    var shortPath: String {
        (path as NSString).lastPathComponent
    }

    /// Most recent active session (for quick access)
    var activeSession: Session? {
        sessions.first { $0.status == .running }
    }

    /// Most recently active session (running or not)
    var mostRecentSession: Session? {
        sessions.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }.first
    }

    // MARK: - Hashable (for Set operations)

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RemoteWorkspace, rhs: RemoteWorkspace) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Session

/// An active Claude CLI instance for a workspace
/// Multiple sessions can exist per workspace (different conversations)
struct Session: Codable, Identifiable, Equatable, Hashable {
    let id: String                  // "sess-xyz789" - session identifier
    let workspaceId: String         // "ws-abc123" - parent workspace
    let status: SessionStatus       // Current state
    let startedAt: Date?            // When session started
    let lastActive: Date?           // Last activity timestamp

    // Runtime state (from session/state call)
    let claudeState: String?        // "idle", "running", "waiting"
    let claudeSessionId: String?    // Claude's internal session ID
    let isRunning: Bool?            // Whether Claude process is running
    let waitingForInput: Bool?      // Waiting for user response
    let pendingToolUseId: String?   // Tool use ID if waiting for permission
    let pendingToolName: String?    // Tool name if waiting for permission

    enum CodingKeys: String, CodingKey {
        case id, status
        case workspaceId = "workspace_id"
        case startedAt = "started_at"
        case lastActive = "last_active"
        case claudeState = "claude_state"
        case claudeSessionId = "claude_session_id"
        case isRunning = "is_running"
        case waitingForInput = "waiting_for_input"
        case pendingToolUseId = "pending_tool_use_id"
        case pendingToolName = "pending_tool_name"
    }

    // MARK: - Init with defaults

    init(
        id: String,
        workspaceId: String,
        status: SessionStatus = .running,
        startedAt: Date? = nil,
        lastActive: Date? = nil,
        claudeState: String? = nil,
        claudeSessionId: String? = nil,
        isRunning: Bool? = nil,
        waitingForInput: Bool? = nil,
        pendingToolUseId: String? = nil,
        pendingToolName: String? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.status = status
        self.startedAt = startedAt
        self.lastActive = lastActive
        self.claudeState = claudeState
        self.claudeSessionId = claudeSessionId
        self.isRunning = isRunning
        self.waitingForInput = waitingForInput
        self.pendingToolUseId = pendingToolUseId
        self.pendingToolName = pendingToolName
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Session Status

/// Status of a session (Claude instance)
enum SessionStatus: String, Codable, Equatable {
    case running    // Session is active
    case stopped    // Session ended
    case starting   // Session is starting
    case stopping   // Session is stopping
    case error      // Session failed

    /// User-friendly display text
    var displayText: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .stopping: return "Stopping..."
        case .error: return "Error"
        }
    }

    /// SF Symbol icon for status
    var iconName: String {
        switch self {
        case .running: return "checkmark.circle.fill"
        case .stopped: return "stop.circle"
        case .starting, .stopping: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Discovered Repository

/// Git repository discovered on the user's laptop
/// Used in the setup flow for adding new workspaces
struct DiscoveredRepository: Codable, Identifiable, Equatable {
    var id: String { path }     // Path is unique identifier

    let name: String            // Repository/folder name
    let path: String            // Full path
    let remoteUrl: String?      // Git remote URL (if available)
    let lastModified: Date?     // Last modification time
    let isConfigured: Bool      // Already added as workspace

    enum CodingKeys: String, CodingKey {
        case name, path
        case remoteUrl = "remote_url"
        case lastModified = "last_modified"
        case isConfigured = "is_configured"
    }

    /// Short path for display
    var shortPath: String {
        (path as NSString).lastPathComponent
    }

    /// GitHub/GitLab repo name from remote URL
    var repoName: String? {
        guard let url = remoteUrl else { return nil }
        // Extract repo name from URLs like:
        // https://github.com/user/repo.git
        // git@github.com:user/repo.git
        let cleaned = url
            .replacingOccurrences(of: ".git", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
        return cleaned.components(separatedBy: "/").last
    }
}

// MARK: - Server Connection

/// Connection info for cdev server
/// Single-port architecture: everything on port 8766
struct ServerConnection: Codable, Identifiable, Equatable {
    let id: UUID
    let host: String            // IP address or hostname
    var name: String?           // User-given name (e.g., "MacBook Pro")
    var lastConnected: Date     // For sorting recent connections

    /// Server port (always 8766 in single-port architecture)
    static let serverPort: Int = 8766

    init(id: UUID = UUID(), host: String, name: String? = nil, lastConnected: Date = Date()) {
        self.id = id
        self.host = host
        self.name = name
        self.lastConnected = lastConnected
    }

    /// Display name (user-given or host)
    var displayName: String {
        name ?? host
    }

    /// WebSocket URL for server connection
    func webSocketURL(isLocal: Bool) -> URL? {
        let scheme = isLocal ? "ws" : "wss"
        if isLocal {
            return URL(string: "\(scheme)://\(host):\(Self.serverPort)/ws")
        } else {
            // Public hostnames (dev tunnels) include port in subdomain
            return URL(string: "\(scheme)://\(host)/ws")
        }
    }

    /// HTTP URL for REST API calls
    func httpURL(isLocal: Bool) -> URL? {
        let scheme = isLocal ? "http" : "https"
        if isLocal {
            return URL(string: "\(scheme)://\(host):\(Self.serverPort)")
        } else {
            return URL(string: "\(scheme)://\(host)")
        }
    }
}

// MARK: - Legacy Type Aliases (for gradual migration)

/// Deprecated: Use ServerConnection instead
typealias ManagerConnection = ServerConnection

// MARK: - Workspace List Response

/// Response from workspace/list JSON-RPC method
struct WorkspaceListResponse: Codable {
    let workspaces: [RemoteWorkspace]
}

// MARK: - Discovery Response

/// Response from workspace/discover JSON-RPC method
struct DiscoveryResponse: Codable {
    let repositories: [DiscoveredRepository]
    let count: Int
}

// MARK: - Session Responses

/// Response from session/start JSON-RPC method
struct SessionStartResponse: Codable {
    let id: String
    let workspaceId: String
    let status: SessionStatus
    let startedAt: Date?
    let lastActive: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case workspaceId = "workspace_id"
        case startedAt = "started_at"
        case lastActive = "last_active"
    }
}

/// Response from session/state JSON-RPC method (for reconnection)
struct SessionStateResponse: Codable {
    let id: String
    let workspaceId: String
    let status: SessionStatus
    let startedAt: Date?
    let lastActive: Date?

    // Runtime state
    let claudeState: String?
    let claudeSessionId: String?
    let isRunning: Bool?
    let waitingForInput: Bool?
    let pendingToolUseId: String?
    let pendingToolName: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case workspaceId = "workspace_id"
        case startedAt = "started_at"
        case lastActive = "last_active"
        case claudeState = "claude_state"
        case claudeSessionId = "claude_session_id"
        case isRunning = "is_running"
        case waitingForInput = "waiting_for_input"
        case pendingToolUseId = "pending_tool_use_id"
        case pendingToolName = "pending_tool_name"
    }

    /// Convert to Session model
    func toSession() -> Session {
        Session(
            id: id,
            workspaceId: workspaceId,
            status: status,
            startedAt: startedAt,
            lastActive: lastActive,
            claudeState: claudeState,
            claudeSessionId: claudeSessionId,
            isRunning: isRunning,
            waitingForInput: waitingForInput,
            pendingToolUseId: pendingToolUseId,
            pendingToolName: pendingToolName
        )
    }
}

/// Response from session/send JSON-RPC method
struct SessionSendResponse: Codable {
    let status: String  // "sent"
}

/// Response from session/active JSON-RPC method
struct ActiveSessionsResponse: Codable {
    let sessions: [Session]
}

// MARK: - Subscription Responses

/// Response from workspace/subscribe JSON-RPC method
struct WorkspaceSubscribeResponse: Codable {
    let success: Bool
    let workspaceId: String
    let subscribed: [String]  // List of currently subscribed workspace IDs

    enum CodingKeys: String, CodingKey {
        case success
        case workspaceId = "workspace_id"
        case subscribed
    }
}

/// Response from workspace/subscriptions JSON-RPC method
struct WorkspaceSubscriptionsResponse: Codable {
    let workspaces: [String]  // Subscribed workspace IDs
    let isFiltering: Bool     // Whether filtering is active
    let count: Int            // Number of subscriptions

    enum CodingKeys: String, CodingKey {
        case workspaces
        case isFiltering = "is_filtering"
        case count
    }
}
