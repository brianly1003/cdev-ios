import Foundation

/// Protocol for agent data repository
protocol AgentRepositoryProtocol {
    /// Current agent status
    var status: AgentStatus { get async }

    /// Get current status from agent
    func fetchStatus() async throws -> AgentStatus

    /// Run Claude with prompt
    func runClaude(
        prompt: String,
        mode: SessionMode,
        sessionId: String?,
        runtime: AgentRuntime,
        yoloMode: Bool
    ) async throws

    /// Stop Claude
    /// - Parameter sessionId: Optional session ID to stop. If nil, uses current session from workspace.
    func stopClaude(sessionId: String?, runtime: AgentRuntime) async throws

    /// Respond to Claude (answer question or approve/deny permission)
    func respondToClaude(response: String, requestId: String?, approved: Bool?, runtime: AgentRuntime) async throws

    // MARK: - PTY Mode (Interactive Terminal)

    /// Send input to an interactive (PTY mode) session
    /// - Parameters:
    ///   - sessionId: Session ID to send input to
    ///   - input: Raw text input (e.g., "1" for Yes, "2" for Yes all, "n" for No)
    func sendInput(sessionId: String, input: String, runtime: AgentRuntime) async throws

    /// Send a special key to an interactive (PTY mode) session
    /// - Parameters:
    ///   - sessionId: Session ID to send key to
    ///   - key: Special key (e.g., .enter, .escape)
    func sendKey(sessionId: String, key: SessionInputKey, runtime: AgentRuntime) async throws

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

    /// Get list of workspace-history sessions (paginated)
    /// - Parameters:
    ///   - workspaceId: Workspace ID (uses workspace/session/history)
    ///   - limit: Maximum sessions to return (default: 20, max: 100)
    ///   - offset: Number of sessions to skip (default: 0)
    func getSessions(workspaceId: String, limit: Int, offset: Int) async throws -> SessionsResponse

    /// Get list of agent sessions for a runtime (JSON-RPC session/list)
    /// - Parameters:
    ///   - runtime: Agent runtime (claude, codex, gemini)
    ///   - workspaceId: Optional workspace ID filter (server resolves path)
    ///   - limit: Maximum sessions to return (default: 20, max: 100)
    ///   - offset: Number of sessions to skip (default: 0)
    func getAgentSessions(runtime: AgentRuntime, workspaceId: String?, limit: Int, offset: Int) async throws -> SessionsResponse

    /// Get messages for a specific session (paginated)
    /// - Parameters:
    ///   - runtime: Agent runtime routing (claude, codex, ...)
    ///   - sessionId: UUID of the session
    ///   - workspaceId: Workspace ID (required for workspace/session/messages)
    ///   - limit: Max messages to return (default: 50, max: 500)
    ///   - offset: Starting position for pagination (default: 0)
    ///   - order: Sort order: "asc" (oldest first) or "desc" (newest first)
    func getSessionMessages(
        runtime: AgentRuntime,
        sessionId: String,
        workspaceId: String?,
        limit: Int,
        offset: Int,
        order: String
    ) async throws -> SessionMessagesResponse

    /// Get messages for a specific agent session (JSON-RPC session/messages)
    func getAgentSessionMessages(
        runtime: AgentRuntime,
        sessionId: String,
        limit: Int,
        offset: Int,
        order: String
    ) async throws -> SessionMessagesResponse

    /// Delete a specific session using workspace/session/delete
    /// - Parameters:
    ///   - runtime: Agent runtime routing (claude, codex, ...)
    ///   - sessionId: Session ID to delete
    ///   - workspaceId: Workspace ID containing the session
    func deleteSession(runtime: AgentRuntime, sessionId: String, workspaceId: String) async throws -> DeleteSessionResponse

    /// Delete a specific agent session (JSON-RPC session/delete)
    func deleteAgentSession(runtime: AgentRuntime, sessionId: String) async throws -> DeleteSessionResponse

    /// Delete all agent sessions for a runtime (JSON-RPC session/delete)
    func deleteAllAgentSessions(runtime: AgentRuntime) async throws -> DeleteAllSessionsResponse

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

/// Sessions list response (paginated)
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
        let agentType: AgentRuntime?

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

        // MARK: - Enhanced metadata (from Codex CLI sessions)

        /// First user message in the session (useful for display when summary is empty)
        let firstPrompt: String?

        /// Git commit hash at session start
        let gitCommit: String?

        /// Git repository URL
        let gitRepo: String?

        /// Project/working directory path
        let projectPath: String?

        /// AI provider (openai, anthropic, etc.)
        let modelProvider: String?

        /// Specific model used (gpt-4, claude-3, etc.)
        let model: String?

        /// CLI version that created the session
        let cliVersion: String?

        /// Session file size in bytes
        let fileSize: Int64?

        /// Full path to the session file
        let filePath: String?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case summary
            case messageCount = "message_count"
            case lastUpdated = "last_updated"
            case branch
            case agentType = "agent_type"
            case status
            case workspaceId = "workspace_id"
            case startedAt = "started_at"
            case lastActive = "last_active"
            case viewers
            case firstPrompt = "first_prompt"
            case gitCommit = "git_commit"
            case gitRepo = "git_repo"
            case projectPath = "project_path"
            case modelProvider = "model_provider"
            case model
            case cliVersion = "cli_version"
            case fileSize = "file_size"
            case filePath = "file_path"
        }

        /// Memberwise initializer for programmatic creation (e.g., from RPC)
        init(
            sessionId: String,
            summary: String,
            messageCount: Int,
            lastUpdated: String,
            branch: String? = nil,
            agentType: AgentRuntime? = nil,
            status: SessionStatus? = nil,
            workspaceId: String? = nil,
            startedAt: String? = nil,
            lastActive: String? = nil,
            viewers: [String]? = nil,
            firstPrompt: String? = nil,
            gitCommit: String? = nil,
            gitRepo: String? = nil,
            projectPath: String? = nil,
            modelProvider: String? = nil,
            model: String? = nil,
            cliVersion: String? = nil,
            fileSize: Int64? = nil,
            filePath: String? = nil
        ) {
            self.sessionId = sessionId
            self.summary = summary
            self.messageCount = messageCount
            self.lastUpdated = lastUpdated
            self.branch = branch
            self.agentType = agentType
            self.status = status
            self.workspaceId = workspaceId
            self.startedAt = startedAt
            self.lastActive = lastActive
            self.viewers = viewers
            self.firstPrompt = firstPrompt
            self.gitCommit = gitCommit
            self.gitRepo = gitRepo
            self.projectPath = projectPath
            self.modelProvider = modelProvider
            self.model = model
            self.cliVersion = cliVersion
            self.fileSize = fileSize
            self.filePath = filePath
        }

        var runtime: AgentRuntime {
            agentType ?? .claude
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

        /// Display text for the session (prefers summary, falls back to first prompt)
        var displaySummary: String {
            if !summary.isEmpty {
                return summary
            }
            if let prompt = firstPrompt, !prompt.isEmpty {
                return prompt
            }
            return "Session \(sessionId.prefix(8))"
        }

        /// Project name extracted from projectPath
        var projectName: String? {
            guard let path = projectPath else { return nil }
            return (path as NSString).lastPathComponent
        }
    }
}

/// Session messages response (paginated)
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
        let isMeta: Bool?

        enum CodingKeys: String, CodingKey {
            case type, uuid, timestamp, message
            case sessionId = "session_id"
            case gitBranch = "git_branch"
            case isContextCompaction = "is_context_compaction"
            case isContextCompactionCamel = "isContextCompaction"
            case isMeta = "is_meta"
            case isMetaCamel = "isMeta"
        }

        /// Memberwise initializer for programmatic creation (e.g., from RPC)
        init(
            type: String,
            uuid: String? = nil,
            sessionId: String? = nil,
            timestamp: String? = nil,
            gitBranch: String? = nil,
            message: MessageContent,
            isContextCompaction: Bool? = nil,
            isMeta: Bool? = nil
        ) {
            self.type = type
            self.uuid = uuid
            self.sessionId = sessionId
            self.timestamp = timestamp
            self.gitBranch = gitBranch
            self.message = message
            self.isContextCompaction = isContextCompaction
            self.isMeta = isMeta
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let decodedIsContextCompaction: Bool?
            if let compaction = try container.decodeIfPresent(Bool.self, forKey: .isContextCompaction) {
                decodedIsContextCompaction = compaction
            } else if let compaction = try container.decodeIfPresent(Bool.self, forKey: .isContextCompactionCamel) {
                decodedIsContextCompaction = compaction
            } else {
                decodedIsContextCompaction = nil
            }

            let decodedIsMeta: Bool?
            if let meta = try container.decodeIfPresent(Bool.self, forKey: .isMeta) {
                decodedIsMeta = meta
            } else if let meta = try container.decodeIfPresent(Bool.self, forKey: .isMetaCamel) {
                decodedIsMeta = meta
            } else {
                decodedIsMeta = nil
            }

            self.init(
                type: try container.decode(String.self, forKey: .type),
                uuid: try container.decodeIfPresent(String.self, forKey: .uuid),
                sessionId: try container.decodeIfPresent(String.self, forKey: .sessionId),
                timestamp: try container.decodeIfPresent(String.self, forKey: .timestamp),
                gitBranch: try container.decodeIfPresent(String.self, forKey: .gitBranch),
                message: try container.decode(MessageContent.self, forKey: .message),
                isContextCompaction: decodedIsContextCompaction,
                isMeta: decodedIsMeta
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(uuid, forKey: .uuid)
            try container.encodeIfPresent(sessionId, forKey: .sessionId)
            try container.encodeIfPresent(timestamp, forKey: .timestamp)
            try container.encodeIfPresent(gitBranch, forKey: .gitBranch)
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(isContextCompaction, forKey: .isContextCompaction)
            try container.encodeIfPresent(isMeta, forKey: .isMeta)
        }

        enum MessageKind {
            case regular
            case contextCompaction
            case meta
        }

        var messageKind: MessageKind {
            if isMeta == true {
                return .meta
            }
            if isContextCompaction == true {
                return .contextCompaction
            }
            return .regular
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

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.type = try container.decode(String.self, forKey: .type)
                    self.text = Self.decodeFlexibleText(from: container, forKey: .text)
                    self.toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
                    self.id = try container.decodeIfPresent(String.self, forKey: .id)
                    self.name = try container.decodeIfPresent(String.self, forKey: .name)
                    self.content = Self.decodeFlexibleText(from: container, forKey: .content)
                    self.input = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .input)
                    self.isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
                }

                private static func decodeFlexibleText(
                    from container: KeyedDecodingContainer<CodingKeys>,
                    forKey key: CodingKeys
                ) -> String? {
                    if let value = try? container.decode(String.self, forKey: key) {
                        return meaningfulText(value)
                    }
                    if let value = try? container.decode(Int.self, forKey: key) {
                        return String(value)
                    }
                    if let value = try? container.decode(Double.self, forKey: key) {
                        return value.rounded() == value ? String(Int(value)) : String(value)
                    }
                    if let value = try? container.decode(Bool.self, forKey: key) {
                        return String(value)
                    }
                    if let value = try? container.decode(JSONValue.self, forKey: key) {
                        return meaningfulText(value.flattenedText)
                    }
                    return nil
                }

                private static func meaningfulText(_ value: String?) -> String? {
                    guard let value else { return nil }
                    return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
                }

                private enum JSONValue: Decodable {
                    case string(String)
                    case int(Int)
                    case double(Double)
                    case bool(Bool)
                    case object([String: JSONValue])
                    case array([JSONValue])
                    case null

                    private static let preferredTextKeys = ["text", "content", "message", "output", "result", "stdout", "stderr"]
                    private static let ignoredMetadataKeys: Set<String> = [
                        "type", "id", "tool_use_id", "tool_id", "tool_name", "name", "is_error", "error"
                    ]

                    init(from decoder: Decoder) throws {
                        let container = try decoder.singleValueContainer()
                        if container.decodeNil() {
                            self = .null
                        } else if let value = try? container.decode(String.self) {
                            self = .string(value)
                        } else if let value = try? container.decode(Int.self) {
                            self = .int(value)
                        } else if let value = try? container.decode(Double.self) {
                            self = .double(value)
                        } else if let value = try? container.decode(Bool.self) {
                            self = .bool(value)
                        } else if let value = try? container.decode([String: JSONValue].self) {
                            self = .object(value)
                        } else if let value = try? container.decode([JSONValue].self) {
                            self = .array(value)
                        } else {
                            self = .null
                        }
                    }

                    var flattenedText: String? {
                        switch self {
                        case .string(let value):
                            return value
                        case .int(let value):
                            return String(value)
                        case .double(let value):
                            return value.rounded() == value ? String(Int(value)) : String(value)
                        case .bool(let value):
                            return String(value)
                        case .array(let values):
                            let pieces = values.compactMap { Self.meaningfulText($0.flattenedText) }
                            return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
                        case .object(let values):
                            var pieces: [String] = []

                            for key in Self.preferredTextKeys {
                                if let value = values[key], let text = Self.meaningfulText(value.flattenedText) {
                                    pieces.append(text)
                                }
                            }
                            if !pieces.isEmpty {
                                return pieces.joined(separator: "\n")
                            }

                            for key in values.keys.sorted() where !Self.ignoredMetadataKeys.contains(key) {
                                if let text = Self.meaningfulText(values[key]?.flattenedText) {
                                    pieces.append(text)
                                }
                            }
                            return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
                        case .null:
                            return nil
                        }
                    }

                    private static func meaningfulText(_ value: String?) -> String? {
                        guard let value else { return nil }
                        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
                    }
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

            /// Extract text content from either format (assistant-focused default)
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

            /// Extract text content for a specific role.
            /// User messages may carry markdown inside tool_result blocks.
            func textContent(forRole role: String) -> String {
                switch self {
                case .string(let str):
                    return str
                case .blocks(let blocks):
                    if role == "user" {
                        return blocks
                            .compactMap { block in
                                if let text = block.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    return text
                                }
                                if let content = block.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    return content
                                }
                                return nil
                            }
                            .joined(separator: "\n")
                    }
                    return blocks
                        .filter { $0.type == "text" }
                        .compactMap { $0.text }
                        .joined(separator: "\n")
                }
            }
        }

        /// Get the text content for display
        var textContent: String {
            message.content?.textContent(forRole: role) ?? ""
        }

        /// Get the role
        var role: String {
            message.role ?? type
        }
    }
}
