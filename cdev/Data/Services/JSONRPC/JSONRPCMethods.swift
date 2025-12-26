import Foundation

// MARK: - JSON-RPC Method Names

/// JSON-RPC method names for cdev unified API
enum JSONRPCMethod {
    // Lifecycle
    static let initialize = "initialize"
    static let initialized = "initialized"  // Notification after init
    static let shutdown = "shutdown"

    // Agent operations (DEPRECATED - use session/* methods for multi-workspace)
    static let agentRun = "agent/run"
    static let agentStop = "agent/stop"
    static let agentRespond = "agent/respond"
    static let agentStatus = "agent/status"

    // Session control (NEW - multi-workspace aware)
    static let sessionStart = "session/start"
    static let sessionSend = "session/send"
    static let sessionStop = "session/stop"
    static let sessionRespond = "session/respond"
    static let sessionInput = "session/input"  // PTY mode: send input/key to interactive session
    static let sessionState = "session/state"
    static let sessionActive = "session/active"

    // Workspace operations
    static let workspaceList = "workspace/list"
    static let workspaceGet = "workspace/get"
    static let workspaceAdd = "workspace/add"
    static let workspaceRemove = "workspace/remove"
    static let workspaceSubscribe = "workspace/subscribe"
    static let workspaceUnsubscribe = "workspace/unsubscribe"
    static let workspaceSubscriptions = "workspace/subscriptions"
    static let workspaceSubscribeAll = "workspace/subscribeAll"
    static let workspaceStatus = "workspace/status"
    // Workspace Git operations (NEW - multi-workspace aware)
    static let workspaceGitStatus = "workspace/git/status"
    static let workspaceGitDiff = "workspace/git/diff"
    static let workspaceGitStage = "workspace/git/stage"
    static let workspaceGitUnstage = "workspace/git/unstage"
    static let workspaceGitDiscard = "workspace/git/discard"
    static let workspaceGitCommit = "workspace/git/commit"
    static let workspaceGitPush = "workspace/git/push"
    static let workspaceGitPull = "workspace/git/pull"
    static let workspaceGitBranches = "workspace/git/branches"
    static let workspaceGitCheckout = "workspace/git/checkout"

    // Status
    static let statusGet = "status/get"
    static let statusHealth = "status/health"

    // Git operations
    static let gitStatus = "git/status"
    static let gitDiff = "git/diff"
    static let gitStage = "git/stage"
    static let gitUnstage = "git/unstage"
    static let gitDiscard = "git/discard"
    static let gitCommit = "git/commit"
    static let gitPush = "git/push"
    static let gitPull = "git/pull"
    static let gitBranches = "git/branches"
    static let gitCheckout = "git/checkout"

    // File operations
    static let fileGet = "file/get"
    static let fileList = "file/list"

    // Session operations (legacy - single workspace)
    static let sessionList = "session/list"
    static let sessionGet = "session/get"
    static let sessionMessages = "session/messages"
    static let sessionElements = "session/elements"
    static let sessionWatch = "session/watch"
    static let sessionUnwatch = "session/unwatch"
    static let sessionDelete = "session/delete"

    // Session history (legacy - kept for backward compatibility)
    static let sessionHistory = "session/history"

    // Workspace session operations (NEW - workspace-aware)
    static let workspaceSessionHistory = "workspace/session/history"
    static let workspaceSessionMessages = "workspace/session/messages"
    static let workspaceSessionWatch = "workspace/session/watch"
    static let workspaceSessionUnwatch = "workspace/session/unwatch"
    static let workspaceSessionActivate = "workspace/session/activate"

    // Client operations (multi-device awareness)
    static let clientSessionFocus = "client/session/focus"

    // Repository operations (file indexing and search)
    static let repositoryIndexStatus = "repository/index/status"
    static let repositorySearch = "repository/search"
    static let repositoryFilesList = "repository/files/list"
    static let repositoryFilesTree = "repository/files/tree"
    static let repositoryStats = "repository/stats"
    static let repositoryIndexRebuild = "repository/index/rebuild"
}

// MARK: - Initialize

/// Client info sent during initialize handshake
struct ClientInfo: Codable, Sendable {
    let name: String
    let version: String

    static var cdevIOS: ClientInfo {
        ClientInfo(
            name: "cdev-ios",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        )
    }
}

/// Initialize request parameters
struct InitializeParams: Codable, Sendable {
    let clientInfo: ClientInfo?
    let capabilities: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case clientInfo = "client_info"
        case capabilities
    }
}

/// Server info returned from initialize
struct ServerInfo: Codable, Sendable {
    let name: String
    let version: String
}

/// Server capabilities returned from initialize
struct ServerCapabilities: Codable, Sendable {
    let agents: [String]?
    let features: [String]?
}

/// Initialize response result
struct InitializeResult: Codable, Sendable {
    let serverInfo: ServerInfo?
    let capabilities: ServerCapabilities?
    /// Unique client ID assigned by server for multi-device awareness
    let clientId: String?

    enum CodingKeys: String, CodingKey {
        case serverInfo = "server_info"
        case capabilities
        case clientId
    }
}

// MARK: - Agent Run

/// Agent run request parameters
struct AgentRunParams: Codable, Sendable {
    let prompt: String
    let mode: String?
    let sessionId: String?
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case prompt, mode
        case sessionId = "session_id"
        case agentType = "agent_type"
    }

    init(prompt: String, mode: String? = "new", sessionId: String? = nil, agentType: String? = nil) {
        self.prompt = prompt
        self.mode = mode
        self.sessionId = sessionId
        self.agentType = agentType
    }
}

/// Agent run response result
struct AgentRunResult: Codable, Sendable {
    let status: String
    let sessionId: String?
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case status
        case sessionId = "session_id"
        case agentType = "agent_type"
    }
}

// MARK: - Agent Stop

/// Agent stop response result
struct AgentStopResult: Codable, Sendable {
    let status: String
}

// MARK: - Agent Respond

/// Agent respond request parameters
struct AgentRespondParams: Codable, Sendable {
    let toolUseId: String
    let response: String
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case response
        case toolUseId = "tool_use_id"
        case isError = "is_error"
    }

    init(toolUseId: String, response: String, isError: Bool = false) {
        self.toolUseId = toolUseId
        self.response = response
        self.isError = isError
    }
}

/// Agent respond response result
struct AgentRespondResult: Codable, Sendable {
    let status: String
    let toolUseId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case toolUseId = "tool_use_id"
    }
}

/// Agent status response result
struct AgentStatusResult: Codable, Sendable {
    let state: String?
    let sessionId: String?
    let agentType: String?
    let isRunning: Bool?

    enum CodingKeys: String, CodingKey {
        case state
        case sessionId = "session_id"
        case agentType = "agent_type"
        case isRunning = "is_running"
    }
}

// MARK: - Shutdown

/// Shutdown response result
struct ShutdownResult: Codable, Sendable {
    let status: String?
}

// MARK: - Status

/// Status get response result
struct StatusGetResult: Codable, Sendable {
    let sessionId: String?
    let agentSessionId: String?
    let agentState: String?
    let agentType: String?
    let connectedClients: Int?
    let repoPath: String?
    let repoName: String?
    let uptimeSeconds: Int?
    let version: String?
    let watcherEnabled: Bool?
    let gitEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentSessionId = "agent_session_id"
        case agentState = "agent_state"
        case agentType = "agent_type"
        case connectedClients = "connected_clients"
        case repoPath = "repo_path"
        case repoName = "repo_name"
        case uptimeSeconds = "uptime_seconds"
        case version
        case watcherEnabled = "watcher_enabled"
        case gitEnabled = "git_enabled"
    }
}

// MARK: - Git

/// File info in git status arrays
struct GitStatusFileInfo: Codable, Sendable {
    let path: String
    let status: String?
}

/// Git status response result
struct GitStatusResult: Codable, Sendable {
    let branch: String?
    let upstream: String?
    let ahead: Int?
    let behind: Int?
    let staged: [GitStatusFileInfo]?
    let unstaged: [GitStatusFileInfo]?
    let untracked: [GitStatusFileInfo]?
    let conflicted: [GitStatusFileInfo]?
    let repoName: String?
    let repoRoot: String?
    let isClean: Bool?

    enum CodingKeys: String, CodingKey {
        case branch, upstream, ahead, behind
        case staged, unstaged, untracked, conflicted
        case repoName = "repo_name"
        case repoRoot = "repo_root"
        case isClean = "is_clean"
    }
}

/// Git diff request parameters
struct GitDiffParams: Codable, Sendable {
    let path: String
}

/// Git diff response result
struct GitDiffResult: Codable, Sendable {
    let path: String?
    let diff: String?
    let isStaged: Bool?
    let isNew: Bool?

    enum CodingKeys: String, CodingKey {
        case path, diff
        case isStaged = "is_staged"
        case isNew = "is_new"
    }
}

// MARK: - File

/// File get request parameters
struct FileGetParams: Codable, Sendable {
    let path: String
}

/// File get response result
struct FileGetResult: Codable, Sendable {
    let path: String?
    let content: String?
    let encoding: String?
    let size: Int?
    let truncated: Bool?
}

// MARK: - Session

/// Session list request parameters
struct SessionListParams: Codable, Sendable {
    let agentType: String?
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case agentType = "agent_type"
        case limit
    }

    init(agentType: String? = nil, limit: Int? = nil) {
        self.agentType = agentType
        self.limit = limit
    }
}

/// Session info
struct SessionInfoResult: Codable, Sendable {
    let id: String?
    let sessionId: String?
    let agentType: String?
    let summary: String?
    let messageCount: Int?
    let startTime: String?
    let lastUpdated: String?
    let projectPath: String?

    // Server returns snake_case
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case agentType = "agent_type"
        case summary
        case messageCount = "message_count"
        case startTime = "start_time"
        case lastUpdated = "last_updated"
        case projectPath = "project_path"
    }

    /// Get the session ID (server may use either 'id' or 'session_id')
    var resolvedId: String {
        sessionId ?? id ?? ""
    }
}

/// Session list response result
struct SessionListResult: Codable, Sendable {
    let sessions: [SessionInfoResult]?
}

/// Session watch request parameters
struct SessionWatchParams: Codable, Sendable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

/// Session watch response result
struct SessionWatchResult: Codable, Sendable {
    let status: String?
    let watching: Bool?
}

/// Session unwatch response result
struct SessionUnwatchResult: Codable, Sendable {
    let status: String?
    let watching: Bool?
}

/// Session get request parameters
struct SessionGetParams: Codable, Sendable {
    let sessionId: String
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentType = "agent_type"
    }
}

/// Session messages request parameters
struct SessionMessagesParams: Codable, Sendable {
    let sessionId: String
    let agentType: String?
    let limit: Int?
    let offset: Int?
    let order: String?  // "asc" or "desc" (default: "asc")

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentType = "agent_type"
        case limit, offset, order
    }
}

/// Session messages response result
/// Note: Uses the same message format as HTTP API - full structure, not simplified
struct SessionMessagesResult: Codable, Sendable {
    let sessionId: String?
    let messages: [SessionMessagesResponse.SessionMessage]?
    let total: Int?
    let limit: Int?
    let offset: Int?
    let hasMore: Bool?
    let queryTimeMs: Double?

    enum CodingKeys: String, CodingKey {
        case messages, total, limit, offset
        case sessionId = "session_id"
        case hasMore = "has_more"
        case queryTimeMs = "query_time_ms"
    }
}

// MARK: - Git Operations (Extended)

/// Git stage/unstage/discard request parameters
struct GitPathsParams: Codable, Sendable {
    let paths: [String]
}

/// Git commit request parameters
struct GitCommitParams: Codable, Sendable {
    let message: String
    let push: Bool?
}

/// Git commit response result
struct GitCommitResult: Codable, Sendable {
    let success: Bool?
    let status: String?
    let sha: String?
    let commitHash: String?
    let message: String?
    let filesCommitted: Int?

    enum CodingKeys: String, CodingKey {
        case success, status, sha, message
        case commitHash = "commit_hash"
        case filesCommitted = "files_committed"
    }

    /// Check if commit was successful (supports both success bool and status string)
    var isSuccess: Bool {
        success == true || status == "ok"
    }

    /// Get commit hash (supports both sha and commit_hash fields)
    var resolvedCommitHash: String? {
        sha ?? commitHash
    }
}

/// Git operation result (stage, unstage, discard, push, pull)
struct GitOperationResult: Codable, Sendable {
    let success: Bool?
    let status: String?
    let message: String?
    let error: String?
    let staged: [String]?
    let unstaged: [String]?
    let discarded: [String]?

    /// Check if operation was successful (supports both success bool and status string)
    var isSuccess: Bool {
        success == true || status == "ok"
    }

    /// Get error or message for display
    var displayMessage: String? {
        error ?? message
    }
}

/// Git branches response result
struct GitBranchesResult: Codable, Sendable {
    let branches: [String]?
    let current: String?
}

/// Git checkout request parameters
struct GitCheckoutParams: Codable, Sendable {
    let branch: String
}

/// Git checkout response result
struct GitCheckoutResult: Codable, Sendable {
    let status: String?
    let branch: String?
}

// MARK: - Health

/// Health check response result
struct HealthResult: Codable, Sendable {
    let status: String?
    let healthy: Bool?
}

// MARK: - File List

/// File list request parameters
struct FileListParams: Codable, Sendable {
    let path: String?
}

/// File info in directory listing
struct FileInfo: Codable, Sendable {
    let name: String?
    let path: String?
    let type: String?  // "file" or "directory"
    let size: Int?
}

/// File list response result (matches file/list JSON-RPC response)
struct FileListResult: Codable, Sendable {
    let path: String?
    let entries: [FileInfo]?
    let totalCount: Int?

    enum CodingKeys: String, CodingKey {
        case path, entries
        case totalCount = "total_count"
    }
}

// MARK: - Session Elements

/// Session elements request parameters
struct SessionElementsParams: Codable, Sendable {
    let sessionId: String
    let agentType: String?
    let limit: Int?
    let before: String?
    let after: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentType = "agent_type"
        case limit, before, after
    }
}

/// UI element for rendering in mobile apps
struct SessionElement: Codable, Sendable {
    let id: String?
    let type: String?  // "text", "code", "tool_use", "tool_result", etc.
    let content: String?
    let timestamp: String?
    let metadata: [String: AnyCodable]?
}

/// Session elements response result
struct SessionElementsResult: Codable, Sendable {
    let sessionId: String?
    let elements: [SessionElement]?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case elements
        case hasMore = "has_more"
    }
}

// MARK: - Session Delete

/// Session delete request parameters
struct SessionDeleteParams: Codable, Sendable {
    let sessionId: String?
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentType = "agent_type"
    }
}

/// Session delete response result
struct SessionDeleteResult: Codable, Sendable {
    let status: String?
    let deleted: Int?
}

// MARK: - Session Control (Multi-Workspace)

/// Session start request parameters (starts Claude for a workspace)
/// Use resume_session_id to continue a historical session
struct SessionStartParams: Codable, Sendable {
    let workspaceId: String

    /// Historical session ID to resume (from workspace/session/history)
    /// When provided, the new session will continue where the historical session left off
    let resumeSessionId: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case resumeSessionId = "resume_session_id"
    }

    init(workspaceId: String, resumeSessionId: String? = nil) {
        self.workspaceId = workspaceId
        self.resumeSessionId = resumeSessionId
    }
}

/// Session start response result
struct SessionStartResult: Codable, Sendable {
    let id: String
    let workspaceId: String
    let status: String
    let startedAt: String?
    let lastActive: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case workspaceId = "workspace_id"
        case startedAt = "started_at"
        case lastActive = "last_active"
    }
}

/// Permission mode for session/send
/// Controls how Claude handles permission requests
enum SessionPermissionMode: String, Codable, Sendable {
    case `default` = "default"           // Normal permission prompts
    case acceptEdits = "acceptEdits"     // Auto-accept file edits
    case bypassPermissions = "bypassPermissions"  // Skip all permission checks
    case plan = "plan"                   // Plan mode
    case interactive = "interactive"     // PTY mode for terminal-like interaction
}

/// Session send request parameters (send prompt to Claude)
struct SessionSendParams: Codable, Sendable {
    let sessionId: String
    let prompt: String
    let mode: String?  // "new" or "continue"
    let permissionMode: SessionPermissionMode?  // Permission handling mode

    enum CodingKeys: String, CodingKey {
        case prompt, mode
        case sessionId = "session_id"
        case permissionMode = "permission_mode"
    }

    init(sessionId: String, prompt: String, mode: String? = "continue", permissionMode: SessionPermissionMode? = nil) {
        self.sessionId = sessionId
        self.prompt = prompt
        self.mode = mode
        self.permissionMode = permissionMode
    }
}

/// Session send response result
struct SessionSendResult: Codable, Sendable {
    let status: String
}

/// Session stop request parameters
struct SessionStopParams: Codable, Sendable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

/// Session stop response result
struct SessionStopResult: Codable, Sendable {
    let status: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case sessionId = "session_id"
    }
}

/// Session respond request parameters (for permission/question responses)
struct SessionRespondParams: Codable, Sendable {
    let sessionId: String
    let type: String  // "permission" or "question"
    let response: String  // "yes"/"no" for permission, free text for question

    enum CodingKeys: String, CodingKey {
        case type, response
        case sessionId = "session_id"
    }
}

/// Session respond response result
struct SessionRespondResult: Codable, Sendable {
    let status: String?
}

// MARK: - Session Input (PTY Mode)

/// Special key names for session/input
/// Used for PTY mode keyboard input
enum SessionInputKey: String, Codable, Sendable {
    case enter
    case `return` = "return"
    case escape
    case esc
    case up
    case down
    case left
    case right
    case tab
    case backspace
    case delete
    case home
    case end
    case pageup
    case pagedown
    case space
}

/// Session input request parameters (for PTY mode interactive input)
/// Used to send keyboard input to a session running in interactive mode
/// Either `input` (text) or `key` (special key) must be provided
struct SessionInputParams: Codable, Sendable {
    let sessionId: String
    let input: String?  // Raw text input (e.g., "1" for Yes, "2" for Yes all)
    let key: String?    // Special key name (e.g., "enter", "escape")

    enum CodingKeys: String, CodingKey {
        case input, key
        case sessionId = "session_id"
    }

    /// Create input params with text input
    init(sessionId: String, input: String) {
        self.sessionId = sessionId
        self.input = input
        self.key = nil
    }

    /// Create input params with special key
    init(sessionId: String, key: SessionInputKey) {
        self.sessionId = sessionId
        self.input = nil
        self.key = key.rawValue
    }
}

/// Session input response result
struct SessionInputResult: Codable, Sendable {
    let status: String?
    let key: String?  // Echoed back if key was sent

    var isSuccess: Bool {
        status == "sent"
    }
}

/// Session state request parameters (for reconnection sync)
struct SessionStateParams: Codable, Sendable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

/// Session state response result (runtime state for reconnection)
struct SessionStateResult: Codable, Sendable {
    let id: String?
    let workspaceId: String?
    let status: String?
    let startedAt: String?
    let lastActive: String?

    // Claude runtime state
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
}

/// Session active request parameters
struct SessionActiveParams: Codable, Sendable {
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String? = nil) {
        self.workspaceId = workspaceId
    }
}

/// Session active response result
struct SessionActiveResult: Codable, Sendable {
    let sessions: [SessionStartResult]?
}

// MARK: - Workspace Git Operations (Multi-Workspace)

/// Workspace git status request parameters
struct WorkspaceGitStatusParams: Codable, Sendable {
    let workspaceId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }
}

/// Workspace git diff request parameters
struct WorkspaceGitDiffParams: Codable, Sendable {
    let workspaceId: String
    let staged: Bool?
    let path: String?

    enum CodingKeys: String, CodingKey {
        case staged, path
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String, staged: Bool? = nil, path: String? = nil) {
        self.workspaceId = workspaceId
        self.staged = staged
        self.path = path
    }
}

/// Workspace git stage/unstage/discard request parameters
struct WorkspaceGitPathsParams: Codable, Sendable {
    let workspaceId: String
    let paths: [String]

    enum CodingKeys: String, CodingKey {
        case paths
        case workspaceId = "workspace_id"
    }
}

/// Workspace git commit request parameters
struct WorkspaceGitCommitParams: Codable, Sendable {
    let workspaceId: String
    let message: String
    let push: Bool?

    enum CodingKeys: String, CodingKey {
        case message, push
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String, message: String, push: Bool? = nil) {
        self.workspaceId = workspaceId
        self.message = message
        self.push = push
    }
}

/// Workspace git push request parameters
struct WorkspaceGitPushParams: Codable, Sendable {
    let workspaceId: String
    let force: Bool?
    let setUpstream: Bool?
    let remote: String?
    let branch: String?

    enum CodingKeys: String, CodingKey {
        case force, remote, branch
        case workspaceId = "workspace_id"
        case setUpstream = "set_upstream"
    }

    init(workspaceId: String, force: Bool? = nil, setUpstream: Bool? = nil, remote: String? = nil, branch: String? = nil) {
        self.workspaceId = workspaceId
        self.force = force
        self.setUpstream = setUpstream
        self.remote = remote
        self.branch = branch
    }
}

/// Workspace git push response result
struct WorkspaceGitPushResult: Codable, Sendable {
    let success: Bool?
    let message: String?
    let commitsPushed: Int?

    enum CodingKeys: String, CodingKey {
        case success, message
        case commitsPushed = "commits_pushed"
    }

    var isSuccess: Bool {
        success == true
    }
}

/// Workspace git pull request parameters
struct WorkspaceGitPullParams: Codable, Sendable {
    let workspaceId: String
    let rebase: Bool?

    enum CodingKeys: String, CodingKey {
        case rebase
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String, rebase: Bool? = nil) {
        self.workspaceId = workspaceId
        self.rebase = rebase
    }
}

/// Workspace git pull response result
struct WorkspaceGitPullResult: Codable, Sendable {
    let success: Bool?
    let message: String?
    let error: String?
    let conflictedFiles: [String]?

    enum CodingKeys: String, CodingKey {
        case success, message, error
        case conflictedFiles = "conflicted_files"
    }

    var isSuccess: Bool {
        success == true
    }
}

/// Workspace git branches request parameters
struct WorkspaceGitBranchesParams: Codable, Sendable {
    let workspaceId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }
}

/// Branch info in workspace git branches response
struct WorkspaceGitBranchInfo: Codable, Sendable {
    let name: String
    let isCurrent: Bool?
    let isRemote: Bool?
    let upstream: String?

    enum CodingKeys: String, CodingKey {
        case name, upstream
        case isCurrent = "is_current"
        case isRemote = "is_remote"
    }
}

/// Workspace git branches response result
struct WorkspaceGitBranchesResult: Codable, Sendable {
    let current: String?
    let upstream: String?
    let ahead: Int?
    let behind: Int?
    let branches: [WorkspaceGitBranchInfo]?
}

/// Workspace git checkout request parameters
struct WorkspaceGitCheckoutParams: Codable, Sendable {
    let workspaceId: String
    let branch: String
    let create: Bool?

    enum CodingKeys: String, CodingKey {
        case branch, create
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String, branch: String, create: Bool? = nil) {
        self.workspaceId = workspaceId
        self.branch = branch
        self.create = create
    }
}

/// Workspace git checkout response result
struct WorkspaceGitCheckoutResult: Codable, Sendable {
    let success: Bool?
    let branch: String?
    let message: String?
    let error: String?

    var isSuccess: Bool {
        success == true
    }
}

// MARK: - Session History (Workspace-Aware)

/// Session history request parameters
struct SessionHistoryParams: Codable, Sendable {
    let workspaceId: String
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case limit
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String, limit: Int? = nil) {
        self.workspaceId = workspaceId
        self.limit = limit
    }
}

/// Historical session info from session/history
/// Sessions can be "running" or "historical"
struct HistorySessionInfo: Codable, Sendable, Identifiable {
    var id: String { sessionId }

    let sessionId: String
    let summary: String?
    let messageCount: Int?
    let lastUpdated: String?
    let branch: String?

    /// Session status: "running" or "historical"
    let status: String?

    /// Workspace ID this session belongs to
    let workspaceId: String?

    /// RFC3339 timestamp when session started (running sessions only)
    let startedAt: String?

    /// RFC3339 timestamp of last activity (running sessions only)
    let lastActive: String?

    /// List of client IDs currently viewing this session (multi-device awareness)
    let viewers: [String]?

    enum CodingKeys: String, CodingKey {
        case summary, branch, status, viewers
        case sessionId = "session_id"
        case messageCount = "message_count"
        case lastUpdated = "last_updated"
        case workspaceId = "workspace_id"
        case startedAt = "started_at"
        case lastActive = "last_active"
    }

    /// Whether this is a running session that can receive prompts
    var isRunning: Bool {
        status == "running"
    }

    /// Whether this is a historical session that must be resumed first
    var isHistorical: Bool {
        status == "historical" || status == nil
    }

    /// Number of viewers
    var viewerCount: Int {
        viewers?.count ?? 0
    }
}

/// Session history response result
struct SessionHistoryResult: Codable, Sendable {
    let sessions: [HistorySessionInfo]?
    let total: Int?
}

// MARK: - Workspace Session Operations (Multi-Workspace)

/// Workspace session messages request parameters
struct WorkspaceSessionMessagesParams: Codable, Sendable {
    let workspaceId: String
    let sessionId: String
    let limit: Int?
    let offset: Int?
    let order: String?  // "asc" or "desc" (default: "asc")

    enum CodingKeys: String, CodingKey {
        case limit, offset, order
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
    }

    init(workspaceId: String, sessionId: String, limit: Int? = nil, offset: Int? = nil, order: String? = nil) {
        self.workspaceId = workspaceId
        self.sessionId = sessionId
        self.limit = limit
        self.offset = offset
        self.order = order
    }
}

/// Message info with additional fields for context compaction and meta
/// Uses the same message format as SessionMessagesResponse.SessionMessage
struct WorkspaceSessionMessage: Codable, Sendable {
    let id: Int?
    let sessionId: String?
    let type: String?
    let uuid: String?
    let timestamp: String?
    let gitBranch: String?
    let message: SessionMessagesResponse.SessionMessage.MessageContent?
    let isContextCompaction: Bool?
    let isMeta: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, uuid, timestamp, message
        case sessionId = "session_id"
        case gitBranch = "git_branch"
        case isContextCompaction = "is_context_compaction"
        case isMeta = "is_meta"
    }
}

/// Workspace session messages response result
struct WorkspaceSessionMessagesResult: Codable, Sendable {
    let sessionId: String?
    let messages: [WorkspaceSessionMessage]?
    let total: Int?
    let limit: Int?
    let offset: Int?
    let hasMore: Bool?
    let queryTimeMs: Double?

    enum CodingKeys: String, CodingKey {
        case messages, total, limit, offset
        case sessionId = "session_id"
        case hasMore = "has_more"
        case queryTimeMs = "query_time_ms"
    }
}

/// Workspace session watch request parameters
struct WorkspaceSessionWatchParams: Codable, Sendable {
    let workspaceId: String
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
    }
}

/// Workspace session watch response result
struct WorkspaceSessionWatchResult: Codable, Sendable {
    let status: String?
    let watching: Bool?
    let workspaceId: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case status, watching
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
    }
}

/// Workspace session unwatch response result
struct WorkspaceSessionUnwatchResult: Codable, Sendable {
    let status: String?
    let watching: Bool?
    let workspaceId: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case status, watching
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
    }
}

// MARK: - Workspace Status

/// Workspace status request parameters
struct WorkspaceStatusParams: Codable, Sendable {
    let workspaceId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }
}

/// Session info in workspace status response
struct WorkspaceStatusSession: Codable, Sendable, Identifiable {
    var id: String { sessionId }

    let sessionId: String
    let workspaceId: String
    let status: String
    let startedAt: String?
    let lastActive: String?

    enum CodingKeys: String, CodingKey {
        case status
        case sessionId = "id"
        case workspaceId = "workspace_id"
        case startedAt = "started_at"
        case lastActive = "last_active"
    }
}

/// Git tracker state enum
/// - healthy: Git tracker working normally
/// - unhealthy: Git operations failing
/// - unavailable: Path doesn't exist
/// - not_git: Path is not a git repository
enum GitTrackerState: String, Codable, Sendable {
    case healthy
    case unhealthy
    case unavailable
    case notGit = "not_git"

    /// Whether git operations are available
    var isAvailable: Bool {
        self == .healthy
    }
}

/// Workspace status response result
/// Returns detailed status including git tracker state, active sessions, and watch status
struct WorkspaceStatusResult: Codable, Sendable {
    // Workspace Info
    let workspaceId: String?
    let workspaceName: String?
    let path: String?
    let autoStart: Bool?
    let createdAt: String?

    // Session Info
    let sessions: [WorkspaceStatusSession]?
    let activeSessionCount: Int?
    let hasActiveSession: Bool?

    // Git Tracker
    let gitTrackerState: String?  // "healthy", "unhealthy", "unavailable", "not_git"
    let gitRepoName: String?
    let isGitRepo: Bool?
    let gitLastError: String?

    // Watch Status
    let isBeingWatched: Bool?
    let watchedSessionId: String?

    enum CodingKeys: String, CodingKey {
        case path, sessions
        case workspaceId = "workspace_id"
        case workspaceName = "workspace_name"
        case autoStart = "auto_start"
        case createdAt = "created_at"
        case activeSessionCount = "active_session_count"
        case hasActiveSession = "has_active_session"
        case gitTrackerState = "git_tracker_state"
        case gitRepoName = "git_repo_name"
        case isGitRepo = "is_git_repo"
        case gitLastError = "git_last_error"
        case isBeingWatched = "is_being_watched"
        case watchedSessionId = "watched_session_id"
    }

    /// Parsed git tracker state
    var trackerState: GitTrackerState {
        guard let state = gitTrackerState else { return .unavailable }
        return GitTrackerState(rawValue: state) ?? .unavailable
    }
}

// MARK: - Session Focus (Multi-Device Awareness)

/// Session focus request parameters
/// Used to notify server when user starts viewing a session
struct SessionFocusParams: Codable, Sendable {
    let workspaceId: String
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
    }
}

/// Session focus response result
/// Returns information about other devices viewing the same session
struct SessionFocusResult: Codable, Sendable {
    let workspaceId: String?
    let sessionId: String?
    let otherViewers: [String]?  // Client UUIDs of other devices viewing this session
    let viewerCount: Int?         // Total number of viewers (including caller)
    let success: Bool?

    enum CodingKeys: String, CodingKey {
        case success
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
        case otherViewers = "other_viewers"
        case viewerCount = "viewer_count"
    }

    /// Whether there are other viewers besides the caller
    var hasOtherViewers: Bool {
        (viewerCount ?? 0) > 1
    }
}

// MARK: - Session Activate (Workspace Session Selection)

/// Session activate request parameters
/// Used to set the active session for a workspace when user resumes a session
struct SessionActivateParams: Codable, Sendable {
    let workspaceId: String
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
    }
}

/// Session activate response result
struct SessionActivateResult: Codable, Sendable {
    let success: Bool?
    let workspaceId: String?
    let sessionId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
        case message
    }
}

// MARK: - Repository Index Status

/// Repository index status request parameters
struct RepositoryIndexStatusParams: Codable, Sendable {
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String? = nil) {
        self.workspaceId = workspaceId
    }
}

/// Repository index status response result
struct RepositoryIndexStatusResult: Codable, Sendable {
    let status: String?           // "ready", "indexing", "error"
    let progress: Double?         // 0.0 - 1.0 when indexing
    let totalFiles: Int?
    let indexedFiles: Int?
    let lastIndexedAt: String?    // ISO8601 timestamp
    let indexSizeBytes: Int64?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case status, progress
        case totalFiles = "total_files"
        case indexedFiles = "indexed_files"
        case lastIndexedAt = "last_indexed_at"
        case indexSizeBytes = "index_size_bytes"
        case errorMessage = "error_message"
    }

    /// Whether the index is ready for search
    var isReady: Bool {
        status == "ready"
    }

    /// Whether indexing is in progress
    var isIndexing: Bool {
        status == "indexing"
    }
}

// MARK: - Repository Search

/// Repository search request parameters
struct RepositorySearchParams: Codable, Sendable {
    let query: String
    let workspaceId: String?
    let mode: String?              // "fuzzy", "exact", "prefix"
    let limit: Int?
    let offset: Int?
    let excludeBinaries: Bool?
    let fileTypes: [String]?       // Filter by extension: ["swift", "ts"]

    enum CodingKeys: String, CodingKey {
        case query, mode, limit, offset
        case workspaceId = "workspace_id"
        case excludeBinaries = "exclude_binaries"
        case fileTypes = "file_types"
    }

    init(
        query: String,
        workspaceId: String? = nil,
        mode: String? = "fuzzy",
        limit: Int? = 50,
        offset: Int? = nil,
        excludeBinaries: Bool? = true,
        fileTypes: [String]? = nil
    ) {
        self.query = query
        self.workspaceId = workspaceId
        self.mode = mode
        self.limit = limit
        self.offset = offset
        self.excludeBinaries = excludeBinaries
        self.fileTypes = fileTypes
    }
}

/// Repository search result file
struct RepositorySearchFile: Codable, Sendable {
    let path: String
    let name: String
    let directory: String?
    let ext: String?
    let sizeBytes: Int64?
    let modifiedAt: String?
    let isBinary: Bool?
    let matchScore: Double?
    let lineCount: Int?

    enum CodingKeys: String, CodingKey {
        case path, name, directory
        case ext = "extension"
        case sizeBytes = "size_bytes"
        case modifiedAt = "modified_at"
        case isBinary = "is_binary"
        case matchScore = "match_score"
        case lineCount = "line_count"
    }
}

/// Repository search response result
struct RepositorySearchResult: Codable, Sendable {
    let query: String?
    let mode: String?
    let results: [RepositorySearchFile]?
    let total: Int?
    let elapsedMs: Int64?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case query, mode, results, total
        case elapsedMs = "elapsed_ms"
        case hasMore = "has_more"
    }
}

// MARK: - Repository Files List

/// Repository files list request parameters
struct RepositoryFilesListParams: Codable, Sendable {
    let workspaceId: String?
    let directory: String?         // Directory path (empty/nil for root)
    let limit: Int?
    let offset: Int?
    let includeHidden: Bool?       // Include .dotfiles

    enum CodingKeys: String, CodingKey {
        case directory, limit, offset
        case workspaceId = "workspace_id"
        case includeHidden = "include_hidden"
    }

    init(
        workspaceId: String? = nil,
        directory: String? = nil,
        limit: Int? = 500,
        offset: Int? = nil,
        includeHidden: Bool? = nil
    ) {
        self.workspaceId = workspaceId
        self.directory = directory
        self.limit = limit
        self.offset = offset
        self.includeHidden = includeHidden
    }
}

/// Repository file info (for files)
struct RepositoryFileInfo: Codable, Sendable {
    let path: String
    let name: String
    let directory: String?
    let ext: String?
    let sizeBytes: Int64?
    let modifiedAt: String?
    let isBinary: Bool?
    let isSensitive: Bool?
    let gitTracked: Bool?
    let gitIgnored: Bool?
    let isSymlink: Bool?
    let lineCount: Int?
    let indexedAt: String?

    enum CodingKeys: String, CodingKey {
        case path, name, directory
        case ext = "extension"
        case sizeBytes = "size_bytes"
        case modifiedAt = "modified_at"
        case isBinary = "is_binary"
        case isSensitive = "is_sensitive"
        case gitTracked = "git_tracked"
        case gitIgnored = "git_ignored"
        case isSymlink = "is_symlink"
        case lineCount = "line_count"
        case indexedAt = "indexed_at"
    }
}

/// Repository directory info (for directories)
struct RepositoryDirectoryInfo: Codable, Sendable {
    let path: String
    let name: String
    let fileCount: Int?
    let totalSizeBytes: Int64?
    let lastModified: String?

    enum CodingKeys: String, CodingKey {
        case path, name
        case fileCount = "file_count"
        case totalSizeBytes = "total_size_bytes"
        case lastModified = "last_modified"
    }
}

/// Repository files list response result
struct RepositoryFilesListResult: Codable, Sendable {
    let directory: String?
    let files: [RepositoryFileInfo]?
    let directories: [RepositoryDirectoryInfo]?
    let totalFiles: Int?
    let totalDirectories: Int?
    let pagination: RepositoryPagination?

    enum CodingKeys: String, CodingKey {
        case directory, files, directories, pagination
        case totalFiles = "total_files"
        case totalDirectories = "total_directories"
    }

    /// Safe accessor for files
    var safeFiles: [RepositoryFileInfo] { files ?? [] }

    /// Safe accessor for directories
    var safeDirectories: [RepositoryDirectoryInfo] { directories ?? [] }
}

/// Pagination info
struct RepositoryPagination: Codable, Sendable {
    let limit: Int?
    let offset: Int?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case limit, offset
        case hasMore = "has_more"
    }
}

// MARK: - Repository Files Tree

/// Repository files tree request parameters
struct RepositoryFilesTreeParams: Codable, Sendable {
    let workspaceId: String?
    let path: String?              // Root path (nil for repo root)
    let depth: Int?                // Max depth to traverse
    let includeHidden: Bool?

    enum CodingKeys: String, CodingKey {
        case path, depth
        case workspaceId = "workspace_id"
        case includeHidden = "include_hidden"
    }

    init(
        workspaceId: String? = nil,
        path: String? = nil,
        depth: Int? = 3,
        includeHidden: Bool? = nil
    ) {
        self.workspaceId = workspaceId
        self.path = path
        self.depth = depth
        self.includeHidden = includeHidden
    }
}

/// Tree node representing a file or directory
struct RepositoryTreeNode: Codable, Sendable, Identifiable {
    var id: String { path }

    let path: String
    let name: String
    let type: String               // "file" or "directory"
    let children: [RepositoryTreeNode]?
    let sizeBytes: Int64?
    let modifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case path, name, type, children
        case sizeBytes = "size_bytes"
        case modifiedAt = "modified_at"
    }

    var isDirectory: Bool { type == "directory" }
    var isFile: Bool { type == "file" }
}

/// Repository files tree response result
struct RepositoryFilesTreeResult: Codable, Sendable {
    let root: RepositoryTreeNode?
    let totalNodes: Int?
    let maxDepthReached: Bool?

    enum CodingKeys: String, CodingKey {
        case root
        case totalNodes = "total_nodes"
        case maxDepthReached = "max_depth_reached"
    }
}

// MARK: - Repository Stats

/// Repository stats request parameters
struct RepositoryStatsParams: Codable, Sendable {
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String? = nil) {
        self.workspaceId = workspaceId
    }
}

/// Language statistics
struct RepositoryLanguageStat: Codable, Sendable {
    let language: String
    let files: Int?
    let lines: Int?
    let bytes: Int64?
    let percentage: Double?
}

/// Repository stats response result
struct RepositoryStatsResult: Codable, Sendable {
    let totalFiles: Int?
    let totalDirectories: Int?
    let totalSizeBytes: Int64?
    let totalLines: Int?
    let languages: [RepositoryLanguageStat]?
    let largestFiles: [RepositoryFileInfo]?
    let recentlyModified: [RepositoryFileInfo]?

    enum CodingKeys: String, CodingKey {
        case languages
        case totalFiles = "total_files"
        case totalDirectories = "total_directories"
        case totalSizeBytes = "total_size_bytes"
        case totalLines = "total_lines"
        case largestFiles = "largest_files"
        case recentlyModified = "recently_modified"
    }
}

// MARK: - Repository Index Rebuild

/// Repository index rebuild request parameters
struct RepositoryIndexRebuildParams: Codable, Sendable {
    let workspaceId: String?
    let force: Bool?               // Force full rebuild even if index exists

    enum CodingKeys: String, CodingKey {
        case force
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String? = nil, force: Bool? = nil) {
        self.workspaceId = workspaceId
        self.force = force
    }
}

/// Repository index rebuild response result
struct RepositoryIndexRebuildResult: Codable, Sendable {
    let status: String?            // "started", "queued", "already_indexing"
    let message: String?

    /// Whether rebuild was started or queued
    var isStarted: Bool {
        status == "started" || status == "queued"
    }
}
