import Foundation

/// Events received from cdev-agent via WebSocket
/// Matches the agent's domain/events types
enum AgentEventType: String, Codable {
    case claudeLog = "claude_log"
    case claudeMessage = "claude_message"  // NEW: Structured message with content blocks
    case claudeStatus = "claude_status"
    case claudeWaiting = "claude_waiting"
    case claudePermission = "claude_permission"
    case claudeSessionInfo = "claude_session_info"
    case fileChanged = "file_changed"
    case gitDiff = "git_diff"
    case gitStatusChanged = "git_status_changed"  // Real-time git status updates
    case gitOperationCompleted = "git_operation_completed"  // Git operation results
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case sessionWatchStarted = "session_watch_started"  // Session watch subscription confirmed
    case sessionWatchStopped = "session_watch_stopped"  // Session watch subscription ended
    case statusResponse = "status_response"
    case fileContent = "file_content"
    case heartbeat = "heartbeat"
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
        case type = "event"  // Agent sends "event", not "type"
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
    case claudeMessage(ClaudeMessagePayload)  // NEW: Structured message
    case claudeStatus(ClaudeStatusPayload)
    case claudeWaiting(ClaudeWaitingPayload)
    case claudePermission(ClaudePermissionPayload)
    case claudeSessionInfo(ClaudeSessionInfoPayload)
    case fileChanged(FileChangedPayload)
    case gitDiff(GitDiffPayload)
    case gitStatusChanged(GitStatusChangedPayload)  // Real-time git status
    case gitOperationCompleted(GitOperationCompletedPayload)  // Git operation result
    case sessionLifecycle(SessionLifecyclePayload)
    case sessionWatch(SessionWatchPayload)  // Session watch start/stop confirmation
    case statusResponse(StatusResponsePayload)
    case fileContent(FileContentPayload)
    case heartbeat(HeartbeatPayload)
    case error(ErrorPayload)
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try each payload type - claude_message first (new structured format)
        // Check for message OR content field (cdev-agent sends content at payload level)
        if let payload = try? container.decode(ClaudeMessagePayload.self),
           (payload.message != nil || payload.content != nil) {
            self = .claudeMessage(payload)
        } else if let payload = try? container.decode(ClaudeLogPayload.self), payload.line != nil {
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
        } else if let payload = try? container.decode(GitStatusChangedPayload.self), payload.branch != nil {
            self = .gitStatusChanged(payload)
        } else if let payload = try? container.decode(GitOperationCompletedPayload.self), payload.operation != nil {
            self = .gitOperationCompleted(payload)
        } else if let payload = try? container.decode(SessionWatchPayload.self), payload.sessionId != nil {
            self = .sessionWatch(payload)
        } else if let payload = try? container.decode(StatusResponsePayload.self), payload.claudeState != nil {
            self = .statusResponse(payload)
        } else if let payload = try? container.decode(FileContentPayload.self), payload.content != nil {
            self = .fileContent(payload)
        } else if let payload = try? container.decode(HeartbeatPayload.self), payload.serverTime != nil {
            self = .heartbeat(payload)
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
        case .claudeMessage(let payload):
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
        case .gitStatusChanged(let payload):
            try container.encode(payload)
        case .gitOperationCompleted(let payload):
            try container.encode(payload)
        case .sessionLifecycle(let payload):
            try container.encode(payload)
        case .sessionWatch(let payload):
            try container.encode(payload)
        case .statusResponse(let payload):
            try container.encode(payload)
        case .fileContent(let payload):
            try container.encode(payload)
        case .heartbeat(let payload):
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

/// NEW: Structured message payload for claude_message events
/// Supports both cdev-agent format and session API format
struct ClaudeMessagePayload: Codable {
    let type: String?           // "user" or "assistant"
    let uuid: String?
    let sessionId: String?      // Supports both sessionId and session_id
    let timestamp: String?
    let message: MessageContent?
    let role: String?           // cdev-agent sends role at payload level
    let content: ContentValue?  // cdev-agent sends content at payload level
    let stopReason: String?     // cdev-agent sends stop_reason
    let isContextCompaction: Bool?  // Context compaction marker

    enum CodingKeys: String, CodingKey {
        case type
        case uuid
        case sessionId
        case sessionIdSnake = "session_id"  // cdev-agent format
        case timestamp
        case message
        case role
        case content
        case stopReason = "stop_reason"
        case isContextCompaction = "is_context_compaction"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decodeIfPresent(String.self, forKey: .type)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        message = try container.decodeIfPresent(MessageContent.self, forKey: .message)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        content = try container.decodeIfPresent(ContentValue.self, forKey: .content)
        stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)
        isContextCompaction = try container.decodeIfPresent(Bool.self, forKey: .isContextCompaction)

        // Handle both sessionId and session_id
        if let sid = try container.decodeIfPresent(String.self, forKey: .sessionId) {
            sessionId = sid
        } else if let sid = try container.decodeIfPresent(String.self, forKey: .sessionIdSnake) {
            sessionId = sid
        } else {
            sessionId = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(uuid, forKey: .uuid)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(stopReason, forKey: .stopReason)
        try container.encodeIfPresent(isContextCompaction, forKey: .isContextCompaction)
    }

    /// Unified access to role (from message or payload level)
    var effectiveRole: String? {
        role ?? message?.role ?? type
    }

    /// Unified access to content (from message or payload level)
    var effectiveContent: ContentValue? {
        content ?? message?.content
    }

    /// Message content with role and content blocks
    struct MessageContent: Codable {
        let role: String?
        let content: ContentValue?
        let model: String?
    }

    /// Content can be string (user) or array of blocks (assistant)
    enum ContentValue: Codable {
        case text(String)
        case blocks([ContentBlock])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else if let blocks = try? container.decode([ContentBlock].self) {
                self = .blocks(blocks)
            } else {
                self = .text("")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(text)
            case .blocks(let blocks):
                try container.encode(blocks)
            }
        }

        /// Extract text content
        var textContent: String {
            switch self {
            case .text(let text):
                return text
            case .blocks(let blocks):
                return blocks
                    .compactMap { $0.text }
                    .joined(separator: "\n")
            }
        }

        /// Check if content contains thinking blocks
        var containsThinking: Bool {
            switch self {
            case .text:
                return false
            case .blocks(let blocks):
                return blocks.contains { $0.type == "thinking" }
            }
        }
    }

    /// Content block types: text, thinking, tool_use, tool_result
    /// Supports both cdev-agent format (tool_name, tool_id, tool_input) and API format (name, id, input)
    struct ContentBlock: Codable, Identifiable {
        var id: String { effectiveId }

        let type: String        // "text", "thinking", "tool_use", "tool_result"
        let text: String?       // For text/thinking blocks

        // API format
        let blockId: String?    // id field
        let name: String?       // Tool name
        let input: [String: AnyCodableValue]?  // Tool input params

        // cdev-agent format
        let toolId: String?     // tool_id field
        let toolName: String?   // tool_name field
        let toolInput: [String: AnyCodableValue]?  // tool_input field

        // Tool result fields
        let toolUseId: String?  // Reference to tool_use (for tool_result)
        let content: String?    // Result content (for tool_result)
        let isError: Bool?      // Whether tool result is error

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case blockId = "id"
            case name
            case input
            case toolId = "tool_id"
            case toolName = "tool_name"
            case toolInput = "tool_input"
            case toolUseId = "tool_use_id"
            case content
            case isError = "is_error"
        }

        /// Unified access to tool ID (supports both formats)
        var effectiveId: String {
            blockId ?? toolId ?? UUID().uuidString
        }

        /// Unified access to tool name (supports both formats)
        var effectiveName: String? {
            name ?? toolName
        }

        /// Unified access to tool input (supports both formats)
        var effectiveInput: [String: AnyCodableValue]? {
            input ?? toolInput
        }
    }
}

/// Helper for encoding/decoding arbitrary JSON values
struct AnyCodableValue: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }

    /// String representation for display
    var stringValue: String {
        if let string = value as? String {
            return string
        } else if let dict = value as? [String: Any] {
            // Format as JSON-like string
            let pairs = dict.map { "\($0.key): \($0.value)" }
            return pairs.joined(separator: ", ")
        } else {
            return String(describing: value)
        }
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

struct QuestionOption: Codable, Identifiable, Equatable {
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
    let size: Int?          // File size in bytes (for created/modified)
    let oldPath: String?    // Previous path (only for renamed)

    enum CodingKeys: String, CodingKey {
        case path, change, size
        case oldPath = "old_path"
    }
}

enum FileChangeType: String, Codable {
    case created
    case modified
    case deleted
    case renamed
}

struct GitDiffPayload: Codable {
    let file: String?  // Maps to "path" in API response
    let diff: String?
    let additions: Int?
    let deletions: Int?
    let isNew: Bool?

    enum CodingKeys: String, CodingKey {
        case file = "path"  // API returns "path" not "file"
        case diff
        case additions
        case deletions
        case isNew = "is_new"
    }
}

/// WebSocket event payload for git_status_changed
/// Emitted when git status changes (file modified, staged, etc.)
struct GitStatusChangedPayload: Codable {
    let branch: String?
    let ahead: Int?
    let behind: Int?
    let stagedCount: Int?
    let unstagedCount: Int?
    let untrackedCount: Int?
    let hasConflicts: Bool?
    let changedFiles: [String]?

    enum CodingKeys: String, CodingKey {
        case branch
        case ahead
        case behind
        case stagedCount = "staged_count"
        case unstagedCount = "unstaged_count"
        case untrackedCount = "untracked_count"
        case hasConflicts = "has_conflicts"
        case changedFiles = "changed_files"
    }
}

/// WebSocket event payload for git_operation_completed
/// Emitted when a git operation (commit, push, pull) completes
struct GitOperationCompletedPayload: Codable {
    let operation: String?  // "commit", "push", "pull", "stage", "unstage", "checkout"
    let success: Bool?
    let sha: String?        // For commits
    let message: String?    // Operation result message
    let error: String?      // Error message if failed

    enum CodingKeys: String, CodingKey {
        case operation
        case success
        case sha
        case message
        case error
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

/// Payload for session_watch_started and session_watch_stopped events
struct SessionWatchPayload: Codable {
    let sessionId: String?
    let watching: Bool?  // true for started, false for stopped
    let reason: String?  // Optional reason for stopped (e.g., "session_ended", "client_request")

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case watching
        case reason
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

/// Heartbeat event payload for connection health monitoring
struct HeartbeatPayload: Codable {
    let serverTime: String?
    let sequence: Int?
    let claudeStatus: String?
    let uptimeSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case sequence
        case claudeStatus = "claude_status"
        case uptimeSeconds = "uptime_seconds"
    }
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
