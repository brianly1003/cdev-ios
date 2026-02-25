import AudioToolbox
import UIKit

/// Haptic feedback utility
/// Automatically respects the "Haptic Feedback" setting from user preferences
/// All methods check the setting before triggering - no need to check manually
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let throttleLock = NSLock()
    private static var lastEmissionAtByKey: [String: TimeInterval] = [:]

    /// Check if haptic feedback is enabled in settings
    /// Returns true by default if setting hasn't been set
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Constants.UserDefaults.hapticFeedback) as? Bool ?? true
    }

    private static func shouldEmit(
        key: String,
        minInterval: TimeInterval,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> Bool {
        throttleLock.lock()
        defer { throttleLock.unlock() }

        let previous = lastEmissionAtByKey[key] ?? 0
        guard now - previous >= minInterval else { return false }
        lastEmissionAtByKey[key] = now
        return true
    }

    private static func emit(
        key: String,
        minInterval: TimeInterval,
        action: @escaping () -> Void
    ) {
        guard isEnabled else { return }
        guard shouldEmit(key: key, minInterval: minInterval) else { return }

        let performAction = {
            guard isEnabled else { return }
            action()
        }

        if Thread.isMainThread {
            performAction()
        } else {
            DispatchQueue.main.async(execute: performAction)
        }
    }

    static func light() {
        emit(key: "impact.light", minInterval: 0.05) {
            lightGenerator.impactOccurred()
            lightGenerator.prepare()
        }
    }

    static func medium() {
        emit(key: "impact.medium", minInterval: 0.05) {
            mediumGenerator.impactOccurred()
            mediumGenerator.prepare()
        }
    }

    static func heavy() {
        emit(key: "impact.heavy", minInterval: 0.05) {
            heavyGenerator.impactOccurred()
            heavyGenerator.prepare()
        }
    }

    static func selection() {
        emit(key: "selection", minInterval: 0.03) {
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        }
    }

    static func success() {
        emit(key: "notification.success", minInterval: 0.1) {
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
        }
    }

    static func warning() {
        emit(key: "notification.warning", minInterval: 0.1) {
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
        }
    }

    static func error() {
        emit(key: "notification.error", minInterval: 0.1) {
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
        }
    }

    /// Warning haptic + audible alert sound for permission prompts
    /// Plays system sound (tri-tone) when app is in foreground to grab attention
    static func permissionAlert() {
        emit(key: "permission.alert", minInterval: 1.0) {
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
            // System sound 1016 = short tri-tone alert
            AudioServicesPlaySystemSound(1016)
        }
    }

    /// Prepare generators for immediate feedback
    static func prepare() {
        guard isEnabled else { return }

        let doPrepare = {
            lightGenerator.prepare()
            mediumGenerator.prepare()
            heavyGenerator.prepare()
            selectionGenerator.prepare()
            notificationGenerator.prepare()
        }

        if Thread.isMainThread {
            doPrepare()
        } else {
            DispatchQueue.main.async(execute: doPrepare)
        }
    }
}
