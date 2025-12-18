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
}
