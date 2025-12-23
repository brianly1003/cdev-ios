import SwiftUI

/// Centralized responsive layout system for consistent sizing across iPhone/iPad
/// Usage: Access via @Environment(\.responsiveLayout) or use ResponsiveLayout.current(for:)
///
/// Example:
/// ```swift
/// struct MyView: View {
///     @Environment(\.horizontalSizeClass) private var sizeClass
///     private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }
///
///     var body: some View {
///         Text("Hello")
///             .font(layout.bodyFont)
///             .padding(layout.standardPadding)
///     }
/// }
/// ```
struct ResponsiveLayout {
    let isCompact: Bool

    // MARK: - Spacing

    /// Standard horizontal padding (sm on iPhone, md on iPad)
    var standardPadding: CGFloat { isCompact ? Spacing.sm : Spacing.md }

    /// Large horizontal padding (md on iPhone, lg on iPad)
    var largePadding: CGFloat { isCompact ? Spacing.md : Spacing.lg }

    /// Small horizontal padding (xs on iPhone, sm on iPad)
    var smallPadding: CGFloat { isCompact ? Spacing.xs : Spacing.sm }

    /// Tight spacing for very compact layouts (4pt on iPhone, 8pt on iPad)
    var tightSpacing: CGFloat { isCompact ? 4 : 8 }

    /// Ultra-tight spacing for minimal layouts (2pt on iPhone, 4pt on iPad)
    var ultraTightSpacing: CGFloat { isCompact ? 2 : 4 }

    /// Content spacing between elements
    var contentSpacing: CGFloat { isCompact ? Spacing.xs : Spacing.sm }

    /// Section spacing
    var sectionSpacing: CGFloat { isCompact ? Spacing.md : Spacing.lg }

    // MARK: - Icon Sizes

    /// Small icon (9pt on iPhone, 10pt on iPad)
    var iconSmall: CGFloat { isCompact ? 9 : 10 }

    /// Medium icon (12pt on iPhone, 14pt on iPad)
    var iconMedium: CGFloat { isCompact ? 12 : 14 }

    /// Action icon for buttons (14pt on iPhone, 16pt on iPad)
    var iconAction: CGFloat { isCompact ? 14 : 16 }

    /// Large icon (16pt on iPhone, 18pt on iPad)
    var iconLarge: CGFloat { isCompact ? 16 : 18 }

    /// Extra large icon (24pt on iPhone, 28pt on iPad)
    var iconXLarge: CGFloat { isCompact ? 24 : 28 }

    // MARK: - Component Sizes

    /// Button height
    var buttonHeight: CGFloat { isCompact ? 32 : 40 }

    /// Small button height
    var buttonHeightSmall: CGFloat { isCompact ? 28 : 32 }

    /// Input field height
    var inputHeight: CGFloat { isCompact ? 40 : 48 }

    /// Status indicator size
    var indicatorSize: CGFloat { isCompact ? 32 : 36 }

    /// Small indicator size
    var indicatorSizeSmall: CGFloat { isCompact ? 12 : 14 }

    /// Dot size (for status dots)
    var dotSize: CGFloat { isCompact ? 6 : 7 }

    /// Avatar/thumbnail size
    var avatarSize: CGFloat { isCompact ? 32 : 40 }

    // MARK: - Typography (Font instances)

    /// Body font - use for main content
    var bodyFont: Font { isCompact ? Typography.body : Typography.bodyBold }

    /// Caption font - use for secondary text
    var captionFont: Font { isCompact ? Typography.caption1 : Typography.body }

    /// Label font - use for buttons, labels
    var labelFont: Font { isCompact ? Typography.caption1 : Typography.body }

    /// Terminal font - use for code/log output
    var terminalFont: Font { isCompact ? Typography.terminal : Typography.terminal }

    // MARK: - Line widths

    /// Standard border width
    var borderWidth: CGFloat { isCompact ? 1 : 1.5 }

    /// Thick border width
    var borderWidthThick: CGFloat { isCompact ? 1.5 : 2 }

    /// Divider width
    var dividerWidth: CGFloat { isCompact ? 0.5 : 1 }

    // MARK: - Shadow

    /// Standard shadow radius
    var shadowRadius: CGFloat { isCompact ? 4 : 6 }

    /// Large shadow radius
    var shadowRadiusLarge: CGFloat { isCompact ? 8 : 12 }

    // MARK: - Factory

    /// Get layout for current size class
    static func current(for sizeClass: UserInterfaceSizeClass?) -> ResponsiveLayout {
        ResponsiveLayout(isCompact: sizeClass == .compact)
    }

    /// Compact layout (iPhone)
    static let compact = ResponsiveLayout(isCompact: true)

    /// Regular layout (iPad)
    static let regular = ResponsiveLayout(isCompact: false)
}

// MARK: - Environment Key

private struct ResponsiveLayoutKey: EnvironmentKey {
    static let defaultValue = ResponsiveLayout.compact
}

extension EnvironmentValues {
    var responsiveLayout: ResponsiveLayout {
        get { self[ResponsiveLayoutKey.self] }
        set { self[ResponsiveLayoutKey.self] = newValue }
    }
}

// MARK: - View Modifier for Auto Layout Detection

/// Automatically injects ResponsiveLayout based on horizontalSizeClass
struct ResponsiveLayoutModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .environment(\.responsiveLayout, ResponsiveLayout.current(for: sizeClass))
    }
}

extension View {
    /// Apply responsive layout to this view and all children
    /// Usage: `.withResponsiveLayout()`
    func withResponsiveLayout() -> some View {
        modifier(ResponsiveLayoutModifier())
    }
}

// MARK: - Convenience View Extensions

extension View {
    /// Apply standard padding based on device size
    func responsivePadding(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        let layout = ResponsiveLayout.current(for: sizeClass)
        return padding(.horizontal, layout.standardPadding)
            .padding(.vertical, layout.smallPadding)
    }

    /// Apply large padding based on device size
    func responsivePaddingLarge(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        let layout = ResponsiveLayout.current(for: sizeClass)
        return padding(.horizontal, layout.largePadding)
            .padding(.vertical, layout.standardPadding)
    }
}

// MARK: - Responsive Conditional Content

/// Show different content for compact vs regular layouts
struct ResponsiveContent<Compact: View, Regular: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    let compact: () -> Compact
    let regular: () -> Regular

    init(
        @ViewBuilder compact: @escaping () -> Compact,
        @ViewBuilder regular: @escaping () -> Regular
    ) {
        self.compact = compact
        self.regular = regular
    }

    var body: some View {
        if sizeClass == .compact {
            compact()
        } else {
            regular()
        }
    }
}
