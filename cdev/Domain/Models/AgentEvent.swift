import Foundation

/// Events received from cdev-agent via WebSocket
/// Matches the agent's domain/events types
enum AgentEventType: String, Codable {
    case claudeLog = "claude_log"
    case claudeStatus = "claude_status"
    case claudeWaiting = "claude_waiting"
    case claudePermission = "claude_permission"
    case claudeSessionInfo = "claude_session_info"
    case fileChanged = "file_changed"
    case gitDiff = "git_diff"
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case statusResponse = "status_response"
    case fileContent = "file_content"
    case error = "error"
}

/// Base event structure from agent
struct AgentEvent: Codable, Identifiable {
    let id: String
    let type: AgentEventType
    let payload: AgentEventPayload
    let timestamp: Date

    init(id: String = UUID().uuidString, type: AgentEventType, payload: AgentEventPayload, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case payload
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.type = try container.decode(AgentEventType.self, forKey: .type)
        self.payload = try container.decode(AgentEventPayload.self, forKey: .payload)

        if let timestampString = try? container.decode(String.self, forKey: .timestamp),
           let date = Date.fromISO8601(timestampString) {
            self.timestamp = date
        } else {
            self.timestamp = Date()
        }
    }
}

/// Event payload union type
enum AgentEventPayload: Codable {
    case claudeLog(ClaudeLogPayload)
    case claudeStatus(ClaudeStatusPayload)
    case claudeWaiting(ClaudeWaitingPayload)
    case claudePermission(ClaudePermissionPayload)
    case claudeSessionInfo(ClaudeSessionInfoPayload)
    case fileChanged(FileChangedPayload)
    case gitDiff(GitDiffPayload)
    case sessionLifecycle(SessionLifecyclePayload)
    case statusResponse(StatusResponsePayload)
    case fileContent(FileContentPayload)
    case error(ErrorPayload)
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try each payload type
        if let payload = try? container.decode(ClaudeLogPayload.self), payload.line != nil {
            self = .claudeLog(payload)
        } else if let payload = try? container.decode(ClaudeStatusPayload.self), payload.state != nil {
            self = .claudeStatus(payload)
        } else if let payload = try? container.decode(ClaudeWaitingPayload.self), payload.question != nil {
            self = .claudeWaiting(payload)
        } else if let payload = try? container.decode(ClaudePermissionPayload.self), payload.tool != nil {
            self = .claudePermission(payload)
        } else if let payload = try? container.decode(ClaudeSessionInfoPayload.self), payload.sessionId != nil {
            self = .claudeSessionInfo(payload)
        } else if let payload = try? container.decode(FileChangedPayload.self), payload.path != nil {
            self = .fileChanged(payload)
        } else if let payload = try? container.decode(GitDiffPayload.self), payload.diff != nil {
            self = .gitDiff(payload)
        } else if let payload = try? container.decode(StatusResponsePayload.self), payload.claudeState != nil {
            self = .statusResponse(payload)
        } else if let payload = try? container.decode(FileContentPayload.self), payload.content != nil {
            self = .fileContent(payload)
        } else if let payload = try? container.decode(ErrorPayload.self), payload.message != nil {
            self = .error(payload)
        } else {
            self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .claudeLog(let payload):
            try container.encode(payload)
        case .claudeStatus(let payload):
            try container.encode(payload)
        case .claudeWaiting(let payload):
            try container.encode(payload)
        case .claudePermission(let payload):
            try container.encode(payload)
        case .claudeSessionInfo(let payload):
            try container.encode(payload)
        case .fileChanged(let payload):
            try container.encode(payload)
        case .gitDiff(let payload):
            try container.encode(payload)
        case .sessionLifecycle(let payload):
            try container.encode(payload)
        case .statusResponse(let payload):
            try container.encode(payload)
        case .fileContent(let payload):
            try container.encode(payload)
        case .error(let payload):
            try container.encode(payload)
        case .unknown:
            try container.encodeNil()
        }
    }
}

// MARK: - Payload Types

struct ClaudeLogPayload: Codable {
    let line: String?
    let stream: String? // "stdout" or "stderr"
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case line
        case stream
        case sessionId = "session_id"
    }
}

struct ClaudeStatusPayload: Codable {
    let state: ClaudeState?
    let sessionId: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case state
        case sessionId = "session_id"
        case error
    }
}

struct ClaudeWaitingPayload: Codable {
    let question: String?
    let options: [QuestionOption]?
    let requestId: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case question
        case options
        case requestId = "request_id"
        case description
    }
}

struct QuestionOption: Codable, Identifiable {
    var id: String { label }
    let label: String
    let description: String?
}

struct ClaudePermissionPayload: Codable {
    let tool: String?
    let description: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case tool
        case description
        case requestId = "request_id"
    }
}

struct ClaudeSessionInfoPayload: Codable {
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

struct FileChangedPayload: Codable {
    let path: String?
    let change: FileChangeType?
}

enum FileChangeType: String, Codable {
    case created
    case modified
    case deleted
    case renamed
}

struct GitDiffPayload: Codable {
    let file: String?
    let diff: String?
    let additions: Int?
    let deletions: Int?
    let isNew: Bool?

    enum CodingKeys: String, CodingKey {
        case file
        case diff
        case additions
        case deletions
        case isNew = "is_new"
    }
}

struct SessionLifecyclePayload: Codable {
    let sessionId: String?
    let repoName: String?
    let repoPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case repoName = "repo_name"
        case repoPath = "repo_path"
    }
}

struct StatusResponsePayload: Codable {
    let claudeState: ClaudeState?
    let sessionId: String?
    let repoName: String?
    let repoPath: String?
    let connectedClients: Int?
    let uptime: Int?

    enum CodingKeys: String, CodingKey {
        case claudeState = "claude_state"
        case sessionId = "session_id"
        case repoName = "repo_name"
        case repoPath = "repo_path"
        case connectedClients = "connected_clients"
        case uptime
    }
}

struct FileContentPayload: Codable {
    let path: String?
    let content: String?
    let encoding: String?
    let truncated: Bool?
}

struct ErrorPayload: Codable {
    let message: String?
    let code: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case message
        case code
        case requestId = "request_id"
    }
}

// MARK: - Claude State

enum ClaudeState: String, Codable {
    case running
    case idle
    case waiting
    case error
    case stopped
}
