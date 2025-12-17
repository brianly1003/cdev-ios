import SwiftUI

/// Card style modifier following CleanerApp design patterns
struct CardStyle: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let useShadow: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: useShadow ? Color.black.opacity(0.1) : .clear,
                radius: useShadow ? 4 : 0,
                x: 0,
                y: useShadow ? 2 : 0
            )
    }
}

/// Gradient card style modifier
struct GradientCardStyle: ViewModifier {
    let gradient: LinearGradient
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - View Extensions

extension View {
    func cardStyle(
        padding: CGFloat = Spacing.md,
        cornerRadius: CGFloat = CornerRadius.large,
        useShadow: Bool = true
    ) -> some View {
        modifier(CardStyle(
            padding: padding,
            cornerRadius: cornerRadius,
            useShadow: useShadow
        ))
    }

    func gradientCard(
        gradient: LinearGradient = Gradients.primaryHero,
        padding: CGFloat = Spacing.lg,
        cornerRadius: CGFloat = CornerRadius.large
    ) -> some View {
        modifier(GradientCardStyle(
            gradient: gradient,
            padding: padding,
            cornerRadius: cornerRadius
        ))
    }
}
