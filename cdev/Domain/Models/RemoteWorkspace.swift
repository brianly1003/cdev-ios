import Foundation

// MARK: - Workspace Git Info

/// Git state information returned from workspace/add
/// Allows the client to know git state without separate API calls
struct WorkspaceGitInfo: Codable, Equatable {
    let initialized: Bool           // Whether git is initialized
    let hasRemotes: Bool            // Whether remotes are configured
    let branch: String?             // Current branch name
    let ahead: Int?                 // Commits ahead of upstream
    let behind: Int?                // Commits behind upstream
    let stagedCount: Int?           // Number of staged files
    let unstagedCount: Int?         // Number of unstaged changes
    let untrackedCount: Int?        // Number of untracked files
    let state: String?              // Git state: "synced", "ahead", "behind", "diverged", etc.

    enum CodingKeys: String, CodingKey {
        case initialized, branch, ahead, behind, state
        case hasRemotes = "has_remotes"
        case stagedCount = "staged_count"
        case unstagedCount = "unstaged_count"
        case untrackedCount = "untracked_count"
    }

    /// Convert to WorkspaceGitState enum for UI
    var workspaceGitState: WorkspaceGitState {
        if !initialized {
            return .noGit
        }
        if branch == nil {
            return .gitInitialized
        }
        if !hasRemotes {
            return .noRemote
        }
        if state == nil || (ahead == nil && behind == nil) {
            return .noPush
        }
        if let state = state {
            switch state.lowercased() {
            case "synced":
                return .synced
            case "diverged":
                return .diverged
            case "conflict":
                return .conflict
            default:
                return .synced
            }
        }
        return .synced
    }
}

// MARK: - Remote Workspace

/// Remote workspace from cdev server
/// Represents a directory (git or non-git) configured on the server
/// Single-port architecture: all workspaces share port 8766
struct RemoteWorkspace: Codable, Identifiable, Equatable, Hashable {
    let id: String              // "ws-abc123" - unique identifier
    let name: String            // "Backend API" - display name
    let path: String            // "/Users/dev/backend" - full path
    let autoStart: Bool         // Auto-start session on server launch
    let createdAt: Date?        // When workspace was registered
    var sessions: [Session]     // Active Claude sessions for this workspace
    let activeSessionId: String? // Currently active session ID (for multi-device)
    let git: WorkspaceGitInfo?  // Git state info (from workspace/add response)

    enum CodingKeys: String, CodingKey {
        case id, name, path, sessions, git
        case autoStart = "auto_start"
        case createdAt = "created_at"
        case activeSessionId = "active_session_id"
    }

    // MARK: - Init with defaults

    init(
        id: String,
        name: String,
        path: String,
        autoStart: Bool = false,
        createdAt: Date? = nil,
        sessions: [Session] = [],
        activeSessionId: String? = nil,
        git: WorkspaceGitInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.autoStart = autoStart
        self.createdAt = createdAt
        self.sessions = sessions
        self.activeSessionId = activeSessionId
        self.git = git
    }

    // MARK: - Custom Decoder (handles missing sessions and date formats)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false

        // Parse createdAt with flexible ISO8601 format (server sends string)
        if let dateString = try? container.decode(String.self, forKey: .createdAt) {
            createdAt = Self.parseDate(from: dateString)
        } else {
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        }

        // Sessions may be missing from workspace/add response - default to empty array
        sessions = try container.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        activeSessionId = try container.decodeIfPresent(String.self, forKey: .activeSessionId)

        // Git info from workspace/add response
        git = try container.decodeIfPresent(WorkspaceGitInfo.self, forKey: .git)
    }

    /// Parse date from string with flexible ISO8601 format
    private static func parseDate(from dateString: String) -> Date? {
        // Try with fractional seconds first (e.g., "2025-12-25T04:37:28.852943Z")
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: dateString) {
            return date
        }

        // Try without fractional seconds (e.g., "2025-12-25T04:50:30+07:00")
        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]
        return formatterWithoutFractional.date(from: dateString)
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

/// A Claude CLI session for a workspace
/// Can be either running (active) or historical (past session)
/// Multiple sessions can exist per workspace (different conversations)
struct Session: Codable, Identifiable, Equatable, Hashable {
    let id: String                  // Session identifier (UUID)
    let workspaceId: String         // Parent workspace ID
    let status: SessionStatus       // "running" or "historical"

    // Running session fields
    let startedAt: Date?            // When session started (running only)
    let lastActive: Date?           // Last activity timestamp (running only)

    // Historical session fields
    let summary: String?            // First prompt summary (historical only)
    let messageCount: Int?          // Number of messages (historical only)
    let lastUpdated: Date?          // Last updated time (historical only)

    // Runtime state (from session/state call)
    let claudeState: String?        // "idle", "running", "waiting"
    let claudeSessionId: String?    // Claude's internal session ID
    let isRunning: Bool?            // Whether Claude process is running
    let waitingForInput: Bool?      // Waiting for user response
    let pendingToolUseId: String?   // Tool use ID if waiting for permission
    let pendingToolName: String?    // Tool name if waiting for permission

    // Multi-device awareness
    let viewers: [String]?          // Client IDs currently viewing this session

    enum CodingKeys: String, CodingKey {
        case id, status, viewers, summary
        case workspaceId = "workspace_id"
        case startedAt = "started_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
        case lastUpdated = "last_updated"
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
        summary: String? = nil,
        messageCount: Int? = nil,
        lastUpdated: Date? = nil,
        claudeState: String? = nil,
        claudeSessionId: String? = nil,
        isRunning: Bool? = nil,
        waitingForInput: Bool? = nil,
        pendingToolUseId: String? = nil,
        pendingToolName: String? = nil,
        viewers: [String]? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.status = status
        self.startedAt = startedAt
        self.lastActive = lastActive
        self.summary = summary
        self.messageCount = messageCount
        self.lastUpdated = lastUpdated
        self.claudeState = claudeState
        self.claudeSessionId = claudeSessionId
        self.isRunning = isRunning
        self.waitingForInput = waitingForInput
        self.pendingToolUseId = pendingToolUseId
        self.pendingToolName = pendingToolName
        self.viewers = viewers
    }

    // MARK: - Custom Decoder (handles different date formats)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        status = try container.decode(SessionStatus.self, forKey: .status)

        // Parse dates with flexible ISO8601 format
        startedAt = Self.parseOptionalDate(from: container, forKey: .startedAt)
        lastActive = Self.parseOptionalDate(from: container, forKey: .lastActive)
        lastUpdated = Self.parseOptionalDate(from: container, forKey: .lastUpdated)

        // Historical session fields
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount)

        // Runtime state
        claudeState = try container.decodeIfPresent(String.self, forKey: .claudeState)
        claudeSessionId = try container.decodeIfPresent(String.self, forKey: .claudeSessionId)
        isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning)
        waitingForInput = try container.decodeIfPresent(Bool.self, forKey: .waitingForInput)
        pendingToolUseId = try container.decodeIfPresent(String.self, forKey: .pendingToolUseId)
        pendingToolName = try container.decodeIfPresent(String.self, forKey: .pendingToolName)

        // Multi-device
        viewers = try container.decodeIfPresent([String].self, forKey: .viewers)
    }

    /// Parse date from string with flexible ISO8601 format
    private static func parseOptionalDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        guard let dateString = try? container.decode(String.self, forKey: key) else {
            return nil
        }

        // Try with fractional seconds first (e.g., "2025-12-25T04:37:57.156106Z")
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: dateString) {
            return date
        }

        // Try without fractional seconds (e.g., "2025-12-25T04:50:30+07:00")
        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]
        return formatterWithoutFractional.date(from: dateString)
    }

    // MARK: - Computed Properties

    /// Display summary - use summary for historical, or generate for running
    var displaySummary: String {
        if let summary = summary, !summary.isEmpty {
            return summary
        }
        return status == .running ? "Active session" : "Session"
    }

    /// Most recent activity date (from lastActive, lastUpdated, or startedAt)
    var mostRecentDate: Date? {
        lastActive ?? lastUpdated ?? startedAt
    }

    /// Viewer count
    var viewerCount: Int {
        viewers?.count ?? 0
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
/// - running: Active Claude CLI process, can use session/send
/// - historical: Past session from ~/.claude/projects/, must resume with session/start + resume_session_id
enum SessionStatus: String, Codable, Equatable {
    case running    // Session is active - can send prompts directly
    case historical // Past session - must resume first
    case stopped    // Session ended (legacy)
    case starting   // Session is starting
    case stopping   // Session is stopping
    case error      // Session failed

    /// User-friendly display text
    var displayText: String {
        switch self {
        case .running: return "Running"
        case .historical: return "Historical"
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
        case .historical: return "clock.arrow.circlepath"
        case .stopped: return "stop.circle"
        case .starting, .stopping: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// Whether prompts can be sent to this session directly
    var canSendPrompts: Bool {
        self == .running
    }

    /// Whether this session needs to be resumed before sending prompts
    var needsResume: Bool {
        self == .historical || self == .stopped
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
/// Includes cache metadata for cache-first strategy
struct DiscoveryResponse: Codable {
    let repositories: [DiscoveredRepository]
    let count: Int

    // Cache metadata (from enterprise discovery engine)
    let cached: Bool?                    // Whether results came from cache
    let cacheAgeSeconds: Int64?          // Age of cache in seconds
    let refreshInProgress: Bool?         // Whether background refresh is running
    let elapsedMs: Int64?                // Time taken for this request
    let scannedPaths: Int?               // Number of directories scanned
    let skippedPaths: Int?               // Number of directories skipped

    enum CodingKeys: String, CodingKey {
        case repositories, count, cached
        case cacheAgeSeconds = "cache_age_seconds"
        case refreshInProgress = "refresh_in_progress"
        case elapsedMs = "elapsed_ms"
        case scannedPaths = "scanned_paths"
        case skippedPaths = "skipped_paths"
    }

    /// Whether the data is from cache
    var isCached: Bool { cached ?? false }

    /// Whether a background refresh is happening
    var isRefreshing: Bool { refreshInProgress ?? false }

    /// Human-readable cache age
    var cacheAgeDescription: String? {
        guard let age = cacheAgeSeconds, age > 0 else { return nil }
        if age < 60 { return "\(age)s ago" }
        if age < 3600 { return "\(age / 60)m ago" }
        return "\(age / 3600)h ago"
    }

    /// Whether cache is considered stale (> 1 hour)
    var isCacheStale: Bool {
        guard let age = cacheAgeSeconds else { return false }
        return age > 3600 // 1 hour
    }
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

    // Historical session fields
    let summary: String?
    let messageCount: Int?
    let lastUpdated: Date?

    // Runtime state
    let claudeState: String?
    let claudeSessionId: String?
    let isRunning: Bool?
    let waitingForInput: Bool?
    let pendingToolUseId: String?
    let pendingToolName: String?

    // Multi-device awareness
    let viewers: [String]?

    enum CodingKeys: String, CodingKey {
        case id, status, viewers, summary
        case workspaceId = "workspace_id"
        case startedAt = "started_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
        case lastUpdated = "last_updated"
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
            summary: summary,
            messageCount: messageCount,
            lastUpdated: lastUpdated,
            claudeState: claudeState,
            claudeSessionId: claudeSessionId,
            isRunning: isRunning,
            waitingForInput: waitingForInput,
            pendingToolUseId: pendingToolUseId,
            pendingToolName: pendingToolName,
            viewers: viewers
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
