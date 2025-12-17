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
}

enum LogStream: String {
    case stdout
    case stderr
    case system
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
