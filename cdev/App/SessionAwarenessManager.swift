import Foundation
import SwiftUI

// MARK: - Session Awareness Manager

/// Manages multi-device session awareness state
/// Tracks who else is viewing the same session and provides real-time notifications
@MainActor
final class SessionAwarenessManager: ObservableObject {
    // MARK: - Singleton

    static let shared = SessionAwarenessManager()

    // MARK: - Published State

    /// Currently focused workspace ID
    @Published private(set) var focusedWorkspaceId: String?

    /// Currently focused session ID
    @Published private(set) var focusedSessionId: String?

    /// Number of devices viewing the current session (including this device)
    @Published private(set) var viewerCount: Int = 0

    /// UUIDs of other devices viewing the same session
    @Published private(set) var otherViewers: [String] = []

    /// Recent join/leave notifications for UI display
    @Published private(set) var recentNotification: SessionNotification?

    // MARK: - Dependencies

    private var agentRepository: AgentRepositoryProtocol?

    // MARK: - Notification Types

    enum SessionNotification: Equatable {
        case joined(clientId: String, viewerCount: Int)
        case left(clientId: String, viewerCount: Int)

        var message: String {
            switch self {
            case .joined(let clientId, let count):
                return "Device \(clientId.prefix(8))... joined (\(count) viewers)"
            case .left(let clientId, let count):
                if count == 1 {
                    return "Device \(clientId.prefix(8))... left (only you)"
                }
                return "Device \(clientId.prefix(8))... left (\(count) viewers)"
            }
        }

        var isJoin: Bool {
            if case .joined = self { return true }
            return false
        }
    }

    // MARK: - Init

    private init() {}

    // MARK: - Configuration

    /// Configure with dependencies
    func configure(agentRepository: AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    // MARK: - Focus Management

    /// Set focus to a session (call when user starts viewing a session)
    /// - Parameters:
    ///   - workspaceId: Workspace containing the session
    ///   - sessionId: Session being viewed
    func setFocus(workspaceId: String, sessionId: String) async {
        guard let repository = agentRepository else {
            AppLogger.log("[SessionAwareness] Not configured, skipping focus", type: .warning)
            return
        }

        // Update local state
        focusedWorkspaceId = workspaceId
        focusedSessionId = sessionId

        do {
            let result = try await repository.setSessionFocus(
                workspaceId: workspaceId,
                sessionId: sessionId
            )

            // Update viewer state from response
            viewerCount = result.viewerCount ?? 1
            otherViewers = result.otherViewers ?? []

            AppLogger.log("[SessionAwareness] Focus set: viewers=\(viewerCount), others=\(otherViewers.count)")
        } catch {
            AppLogger.log("[SessionAwareness] Failed to set focus: \(error)", type: .error)
            // Keep local state but clear viewer info
            viewerCount = 1
            otherViewers = []
        }
    }

    /// Clear focus (call when user leaves session view)
    func clearFocus() {
        focusedWorkspaceId = nil
        focusedSessionId = nil
        viewerCount = 0
        otherViewers = []
        recentNotification = nil
    }

    // MARK: - Event Handling

    /// Handle session_joined event from WebSocket
    func handleSessionJoined(_ payload: SessionJoinedPayload) {
        guard let joiningClientId = payload.joiningClientId else { return }

        // Update viewer count
        viewerCount = payload.viewerCount ?? (viewerCount + 1)
        otherViewers = payload.otherViewers ?? otherViewers

        // Set notification for UI
        recentNotification = .joined(clientId: joiningClientId, viewerCount: viewerCount)

        // Haptic feedback
        Haptics.light()

        AppLogger.log("[SessionAwareness] Device joined: \(joiningClientId.prefix(8)), viewers=\(viewerCount)")

        // Clear notification after delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if case .joined(let id, _) = recentNotification, id == joiningClientId {
                recentNotification = nil
            }
        }
    }

    /// Handle session_left event from WebSocket
    func handleSessionLeft(_ payload: SessionLeftPayload) {
        guard let leavingClientId = payload.leavingClientId else { return }

        // Update viewer count
        viewerCount = payload.viewerCount ?? max(1, viewerCount - 1)
        otherViewers = payload.remainingViewers ?? otherViewers.filter { $0 != leavingClientId }

        // Set notification for UI
        recentNotification = .left(clientId: leavingClientId, viewerCount: viewerCount)

        AppLogger.log("[SessionAwareness] Device left: \(leavingClientId.prefix(8)), viewers=\(viewerCount)")

        // Clear notification after delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if case .left(let id, _) = recentNotification, id == leavingClientId {
                recentNotification = nil
            }
        }
    }

    // MARK: - Computed Properties

    /// Whether there are other viewers besides this device
    var hasOtherViewers: Bool {
        viewerCount > 1
    }

    /// Display string for viewer count
    var viewerCountDisplay: String {
        if viewerCount <= 1 {
            return "Only you"
        }
        return "\(viewerCount) viewers"
    }
}
