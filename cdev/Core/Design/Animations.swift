import SwiftUI

/// Pulse Terminal Animation System
/// Consistent motion language for the cdev app
enum Animations {
    // MARK: - Signature Animations

    /// Breathing pulse animation - signature cdev effect for active states
    static let pulse = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)

    /// Quick state transition
    static let stateChange = Animation.spring(response: 0.25, dampingFraction: 0.8)

    /// Tab selection slide
    static let tabSlide = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Banner appear/disappear
    static let bannerTransition = Animation.spring(response: 0.35, dampingFraction: 0.75)

    /// Log entry appear
    static let logAppear = Animation.easeOut(duration: 0.15)

    /// Glow intensity change
    static let glowPulse = Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)

    /// Micro-interaction
    static let micro = Animation.easeInOut(duration: 0.1)

    /// Standard fade
    static let fade = Animation.easeInOut(duration: 0.2)

    // MARK: - Durations

    enum Duration {
        static let micro: Double = 0.1
        static let fast: Double = 0.15
        static let standard: Double = 0.25
        static let slow: Double = 0.35
        static let pulse: Double = 1.5
    }

    // MARK: - Transitions

    static let slideUp = AnyTransition.move(edge: .bottom).combined(with: .opacity)
    static let slideDown = AnyTransition.move(edge: .top).combined(with: .opacity)
    static let slideLeft = AnyTransition.move(edge: .trailing).combined(with: .opacity)
    static let slideRight = AnyTransition.move(edge: .leading).combined(with: .opacity)
    static let fadeScale = AnyTransition.scale(scale: 0.95).combined(with: .opacity)
    static let fadeOnly = AnyTransition.opacity
}

// MARK: - View Modifiers

extension View {
    /// Apply pulse animation when condition is true
    func pulseWhen(_ condition: Bool) -> some View {
        scaleEffect(condition ? 1.05 : 1.0)
            .opacity(condition ? 0.9 : 1.0)
            .animation(condition ? Animations.pulse : .none, value: condition)
    }

    /// Apply glow effect when condition is true
    func glowWhen(_ condition: Bool, color: Color) -> some View {
        shadow(
            color: condition ? color.opacity(0.6) : .clear,
            radius: condition ? 6 : 0
        )
        .animation(condition ? Animations.glowPulse : .none, value: condition)
    }

    /// Scale effect on press with spring animation
    func pressScale(_ isPressed: Bool, scale: CGFloat = 0.95) -> some View {
        scaleEffect(isPressed ? scale : 1.0)
            .animation(Animations.micro, value: isPressed)
    }

    /// Animated visibility toggle
    func animatedVisibility(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .animation(Animations.stateChange, value: isVisible)
    }
}
