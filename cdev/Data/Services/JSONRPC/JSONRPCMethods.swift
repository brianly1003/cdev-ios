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

    // Client operations (multi-device awareness)
    static let clientSessionFocus = "client/session/focus"
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

    enum CodingKeys: String, CodingKey {
        case serverInfo = "server_info"
        case capabilities
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

/// File list response result
struct FileListResult: Codable, Sendable {
    let path: String?
    let files: [FileInfo]?
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
struct SessionStartParams: Codable, Sendable {
    let workspaceId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
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

/// Session send request parameters (send prompt to Claude)
struct SessionSendParams: Codable, Sendable {
    let sessionId: String
    let prompt: String
    let mode: String?  // "new" or "continue"

    enum CodingKeys: String, CodingKey {
        case prompt, mode
        case sessionId = "session_id"
    }

    init(sessionId: String, prompt: String, mode: String? = "continue") {
        self.sessionId = sessionId
        self.prompt = prompt
        self.mode = mode
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
struct HistorySessionInfo: Codable, Sendable, Identifiable {
    var id: String { sessionId }

    let sessionId: String
    let summary: String?
    let messageCount: Int?
    let lastUpdated: String?
    let branch: String?

    enum CodingKeys: String, CodingKey {
        case summary, branch
        case sessionId = "session_id"
        case messageCount = "message_count"
        case lastUpdated = "last_updated"
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
