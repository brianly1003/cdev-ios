import SwiftUI

/// Gradient definitions following CleanerApp design guidelines
enum Gradients {
    /// Primary hero gradient (blue to purple)
    static let primaryHero = LinearGradient(
        colors: [Color.primaryBlue, Color.secondaryPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Success gradient
    static let success = LinearGradient(
        colors: [Color.accentGreen, Color(hex: "#30D158")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warning gradient
    static let warning = LinearGradient(
        colors: [Color.warningOrange, Color(hex: "#FFD60A")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Error gradient
    static let error = LinearGradient(
        colors: [Color.errorRed, Color(hex: "#FF6961")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Neutral/idle gradient
    static let neutral = LinearGradient(
        colors: [Color.gray, Color.secondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Dark overlay gradient (for text on images)
    static let darkOverlay = LinearGradient(
        colors: [Color.clear, Color.black.opacity(0.7)],
        startPoint: .top,
        endPoint: .bottom
    )
}
