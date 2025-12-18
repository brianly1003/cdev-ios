import Foundation
import SwiftUI

// Note: DebugLogCategory and DebugLogLevel are defined in DebugLogTypes.swift

// MARK: - Debug Log Entry

/// A single debug log entry
struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: DebugLogCategory
    let level: DebugLogLevel
    let title: String
    let subtitle: String?
    let details: DebugLogDetails?

    /// Compact timestamp for display (HH:mm:ss)
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    /// Full timestamp for detail view
    var fullTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// Detailed log information (expandable)
enum DebugLogDetails {
    case http(HTTPLogDetails)
    case websocket(WebSocketLogDetails)
    case text(String)
}

/// HTTP request/response details
struct HTTPLogDetails {
    let method: String
    let path: String
    let queryParams: String?
    let requestBody: String?
    let responseStatus: Int?
    let responseBody: String?
    let duration: TimeInterval?
    let error: String?

    /// Status indicator
    var statusIcon: String {
        guard let status = responseStatus else { return "⋯" }
        if (200...299).contains(status) { return "✓" }
        if (400...499).contains(status) { return "⚠" }
        return "✗"
    }

    var statusColor: Color {
        guard let status = responseStatus else { return ColorSystem.textTertiary }
        if (200...299).contains(status) { return ColorSystem.success }
        if (400...499).contains(status) { return ColorSystem.warning }
        return ColorSystem.error
    }

    /// Duration string (ms)
    var durationString: String? {
        guard let duration = duration else { return nil }
        return "\(Int(duration * 1000))ms"
    }
}

/// WebSocket event details
struct WebSocketLogDetails {
    let direction: Direction
    let eventType: String?
    let payload: String?

    enum Direction: String {
        case incoming = "←"
        case outgoing = "→"
        case status = "◆"
    }
}

// MARK: - Debug Log Store

/// Centralized store for debug logs - singleton, observable
@MainActor
final class DebugLogStore: ObservableObject {
    static let shared = DebugLogStore()

    /// Maximum logs to keep in memory (circular buffer)
    private let maxLogs = 500

    /// All captured logs
    @Published private(set) var logs: [DebugLogEntry] = []

    /// Whether auto-scroll is enabled
    @Published var autoScroll = true

    /// Whether logging is paused
    @Published var isPaused = false

    private init() {}

    // MARK: - Public API

    /// Add a log entry
    func add(_ entry: DebugLogEntry) {
        guard !isPaused else { return }

        logs.append(entry)

        // Trim if over limit
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
    }

    /// Clear all logs
    func clear() {
        logs.removeAll()
    }

    /// Clear logs of specific category
    func clear(category: DebugLogCategory) {
        if category == .all {
            logs.removeAll()
        } else {
            logs.removeAll { $0.category == category }
        }
    }

    /// Get logs filtered by category
    func logs(for category: DebugLogCategory) -> [DebugLogEntry] {
        if category == .all {
            return logs
        }
        return logs.filter { $0.category == category }
    }

    /// Export logs as text
    func exportLogs(category: DebugLogCategory = .all) -> String {
        let filtered = logs(for: category)
        return filtered.map { entry in
            var line = "[\(entry.fullTimeString)] [\(entry.category.rawValue)] \(entry.title)"
            if let subtitle = entry.subtitle {
                line += " - \(subtitle)"
            }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - Convenience Methods

    /// Log HTTP request start
    func logHTTPRequest(method: String, path: String, queryParams: String?, body: String?) {
        let details = HTTPLogDetails(
            method: method,
            path: path,
            queryParams: queryParams,
            requestBody: body,
            responseStatus: nil,
            responseBody: nil,
            duration: nil,
            error: nil
        )

        var subtitle = "→ \(method)"
        if let params = queryParams, !params.isEmpty {
            subtitle += " ?\(params)"
        }

        let entry = DebugLogEntry(
            timestamp: Date(),
            category: .http,
            level: .info,
            title: path,
            subtitle: subtitle,
            details: .http(details)
        )
        add(entry)
    }

    /// Log HTTP response
    func logHTTPResponse(
        method: String,
        path: String,
        queryParams: String?,
        requestBody: String?,
        status: Int,
        responseBody: String?,
        duration: TimeInterval
    ) {
        let details = HTTPLogDetails(
            method: method,
            path: path,
            queryParams: queryParams,
            requestBody: requestBody,
            responseStatus: status,
            responseBody: responseBody,
            duration: duration,
            error: nil
        )

        let level: DebugLogLevel = (200...299).contains(status) ? .success : .error
        let durationMs = Int(duration * 1000)

        let entry = DebugLogEntry(
            timestamp: Date(),
            category: .http,
            level: level,
            title: "\(method) \(path)",
            subtitle: "← \(status) (\(durationMs)ms)",
            details: .http(details)
        )
        add(entry)
    }

    /// Log HTTP error
    func logHTTPError(method: String, path: String, error: String, duration: TimeInterval?) {
        let details = HTTPLogDetails(
            method: method,
            path: path,
            queryParams: nil,
            requestBody: nil,
            responseStatus: nil,
            responseBody: nil,
            duration: duration,
            error: error
        )

        let durationStr = duration.map { "(\(Int($0 * 1000))ms)" } ?? ""

        let entry = DebugLogEntry(
            timestamp: Date(),
            category: .http,
            level: .error,
            title: "\(method) \(path)",
            subtitle: "✗ \(error) \(durationStr)",
            details: .http(details)
        )
        add(entry)
    }

    /// Log WebSocket event
    func logWebSocket(
        direction: WebSocketLogDetails.Direction,
        title: String,
        eventType: String? = nil,
        payload: String? = nil,
        level: DebugLogLevel = .info
    ) {
        let details = WebSocketLogDetails(
            direction: direction,
            eventType: eventType,
            payload: payload
        )

        let entry = DebugLogEntry(
            timestamp: Date(),
            category: .websocket,
            level: level,
            title: title,
            subtitle: eventType,
            details: .websocket(details)
        )
        add(entry)
    }

    /// Log general app event
    func logApp(_ message: String, level: DebugLogLevel = .info, details: String? = nil) {
        let entry = DebugLogEntry(
            timestamp: Date(),
            category: .app,
            level: level,
            title: message,
            subtitle: nil,
            details: details.map { .text($0) }
        )
        add(entry)
    }
}
