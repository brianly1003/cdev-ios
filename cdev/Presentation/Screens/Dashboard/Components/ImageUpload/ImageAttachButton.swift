import SwiftUI

/// Image attachment button following cdev design system
/// Uses: ColorSystem, ResponsiveLayout, Typography, Spacing, CornerRadius
/// Animates from "+" to "×" when menu is open (Messenger-style)
struct ImageAttachButton: View {
    let attachedCount: Int
    let isUploading: Bool
    let hasError: Bool
    @Binding var isMenuOpen: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    @State private var rotation: Double = 0

    /// Icon to show based on state
    private var iconName: String {
        if attachedCount > 0 { return "photo.stack" }
        return "plus"  // Simple plus that rotates to X
    }

    /// Icon color based on state
    private var iconColor: Color {
        if isMenuOpen { return ColorSystem.primary }
        if attachedCount > 0 { return ColorSystem.primary }
        return ColorSystem.textTertiary
    }

    /// Background color based on state
    private var bgColor: Color {
        if isMenuOpen { return ColorSystem.primary.opacity(0.2) }
        if attachedCount > 0 { return ColorSystem.primary.opacity(0.15) }
        return ColorSystem.terminalBgHighlight
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Main icon with rotation animation
                ZStack {
                    // Rotating ring animation when uploading (same style as StopButtonWithAnimation)
                    if isUploading {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        ColorSystem.primary.opacity(0),
                                        ColorSystem.primary.opacity(0.3),
                                        ColorSystem.primary.opacity(0.6),
                                        ColorSystem.primary
                                    ]),
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(360)
                                ),
                                lineWidth: 2
                            )
                            .frame(width: layout.indicatorSize, height: layout.indicatorSize)
                            .rotationEffect(.degrees(rotation))
                    }

                    Image(systemName: iconName)
                        .font(.system(size: layout.iconAction + 2, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: layout.indicatorSize, height: layout.indicatorSize)
                        .background(bgColor)
                        .clipShape(Circle())
                        .rotationEffect(.degrees(isMenuOpen && attachedCount == 0 ? 45 : 0))  // + rotates to ×
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isMenuOpen)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    (attachedCount > 0 || isMenuOpen) ? ColorSystem.primaryGlow : .clear,
                                    lineWidth: layout.borderWidthThick
                                )
                        )
                }

                // Count badge - using Typography.badge styling
                if attachedCount > 0 {
                    Text("\(attachedCount)")
                        .font(Typography.badge)  // 9pt rounded bold
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(ColorSystem.primary)  // Cdev Teal
                        .clipShape(Circle())
                        .offset(x: Spacing.xxs, y: -Spacing.xxs)  // 4pt offset
                }

                // Error indicator - using ColorSystem.error (soft coral-red)
                if hasError && attachedCount == 0 {
                    Circle()
                        .fill(ColorSystem.error)  // #FC8181 dark mode
                        .frame(width: layout.dotSize + 2, height: layout.dotSize + 2)  // 8pt iPhone
                        .offset(x: Spacing.xxs, y: -Spacing.xxs)
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    Haptics.medium()
                    onLongPress()
                }
        )
        .onChange(of: isUploading) { _, uploading in
            if uploading {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                rotation = 0
            }
        }
        .accessibilityLabel("Attach image")
        .accessibilityHint("Opens menu to attach photos, take pictures, or capture screenshot")
        .accessibilityValue(attachedCount > 0 ? "\(attachedCount) images attached" : "No images attached")
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var isMenuOpen = false

        var body: some View {
            HStack(spacing: 20) {
                // Default state (tap to toggle)
                ImageAttachButton(
                    attachedCount: 0,
                    isUploading: false,
                    hasError: false,
                    isMenuOpen: $isMenuOpen,
                    onTap: { isMenuOpen.toggle() },
                    onLongPress: {}
                )

                // With images
                ImageAttachButton(
                    attachedCount: 2,
                    isUploading: false,
                    hasError: false,
                    isMenuOpen: .constant(false),
                    onTap: {},
                    onLongPress: {}
                )

                // Uploading
                ImageAttachButton(
                    attachedCount: 1,
                    isUploading: true,
                    hasError: false,
                    isMenuOpen: .constant(false),
                    onTap: {},
                    onLongPress: {}
                )

                // Menu open state
                ImageAttachButton(
                    attachedCount: 0,
                    isUploading: false,
                    hasError: false,
                    isMenuOpen: .constant(true),
                    onTap: {},
                    onLongPress: {}
                )
            }
            .padding()
            .background(ColorSystem.terminalBg)
        }
    }

    return PreviewWrapper()
}
