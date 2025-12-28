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
    case sessionJoined = "session_joined"  // Multi-device: another device joined session
    case sessionLeft = "session_left"      // Multi-device: another device left session
    case statusResponse = "status_response"
    case fileContent = "file_content"
    case heartbeat = "heartbeat"
    case error = "error"
    case deprecationWarning = "deprecation_warning"  // Server deprecation notices

    // PTY Mode events (Terminal/Interactive mode)
    case ptyOutput = "pty_output"          // Terminal output from PTY mode
    case ptyPermission = "pty_permission"  // Permission prompt from PTY mode
    case ptyState = "pty_state"            // PTY state change (idle, thinking, permission, etc.)
    case ptySpinner = "pty_spinner"        // Spinner/thinking status with message
    case ptyPermissionResolved = "pty_permission_resolved"  // Permission resolved by another device

    // Session lifecycle events
    case sessionIdResolved = "session_id_resolved"  // Temp session ID resolved to real ID
    case sessionIdFailed = "session_id_failed"      // Session ID resolution failed (e.g., user declined trust)
    case sessionStopped = "session_stopped"         // Session stopped (broadcast to all clients)

    // Stream events
    case streamReadComplete = "stream_read_complete"  // JSONL reader caught up to end of file

    // Workspace events
    case workspaceRemoved = "workspace_removed"  // Workspace removed from server (broadcast to subscribers)
}

/// Base event structure from agent
/// Events now include workspace_id and session_id at top level for filtering
struct AgentEvent: Codable, Identifiable {
    let id: String
    let type: AgentEventType
    let payload: AgentEventPayload
    let timestamp: Date

    /// Workspace ID for event filtering (events from multi-workspace server)
    let workspaceId: String?

    /// Session ID for event filtering (filter events by current session)
    let sessionId: String?

    init(
        id: String = UUID().uuidString,
        type: AgentEventType,
        payload: AgentEventPayload,
        timestamp: Date = Date(),
        workspaceId: String? = nil,
        sessionId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
        self.workspaceId = workspaceId
        self.sessionId = sessionId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type = "event"  // Agent sends "event", not "type"
        case payload
        case timestamp
        case workspaceId = "workspace_id"
        case sessionId = "session_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.type = try container.decode(AgentEventType.self, forKey: .type)
        self.payload = try container.decode(AgentEventPayload.self, forKey: .payload)
        self.workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)

        if let timestampString = try? container.decode(String.self, forKey: .timestamp),
           let date = Date.fromISO8601(timestampString) {
            self.timestamp = date
        } else {
            self.timestamp = Date()
        }
    }

    /// Check if this event matches the specified session
    /// - Parameter targetSessionId: The session ID to match against
    /// - Returns: true if event matches session or has no session context
    func matchesSession(_ targetSessionId: String?) -> Bool {
        guard let targetSessionId = targetSessionId else { return true }
        guard let eventSessionId = sessionId else { return true }
        return eventSessionId == targetSessionId
    }

    /// Check if this event matches the specified workspace
    /// - Parameter targetWorkspaceId: The workspace ID to match against
    /// - Returns: true if event matches workspace or has no workspace context
    func matchesWorkspace(_ targetWorkspaceId: String?) -> Bool {
        guard let targetWorkspaceId = targetWorkspaceId else { return true }
        guard let eventWorkspaceId = workspaceId else { return true }
        return eventWorkspaceId == targetWorkspaceId
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
    case sessionJoined(SessionJoinedPayload)  // Multi-device: someone joined
    case sessionLeft(SessionLeftPayload)      // Multi-device: someone left
    case statusResponse(StatusResponsePayload)
    case fileContent(FileContentPayload)
    case heartbeat(HeartbeatPayload)
    case error(ErrorPayload)
    case deprecationWarning(DeprecationWarningPayload)  // Server deprecation notices

    // PTY Mode payloads (Terminal/Interactive mode)
    case ptyOutput(PTYOutputPayload)          // Terminal output
    case ptyPermission(PTYPermissionPayload)  // Permission prompt with options
    case ptyState(PTYStatePayload)            // PTY state change
    case ptySpinner(PTYSpinnerPayload)        // Spinner/thinking status
    case ptyPermissionResolved(PTYPermissionResolvedPayload)  // Permission resolved by another device

    // Session lifecycle payloads
    case sessionIdResolved(SessionIDResolvedPayload)  // Temp ID resolved to real ID
    case sessionIdFailed(SessionIDFailedPayload)      // Session ID resolution failed
    case sessionStopped(SessionStoppedPayload)        // Session stopped (broadcast)

    // Stream payloads
    case streamReadComplete(StreamReadCompletePayload)  // JSONL reader caught up to EOF

    // Workspace payloads
    case workspaceRemoved(WorkspaceRemovedPayload)  // Workspace removed from server

    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try each payload type in order of specificity
        // PTY Mode payloads FIRST - they have unique fields (options, preview, target)
        // that won't match other payload types
        if let payload = try? container.decode(PTYPermissionPayload.self),
           payload.type != nil, payload.options != nil {
            self = .ptyPermission(payload)
        } else if let payload = try? container.decode(PTYOutputPayload.self),
                  payload.cleanText != nil {
            self = .ptyOutput(payload)
        } else if let payload = try? container.decode(PTYStatePayload.self),
                  payload.state != nil {
            // Note: pty_state should be checked by event type, not just payload
            self = .ptyState(payload)
        } else if let payload = try? container.decode(PTYSpinnerPayload.self),
                  payload.symbol != nil {
            self = .ptySpinner(payload)
        // PTYPermissionResolvedPayload - check by unique field resolved_by
        } else if let payload = try? container.decode(PTYPermissionResolvedPayload.self),
                  payload.resolvedBy != nil {
            self = .ptyPermissionResolved(payload)
        // claude_message next (new structured format)
        // Check for message OR content field (cdev-agent sends content at payload level)
        } else if let payload = try? container.decode(ClaudeMessagePayload.self),
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
        // StreamReadCompletePayload - check BEFORE ClaudeSessionInfoPayload since both have session_id
        } else if let payload = try? container.decode(StreamReadCompletePayload.self), payload.messagesEmitted != nil {
            self = .streamReadComplete(payload)
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
        } else if let payload = try? container.decode(SessionWatchPayload.self),
                  payload.sessionId != nil, payload.watching != nil {
            // Require watching field to distinguish from other payloads with session_id
            self = .sessionWatch(payload)
        } else if let payload = try? container.decode(SessionJoinedPayload.self), payload.joiningClientId != nil {
            self = .sessionJoined(payload)
        } else if let payload = try? container.decode(SessionLeftPayload.self), payload.leavingClientId != nil {
            self = .sessionLeft(payload)
        } else if let payload = try? container.decode(StatusResponsePayload.self), payload.claudeState != nil {
            self = .statusResponse(payload)
        } else if let payload = try? container.decode(FileContentPayload.self), payload.content != nil {
            self = .fileContent(payload)
        } else if let payload = try? container.decode(HeartbeatPayload.self), payload.serverTime != nil {
            self = .heartbeat(payload)
        // Session lifecycle payloads - check BEFORE ErrorPayload/DeprecationWarningPayload since they have more specific fields
        } else if let payload = try? container.decode(SessionIDResolvedPayload.self), payload.temporaryId != nil, payload.realId != nil {
            self = .sessionIdResolved(payload)
        } else if let payload = try? container.decode(SessionIDFailedPayload.self), payload.temporaryId != nil {
            self = .sessionIdFailed(payload)
        // SessionStoppedPayload - check by unique field combination (session_id + workspace_id, no temporary_id)
        } else if let payload = try? container.decode(SessionStoppedPayload.self),
                  payload.sessionId != nil, payload.workspaceId != nil {
            self = .sessionStopped(payload)
        // Workspace payloads - check by unique field combination (id + name + path)
        } else if let payload = try? container.decode(WorkspaceRemovedPayload.self),
                  payload.id != nil, payload.name != nil, payload.path != nil {
            self = .workspaceRemoved(payload)
        // Generic error/warning payloads - check AFTER specific payloads that also have 'message' field
        } else if let payload = try? container.decode(ErrorPayload.self), payload.message != nil {
            self = .error(payload)
        } else if let payload = try? container.decode(DeprecationWarningPayload.self), payload.message != nil {
            self = .deprecationWarning(payload)
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
        case .sessionJoined(let payload):
            try container.encode(payload)
        case .sessionLeft(let payload):
            try container.encode(payload)
        case .statusResponse(let payload):
            try container.encode(payload)
        case .fileContent(let payload):
            try container.encode(payload)
        case .heartbeat(let payload):
            try container.encode(payload)
        case .error(let payload):
            try container.encode(payload)
        case .deprecationWarning(let payload):
            try container.encode(payload)
        case .ptyOutput(let payload):
            try container.encode(payload)
        case .ptyPermission(let payload):
            try container.encode(payload)
        case .ptyState(let payload):
            try container.encode(payload)
        case .ptySpinner(let payload):
            try container.encode(payload)
        case .ptyPermissionResolved(let payload):
            try container.encode(payload)
        case .sessionIdResolved(let payload):
            try container.encode(payload)
        case .sessionIdFailed(let payload):
            try container.encode(payload)
        case .sessionStopped(let payload):
            try container.encode(payload)
        case .streamReadComplete(let payload):
            try container.encode(payload)
        case .workspaceRemoved(let payload):
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
    let parsed: ClaudeLogParsed?  // Parsed JSON content from line

    enum CodingKeys: String, CodingKey {
        case line
        case stream
        case sessionId = "session_id"
        case parsed
    }
}

/// Parsed content from claude_log line (extracted by cdev-agent)
/// Used to capture session_id from system/init events
struct ClaudeLogParsed: Codable {
    let type: String?       // "system", "result", etc.
    let subtype: String?    // "init" for session initialization (optional)
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case subtype
        case sessionId = "session_id"
    }

    /// Check if this is a session initialization event
    /// cdev-agent sends type="system" with session_id for init events
    var isSessionInit: Bool {
        type == "system" && sessionId != nil && !(sessionId?.isEmpty ?? true)
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

/// Payload for session_id_resolved event
/// Sent when a temporary session ID is resolved to the real Claude session ID
/// This happens after user accepts trust_folder for a new workspace
struct SessionIDResolvedPayload: Codable {
    let temporaryId: String?      // The UUID generated by cdev (from session/start)
    let realId: String?           // The actual session ID from Claude
    let workspaceId: String?
    let sessionFile: String?      // Path to .jsonl file

    enum CodingKeys: String, CodingKey {
        case temporaryId = "temporary_id"
        case realId = "real_id"
        case workspaceId = "workspace_id"
        case sessionFile = "session_file"
    }
}

/// Payload for session_id_failed event
/// Sent when session ID resolution fails (e.g., user declined trust_folder)
struct SessionIDFailedPayload: Codable {
    let temporaryId: String?      // The temporary UUID that failed to resolve
    let workspaceId: String?
    let reason: String?           // Reason for failure (e.g., "trust_declined")
    let message: String?          // Human-readable message

    enum CodingKeys: String, CodingKey {
        case temporaryId = "temporary_id"
        case workspaceId = "workspace_id"
        case reason
        case message
    }
}

/// Payload for session_stopped event
/// Broadcast to ALL connected clients when a session is stopped
/// Enables multi-device sync - other devices can update UI from "Active" to "Idle"
struct SessionStoppedPayload: Codable {
    let sessionId: String?        // The session that was stopped
    let workspaceId: String?      // The workspace containing the session
    let stoppedBy: String?        // Client ID of the device that stopped it (optional)

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case workspaceId = "workspace_id"
        case stoppedBy = "stopped_by"
    }
}

/// Payload for stream_read_complete event
/// Sent when the JSONL reader catches up to the current end of file
struct StreamReadCompletePayload: Codable {
    let sessionId: String?
    let messagesEmitted: Int?    // Number of messages emitted in this read
    let fileOffset: Int?         // Current file offset
    let fileSize: Int?           // Total file size

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case messagesEmitted = "messages_emitted"
        case fileOffset = "file_offset"
        case fileSize = "file_size"
    }
}

// MARK: - Workspace Event Payloads

/// Payload for workspace_removed event
/// Sent when a workspace is removed from the server, broadcast to all subscribers
struct WorkspaceRemovedPayload: Codable {
    let id: String?          // Workspace ID
    let name: String?        // Workspace name
    let path: String?        // Workspace path on server
}

// MARK: - Multi-Device Session Awareness Payloads

/// Payload for session_joined event - emitted when another device joins a session we're viewing
struct SessionJoinedPayload: Codable {
    let joiningClientId: String?   // UUID of the device that joined
    let otherViewers: [String]?    // List of all other viewer UUIDs
    let viewerCount: Int?          // Total number of viewers including the new one

    enum CodingKeys: String, CodingKey {
        case joiningClientId = "joining_client_id"
        case otherViewers = "other_viewers"
        case viewerCount = "viewer_count"
    }
}

/// Payload for session_left event - emitted when another device leaves a session we're viewing
struct SessionLeftPayload: Codable {
    let leavingClientId: String?   // UUID of the device that left
    let remainingViewers: [String]? // List of remaining viewer UUIDs
    let viewerCount: Int?          // Total number of remaining viewers

    enum CodingKeys: String, CodingKey {
        case leavingClientId = "leaving_client_id"
        case remainingViewers = "remaining_viewers"
        case viewerCount = "viewer_count"
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

/// Deprecation warning payload from server
struct DeprecationWarningPayload: Codable {
    let message: String?
    let command: String?
    let documentation: String?
    let removal: String?
    let migration: [String: String]?
}

// MARK: - Claude State

enum ClaudeState: String, Codable {
    case running
    case idle
    case waiting
    case error
    case stopped
}

// MARK: - PTY Mode Types

/// PTY state for terminal/interactive mode
enum PTYState: String, Codable {
    case idle           // Waiting for input at prompt
    case thinking       // Claude is processing
    case permission     // Waiting for permission response
    case question       // Waiting for question response
    case error          // Error state
}

/// Permission type for PTY mode permission prompts
enum PTYPermissionType: String, Codable {
    case writeFile = "write_file"
    case editFile = "edit_file"
    case deleteFile = "delete_file"
    case bashCommand = "bash_command"
    case mcpTool = "mcp_tool"
    case trustFolder = "trust_folder"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = PTYPermissionType(rawValue: value) ?? .unknown
    }
}

/// Option for PTY permission prompts
/// Each option has a key (keyboard shortcut), label, and description
struct PTYPromptOption: Codable, Identifiable, Equatable {
    var id: String { key }

    let key: String           // Keyboard shortcut (e.g., "1", "2", "n", "Esc")
    let label: String         // Display label (e.g., "Yes", "Yes all", "No")
    let description: String?  // Optional description
    let selected: Bool?       // Whether this option is currently selected (for navigation)

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case description
        case selected
    }
}

/// Payload for pty_output events
/// Terminal output from PTY mode with clean and raw text
struct PTYOutputPayload: Codable {
    let cleanText: String?    // ANSI-stripped clean text
    let rawText: String?      // Raw terminal output with escape codes
    let state: String?        // Current PTY state as string
    let sessionId: String?    // Session ID for event context

    enum CodingKeys: String, CodingKey {
        case cleanText = "clean_text"
        case rawText = "raw_text"
        case state
        case sessionId = "session_id"
    }

    /// Parsed PTY state enum
    var ptyState: PTYState {
        guard let stateString = state else { return .idle }
        return PTYState(rawValue: stateString) ?? .idle
    }
}

/// Payload for pty_permission events
/// Permission prompt from PTY mode with structured options
struct PTYPermissionPayload: Codable {
    let type: PTYPermissionType?   // Type of permission being requested
    let target: String?            // Target of the operation (file path, command, etc.)
    let description: String?       // Description of what the tool wants to do
    let preview: String?           // Code preview for file operations
    let options: [PTYPromptOption]? // Available options for user to choose
    let sessionId: String?         // Session ID for event context

    // Legacy fields (may be sent by older server versions)
    let toolName: String?          // Name of the tool requesting permission
    let filePath: String?          // File path (for file operations)
    let command: String?           // Command (for bash operations)

    enum CodingKeys: String, CodingKey {
        case type
        case target
        case description
        case preview
        case options
        case sessionId = "session_id"
        case toolName = "tool_name"
        case filePath = "file_path"
        case command
    }

    /// Get the primary target for display (supports new and legacy fields)
    var displayTarget: String {
        if let t = target, !t.isEmpty {
            return t
        }
        if let path = filePath, !path.isEmpty {
            return path
        }
        if let cmd = command, !cmd.isEmpty {
            return cmd
        }
        return toolName ?? "Unknown"
    }

    /// Get the primary description for display
    var displayDescription: String {
        if let desc = description, !desc.isEmpty {
            return desc
        }
        return "Claude wants to perform an operation"
    }

    /// Get a compact title for the permission prompt
    var title: String {
        switch type {
        case .writeFile: return "Write File"
        case .editFile: return "Edit File"
        case .deleteFile: return "Delete File"
        case .bashCommand: return "Run Command"
        case .mcpTool: return "MCP Tool"
        case .trustFolder: return "Trust Folder"
        case .unknown, .none: return "Permission Request"
        }
    }
}

/// Payload for pty_state events
/// PTY state change notifications
struct PTYStatePayload: Codable {
    let state: PTYState?
    let previousState: PTYState?

    enum CodingKeys: String, CodingKey {
        case state
        case previousState = "previous_state"
    }
}

/// Payload for pty_spinner events
/// Spinner/thinking status with cycling symbol and message
/// Events are debounced at 150ms - only emitted when message changes or 150ms passes
struct PTYSpinnerPayload: Codable {
    let text: String?       // Full spinner text as displayed (e.g., "✶ Vibing…")
    let symbol: String?     // Just the spinner symbol (✳, ✶, ✻, ✽, ✢, or ·)
    let message: String?    // Just the message without symbol (e.g., "Vibing…")
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case text
        case symbol
        case message
        case sessionId = "session_id"
    }
}

/// Payload for pty_permission_resolved events
/// Sent when another device responds to a permission prompt
/// Used for multi-device sync - dismiss permission UI when another device responds
struct PTYPermissionResolvedPayload: Codable {
    let sessionId: String?      // Session where permission was resolved
    let workspaceId: String?    // Workspace containing the session
    let resolvedBy: String?     // Client ID of the device that responded
    let input: String?          // The input that was sent: "1", "2", "3", "enter", "escape"

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case workspaceId = "workspace_id"
        case resolvedBy = "resolved_by"
        case input
    }

    /// Check if permission was approved (input "1" or "2" typically means yes/yes-all)
    var wasApproved: Bool {
        guard let input = input else { return false }
        return input == "1" || input == "2" || input.lowercased() == "enter"
    }

    /// Check if permission was denied (input "3" or escape typically means no/cancel)
    var wasDenied: Bool {
        guard let input = input else { return false }
        return input == "3" || input.lowercased() == "escape" || input.lowercased() == "n"
    }
}
