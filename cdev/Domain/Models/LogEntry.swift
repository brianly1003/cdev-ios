import Foundation

/// Log entry from Claude output
struct LogEntry: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let content: String
    let stream: LogStream
    let sessionId: String?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        content: String,
        stream: LogStream = .stdout,
        sessionId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.stream = stream
        self.sessionId = sessionId
    }

    /// Create from agent event
    static func from(event: AgentEvent) -> LogEntry? {
        guard case .claudeLog(let payload) = event.payload,
              let line = payload.line else {
            return nil
        }

        let stream: LogStream
        if let streamStr = payload.stream {
            stream = LogStream(rawValue: streamStr) ?? .stdout
        } else {
            stream = .stdout
        }

        return LogEntry(
            id: event.id,
            timestamp: event.timestamp,
            content: line,
            stream: stream,
            sessionId: payload.sessionId
        )
    }

    /// Create from session message (for history loading)
    static func from(sessionMessage: SessionMessagesResponse.SessionMessage, sessionId: String) -> LogEntry? {
        // Parse timestamp from ISO8601 format with fractional seconds
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.date(from: sessionMessage.timestamp ?? "") ?? Date()

        // Get text content - skip tool_use and tool_result messages (no text to display)
        let textContent = sessionMessage.textContent
        guard !textContent.isEmpty else { return nil }
        guard !ChatContentFilter.shouldHideInternalMessage(textContent) else { return nil }

        // Determine stream type based on message type
        let stream: LogStream = sessionMessage.type == "user" ? .user : .stdout

        // For user messages, prefix with "> " to match live input display
        let content = sessionMessage.type == "user" ? "> \(textContent)" : textContent

        return LogEntry(
            id: sessionMessage.id,
            timestamp: timestamp,
            content: content,
            stream: stream,
            sessionId: sessionId
        )
    }
}

enum LogStream: String {
    case stdout
    case stderr
    case system
    case user  // User's prompts/messages
}

// MARK: - Log Content Type Detection

/// Content type for rich Terminal rendering
enum LogContentType {
    case userPrompt           // User's message (prefixed with >)
    case toolUse(name: String) // Tool being called
    case toolResult           // Tool result/output
    case thinking             // Claude's thinking/reasoning
    case fileOperation(op: String, path: String) // Read/Write/Edit file
    case command(cmd: String) // Bash/Git command
    case error                // Error messages
    case systemMessage        // System notifications
    case text                 // Regular text output
}

// MARK: - Log Formatting

extension LogEntry {
    /// Formatted timestamp for display
    var formattedTimestamp: String {
        timestamp.timestampString
    }

    /// Check if content contains JSON
    var containsJSON: Bool {
        content.contains("{") && content.contains("}")
    }

    /// Pretty-printed JSON if applicable
    var prettyContent: String {
        guard containsJSON,
              let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return content
        }
        return prettyString
    }

    /// Detect content type for rich rendering
    var contentType: LogContentType {
        let trimmed = content.trimmingCharacters(in: .whitespaces)

        // User prompt
        if stream == .user || trimmed.hasPrefix("> ") {
            return .userPrompt
        }

        // System message
        if stream == .system {
            return .systemMessage
        }

        // Error (stderr or error keywords)
        if stream == .stderr || trimmed.lowercased().contains("error:") {
            return .error
        }

        // Tool use detection - common Claude Code tool patterns
        let toolPatterns: [(pattern: String, name: String)] = [
            ("Read(", "Read"),
            ("Write(", "Write"),
            ("Edit(", "Edit"),
            ("Bash(", "Bash"),
            ("Glob(", "Glob"),
            ("Grep(", "Grep"),
            ("LS(", "LS"),
            ("Task(", "Task"),
            ("WebFetch(", "WebFetch"),
            ("WebSearch(", "WebSearch"),
            ("TodoWrite(", "TodoWrite"),
            ("AskUser", "AskUser"),
            ("NotebookEdit(", "NotebookEdit"),
        ]

        for (pattern, name) in toolPatterns {
            if trimmed.contains(pattern) {
                return .toolUse(name: name)
            }
        }

        // File operation patterns
        if let match = detectFileOperation(trimmed) {
            return .fileOperation(op: match.op, path: match.path)
        }

        // Command patterns
        if let cmd = detectCommand(trimmed) {
            return .command(cmd: cmd)
        }

        // Thinking patterns - Claude's reasoning
        if isThinkingContent(trimmed) {
            return .thinking
        }

        // Tool result - typically follows tool use
        if trimmed.hasPrefix("Result:") || trimmed.hasPrefix("Output:") ||
           trimmed.hasPrefix("✓") || trimmed.hasPrefix("✗") {
            return .toolResult
        }

        return .text
    }

    /// Detect file operation from content
    private func detectFileOperation(_ text: String) -> (op: String, path: String)? {
        let patterns: [(prefix: String, op: String)] = [
            ("Reading ", "Read"),
            ("Writing ", "Write"),
            ("Editing ", "Edit"),
            ("Created ", "Create"),
            ("Deleted ", "Delete"),
            ("Modified ", "Modify"),
        ]

        for (prefix, op) in patterns {
            if text.hasPrefix(prefix) {
                let path = String(text.dropFirst(prefix.count)).components(separatedBy: " ").first ?? ""
                if !path.isEmpty {
                    return (op, path)
                }
            }
        }
        return nil
    }

    /// Detect command from content
    private func detectCommand(_ text: String) -> String? {
        let cmdPatterns = ["$ ", "❯ ", "➜ "]
        for pattern in cmdPatterns {
            if text.hasPrefix(pattern) {
                return String(text.dropFirst(pattern.count).prefix(50))
            }
        }
        return nil
    }

    /// Check if content appears to be thinking/reasoning
    private func isThinkingContent(_ text: String) -> Bool {
        let thinkingIndicators = [
            "I'll ", "I will ", "I need to ", "I should ",
            "Let me ", "First, ", "Now I ", "Looking at ",
            "Based on ", "It seems ", "This means ",
            "I notice ", "I see ", "I can ",
        ]
        return thinkingIndicators.contains { text.hasPrefix($0) }
    }

    /// Icon for content type
    var contentIcon: String {
        switch contentType {
        case .userPrompt: return "chevron.right"
        case .toolUse: return "wrench.and.screwdriver"
        case .toolResult: return "checkmark.circle"
        case .thinking: return "brain"
        case .fileOperation: return "doc"
        case .command: return "terminal"
        case .error: return "exclamationmark.triangle"
        case .systemMessage: return "info.circle"
        case .text: return ""
        }
    }

    /// Whether content should be collapsible
    var isCollapsible: Bool {
        switch contentType {
        case .toolUse, .toolResult, .fileOperation, .command:
            return content.count > 100  // Only collapse long content
        default:
            return false
        }
    }
}
