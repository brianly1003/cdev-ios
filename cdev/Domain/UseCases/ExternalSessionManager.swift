//
//  ExternalSessionManager.swift
//  Cdev
//
//  Manages external Claude sessions detected via hooks
//  Tracks session lifecycle, tool executions, and permissions
//

import Foundation
import Combine

/// Manages external Claude Code sessions detected via hooks
///
/// External sessions come from Claude running in VS Code, Cursor, or terminal.
/// This manager tracks their lifecycle and provides data for UI display.
///
/// - Note: External sessions are read-only. Users cannot send prompts,
///   approve permissions, or stop these sessions from the iOS app.
@MainActor
final class ExternalSessionManager: ObservableObject {

    // MARK: - Published State

    /// Active external sessions
    @Published private(set) var sessions: [ExternalSession] = []

    /// Whether any session has a pending permission
    @Published private(set) var hasActivePermissions: Bool = false

    // MARK: - Configuration

    /// Time after which inactive sessions are removed (5 minutes)
    private let staleTimeout: TimeInterval = 300

    /// Maximum tool history per session
    private let maxToolHistory: Int = 50

    /// Timer for pruning stale sessions
    private var pruneTimer: Timer?

    // MARK: - Computed Properties

    /// Number of active external sessions
    var activeSessionCount: Int { sessions.count }

    /// Sessions sorted by last activity (most recent first)
    var sessionsByActivity: [ExternalSession] {
        sessions.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Sessions with pending permissions
    var sessionsWithPermissions: [ExternalSession] {
        sessions.filter { $0.hasPendingPermission }
    }

    // MARK: - Initialization

    init() {
        startPruneTimer()
    }

    deinit {
        pruneTimer?.invalidate()
    }

    // MARK: - Event Handling

    /// Handle external session start event
    func handleSessionStart(_ payload: HookSessionPayload) {
        guard let sessionId = payload.sessionId, !sessionId.isEmpty else {
            AppLogger.log("[ExternalSessions] Ignoring session with empty ID")
            return
        }

        // Check if session already exists
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            // Update existing session
            sessions[index].lastActivity = Date()
            AppLogger.log("[ExternalSessions] Updated existing session: \(sessionId)")
        } else {
            // Add new session
            let session = ExternalSession(from: payload)
            sessions.append(session)
            AppLogger.log("[ExternalSessions] New session: \(session.projectName) (\(sessionId))")
        }
    }

    /// Handle permission request in external session
    func handlePermission(_ payload: HookPermissionPayload) {
        guard let sessionId = payload.sessionId else { return }

        // Find or create session
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].lastActivity = Date()
            sessions[index].hasPendingPermission = true
            sessions[index].pendingPermission = PendingExternalPermission(from: payload)
            updatePermissionState()
            AppLogger.log("[ExternalSessions] Permission pending: \(payload.tool ?? "?") in \(sessions[index].projectName)")
        } else {
            // Session not found - create placeholder
            var session = ExternalSession(
                id: sessionId,
                workingDirectory: payload.path ?? "Unknown"
            )
            session.hasPendingPermission = true
            session.pendingPermission = PendingExternalPermission(from: payload)
            sessions.append(session)
            updatePermissionState()
            AppLogger.log("[ExternalSessions] Permission for unknown session: \(sessionId)")
        }
    }

    /// Handle tool start in external session
    func handleToolStart(_ payload: HookToolStartPayload) {
        guard let sessionId = payload.sessionId else { return }

        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].lastActivity = Date()
            sessions[index].currentTool = payload.toolName

            // Clear any pending permission (tool started = permission was granted)
            if sessions[index].hasPendingPermission {
                sessions[index].hasPendingPermission = false
                sessions[index].pendingPermission = nil
                updatePermissionState()
            }

            // Add to tool history
            let execution = ToolExecution(from: payload)
            sessions[index].toolHistory.insert(execution, at: 0)

            // Trim history if needed
            if sessions[index].toolHistory.count > maxToolHistory {
                sessions[index].toolHistory = Array(sessions[index].toolHistory.prefix(maxToolHistory))
            }

            AppLogger.log("[ExternalSessions] Tool started: \(payload.toolName ?? "?") in \(sessions[index].projectName)")
        }
    }

    /// Handle tool end in external session
    func handleToolEnd(_ payload: HookToolEndPayload) {
        guard let sessionId = payload.sessionId else { return }

        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].lastActivity = Date()
            sessions[index].currentTool = nil

            // Update the most recent matching tool execution
            if let toolIndex = sessions[index].toolHistory.firstIndex(where: {
                $0.toolName == payload.toolName && $0.isRunning
            }) {
                sessions[index].toolHistory[toolIndex].endTime = Date()
                sessions[index].toolHistory[toolIndex].outputSummary = payload.resultSummary
            }

            AppLogger.log("[ExternalSessions] Tool ended: \(payload.toolName ?? "?") in \(sessions[index].projectName)")
        }
    }

    /// Clear permission for a session (e.g., when it's resolved on desktop)
    func clearPermission(for sessionId: String) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].hasPendingPermission = false
            sessions[index].pendingPermission = nil
            updatePermissionState()
        }
    }

    /// Remove a specific session
    func removeSession(_ sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
        updatePermissionState()
    }

    /// Remove all sessions
    func clearAll() {
        sessions.removeAll()
        hasActivePermissions = false
    }

    // MARK: - Session Lookup

    /// Get session by ID
    func session(for id: String) -> ExternalSession? {
        sessions.first { $0.id == id }
    }

    /// Check if a session exists
    func hasSession(_ id: String) -> Bool {
        sessions.contains { $0.id == id }
    }

    // MARK: - Private Methods

    private func updatePermissionState() {
        hasActivePermissions = sessions.contains { $0.hasPendingPermission }
    }

    private func startPruneTimer() {
        // Prune stale sessions every 60 seconds
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pruneStale()
            }
        }
    }

    /// Remove sessions that haven't had activity for staleTimeout
    func pruneStale() {
        let now = Date()
        let countBefore = sessions.count

        sessions.removeAll { session in
            now.timeIntervalSince(session.lastActivity) > staleTimeout
        }

        let removed = countBefore - sessions.count
        if removed > 0 {
            AppLogger.log("[ExternalSessions] Pruned \(removed) stale session(s)")
            updatePermissionState()
        }
    }
}
