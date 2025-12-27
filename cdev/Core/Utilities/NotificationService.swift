import Foundation
import UserNotifications
import UIKit

/// Service for managing local notifications
/// Used to alert users about pending permissions when app is in background
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    // MARK: - Published State

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Private Properties

    private let notificationCenter = UNUserNotificationCenter.current()

    // Notification identifiers
    private enum NotificationID {
        static let permissionRequest = "cdev.permission_request"
    }

    // MARK: - Init

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Request notification authorization from user
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            isAuthorized = granted
            await checkAuthorizationStatus()
            AppLogger.log("[Notification] Authorization \(granted ? "granted" : "denied")")
            return granted
        } catch {
            AppLogger.log("[Notification] Authorization request failed: \(error)", type: .error)
            return false
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized

        AppLogger.log("[Notification] Status: \(authorizationStatus.description)")
    }

    // MARK: - Permission Notifications

    /// Send a local notification for a pending permission request
    /// Only sends if app is in background and notifications are authorized
    func sendPermissionNotification(
        toolName: String?,
        description: String,
        workspaceName: String?
    ) async {
        // Check if app is in background
        let appState = await UIApplication.shared.applicationState
        guard appState != .active else {
            AppLogger.log("[Notification] Skipping - app is active")
            return
        }

        // Check authorization
        guard isAuthorized else {
            AppLogger.log("[Notification] Skipping - not authorized")
            return
        }

        // Create notification content
        let content = UNMutableNotificationContent()

        // Title based on tool name
        if let tool = toolName, !tool.isEmpty {
            content.title = "Permission: \(tool)"
        } else {
            content.title = "Claude needs permission"
        }

        // Body with description
        var body = description
        if let workspace = workspaceName, !workspace.isEmpty {
            body = "[\(workspace)] \(description)"
        }
        content.body = body

        // Sound for attention
        content.sound = .default

        // Badge count
        content.badge = 1

        // Category for actions (can be extended later for approve/deny actions)
        content.categoryIdentifier = "PERMISSION_REQUEST"

        // User info for handling tap
        var userInfo: [String: Any] = ["type": "permission"]
        if let tool = toolName {
            userInfo["tool"] = tool
        }
        content.userInfo = userInfo

        // Create request with immediate trigger
        let request = UNNotificationRequest(
            identifier: NotificationID.permissionRequest,
            content: content,
            trigger: nil // Immediate delivery
        )

        do {
            try await notificationCenter.add(request)
            AppLogger.log("[Notification] Permission notification sent: \(toolName ?? "unknown")")
        } catch {
            AppLogger.log("[Notification] Failed to send: \(error)", type: .error)
        }
    }

    /// Clear the permission notification (when permission is handled)
    func clearPermissionNotification() {
        notificationCenter.removeDeliveredNotifications(
            withIdentifiers: [NotificationID.permissionRequest]
        )
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [NotificationID.permissionRequest]
        )

        // Clear badge
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = 0
        }

        AppLogger.log("[Notification] Cleared permission notification")
    }

    /// Clear all notifications and badge
    func clearAll() {
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.removeAllPendingNotificationRequests()

        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
}

// MARK: - UNAuthorizationStatus Description

extension UNAuthorizationStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }
}
