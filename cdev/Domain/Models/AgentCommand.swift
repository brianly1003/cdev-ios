import Foundation

/// Commands sent to cdev-agent
/// Matches the agent's domain/commands types
enum AgentCommandType: String, Codable {
    case runClaude = "run_claude"
    case stopClaude = "stop_claude"
    case respondToClaude = "respond_to_claude"
    case getStatus = "get_status"
    case getFile = "get_file"
}

/// Base command structure to agent
struct AgentCommand: Codable {
    let command: AgentCommandType
    let payload: AgentCommandPayload?
    let requestId: String

    init(command: AgentCommandType, payload: AgentCommandPayload? = nil, requestId: String = UUID().uuidString) {
        self.command = command
        self.payload = payload
        self.requestId = requestId
    }

    enum CodingKeys: String, CodingKey {
        case command
        case payload
        case requestId = "request_id"
    }
}

/// Command payload union type
enum AgentCommandPayload: Codable {
    case runClaude(RunClaudePayload)
    case respondToClaude(RespondToClaudePayload)
    case getFile(GetFilePayload)
    case empty

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let payload = try? container.decode(RunClaudePayload.self) {
            self = .runClaude(payload)
        } else if let payload = try? container.decode(RespondToClaudePayload.self) {
            self = .respondToClaude(payload)
        } else if let payload = try? container.decode(GetFilePayload.self) {
            self = .getFile(payload)
        } else {
            self = .empty
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .runClaude(let payload):
            try container.encode(payload)
        case .respondToClaude(let payload):
            try container.encode(payload)
        case .getFile(let payload):
            try container.encode(payload)
        case .empty:
            try container.encodeNil()
        }
    }
}

// MARK: - Payload Types

struct RunClaudePayload: Codable {
    let prompt: String
    let sessionMode: SessionMode?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case sessionMode = "session_mode"
        case sessionId = "session_id"
    }

    init(prompt: String, sessionMode: SessionMode? = .new, sessionId: String? = nil) {
        self.prompt = prompt
        self.sessionMode = sessionMode
        self.sessionId = sessionId
    }
}

enum SessionMode: String, Codable {
    case new
    case `continue`
    // Note: 'resume' mode was removed from cdev-agent API
    // Use 'continue' with session_id to continue a specific session
}

struct RespondToClaudePayload: Codable {
    let response: String
    let requestId: String?
    let approved: Bool?

    enum CodingKeys: String, CodingKey {
        case response
        case requestId = "request_id"
        case approved
    }

    init(response: String, requestId: String? = nil, approved: Bool? = nil) {
        self.response = response
        self.requestId = requestId
        self.approved = approved
    }
}

struct GetFilePayload: Codable {
    let path: String
}

// MARK: - Factory Methods

extension AgentCommand {
    /// Create run_claude command
    static func runClaude(prompt: String, mode: SessionMode = .new, sessionId: String? = nil) -> AgentCommand {
        AgentCommand(
            command: .runClaude,
            payload: .runClaude(RunClaudePayload(prompt: prompt, sessionMode: mode, sessionId: sessionId))
        )
    }

    /// Create stop_claude command
    static func stopClaude() -> AgentCommand {
        AgentCommand(command: .stopClaude)
    }

    /// Create respond_to_claude command (for questions)
    static func respondToClaude(response: String, requestId: String? = nil) -> AgentCommand {
        AgentCommand(
            command: .respondToClaude,
            payload: .respondToClaude(RespondToClaudePayload(response: response, requestId: requestId))
        )
    }

    /// Create respond_to_claude command (for permissions)
    static func approvePermission(requestId: String, approved: Bool) -> AgentCommand {
        AgentCommand(
            command: .respondToClaude,
            payload: .respondToClaude(RespondToClaudePayload(
                response: approved ? "yes" : "no",
                requestId: requestId,
                approved: approved
            ))
        )
    }

    /// Create get_status command
    static func getStatus() -> AgentCommand {
        AgentCommand(command: .getStatus)
    }

    /// Create get_file command
    static func getFile(path: String) -> AgentCommand {
        AgentCommand(
            command: .getFile,
            payload: .getFile(GetFilePayload(path: path))
        )
    }
}
