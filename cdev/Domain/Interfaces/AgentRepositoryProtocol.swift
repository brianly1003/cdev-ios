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
    func stopClaude() async throws

    /// Respond to Claude (answer question or approve/deny permission)
    func respondToClaude(response: String, requestId: String?, approved: Bool?) async throws

    /// Get file content
    func getFile(path: String) async throws -> FileContentPayload

    /// Get git status (basic format)
    func getGitStatus() async throws -> GitStatusResponse

    /// Get git status (enhanced format with staged/unstaged/untracked arrays)
    /// This is the preferred method for Source Control features
    func getGitStatusExtended() async throws -> GitStatusExtendedResponse

    /// Get git diff for file
    func getGitDiff(file: String?) async throws -> [GitDiffPayload]

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
    ///   - limit: Maximum sessions to return (default: 20, max: 100)
    ///   - offset: Number of sessions to skip (default: 0)
    func getSessions(limit: Int, offset: Int) async throws -> SessionsResponse

    /// Get messages for a specific session (paginated)
    /// - Parameters:
    ///   - sessionId: UUID of the session
    ///   - limit: Max messages to return (default: 50, max: 500)
    ///   - offset: Starting position for pagination (default: 0)
    ///   - order: Sort order: "asc" (oldest first) or "desc" (newest first)
    func getSessionMessages(
        sessionId: String,
        limit: Int,
        offset: Int,
        order: String
    ) async throws -> SessionMessagesResponse

    /// Delete a specific session
    func deleteSession(sessionId: String) async throws -> DeleteSessionResponse

    /// Delete all sessions
    func deleteAllSessions() async throws -> DeleteAllSessionsResponse
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

    /// Whether there are more sessions to load
    var hasMore: Bool {
        guard let total = total, let limit = limit, let offset = offset else {
            return false
        }
        return offset + sessions.count < total
    }

    /// Next offset for pagination
    var nextOffset: Int {
        (offset ?? 0) + sessions.count
    }

    struct SessionInfo: Codable, Identifiable {
        var id: String { sessionId }
        let sessionId: String
        let summary: String
        let messageCount: Int
        let lastUpdated: String
        let branch: String?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case summary
            case messageCount = "message_count"
            case lastUpdated = "last_updated"
            case branch
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
