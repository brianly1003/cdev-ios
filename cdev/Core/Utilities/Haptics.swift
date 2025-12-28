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

    /// Check if haptic feedback is enabled in settings
    /// Returns true by default if setting hasn't been set
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Constants.UserDefaults.hapticFeedback) as? Bool ?? true
    }

    static func light() {
        guard isEnabled else { return }
        lightGenerator.impactOccurred()
    }

    static func medium() {
        guard isEnabled else { return }
        mediumGenerator.impactOccurred()
    }

    static func heavy() {
        guard isEnabled else { return }
        heavyGenerator.impactOccurred()
    }

    static func selection() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    static func success() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
    }

    static func error() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.error)
    }

    /// Prepare generators for immediate feedback
    static func prepare() {
        guard isEnabled else { return }
        lightGenerator.prepare()
        mediumGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }
}
