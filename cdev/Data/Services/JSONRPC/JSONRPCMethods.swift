import Foundation

// MARK: - JSON-RPC Method Names

/// JSON-RPC method names for cdev unified API
enum JSONRPCMethod {
    // Lifecycle
    static let initialize = "initialize"
    static let initialized = "initialized"  // Notification after init
    static let shutdown = "shutdown"

    // Session control (multi-workspace aware)
    static let sessionStart = "session/start"
    static let sessionSend = "session/send"
    static let sessionStop = "session/stop"
    static let sessionRespond = "session/respond"
    static let sessionInput = "session/input"  // PTY mode: send input/key to interactive session
    static let sessionState = "session/state"
    static let sessionActive = "session/active"

    // Permission operations (hook bridge mode)
    static let permissionRespond = "permission/respond"  // Respond to hook bridge permission request

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
    static let workspaceDiscover = "workspace/discover"
    // Workspace Git operations (multi-workspace aware)
    // Note: All git/* methods require workspace_id parameter
    static let workspaceGitStatus = "git/status"
    static let workspaceGitDiff = "git/diff"
    static let workspaceGitStage = "git/stage"
    static let workspaceGitUnstage = "git/unstage"
    static let workspaceGitDiscard = "git/discard"
    static let workspaceGitCommit = "git/commit"
    static let workspaceGitPush = "git/push"
    static let workspaceGitPull = "git/pull"
    static let workspaceGitUpstreamSet = "git/upstream/set"
    static let workspaceGitBranches = "git/branches"
    static let workspaceGitCheckout = "git/checkout"
    // Git setup operations (init, remote management)
    static let workspaceGitInit = "git/init"
    static let workspaceGitRemoteAdd = "git/remote/add"
    static let workspaceGitRemoteRemove = "git/remote/remove"
    static let workspaceGitRemoteList = "git/remote/list"
    // Git state (workspace git configuration state)
    static let workspaceGitState = "git/state"
    // Git log (commit history)
    static let workspaceGitLog = "git/log"
    static let workspaceGitFetch = "git/fetch"
    // Git branch operations
    static let workspaceGitBranchDelete = "git/branch/delete"

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

    // File operations (single-repo mode)
    static let fileGet = "file/get"
    static let fileList = "file/list"

    // File operations (multi-workspace mode)
    static let workspaceFileGet = "workspace/file/get"

    // Workspace session operations (workspace-aware)
    static let workspaceSessionHistory = "workspace/session/history"
    static let workspaceSessionMessages = "workspace/session/messages"
    static let workspaceSessionWatch = "workspace/session/watch"
    static let workspaceSessionUnwatch = "workspace/session/unwatch"
    static let workspaceSessionActivate = "workspace/session/activate"
    static let workspaceSessionDelete = "workspace/session/delete"

    // Agent session operations (multi-agent)
    static let sessionList = "session/list"
    static let sessionMessages = "session/messages"
    static let sessionDelete = "session/delete"
    static let sessionWatch = "session/watch"
    static let sessionUnwatch = "session/unwatch"

    // Client operations (multi-device awareness)
    static let clientSessionFocus = "client/session/focus"

    // Repository operations (file indexing and search)
    static let repositoryIndexStatus = "repository/index/status"
    static let repositorySearch = "repository/search"
    static let workspaceFilesList = "workspace/files/list"
    static let repositoryFilesTree = "repository/files/tree"
    static let repositoryStats = "repository/stats"
    static let repositoryIndexRebuild = "repository/index/rebuild"
}

// MARK: - Runtime Capability Registry

/// Server-driven runtime capability registry from initialize.capabilities.runtimeRegistry.
/// All fields are optional/tolerant so older servers and future schema extensions remain compatible.
struct RuntimeCapabilityRegistry: Codable, Sendable {
    let schemaVersion: String?
    let generatedAt: String?
    let defaultRuntime: String?
    let routing: RuntimeRouting?
    let runtimes: [RuntimeDescriptor]

    init(
        schemaVersion: String? = nil,
        generatedAt: String? = nil,
        defaultRuntime: String? = nil,
        routing: RuntimeRouting? = nil,
        runtimes: [RuntimeDescriptor] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.defaultRuntime = defaultRuntime
        self.routing = routing
        self.runtimes = runtimes
    }
}

struct RuntimeRouting: Codable, Sendable {
    let agentTypeField: String?
    let defaultAgentType: String?
    let requiredOnMethods: [String]?
}

struct RuntimeDescriptor: Codable, Sendable {
    let id: String
    let displayName: String?
    let status: String?
    let sessionListSource: String?
    let sessionMessagesSource: String?
    let sessionWatchSource: String?
    let requiresWorkspaceActivationOnResume: Bool?
    let requiresSessionResolutionOnNewSession: Bool?
    let supportsResume: Bool?
    let supportsInteractiveQuestions: Bool?
    let supportsPermissions: Bool?
    let methods: RuntimeMethods?
}

struct RuntimeMethods: Codable, Sendable {
    let history: String?
    let messages: String?
    let watch: String?
    let unwatch: String?
    let start: String?
    let send: String?
    let stop: String?
    let input: String?
    let respond: String?
    let state: String?
}

/// In-memory runtime capability snapshot used by routing/UI.
/// Falls back to compile-time runtime defaults whenever server metadata is absent or partial.
final class RuntimeCapabilityRegistryStore: @unchecked Sendable {
    static let shared = RuntimeCapabilityRegistryStore()

    private let lock = NSLock()
    private var descriptorByID: [String: RuntimeDescriptor] = [:]
    private var runtimeOrder: [String] = AgentRuntime.defaultRuntimeOrder.map(\.rawValue)
    private var defaultRuntimeID: String = AgentRuntime.defaultRuntime.rawValue

    private init() {}

    func apply(
        supportedAgentIDs: [String]?,
        runtimeRegistry: RuntimeCapabilityRegistry?
    ) {
        lock.withLock {
            var descriptors: [String: RuntimeDescriptor] = [:]
            var orderedIDs: [String] = []

            if let runtimeRegistry {
                for descriptor in runtimeRegistry.runtimes {
                    let id = Self.normalizeRuntimeID(descriptor.id)
                    guard !id.isEmpty else { continue }

                    descriptors[id] = descriptor
                    if !orderedIDs.contains(id) {
                        orderedIDs.append(id)
                    }
                }
            }

            if orderedIDs.isEmpty {
                orderedIDs = Self.normalizeRuntimeIDs(supportedAgentIDs ?? [])
            }

            orderedIDs = AgentRuntime.normalizeKnownRuntimeIDs(orderedIDs)
            if orderedIDs.isEmpty {
                orderedIDs = AgentRuntime.defaultRuntimeOrder.map(\.rawValue)
            }

            var resolvedDefault = Self.normalizeRuntimeID(runtimeRegistry?.defaultRuntime)
            if resolvedDefault.isEmpty || !orderedIDs.contains(resolvedDefault) {
                let fallbackDefault = AgentRuntime.defaultRuntime.rawValue
                if orderedIDs.contains(fallbackDefault) {
                    resolvedDefault = fallbackDefault
                } else {
                    resolvedDefault = orderedIDs.first ?? fallbackDefault
                }
            }

            descriptorByID = descriptors
            runtimeOrder = orderedIDs
            defaultRuntimeID = resolvedDefault
        }
    }

    func resetToDefaults() {
        lock.withLock {
            descriptorByID = [:]
            runtimeOrder = AgentRuntime.defaultRuntimeOrder.map(\.rawValue)
            defaultRuntimeID = AgentRuntime.defaultRuntime.rawValue
        }
    }

    func descriptor(for runtime: AgentRuntime) -> RuntimeDescriptor? {
        lock.withLock {
            descriptorByID[runtime.rawValue]
        }
    }

    func availableRuntimes() -> [AgentRuntime] {
        lock.withLock {
            let runtimes = availableRuntimesLocked()
            return runtimes.isEmpty ? AgentRuntime.defaultRuntimeOrder : runtimes
        }
    }

    func defaultRuntime() -> AgentRuntime {
        lock.withLock {
            let available = availableRuntimesLocked()
            if let configured = AgentRuntime(rawValue: defaultRuntimeID),
               available.contains(configured) {
                return configured
            }
            if let first = available.first {
                return first
            }
            return AgentRuntime.defaultRuntime
        }
    }

    func isSupported(_ runtime: AgentRuntime) -> Bool {
        lock.withLock {
            availableRuntimesLocked().contains(runtime)
        }
    }

    private func availableRuntimesLocked() -> [AgentRuntime] {
        var result: [AgentRuntime] = []
        for id in runtimeOrder {
            guard let runtime = AgentRuntime(rawValue: id) else { continue }
            if descriptorByID[id]?.isDisabled == true {
                continue
            }
            result.append(runtime)
        }
        return result
    }

    private static func normalizeRuntimeIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for id in ids {
            let normalized = normalizeRuntimeID(id)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }

    private static func normalizeRuntimeID(_ raw: String?) -> String {
        raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}

private extension RuntimeDescriptor {
    var isDisabled: Bool {
        status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "disabled"
    }
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
    /// Legacy server field used by earlier cdev versions.
    let agents: [String]?
    /// Preferred field introduced by runtime capability registry contract.
    let supportedAgents: [String]?
    let features: [String]?
    let runtimeRegistry: RuntimeCapabilityRegistry?

    enum CodingKeys: String, CodingKey {
        case agents
        case supportedAgents
        case features
        case runtimeRegistry
    }

    /// Normalized runtime IDs exposed by server capability payload.
    /// Prefers supportedAgents and falls back to legacy agents.
    var declaredAgentIDs: [String] {
        let source = supportedAgents ?? agents ?? []
        var seen = Set<String>()
        var result: [String] = []

        for raw in source {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }
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
    let isTruncated: Bool?

    enum CodingKeys: String, CodingKey {
        case path, diff
        case isStaged = "is_staged"
        case isNew = "is_new"
        case isTruncated = "is_truncated"
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

/// Workspace file get request parameters (multi-workspace mode)
struct WorkspaceFileGetParams: Codable, Sendable {
    let workspaceId: String
    let path: String
    let maxSizeKb: Int?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case path
        case maxSizeKb = "max_size_kb"
    }

    init(workspaceId: String, path: String, maxSizeKb: Int? = nil) {
        self.workspaceId = workspaceId
        self.path = path
        self.maxSizeKb = maxSizeKb
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

// MARK: - Session List (Agent)

/// Session list request parameters
struct SessionListParams: Codable, Sendable {
    let agentType: String?
    let workspaceId: String?
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case agentType = "agent_type"
        case workspaceId = "workspace_id"
        case limit
    }

    init(agentType: String? = nil, workspaceId: String? = nil, limit: Int? = nil) {
        self.agentType = agentType
        self.workspaceId = workspaceId
        self.limit = limit
    }
}

/// Session info returned by session/list
/// Enhanced with rich metadata from Codex CLI sessions (git info, model, first prompt)
struct SessionListSessionInfo: Codable, Sendable {
    let sessionId: String
    let agentType: String?
    let summary: String?
    let firstPrompt: String?
    let messageCount: Int?
    let startTime: String?
    let lastUpdated: String?
    let branch: String?
    let gitCommit: String?
    let gitRepo: String?
    let projectPath: String?
    let modelProvider: String?
    let model: String?
    let cliVersion: String?
    let fileSize: Int64?
    let filePath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentType = "agent_type"
        case summary
        case firstPrompt = "first_prompt"
        case messageCount = "message_count"
        case startTime = "start_time"
        case lastUpdated = "last_updated"
        case branch
        case gitCommit = "git_commit"
        case gitRepo = "git_repo"
        case projectPath = "project_path"
        case modelProvider = "model_provider"
        case model
        case cliVersion = "cli_version"
        case fileSize = "file_size"
        case filePath = "file_path"
    }
}

/// Session list response result
struct SessionListResult: Codable, Sendable {
    let sessions: [SessionListSessionInfo]?
    let total: Int?
}

// MARK: - Session Messages (Agent)

/// Session messages request parameters
struct SessionMessagesParams: Codable, Sendable {
    let sessionId: String
    let agentType: String?
    let limit: Int?
    let offset: Int?
    let order: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentType = "agent_type"
        case limit, offset, order
    }
}

/// Session messages response result
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

// MARK: - Session Delete (Agent)

/// Session delete request parameters (session/delete)
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

// MARK: - Workspace Session Delete (NEW - workspace-aware)

/// Workspace session delete request parameters
/// Deletes a session's .jsonl file from ~/.claude/projects/<encoded-path>/
struct WorkspaceSessionDeleteParams: Codable, Sendable {
    let workspaceId: String
    let sessionId: String
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
        case agentType = "agent_type"
    }

    init(workspaceId: String, sessionId: String, agentType: String? = nil) {
        self.workspaceId = workspaceId
        self.sessionId = sessionId
        self.agentType = agentType
    }
}

/// Workspace session delete response result
struct WorkspaceSessionDeleteResult: Codable, Sendable {
    let status: String?       // "deleted"
    let workspaceId: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
    }

    var isDeleted: Bool {
        status == "deleted"
    }
}

// MARK: - Session Control (Multi-Workspace)

/// Session start request parameters (starts selected runtime for a workspace)
/// Use resume_session_id to continue a historical session
struct SessionStartParams: Codable, Sendable {
    let workspaceId: String

    /// Historical session ID to resume (from workspace/session/history)
    /// When provided, the new session will continue where the historical session left off
    let resumeSessionId: String?
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case resumeSessionId = "resume_session_id"
        case agentType = "agent_type"
    }

    init(workspaceId: String, resumeSessionId: String? = nil, agentType: String? = nil) {
        self.workspaceId = workspaceId
        self.resumeSessionId = resumeSessionId
        self.agentType = agentType
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
/// Note: session_id should NOT be included when mode is "new"
struct SessionSendParams: Codable, Sendable {
    let sessionId: String?  // Optional - omit for "new" mode
    let prompt: String
    let mode: String?  // "new" or "continue"
    let permissionMode: SessionPermissionMode?  // Permission handling mode
    let agentType: String?  // Optional runtime routing ("claude", "codex")

    enum CodingKeys: String, CodingKey {
        case prompt, mode
        case sessionId = "session_id"
        case permissionMode = "permission_mode"
        case agentType = "agent_type"
    }

    init(
        sessionId: String?,
        prompt: String,
        mode: String? = "continue",
        permissionMode: SessionPermissionMode? = nil,
        agentType: String? = nil
    ) {
        // For "new" mode, don't include session_id even if provided
        if mode == "new" {
            self.sessionId = nil
        } else {
            self.sessionId = sessionId
        }
        self.prompt = prompt
        self.mode = mode
        self.permissionMode = permissionMode
        self.agentType = agentType
    }

    /// Custom encoder to omit nil session_id (important for "new" mode)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(permissionMode, forKey: .permissionMode)
        try container.encodeIfPresent(agentType, forKey: .agentType)
    }
}

/// Session send response result
struct SessionSendResult: Codable, Sendable {
    let status: String
}

/// Session stop request parameters
struct SessionStopParams: Codable, Sendable {
    let sessionId: String
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentType = "agent_type"
    }

    init(sessionId: String, agentType: String? = nil) {
        self.sessionId = sessionId
        self.agentType = agentType
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
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case type, response
        case sessionId = "session_id"
        case agentType = "agent_type"
    }

    init(sessionId: String, type: String, response: String, agentType: String? = nil) {
        self.sessionId = sessionId
        self.type = type
        self.response = response
        self.agentType = agentType
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
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case input, key
        case sessionId = "session_id"
        case agentType = "agent_type"
    }

    /// Create input params with text input
    init(sessionId: String, input: String, agentType: String? = nil) {
        self.sessionId = sessionId
        self.input = input
        self.key = nil
        self.agentType = agentType
    }

    /// Create input params with special key
    init(sessionId: String, key: SessionInputKey, agentType: String? = nil) {
        self.sessionId = sessionId
        self.input = nil
        self.key = key.rawValue
        self.agentType = agentType
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
    let error: String?
    let commitsPushed: Int?

    enum CodingKeys: String, CodingKey {
        case success, message, error
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

/// Workspace git upstream set request parameters
struct WorkspaceGitUpstreamSetParams: Codable, Sendable {
    let workspaceId: String
    let branch: String
    let upstream: String

    enum CodingKeys: String, CodingKey {
        case branch, upstream
        case workspaceId = "workspace_id"
    }
}

/// Workspace git upstream set response result
struct WorkspaceGitUpstreamSetResult: Codable, Sendable {
    let success: Bool?
    let message: String?
    let error: String?

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
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case limit
        case workspaceId = "workspace_id"
        case agentType = "agent_type"
    }

    init(workspaceId: String, limit: Int? = nil, agentType: String? = nil) {
        self.workspaceId = workspaceId
        self.limit = limit
        self.agentType = agentType
    }
}

/// Historical session info from workspace/session/history
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
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case limit, offset, order
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
        case agentType = "agent_type"
    }

    init(workspaceId: String, sessionId: String, limit: Int? = nil, offset: Int? = nil, order: String? = nil, agentType: String? = nil) {
        self.workspaceId = workspaceId
        self.sessionId = sessionId
        self.limit = limit
        self.offset = offset
        self.order = order
        self.agentType = agentType
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
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
        case agentType = "agent_type"
    }

    init(workspaceId: String, sessionId: String, agentType: String? = nil) {
        self.workspaceId = workspaceId
        self.sessionId = sessionId
        self.agentType = agentType
    }
}

/// Workspace session unwatch request parameters
struct WorkspaceSessionUnwatchParams: Codable, Sendable {
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case agentType = "agent_type"
    }

    init(agentType: String? = nil) {
        self.agentType = agentType
    }
}

/// Agent session watch request parameters
struct SessionWatchParams: Codable, Sendable {
    let sessionId: String
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentType = "agent_type"
    }
}

struct SessionUnwatchParams: Codable, Sendable {
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case agentType = "agent_type"
    }

    init(agentType: String? = nil) {
        self.agentType = agentType
    }
}

/// Agent session watch response result
struct SessionWatchResult: Codable, Sendable {
    let status: String?
    let watching: Bool?
}

/// Agent session unwatch response result
struct SessionUnwatchResult: Codable, Sendable {
    let status: String?
    let watching: Bool?
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

// MARK: - Workspace Files List

/// Workspace files list request parameters
struct WorkspaceFilesListParams: Codable, Sendable {
    let workspaceId: String         // Required workspace ID
    let directory: String?          // Directory path (empty/nil for root)
    let limit: Int?
    let offset: Int?
    let includeHidden: Bool?        // Include .dotfiles

    enum CodingKeys: String, CodingKey {
        case directory, limit, offset
        case workspaceId = "workspace_id"
        case includeHidden = "include_hidden"
    }

    init(
        workspaceId: String,
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
    let folderCount: Int?          // Number of subdirectories (direct children)
    let fileCount: Int?            // Number of files (recursive)
    let totalSizeBytes: Int64?
    let totalSizeDisplay: String?  // Pre-formatted size like "38.8 KB"
    let lastModified: String?
    let modifiedDisplay: String?   // Pre-formatted like "2 hours ago"

    enum CodingKeys: String, CodingKey {
        case path, name
        case folderCount = "folder_count"
        case fileCount = "file_count"
        case totalSizeBytes = "total_size_bytes"
        case totalSizeDisplay = "total_size_display"
        case lastModified = "last_modified"
        case modifiedDisplay = "modified_display"
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

// MARK: - Git Init & Remote Operations

/// Workspace git init request parameters
struct WorkspaceGitInitParams: Codable, Sendable {
    let workspaceId: String
    let initialBranch: String?
    let initialCommit: Bool?
    let commitMessage: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case initialBranch = "initial_branch"
        case initialCommit = "initial_commit"
        case commitMessage = "commit_message"
    }

    init(workspaceId: String, initialBranch: String? = "main", initialCommit: Bool? = nil, commitMessage: String? = nil) {
        self.workspaceId = workspaceId
        self.initialBranch = initialBranch
        self.initialCommit = initialCommit
        self.commitMessage = commitMessage
    }
}

/// Workspace git init response result
struct WorkspaceGitInitResult: Codable, Sendable {
    let success: Bool?
    let branch: String?
    let commitSha: String?
    let filesCommitted: Int?
    let message: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, branch, message, error
        case commitSha = "commit_sha"
        case filesCommitted = "files_committed"
    }

    var isSuccess: Bool {
        success == true
    }
}

/// Workspace git remote add request parameters
struct WorkspaceGitRemoteAddParams: Codable, Sendable {
    let workspaceId: String
    let name: String
    let url: String
    let fetch: Bool?

    enum CodingKeys: String, CodingKey {
        case name, url, fetch
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String, name: String = "origin", url: String, fetch: Bool? = nil) {
        self.workspaceId = workspaceId
        self.name = name
        self.url = url
        self.fetch = fetch
    }
}

/// Workspace git remote add response result
struct WorkspaceGitRemoteAddResult: Codable, Sendable {
    let success: Bool?
    let remote: RemoteInfoResult?
    let fetchedBranches: [String]?
    let message: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, remote, message, error
        case fetchedBranches = "fetched_branches"
    }

    struct RemoteInfoResult: Codable, Sendable {
        let name: String?
        let fetchUrl: String?
        let pushUrl: String?
        let provider: String?

        enum CodingKeys: String, CodingKey {
            case name, provider
            case fetchUrl = "fetch_url"
            case pushUrl = "push_url"
        }
    }

    var isSuccess: Bool {
        success == true
    }
}

/// Workspace git remote remove request parameters
struct WorkspaceGitRemoteRemoveParams: Codable, Sendable {
    let workspaceId: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case name
        case workspaceId = "workspace_id"
    }
}

/// Workspace git remote remove response result
struct WorkspaceGitRemoteRemoveResult: Codable, Sendable {
    let success: Bool?
    let message: String?
    let error: String?

    var isSuccess: Bool {
        success == true
    }
}

/// Workspace git remote list request parameters
struct WorkspaceGitRemoteListParams: Codable, Sendable {
    let workspaceId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }
}

/// Remote info in list response
struct WorkspaceGitRemoteInfo: Codable, Sendable, Identifiable {
    var id: String { name }

    let name: String
    let fetchUrl: String?
    let pushUrl: String?
    let provider: String?
    let trackingBranches: [String]?

    enum CodingKeys: String, CodingKey {
        case name, provider
        case fetchUrl = "fetch_url"
        case pushUrl = "push_url"
        case trackingBranches = "tracking_branches"
    }

    /// Parsed remote URL for UI display
    var parsedURL: GitRemoteURL? {
        guard let url = fetchUrl else { return nil }
        return GitRemoteURL.parse(url)
    }
}

/// Workspace git remote list response result
struct WorkspaceGitRemoteListResult: Codable, Sendable {
    let remotes: [WorkspaceGitRemoteInfo]?
    let message: String?
    let error: String?

    /// Safe accessor for remotes
    var safeRemotes: [WorkspaceGitRemoteInfo] {
        remotes ?? []
    }
}

// MARK: - Git State

/// Workspace git state request parameters
struct WorkspaceGitStateParams: Codable, Sendable {
    let workspaceId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }
}

/// Workspace git state response result
/// Returns the overall git configuration state for a workspace
struct WorkspaceGitStateResult: Codable, Sendable {
    let state: String?           // "no_git", "git_initialized", "no_remote", "no_push", "synced", "diverged", "conflict"
    let isGitRepo: Bool?
    let hasRemote: Bool?
    let hasUpstream: Bool?
    let branch: String?
    let remote: String?
    let upstream: String?
    let ahead: Int?
    let behind: Int?
    let hasConflicts: Bool?
    let message: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case state, branch, remote, upstream, ahead, behind, message, error
        case isGitRepo = "is_git_repo"
        case hasRemote = "has_remote"
        case hasUpstream = "has_upstream"
        case hasConflicts = "has_conflicts"
    }

    /// Convert to WorkspaceGitState enum
    var gitState: WorkspaceGitState {
        guard let stateString = state else { return .noGit }

        switch stateString {
        case "no_git": return .noGit
        case "git_initialized": return .gitInitialized
        case "no_remote": return .noRemote
        case "no_push": return .noPush
        case "synced": return .synced
        case "diverged": return .diverged
        case "conflict": return .conflict
        default: return .synced
        }
    }
}

// MARK: - Git Log (Commit History)

/// Git log request parameters
struct WorkspaceGitLogParams: Codable, Sendable {
    let workspaceId: String
    let limit: Int?
    let offset: Int?
    let branch: String?
    let path: String?
    let author: String?
    let since: String?
    let until: String?
    let graph: Bool?

    enum CodingKeys: String, CodingKey {
        case limit, offset, branch, path, author, since, until, graph
        case workspaceId = "workspace_id"
    }

    init(
        workspaceId: String,
        limit: Int? = 50,
        offset: Int? = nil,
        branch: String? = nil,
        path: String? = nil,
        author: String? = nil,
        since: String? = nil,
        until: String? = nil,
        graph: Bool? = true
    ) {
        self.workspaceId = workspaceId
        self.limit = limit
        self.offset = offset
        self.branch = branch
        self.path = path
        self.author = author
        self.since = since
        self.until = until
        self.graph = graph
    }
}

/// Commit author info (for structured author data)
struct GitCommitAuthor: Codable, Sendable {
    let name: String
    let email: String
}

/// Commit author info (simple string format from API)
struct GitCommitAuthorSimple: Codable, Sendable {
    let author: String
    let authorEmail: String

    enum CodingKeys: String, CodingKey {
        case author
        case authorEmail = "author_email"
    }
}

/// Git reference (branch, tag, HEAD)
struct GitCommitRef: Codable, Sendable, Identifiable {
    var id: String { name }

    let name: String
    let type: String  // "head", "local_branch", "remote_branch", "tag"

    enum CodingKeys: String, CodingKey {
        case name, type
    }

    /// Ref type enum for easier handling
    var refType: GitRefType {
        switch type {
        case "head": return .head
        case "local_branch": return .localBranch
        case "remote_branch": return .remoteBranch
        case "tag": return .tag
        default: return .localBranch
        }
    }

    enum GitRefType {
        case head
        case localBranch
        case remoteBranch
        case tag
    }
}

/// Graph line for visualization
struct GitGraphLine: Codable, Sendable {
    let fromColumn: Int
    let toColumn: Int
    let type: String  // "straight", "merge_left", "merge_right", "branch_left", "branch_right"

    enum CodingKeys: String, CodingKey {
        case type
        case fromColumn = "from_column"
        case toColumn = "to_column"
    }

    var lineType: GraphLineType {
        switch type {
        case "straight": return .straight
        case "merge_left": return .mergeLeft
        case "merge_right": return .mergeRight
        case "branch_left": return .branchLeft
        case "branch_right": return .branchRight
        case "horizontal": return .horizontal
        case "cross": return .cross
        default: return .straight
        }
    }

    enum GraphLineType {
        case straight
        case mergeLeft
        case mergeRight
        case branchLeft
        case branchRight
        case horizontal
        case cross
    }
}

/// Graph position for commit node
struct GitGraphPosition: Codable, Sendable {
    let column: Int
    let lines: [GitGraphLine]?
}

/// Commit node in git log
struct GitCommitNode: Codable, Sendable, Identifiable {
    var id: String { sha }

    let sha: String
    let shortSha: String?
    let subject: String
    let author: String
    let authorEmail: String
    let date: String
    let relativeDate: String?
    let parentShas: [String]?
    let isMerge: Bool?
    let refs: [GitCommitRef]?
    let graphPosition: GitGraphPosition?

    enum CodingKeys: String, CodingKey {
        case sha, subject, author, date, refs
        case shortSha = "short_sha"
        case authorEmail = "author_email"
        case relativeDate = "relative_date"
        case parentShas = "parent_shas"
        case isMerge = "is_merge"
        case graphPosition = "graph_position"
    }

    /// Get short SHA (first 7 chars if not provided)
    var displaySha: String {
        shortSha ?? String(sha.prefix(7))
    }

    /// Author info as structured object
    var authorInfo: GitCommitAuthor {
        GitCommitAuthor(name: author, email: authorEmail)
    }

    /// Check if this is a merge commit
    var isMergeCommit: Bool {
        isMerge ?? ((parentShas?.count ?? 0) > 1)
    }

    /// Parse date from ISO8601 string
    var parsedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: date) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: date)
    }

    /// Get relative date string (from API or fallback to date prefix)
    var displayRelativeDate: String {
        relativeDate ?? String(date.prefix(10))
    }
}

/// Git log response result
struct WorkspaceGitLogResult: Codable, Sendable {
    let commits: [GitCommitNode]?
    let totalCount: Int?
    let hasMore: Bool?
    let maxColumns: Int?

    enum CodingKeys: String, CodingKey {
        case commits
        case totalCount = "total_count"
        case hasMore = "has_more"
        case maxColumns = "max_columns"
    }

    /// Safe accessor for commits
    var safeCommits: [GitCommitNode] {
        commits ?? []
    }
}

// MARK: - Git Fetch

/// Git fetch request parameters
struct WorkspaceGitFetchParams: Codable, Sendable {
    let workspaceId: String
    let remote: String?
    let prune: Bool?

    enum CodingKeys: String, CodingKey {
        case remote, prune
        case workspaceId = "workspace_id"
    }

    init(workspaceId: String, remote: String? = "origin", prune: Bool? = true) {
        self.workspaceId = workspaceId
        self.remote = remote
        self.prune = prune
    }
}

/// Git fetch response result
struct WorkspaceGitFetchResult: Codable, Sendable {
    let success: Bool?
    let newCommits: Int?
    let newBranches: [String]?
    let prunedBranches: [String]?
    let message: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, message, error
        case newCommits = "new_commits"
        case newBranches = "new_branches"
        case prunedBranches = "pruned_branches"
    }

    var isSuccess: Bool {
        success == true
    }
}

// MARK: - Git Branch Delete

/// Git branch delete request parameters
struct WorkspaceGitBranchDeleteParams: Codable, Sendable {
    let workspaceId: String
    let branch: String
    let force: Bool?
    let deleteRemote: Bool?

    enum CodingKeys: String, CodingKey {
        case branch, force
        case workspaceId = "workspace_id"
        case deleteRemote = "delete_remote"
    }

    init(workspaceId: String, branch: String, force: Bool = false, deleteRemote: Bool = false) {
        self.workspaceId = workspaceId
        self.branch = branch
        self.force = force
        self.deleteRemote = deleteRemote
    }
}

/// Git branch delete response result
struct WorkspaceGitBranchDeleteResult: Codable, Sendable {
    let success: Bool?
    let branch: String?
    let message: String?
    let error: String?
    let deletedRemote: Bool?

    enum CodingKeys: String, CodingKey {
        case success, branch, message, error
        case deletedRemote = "deleted_remote"
    }

    var isSuccess: Bool {
        success == true
    }
}

// MARK: - Permission Respond (Hook Bridge Mode)

/// Permission decision scope for hook bridge mode
enum PermissionScope: String, Codable, Sendable {
    case once = "once"           // Allow/deny just this one request
    case session = "session"     // Remember for the rest of this session
}

/// Permission decision for hook bridge mode
enum PermissionDecision: String, Codable, Sendable {
    case allow = "allow"
    case deny = "deny"
}

/// Permission respond request parameters (hook bridge mode)
/// Used when responding to permission requests from Claude Code hooks
struct PermissionRespondParams: Codable, Sendable {
    let toolUseId: String        // Tool use ID from the permission event
    let decision: PermissionDecision  // "allow" or "deny"
    let scope: PermissionScope   // "once" or "session"

    enum CodingKeys: String, CodingKey {
        case toolUseId = "tool_use_id"
        case decision
        case scope
    }

    init(toolUseId: String, decision: PermissionDecision, scope: PermissionScope = .once) {
        self.toolUseId = toolUseId
        self.decision = decision
        self.scope = scope
    }
}

/// Permission respond response result
struct PermissionRespondResult: Codable, Sendable {
    let success: Bool?
    let message: String?
    let error: String?

    var isSuccess: Bool {
        success == true
    }
}
