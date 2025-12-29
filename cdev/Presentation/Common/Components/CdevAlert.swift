import SwiftUI

// MARK: - Alert Type

/// Alert types with semantic meaning and styling
/// Colors follow CDEV-COLOR-SYSTEM.md:
/// - Error (Signal Coral #FC8181): Errors, destructive actions
/// - Warning (Golden Pulse #F6C85D): Caution, pending states
/// - Success (Terminal Mint #68D391): Completed, approved
/// - Info (Stream Blue #63B3ED): Informational messages
enum CdevAlertType {
    case error
    case warning
    case success
    case info

    var icon: String {
        switch self {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .error: return ColorSystem.error
        case .warning: return ColorSystem.warning
        case .success: return ColorSystem.success
        case .info: return ColorSystem.info
        }
    }

    /// Glow color for icon background (from ColorSystem)
    var glowColor: Color {
        switch self {
        case .error: return ColorSystem.errorGlow
        case .warning: return ColorSystem.warningGlow
        case .success: return ColorSystem.successGlow
        case .info: return ColorSystem.infoGlow
        }
    }

    var defaultTitle: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .success: return "Success"
        case .info: return "Info"
        }
    }
}

// MARK: - Alert Action

/// Action button for alerts
struct CdevAlertAction: Identifiable {
    let id = UUID()
    let title: String
    let style: ActionStyle
    let action: () -> Void

    enum ActionStyle {
        case primary
        case secondary
        case destructive
    }

    /// Quick initializer for OK button
    static func ok(_ action: @escaping () -> Void = {}) -> CdevAlertAction {
        CdevAlertAction(title: "OK", style: .primary, action: action)
    }

    /// Quick initializer for Cancel button
    static func cancel(_ action: @escaping () -> Void = {}) -> CdevAlertAction {
        CdevAlertAction(title: "Cancel", style: .secondary, action: action)
    }

    /// Quick initializer for destructive action
    static func destructive(_ title: String, action: @escaping () -> Void) -> CdevAlertAction {
        CdevAlertAction(title: title, style: .destructive, action: action)
    }
}

// MARK: - Alert Configuration

/// Configuration for displaying an alert
struct CdevAlertConfig: Identifiable {
    let id = UUID()
    let type: CdevAlertType
    let title: String?
    let message: String
    let codeBlock: String?  // Optional code block displayed with left alignment
    let actions: [CdevAlertAction]

    init(
        type: CdevAlertType,
        title: String? = nil,
        message: String,
        codeBlock: String? = nil,
        actions: [CdevAlertAction] = [.ok()]
    ) {
        self.type = type
        self.title = title
        self.message = message
        self.codeBlock = codeBlock
        self.actions = actions
    }

    // MARK: - Convenience Initializers

    /// Error alert with OK button
    static func error(_ message: String, title: String? = nil, onDismiss: @escaping () -> Void = {}) -> CdevAlertConfig {
        CdevAlertConfig(type: .error, title: title, message: message, codeBlock: nil, actions: [.ok(onDismiss)])
    }

    /// Error alert with code block
    static func error(_ message: String, codeBlock: String, title: String? = nil, onDismiss: @escaping () -> Void = {}) -> CdevAlertConfig {
        CdevAlertConfig(type: .error, title: title, message: message, codeBlock: codeBlock, actions: [.ok(onDismiss)])
    }

    /// Warning alert with OK button
    static func warning(_ message: String, title: String? = nil, onDismiss: @escaping () -> Void = {}) -> CdevAlertConfig {
        CdevAlertConfig(type: .warning, title: title, message: message, codeBlock: nil, actions: [.ok(onDismiss)])
    }

    /// Success alert with OK button
    static func success(_ message: String, title: String? = nil, onDismiss: @escaping () -> Void = {}) -> CdevAlertConfig {
        CdevAlertConfig(type: .success, title: title, message: message, codeBlock: nil, actions: [.ok(onDismiss)])
    }

    /// Info alert with OK button
    static func info(_ message: String, title: String? = nil, onDismiss: @escaping () -> Void = {}) -> CdevAlertConfig {
        CdevAlertConfig(type: .info, title: title, message: message, codeBlock: nil, actions: [.ok(onDismiss)])
    }

    /// Confirmation alert with Cancel and Confirm buttons
    static func confirm(
        _ message: String,
        title: String? = nil,
        confirmTitle: String = "Confirm",
        onCancel: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void
    ) -> CdevAlertConfig {
        CdevAlertConfig(
            type: .warning,
            title: title,
            message: message,
            actions: [
                .cancel(onCancel),
                CdevAlertAction(title: confirmTitle, style: .primary, action: onConfirm)
            ]
        )
    }

    /// Destructive confirmation alert
    static func destructive(
        _ message: String,
        title: String? = nil,
        destructiveTitle: String = "Delete",
        onCancel: @escaping () -> Void = {},
        onDestroy: @escaping () -> Void
    ) -> CdevAlertConfig {
        CdevAlertConfig(
            type: .error,
            title: title,
            message: message,
            actions: [
                .cancel(onCancel),
                .destructive(destructiveTitle, action: onDestroy)
            ]
        )
    }
}

// MARK: - Alert View

/// Styled alert view matching cdev design system
/// Responsive design: Compact on iPhone, spacious on iPad
/// Following ResponsiveLayout system for consistent sizing
struct CdevAlertView: View {
    let config: CdevAlertConfig
    let onDismiss: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    // MARK: - Responsive Sizing

    /// Alert max width: 310pt iPhone, 400pt iPad
    private var alertMaxWidth: CGFloat { layout.isCompact ? 310 : 400 }

    /// Icon container size: 44pt iPhone, 56pt iPad
    private var iconContainerSize: CGFloat { layout.isCompact ? 44 : 56 }

    /// Icon size: 22pt iPhone, 28pt iPad
    private var iconSize: CGFloat { layout.isCompact ? 22 : 28 }

    /// Button height: 44pt iPhone, 48pt iPad
    private var buttonHeight: CGFloat { layout.isCompact ? 44 : 48 }

    /// Message max height: 160pt iPhone, 200pt iPad
    private var messageMaxHeight: CGFloat { layout.isCompact ? 160 : 200 }

    var body: some View {
        ZStack {
            // Backdrop - slightly darker for better focus
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    // Dismiss on backdrop tap only if single OK action
                    if config.actions.count == 1 {
                        config.actions.first?.action()
                        onDismiss()
                    }
                }

            // Alert card - centered with max width constraint
            VStack(spacing: 0) {
                // Header with icon
                VStack(spacing: layout.smallPadding) {
                    // Icon with glow effect (responsive sizing)
                    ZStack {
                        Circle()
                            .fill(config.type.glowColor)
                            .frame(width: iconContainerSize, height: iconContainerSize)

                        Image(systemName: config.type.icon)
                            .font(.system(size: iconSize, weight: .medium))
                            .foregroundStyle(config.type.color)
                    }

                    // Title
                    Text(config.title ?? config.type.defaultTitle)
                        .font(layout.bodyFont)
                        .foregroundStyle(ColorSystem.textPrimary)
                }
                .padding(.top, layout.standardPadding)
                .padding(.bottom, layout.smallPadding)

                // Message - scrollable with responsive max height
                ScrollView {
                    VStack(spacing: layout.contentSpacing) {
                        // Message text (centered)
                        Text(config.message)
                            .font(layout.isCompact ? Typography.terminalSmall : Typography.terminal)
                            .foregroundStyle(ColorSystem.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(layout.isCompact ? 3 : 4)
                            .fixedSize(horizontal: false, vertical: true)

                        // Code block (left-aligned, monospace, with background)
                        if let codeBlock = config.codeBlock {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(codeBlock.components(separatedBy: "\n"), id: \.self) { line in
                                    Text(line)
                                        .font(Typography.terminal)
                                        .foregroundStyle(ColorSystem.textPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(layout.smallPadding)
                            .background(ColorSystem.terminalBg)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                        }
                    }
                }
                .frame(maxHeight: messageMaxHeight)
                .padding(.horizontal, layout.standardPadding)
                .padding(.bottom, layout.standardPadding)

                Divider()
                    .overlay(ColorSystem.terminalBgHighlight)

                // Actions
                actionButtons
            }
            .frame(maxWidth: alertMaxWidth)
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: layout.isCompact ? CornerRadius.medium : CornerRadius.large))
            .shadow(color: .black.opacity(0.3), radius: layout.shadowRadiusLarge, x: 0, y: 4)
            .padding(.horizontal, layout.largePadding)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if config.actions.count == 1 {
            // Single button - full width
            if let action = config.actions.first {
                Button {
                    action.action()
                    onDismiss()
                } label: {
                    Text(action.title)
                        .font(Typography.buttonLabel)
                        .foregroundStyle(buttonTextColor(for: action.style))
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                }
                .buttonStyle(.plain)
            }
        } else {
            // Multiple buttons - horizontal layout
            HStack(spacing: 0) {
                ForEach(Array(config.actions.enumerated()), id: \.element.id) { index, action in
                    Button {
                        action.action()
                        onDismiss()
                    } label: {
                        Text(action.title)
                            .font(Typography.buttonLabel)
                            .foregroundStyle(buttonTextColor(for: action.style))
                            .frame(maxWidth: .infinity)
                            .frame(height: buttonHeight)
                    }
                    .buttonStyle(.plain)

                    // Divider between buttons
                    if index < config.actions.count - 1 {
                        Divider()
                            .overlay(ColorSystem.terminalBgHighlight)
                    }
                }
            }
        }
    }

    private func buttonTextColor(for style: CdevAlertAction.ActionStyle) -> Color {
        switch style {
        case .primary: return ColorSystem.primary
        case .secondary: return ColorSystem.textSecondary
        case .destructive: return ColorSystem.error
        }
    }
}

// MARK: - View Modifier

/// View modifier for presenting cdev alerts
struct CdevAlertModifier: ViewModifier {
    @Binding var config: CdevAlertConfig?

    func body(content: Content) -> some View {
        ZStack {
            content

            if let alertConfig = config {
                CdevAlertView(config: alertConfig) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        config = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(1000)
            }
        }
        .animation(.easeOut(duration: 0.2), value: config != nil)
    }
}

// MARK: - View Extension

extension View {
    /// Present a styled cdev alert
    func cdevAlert(_ config: Binding<CdevAlertConfig?>) -> some View {
        modifier(CdevAlertModifier(config: config))
    }
}

// MARK: - Previews

#Preview("Error Alert") {
    struct PreviewWrapper: View {
        @State private var alert: CdevAlertConfig? = .error(
            """
            Branch 'main' does not exist yet.

            This usually means no commits have been made. Please try running these commands on your PC/laptop:

            git add .
            git commit -m "Initial commit"
            git push -u origin main
            """
        )

        var body: some View {
            ZStack {
                ColorSystem.terminalBg.ignoresSafeArea()
                Text("Content behind alert")
                    .foregroundStyle(ColorSystem.textPrimary)
            }
            .cdevAlert($alert)
        }
    }
    return PreviewWrapper()
}

#Preview("Warning Alert") {
    struct PreviewWrapper: View {
        @State private var alert: CdevAlertConfig? = .warning(
            "This action cannot be undone.",
            title: "Are you sure?"
        )

        var body: some View {
            ZStack {
                ColorSystem.terminalBg.ignoresSafeArea()
            }
            .cdevAlert($alert)
        }
    }
    return PreviewWrapper()
}

#Preview("Confirm Alert") {
    struct PreviewWrapper: View {
        @State private var alert: CdevAlertConfig? = .confirm(
            "Do you want to discard all unsaved changes?",
            title: "Discard Changes",
            confirmTitle: "Discard",
            onConfirm: {}
        )

        var body: some View {
            ZStack {
                ColorSystem.terminalBg.ignoresSafeArea()
            }
            .cdevAlert($alert)
        }
    }
    return PreviewWrapper()
}

#Preview("Success Alert") {
    struct PreviewWrapper: View {
        @State private var alert: CdevAlertConfig? = .success(
            "Your changes have been pushed to the remote repository.",
            title: "Push Complete"
        )

        var body: some View {
            ZStack {
                ColorSystem.terminalBg.ignoresSafeArea()
            }
            .cdevAlert($alert)
        }
    }
    return PreviewWrapper()
}
