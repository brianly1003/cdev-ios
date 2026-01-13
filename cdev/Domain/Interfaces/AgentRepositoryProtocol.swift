import Foundation

/// Protocol for agent data repository
protocol AgentRepositoryProtocol {
    /// Current agent status
    var status: AgentStatus { get async }

    /// Get current status from agent
    func fetchStatus() async throws -> AgentStatus

    /// Run Claude with prompt
    func runClaude(prompt: String, mode: SessionMode, sessionId: String?) async throws

    /// Stop Claude
    /// - Parameter sessionId: Optional session ID to stop. If nil, uses current session from workspace.
    func stopClaude(sessionId: String?) async throws

    /// Respond to Claude (answer question or approve/deny permission)
    func respondToClaude(response: String, requestId: String?, approved: Bool?) async throws

    // MARK: - PTY Mode (Interactive Terminal)

    /// Send input to an interactive (PTY mode) session
    /// - Parameters:
    ///   - sessionId: Session ID to send input to
    ///   - input: Raw text input (e.g., "1" for Yes, "2" for Yes all, "n" for No)
    func sendInput(sessionId: String, input: String) async throws

    /// Send a special key to an interactive (PTY mode) session
    /// - Parameters:
    ///   - sessionId: Session ID to send key to
    ///   - key: Special key (e.g., .enter, .escape)
    func sendKey(sessionId: String, key: SessionInputKey) async throws

    // MARK: - Hook Bridge Mode (Permission Respond)

    /// Respond to a permission request from hook bridge mode
    /// Used when Claude Code is running externally and using hooks to request permissions
    /// - Parameters:
    ///   - toolUseId: Tool use ID from the permission event
    ///   - decision: Whether to allow or deny the permission
    ///   - scope: Scope of the decision (once or session)
    func respondToPermission(
        toolUseId: String,
        decision: PermissionDecision,
        scope: PermissionScope
    ) async throws

    /// Get file content
    func getFile(path: String) async throws -> FileContentPayload

    /// Get git status (basic format)
    func getGitStatus() async throws -> GitStatusResponse

    /// Get git status (enhanced format with staged/unstaged/untracked arrays)
    /// This is the preferred method for Source Control features
    func getGitStatusExtended() async throws -> GitStatusExtendedResponse

    /// Get git diff for file
    func getGitDiff(file: String?, workspaceId: String?) async throws -> [GitDiffPayload]

    // MARK: - Git Operations (Source Control)

    /// Stage files for commit
    /// - Returns: Operation response with staged count
    @discardableResult
    func gitStage(paths: [String]) async throws -> GitOperationResponse

    /// Unstage files
    /// - Returns: Operation response with unstaged count
    @discardableResult
    func gitUnstage(paths: [String]) async throws -> GitOperationResponse

    /// Discard changes in files
    /// - Returns: Operation response with discarded count
    @discardableResult
    func gitDiscard(paths: [String]) async throws -> GitOperationResponse

    /// Commit staged changes
    /// - Returns: Commit response with SHA and details
    @discardableResult
    func gitCommit(message: String, push: Bool) async throws -> GitCommitResponse

    /// Push to remote
    /// - Returns: Sync response with push details
    @discardableResult
    func gitPush() async throws -> GitSyncResponse

    /// Pull from remote
    /// - Returns: Sync response with pull details
    @discardableResult
    func gitPull() async throws -> GitSyncResponse

    // MARK: - Sessions

    /// Get list of available Claude sessions (paginated)
    /// - Parameters:
    ///   - workspaceId: Optional workspace ID for workspace-aware API (uses workspace/session/history)
    ///   - limit: Maximum sessions to return (default: 20, max: 100)
    ///   - offset: Number of sessions to skip (default: 0)
    func getSessions(workspaceId: String?, limit: Int, offset: Int) async throws -> SessionsResponse

    /// Get messages for a specific session (paginated)
    /// - Parameters:
    ///   - sessionId: UUID of the session
    ///   - workspaceId: Optional workspace ID for workspace-aware API
    ///   - limit: Max messages to return (default: 50, max: 500)
    ///   - offset: Starting position for pagination (default: 0)
    ///   - order: Sort order: "asc" (oldest first) or "desc" (newest first)
    func getSessionMessages(
        sessionId: String,
        workspaceId: String?,
        limit: Int,
        offset: Int,
        order: String
    ) async throws -> SessionMessagesResponse

    /// Delete a specific session using workspace/session/delete
    /// - Parameters:
    ///   - sessionId: Session ID to delete
    ///   - workspaceId: Workspace ID containing the session
    func deleteSession(sessionId: String, workspaceId: String) async throws -> DeleteSessionResponse

    // MARK: - Workspace Status

    /// Get detailed workspace status including git tracker state, sessions, and watch status
    /// - Parameter workspaceId: Workspace ID to get status for
    /// - Returns: Workspace status with git tracker info, active sessions, and watch status
    func getWorkspaceStatus(workspaceId: String) async throws -> WorkspaceStatusResult

    // MARK: - Multi-Device Session Awareness

    /// Notify server that this device is focusing on a specific session
    /// - Parameters:
    ///   - workspaceId: Workspace containing the session
    ///   - sessionId: Session being viewed
    /// - Returns: Focus result with information about other viewers
    func setSessionFocus(workspaceId: String, sessionId: String) async throws -> SessionFocusResult

    /// Activate a session for a workspace (set as active/selected session)
    /// - Parameters:
    ///   - workspaceId: Workspace containing the session
    ///   - sessionId: Session to activate
    /// - Returns: Activation result with success status
    func activateSession(workspaceId: String, sessionId: String) async throws -> SessionActivateResult
}

/// Response for deleting a single session
struct DeleteSessionResponse: Codable {
    let message: String
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case message
        case sessionId = "session_id"
    }
}

/// Response for deleting all sessions
struct DeleteAllSessionsResponse: Codable {
    let message: String
    let deleted: Int
}

/// Git status response from HTTP API
struct GitStatusResponse: Codable {
    let files: [GitFileStatus]
    let repoName: String?
    let repoRoot: String?

    enum CodingKeys: String, CodingKey {
        case files
        case repoName = "repo_name"
        case repoRoot = "repo_root"
    }

    /// Memberwise initializer for programmatic creation
    init(files: [GitFileStatus], repoName: String?, repoRoot: String?) {
        self.files = files
        self.repoName = repoName
        self.repoRoot = repoRoot
    }

    /// Custom decoder to handle null files array from Go
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Go marshals nil slices as null, so we need to handle that
        files = (try? container.decode([GitFileStatus].self, forKey: .files)) ?? []
        repoName = try container.decodeIfPresent(String.self, forKey: .repoName)
        repoRoot = try container.decodeIfPresent(String.self, forKey: .repoRoot)
    }

    struct GitFileStatus: Codable, Identifiable {
        var id: String { path }
        let path: String
        let status: String
        let isStaged: Bool
        let isUntracked: Bool

        enum CodingKeys: String, CodingKey {
            case path
            case status
            case isStaged = "is_staged"
            case isUntracked = "is_untracked"
        }

        /// Memberwise initializer for programmatic creation
        init(path: String, status: String, isStaged: Bool, isUntracked: Bool) {
            self.path = path
            self.status = status
            self.isStaged = isStaged
            self.isUntracked = isUntracked
        }

        /// Convert git status to change type
        /// Git status format: XY where X=staging status, Y=working tree status
        /// Common values: M=modified, A=added, D=deleted, R=renamed, ?=untracked
        var changeType: FileChangeType {
            if isUntracked { return .created }

            // Check for deleted - either in staging (first char) or working tree (second char)
            // "D " = deleted in staging
            // " D" = deleted in working tree
            // "AD" = added then deleted
            if status.contains("D") { return .deleted }

            // Check for renamed
            if status.contains("R") { return .renamed }

            // Check for newly added (staged)
            // "A " = added in staging
            // "AM" = added in staging, modified in working tree
            let firstChar = status.first
            if firstChar == "A" { return .created }

            return .modified
        }
    }
}

/// Sessions list response from HTTP API (with pagination)
struct SessionsResponse: Codable {
    let sessions: [SessionInfo]
    let current: String?

    // Pagination fields
    let total: Int?
    let limit: Int?
    let offset: Int?

    /// Memberwise initializer for programmatic creation (e.g., from RPC)
    init(sessions: [SessionInfo], current: String? = nil, total: Int? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.sessions = sessions
        self.current = current
        self.total = total
        self.limit = limit
        self.offset = offset
    }

    /// Whether there are more sessions to load
    var hasMore: Bool {
        guard let total = total, let _ = limit, let offset = offset else {
            return false
        }
        return offset + sessions.count < total
    }

    /// Next offset for pagination
    var nextOffset: Int {
        (offset ?? 0) + sessions.count
    }

    /// Session status types
    /// - running: Active Claude CLI process, can use session/send
    /// - historical: Past session from ~/.claude/projects/, must resume first
    /// - attached: Session attached to LIVE mode
    enum SessionStatus: String, Codable {
        case running
        case historical
        case attached  // Session attached to LIVE mode

        /// Whether prompts can be sent to this session directly
        var canSendPrompts: Bool {
            self == .running || self == .attached
        }
    }

    struct SessionInfo: Codable, Identifiable {
        var id: String { sessionId }
        let sessionId: String
        let summary: String
        let messageCount: Int
        let lastUpdated: String
        let branch: String?

        /// Session status: "running" or "historical"
        /// - running: Active Claude CLI process, can use session/send
        /// - historical: Past session, must resume with session/start + resume_session_id
        let status: SessionStatus?

        /// Workspace ID this session belongs to
        let workspaceId: String?

        /// RFC3339 timestamp when session started (running sessions only)
        let startedAt: String?

        /// RFC3339 timestamp of last activity (running sessions only)
        let lastActive: String?

        /// List of client IDs currently viewing this session (multi-device awareness)
        let viewers: [String]?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case summary
            case messageCount = "message_count"
            case lastUpdated = "last_updated"
            case branch
            case status
            case workspaceId = "workspace_id"
            case startedAt = "started_at"
            case lastActive = "last_active"
            case viewers
        }

        /// Memberwise initializer for programmatic creation (e.g., from RPC)
        init(
            sessionId: String,
            summary: String,
            messageCount: Int,
            lastUpdated: String,
            branch: String? = nil,
            status: SessionStatus? = nil,
            workspaceId: String? = nil,
            startedAt: String? = nil,
            lastActive: String? = nil,
            viewers: [String]? = nil
        ) {
            self.sessionId = sessionId
            self.summary = summary
            self.messageCount = messageCount
            self.lastUpdated = lastUpdated
            self.branch = branch
            self.status = status
            self.workspaceId = workspaceId
            self.startedAt = startedAt
            self.lastActive = lastActive
            self.viewers = viewers
        }

        /// Whether this is a running session that can receive prompts
        var isRunning: Bool {
            status == .running
        }

        /// Whether this is a historical session that must be resumed first
        var isHistorical: Bool {
            status == .historical || status == nil
        }

        /// Number of other viewers (excluding self)
        var viewerCount: Int {
            viewers?.count ?? 0
        }
    }
}

/// Session messages response from HTTP API (paginated)
struct SessionMessagesResponse: Codable {
    let sessionId: String
    let messages: [SessionMessage]

    // Pagination fields
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool

    // Performance metrics (optional)
    let cacheHit: Bool?
    let queryTimeMs: Double?

    /// Memberwise initializer for programmatic creation (e.g., from RPC)
    init(
        sessionId: String,
        messages: [SessionMessage],
        total: Int,
        limit: Int,
        offset: Int,
        hasMore: Bool,
        cacheHit: Bool? = nil,
        queryTimeMs: Double? = nil
    ) {
        self.sessionId = sessionId
        self.messages = messages
        self.total = total
        self.limit = limit
        self.offset = offset
        self.hasMore = hasMore
        self.cacheHit = cacheHit
        self.queryTimeMs = queryTimeMs
    }

    /// Computed count for backward compatibility
    var count: Int { messages.count }

    /// Whether there are more messages to load
    var canLoadMore: Bool { hasMore }

    /// Next offset for pagination
    var nextOffset: Int { offset + messages.count }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case messages
        case total
        case limit
        case offset
        case hasMore = "has_more"
        case cacheHit = "cache_hit"
        case queryTimeMs = "query_time_ms"
    }

    struct SessionMessage: Codable, Identifiable {
        var id: String { uuid ?? "\(timestamp ?? "")-\(type)" }
        let type: String
        let uuid: String?
        let sessionId: String?
        let timestamp: String?
        let gitBranch: String?
        let message: MessageContent
        let isContextCompaction: Bool?

        enum CodingKeys: String, CodingKey {
            case type, uuid, timestamp, message
            case sessionId = "session_id"
            case gitBranch = "git_branch"
            case isContextCompaction = "is_context_compaction"
        }

        /// Memberwise initializer for programmatic creation (e.g., from RPC)
        init(
            type: String,
            uuid: String? = nil,
            sessionId: String? = nil,
            timestamp: String? = nil,
            gitBranch: String? = nil,
            message: MessageContent,
            isContextCompaction: Bool? = nil
        ) {
            self.type = type
            self.uuid = uuid
            self.sessionId = sessionId
            self.timestamp = timestamp
            self.gitBranch = gitBranch
            self.message = message
            self.isContextCompaction = isContextCompaction
        }

        /// Nested message content
        struct MessageContent: Codable {
            let role: String?
            let content: ContentType?
            let model: String?

            // Usage info for assistant messages
            struct Usage: Codable {
                let inputTokens: Int?
                let outputTokens: Int?

                enum CodingKeys: String, CodingKey {
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                }
            }
            let usage: Usage?

            enum CodingKeys: String, CodingKey {
                case role, content, model, usage
            }

            /// Memberwise initializer for programmatic creation
            init(role: String?, content: ContentType?, model: String? = nil, usage: Usage? = nil) {
                self.role = role
                self.content = content
                self.model = model
                self.usage = usage
            }
        }

        /// Content can be a string or array of content blocks
        enum ContentType: Codable {
            case string(String)
            case blocks([ContentBlock])

            struct ContentBlock: Codable {
                let type: String
                let text: String?
                let toolUseId: String?  // For tool_result: references the tool_use id
                let id: String?         // For tool_use: the tool call id
                let name: String?       // Tool name
                let content: String?    // Tool result content
                let input: [String: AnyCodableValue]?  // Tool input parameters
                let isError: Bool?      // For tool_result: whether it's an error

                enum CodingKeys: String, CodingKey {
                    case type, text, name, content, id, input
                    case toolUseId = "tool_use_id"
                    case isError = "is_error"
                }
            }

            /// Helper for decoding arbitrary JSON values
            struct AnyCodableValue: Codable {
                let value: Any

                init(_ value: Any) {
                    self.value = value
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let str = try? container.decode(String.self) {
                        value = str
                    } else if let int = try? container.decode(Int.self) {
                        value = int
                    } else if let double = try? container.decode(Double.self) {
                        value = double
                    } else if let bool = try? container.decode(Bool.self) {
                        value = bool
                    } else {
                        value = ""
                    }
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    if let str = value as? String {
                        try container.encode(str)
                    } else if let int = value as? Int {
                        try container.encode(int)
                    } else if let double = value as? Double {
                        try container.encode(double)
                    } else if let bool = value as? Bool {
                        try container.encode(bool)
                    }
                }

                var stringValue: String {
                    if let str = value as? String { return str }
                    if let int = value as? Int { return String(int) }
                    if let double = value as? Double { return String(double) }
                    if let bool = value as? Bool { return String(bool) }
                    return String(describing: value)
                }
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let str = try? container.decode(String.self) {
                    self = .string(str)
                } else if let blocks = try? container.decode([ContentBlock].self) {
                    self = .blocks(blocks)
                } else {
                    self = .string("")
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let str):
                    try container.encode(str)
                case .blocks(let blocks):
                    try container.encode(blocks)
                }
            }

            /// Extract text content from either format
            var textContent: String {
                switch self {
                case .string(let str):
                    return str
                case .blocks(let blocks):
                    return blocks
                        .filter { $0.type == "text" }
                        .compactMap { $0.text }
                        .joined(separator: "\n")
                }
            }
        }

        /// Get the text content for display
        var textContent: String {
            message.content?.textContent ?? ""
        }

        /// Get the role
        var role: String {
            message.role ?? type
        }
    }
}
