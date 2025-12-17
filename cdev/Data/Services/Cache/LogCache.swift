import Foundation

/// In-memory cache for log entries with size limit
actor LogCache {
    private var logs: [LogEntry] = []
    private let maxSize: Int

    init(maxSize: Int = Constants.Cache.maxLogLines) {
        self.maxSize = maxSize
    }

    /// Add log entry
    func add(_ entry: LogEntry) {
        logs.append(entry)

        // Trim if over limit
        if logs.count > maxSize {
            logs.removeFirst(logs.count - maxSize)
        }
    }

    /// Add multiple log entries
    func add(_ entries: [LogEntry]) {
        logs.append(contentsOf: entries)

        if logs.count > maxSize {
            logs.removeFirst(logs.count - maxSize)
        }
    }

    /// Get all logs
    func getAll() -> [LogEntry] {
        logs
    }

    /// Get recent logs
    func getRecent(_ count: Int) -> [LogEntry] {
        Array(logs.suffix(count))
    }

    /// Clear all logs
    func clear() {
        logs.removeAll()
    }

    /// Clear logs for session
    func clear(sessionId: String) {
        logs.removeAll { $0.sessionId == sessionId }
    }

    /// Count
    var count: Int {
        logs.count
    }
}
