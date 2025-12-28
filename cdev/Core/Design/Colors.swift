import SwiftUI

/// Color palette following CleanerApp design guidelines
extension Color {
    // MARK: - Primary Colors

    /// Primary brand blue (iOS system blue)
    static let primaryBlue = Color(hex: "#007AFF")

    /// Secondary purple
    static let secondaryPurple = Color(hex: "#5856D6")

    /// Accent green for success states
    static let accentGreen = Color(hex: "#34C759")

    /// Warning orange
    static let warningOrange = Color(hex: "#FF9500")

    /// Error/destructive red
    static let errorRed = Color(hex: "#FF3B30")

    // MARK: - Semantic Colors

    /// Success color
    static let success = accentGreen

    /// Warning color
    static let warning = warningOrange

    /// Error color
    static let error = errorRed

    // MARK: - Status Colors

    /// Claude running status
    static let statusRunning = accentGreen

    /// Claude idle status
    static let statusIdle = Color.secondary

    /// Claude waiting status
    static let statusWaiting = warningOrange

    /// Claude error status
    static let statusError = errorRed

    // MARK: - Diff Colors

    /// Added lines in diff
    static let diffAdded = Color(hex: "#22863a")

    /// Removed lines in diff
    static let diffRemoved = Color(hex: "#cb2431")

    /// Modified context
    static let diffContext = Color.secondary

    // MARK: - Log Colors

    /// Standard log output
    static let logStdout = Color.primary

    /// Error log output
    static let logStderr = errorRed

    /// System/info log
    static let logInfo = primaryBlue

    // MARK: - Hex Initializer

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: - Adaptive Color Initializer (Light/Dark Mode)

    /// Creates an adaptive color that automatically switches between light and dark mode
    /// - Parameters:
    ///   - light: Hex color for light mode
    ///   - dark: Hex color for dark mode
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(Color(hex: dark))
            default:
                return UIColor(Color(hex: light))
            }
        })
    }
}
