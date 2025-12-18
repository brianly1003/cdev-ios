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

    /// Get git status
    func getGitStatus() async throws -> GitStatusResponse

    /// Get git diff for file
    func getGitDiff(file: String?) async throws -> [GitDiffPayload]

    /// Get list of available Claude sessions
    func getSessions() async throws -> SessionsResponse

    /// Get messages for a specific session
    func getSessionMessages(sessionId: String) async throws -> SessionMessagesResponse

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
        var changeType: FileChangeType {
            if isUntracked { return .created }
            let trimmed = status.trimmingCharacters(in: .whitespaces)
            switch trimmed {
            case "D": return .deleted
            case "R": return .renamed
            default: return .modified
            }
        }
    }
}

/// Sessions list response from HTTP API
struct SessionsResponse: Codable {
    let sessions: [SessionInfo]
    let current: String?

    struct SessionInfo: Codable, Identifiable {
        var id: String { sessionId }
        let sessionId: String
        let summary: String
        let messageCount: Int
        let lastUpdated: String

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case summary
            case messageCount = "message_count"
            case lastUpdated = "last_updated"
        }
    }
}

/// Session messages response from HTTP API
struct SessionMessagesResponse: Codable {
    let sessionId: String
    let messages: [SessionMessage]
    let count: Int

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case messages
        case count
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
                let toolUseId: String?
                let name: String?
                let content: String?

                enum CodingKeys: String, CodingKey {
                    case type, text, name, content
                    case toolUseId = "tool_use_id"
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
