import Foundation
import SwiftUI
import Combine
import UIKit

// Note: DebugLogCategory and DebugLogLevel are defined in DebugLogTypes.swift

// MARK: - Debug Log Entry

/// A single debug log entry
struct DebugLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let category: DebugLogCategory
    let level: DebugLogLevel
    let title: String
    let subtitle: String?
    let details: DebugLogDetails?
    let sessionId: UUID?  // Session this log belongs to

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: DebugLogCategory,
        level: DebugLogLevel,
        title: String,
        subtitle: String? = nil,
        details: DebugLogDetails? = nil,
        sessionId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.sessionId = sessionId
    }

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
enum DebugLogDetails: Codable {
    case http(HTTPLogDetails)
    case websocket(WebSocketLogDetails)
    case text(String)

    enum CodingKeys: String, CodingKey {
        case type, http, websocket, text
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .http(let details):
            try container.encode("http", forKey: .type)
            try container.encode(details, forKey: .http)
        case .websocket(let details):
            try container.encode("websocket", forKey: .type)
            try container.encode(details, forKey: .websocket)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "http":
            let details = try container.decode(HTTPLogDetails.self, forKey: .http)
            self = .http(details)
        case "websocket":
            let details = try container.decode(WebSocketLogDetails.self, forKey: .websocket)
            self = .websocket(details)
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }
}

/// HTTP request/response details
struct HTTPLogDetails: Codable {
    let method: String
    let path: String
    let queryParams: String?
    let requestBody: String?
    let responseStatus: Int?
    let responseBody: String?
    let duration: TimeInterval?
    let error: String?

    // For cURL generation
    let fullURL: String?
    let requestHeaders: [String: String]?

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

    // MARK: - cURL Generation

    /// Generate a cURL command string for this request
    /// Output is ready to paste into terminal
    var curlCommand: String? {
        guard let url = fullURL else { return nil }

        var parts: [String] = ["curl"]

        // Method (skip for GET as it's default)
        if method.uppercased() != "GET" {
            parts.append("-X \(method.uppercased())")
        }

        // URL (quoted for safety)
        parts.append("'\(url)'")

        // Headers
        if let headers = requestHeaders {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                // Escape single quotes in header values
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("-H '\(key): \(escapedValue)'")
            }
        }

        // Request body
        if let body = requestBody, !body.isEmpty {
            // Escape single quotes in body
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escapedBody)'")
        }

        return parts.joined(separator: " \\\n  ")
    }

    /// Compact cURL (single line, for quick copy)
    var curlCommandCompact: String? {
        guard let url = fullURL else { return nil }

        var parts: [String] = ["curl"]

        if method.uppercased() != "GET" {
            parts.append("-X \(method.uppercased())")
        }

        parts.append("'\(url)'")

        if let headers = requestHeaders {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("-H '\(key): \(escapedValue)'")
            }
        }

        if let body = requestBody, !body.isEmpty {
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escapedBody)'")
        }

        return parts.joined(separator: " ")
    }
}

/// WebSocket event details
struct WebSocketLogDetails: Codable {
    let direction: Direction
    let eventType: String?
    let payload: String?
    let sessionId: String?

    enum Direction: String, Codable {
        case incoming = "←"
        case outgoing = "→"
        case status = "◆"
    }

    /// Short session ID for display (last 8 chars)
    var shortSessionId: String? {
        guard let id = sessionId, !id.isEmpty else { return nil }
        if id.count <= 8 { return id }
        return "..." + String(id.suffix(8))
    }
}

// MARK: - Debug Log Store

/// Centralized store for debug logs - singleton, observable
/// Supports file persistence across app sessions
@MainActor
final class DebugLogStore: ObservableObject {
    static let shared = DebugLogStore()

    /// Maximum logs to keep in memory (circular buffer)
    private let maxLogs = 500

    /// Maximum logs to persist to file
    private let maxPersistedLogs = 2000

    /// Auto-save interval in seconds
    private let autoSaveInterval: TimeInterval = 30

    /// Current app session ID
    let currentSessionId = UUID()

    /// All captured logs
    @Published private(set) var logs: [DebugLogEntry] = []

    /// Whether auto-scroll is enabled
    @Published var autoScroll = true

    /// Whether logging is paused
    @Published var isPaused = false

    /// Whether file persistence is enabled (stored in UserDefaults)
    @Published var persistenceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(persistenceEnabled, forKey: "debugLogPersistenceEnabled")
        }
    }

    /// UserDefaults key for persistence setting
    private static let persistenceKey = "debugLogPersistenceEnabled"

    /// Last save timestamp
    @Published private(set) var lastSaveTime: Date?

    /// Number of logs from previous sessions
    @Published private(set) var previousSessionLogCount = 0

    private var autoSaveTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var hasUnsavedChanges = false

    // MARK: - File Paths

    private var logsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logsPath = documentsPath.appendingPathComponent("Logs", isDirectory: true)

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: logsPath.path) {
            try? FileManager.default.createDirectory(at: logsPath, withIntermediateDirectories: true)
        }

        return logsPath
    }

    private var logsFilePath: URL {
        logsDirectory.appendingPathComponent("debug_logs.json")
    }

    private init() {
        // Load persistence setting from UserDefaults (default: true)
        self.persistenceEnabled = UserDefaults.standard.object(forKey: Self.persistenceKey) as? Bool ?? true

        setupAutoSave()
        setupAppLifecycleObservers()
        loadPersistedLogs()
        logSessionStart()
    }

    deinit {
        autoSaveTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupAutoSave() {
        // Auto-save timer
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveIfNeeded()
            }
        }
    }

    private func setupAppLifecycleObservers() {
        // Save when app goes to background
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.saveToFile()
                }
            }
            .store(in: &cancellables)

        // Save when app terminates
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.saveToFile()
                }
            }
            .store(in: &cancellables)
    }

    private func logSessionStart() {
        let entry = DebugLogEntry(
            timestamp: Date(),
            category: .app,
            level: .info,
            title: "Session Started",
            subtitle: "Session: \(currentSessionId.uuidString.prefix(8))...",
            details: .text("App launched. Session ID: \(currentSessionId.uuidString)"),
            sessionId: currentSessionId
        )
        logs.append(entry)
        hasUnsavedChanges = true
    }

    // MARK: - Public API

    /// Add a log entry
    func add(_ entry: DebugLogEntry) {
        guard !isPaused else { return }

        // Add session ID to entry if not set
        var entryWithSession = entry
        if entry.sessionId == nil {
            entryWithSession = DebugLogEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                category: entry.category,
                level: entry.level,
                title: entry.title,
                subtitle: entry.subtitle,
                details: entry.details,
                sessionId: currentSessionId
            )
        }

        logs.append(entryWithSession)
        hasUnsavedChanges = true

        // Trim if over limit (keep previous session logs separate from count)
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
    }

    /// Clear all logs (memory only, optionally clear persisted)
    func clear(clearPersisted: Bool = false) {
        logs.removeAll()
        hasUnsavedChanges = true
        previousSessionLogCount = 0

        if clearPersisted {
            clearPersistedLogs()
        }
    }

    /// Clear logs of specific category
    func clear(category: DebugLogCategory) {
        if category == .all {
            clear(clearPersisted: false)
        } else {
            logs.removeAll { $0.category == category }
            hasUnsavedChanges = true
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

    /// Export logs as JSON data (for sharing)
    func exportLogsAsJSON(category: DebugLogCategory = .all) -> Data? {
        let filtered = logs(for: category)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(filtered)
    }

    /// Get file URL for sharing
    func getLogsFileURL() -> URL? {
        // Save current logs first
        saveToFile()
        return logsFilePath
    }

    /// Force save to file
    func forceSave() {
        saveToFile()
    }

    // MARK: - File Persistence

    private func saveIfNeeded() {
        guard hasUnsavedChanges && persistenceEnabled else { return }
        saveToFile()
    }

    private func saveToFile() {
        guard persistenceEnabled else { return }

        do {
            // Get logs to persist (trim to max)
            var logsToSave = logs
            if logsToSave.count > maxPersistedLogs {
                logsToSave = Array(logsToSave.suffix(maxPersistedLogs))
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(logsToSave)

            try data.write(to: logsFilePath, options: .atomic)
            lastSaveTime = Date()
            hasUnsavedChanges = false

            #if DEBUG
            print("[DebugLogStore] Saved \(logsToSave.count) logs to file")
            #endif
        } catch {
            #if DEBUG
            print("[DebugLogStore] Failed to save logs: \(error)")
            #endif
        }
    }

    private func loadPersistedLogs() {
        guard persistenceEnabled else { return }
        guard FileManager.default.fileExists(atPath: logsFilePath.path) else { return }

        do {
            let data = try Data(contentsOf: logsFilePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedLogs = try decoder.decode([DebugLogEntry].self, from: data)

            // Filter out logs from current session (shouldn't exist but safety check)
            let previousLogs = loadedLogs.filter { $0.sessionId != currentSessionId }
            previousSessionLogCount = previousLogs.count

            // Prepend previous session logs
            logs = previousLogs

            #if DEBUG
            print("[DebugLogStore] Loaded \(previousLogs.count) logs from previous sessions")
            #endif
        } catch {
            #if DEBUG
            print("[DebugLogStore] Failed to load persisted logs: \(error)")
            #endif
        }
    }

    private func clearPersistedLogs() {
        try? FileManager.default.removeItem(at: logsFilePath)
        lastSaveTime = nil
    }

    /// Get logs file size in bytes
    func getLogsFileSize() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logsFilePath.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Get formatted file size string
    func getFormattedFileSize() -> String {
        let size = getLogsFileSize()
        if size == 0 { return "No saved logs" }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - Convenience Methods

    /// Log HTTP request start
    func logHTTPRequest(
        method: String,
        path: String,
        queryParams: String?,
        body: String?,
        fullURL: String? = nil,
        headers: [String: String]? = nil
    ) {
        let details = HTTPLogDetails(
            method: method,
            path: path,
            queryParams: queryParams,
            requestBody: body,
            responseStatus: nil,
            responseBody: nil,
            duration: nil,
            error: nil,
            fullURL: fullURL,
            requestHeaders: headers
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
        duration: TimeInterval,
        fullURL: String? = nil,
        headers: [String: String]? = nil
    ) {
        let details = HTTPLogDetails(
            method: method,
            path: path,
            queryParams: queryParams,
            requestBody: requestBody,
            responseStatus: status,
            responseBody: responseBody,
            duration: duration,
            error: nil,
            fullURL: fullURL,
            requestHeaders: headers
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
    func logHTTPError(
        method: String,
        path: String,
        error: String,
        duration: TimeInterval?,
        fullURL: String? = nil,
        headers: [String: String]? = nil,
        requestBody: String? = nil
    ) {
        let details = HTTPLogDetails(
            method: method,
            path: path,
            queryParams: nil,
            requestBody: requestBody,
            responseStatus: nil,
            responseBody: nil,
            duration: duration,
            error: error,
            fullURL: fullURL,
            requestHeaders: headers
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
        // Extract session_id from payload if present
        let sessionId = extractSessionId(from: payload)

        let details = WebSocketLogDetails(
            direction: direction,
            eventType: eventType,
            payload: payload,
            sessionId: sessionId
        )

        // Build subtitle: prefer full session_id, fallback to eventType
        let subtitle: String?
        if let fullId = sessionId, !fullId.isEmpty {
            subtitle = fullId
        } else {
            subtitle = eventType
        }

        let entry = DebugLogEntry(
            timestamp: Date(),
            category: .websocket,
            level: level,
            title: title,
            subtitle: subtitle,
            details: .websocket(details)
        )
        add(entry)
    }

    /// Extract session_id from JSON payload
    private func extractSessionId(from payload: String?) -> String? {
        guard let payload = payload else { return nil }

        // Try to extract session_id using regex patterns
        // Pattern 1: "session_id": "uuid"
        // Pattern 2: "sessionId": "uuid"
        // Pattern 3: "session_id":"uuid" (no space)
        let patterns = [
            #""session_id"\s*:\s*"([a-f0-9-]+)""#,
            #""sessionId"\s*:\s*"([a-f0-9-]+)""#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: payload, options: [], range: NSRange(payload.startIndex..., in: payload)),
               let range = Range(match.range(at: 1), in: payload) {
                return String(payload[range])
            }
        }

        return nil
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
