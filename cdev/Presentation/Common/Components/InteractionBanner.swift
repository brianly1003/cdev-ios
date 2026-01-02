import SwiftUI

/// Compact banner for pending interactions (permissions, questions)
struct InteractionBanner: View {
    let interaction: PendingInteraction
    let onApprove: () -> Void
    let onDeny: () -> Void
    let onAnswer: (String) -> Void
    /// PTY mode: respond with a key (e.g., "1", "2", "n")
    var onPTYResponse: ((String) -> Void)?

    @State private var answerText = ""

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Header
            HStack(spacing: Spacing.xs) {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)

                Text(headerText)
                    .font(Typography.bodyBold)

                Spacer()

                Text(interaction.timestamp.relativeString)
                    .font(Typography.terminalTimestamp)
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            // Description
            Text(interaction.description)
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)

            // Actions
            switch interaction.type {
            case .permission:
                PermissionActions(onApprove: onApprove, onDeny: onDeny)

            case .ptyPermission:
                // PTY mode: show options with key shortcuts
                if let ptyOptions = interaction.ptyOptions, !ptyOptions.isEmpty {
                    PTYPermissionOptions(options: ptyOptions) { key in
                        onPTYResponse?(key)
                    }
                } else {
                    // Fallback to standard Yes/No (using keys "1" and "n")
                    PermissionActions(
                        onApprove: { onPTYResponse?("1") },
                        onDeny: { onPTYResponse?("n") }
                    )
                }

            case .question:
                if let options = interaction.options, !options.isEmpty {
                    QuestionOptions(options: options, onSelect: onAnswer)
                } else {
                    QuestionInput(text: $answerText, onSubmit: {
                        onAnswer(answerText)
                        answerText = ""
                    })
                }
            }
        }
        .padding(Spacing.sm)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }

    private var iconName: String {
        switch interaction.type {
        case .permission: return "lock.shield"
        case .ptyPermission: return "terminal"
        case .question: return "questionmark.bubble"
        }
    }

    private var iconColor: Color {
        switch interaction.type {
        case .permission: return .warningOrange
        case .ptyPermission: return .warningOrange
        case .question: return .primaryBlue
        }
    }

    private var headerText: String {
        switch interaction.type {
        case .permission(let tool): return "Permission: \(tool)"
        case .ptyPermission(let type, let toolName):
            let title = toolName ?? type.displayName
            return "Permission: \(title)"
        case .question: return "Question"
        }
    }

    private var bannerBackground: Color {
        switch interaction.type {
        case .permission: return Color.warningOrange.opacity(0.15)
        case .ptyPermission: return Color.warningOrange.opacity(0.15)
        case .question: return Color.primaryBlue.opacity(0.15)
        }
    }
}

// MARK: - PTY Permission Type Extension

extension PTYPermissionType {
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .writeFile: return "Write File"
        case .editFile: return "Edit File"
        case .deleteFile: return "Delete File"
        case .bashCommand: return "Command"
        case .mcpTool: return "MCP Tool"
        case .trustFolder: return "Trust Folder"
        case .unknown: return "Permission"
        }
    }
}

// MARK: - Permission Actions

struct PermissionActions: View {
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onDeny) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "xmark")
                    Text("Deny")
                }
                .font(Typography.footnote)
                .fontWeight(.medium)
                .foregroundStyle(Color.errorRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background(Color.errorRed.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
            .pressEffect()

            Button(action: onApprove) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "checkmark")
                    Text("Allow")
                }
                .font(Typography.footnote)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background(Color.accentGreen)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
            .pressEffect()
        }
    }
}

// MARK: - Question Options

struct QuestionOptions: View {
    let options: [QuestionOption]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(options) { option in
                Button {
                    onSelect(option.label)
                } label: {
                    HStack {
                        Text(option.label)
                            .font(Typography.footnote)
                            .fontWeight(.medium)

                        Spacer()

                        if let description = option.description {
                            Text(description)
                                .font(Typography.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                }
                .buttonStyle(.plain)
                .pressEffect()
            }
        }
    }
}

// MARK: - Question Input

struct QuestionInput: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            TextField("Type your answer...", text: $text)
                .font(Typography.footnote)
                .textFieldStyle(.plain)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                .submitLabel(.send)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(text.isBlank ? .secondary : Color.primaryBlue)
            }
            .disabled(text.isBlank)
        }
    }
}

// MARK: - PTY Permission Options (Legacy - used in InteractionBanner)

/// Displays PTY permission options with keyboard shortcut keys (horizontal layout)
struct PTYPermissionOptions: View {
    let options: [PTYPromptOption]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(options) { option in
                Button {
                    onSelect(option.key)
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        // Key badge (e.g., "1", "2", "n")
                        Text(option.key)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(buttonColor(for: option))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(option.label)
                            .font(Typography.footnote)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(buttonColor(for: option))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(buttonColor(for: option).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                }
                .pressEffect()
            }
        }
    }

    /// Color based on option type (approve = green, deny = red, other = blue)
    private func buttonColor(for option: PTYPromptOption) -> Color {
        PTYPermissionPanel.buttonColor(for: option)
    }
}

// MARK: - PTY Permission Panel (Sophisticated Bottom Panel)

/// A sophisticated, compact permission panel positioned above the chat input.
/// Designed following Claude Code CLI style with keyboard shortcut indicators.
/// Supports iPhone and iPad via ResponsiveLayout.
struct PTYPermissionPanel: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    let interaction: PendingInteraction
    let onResponse: (String) -> Void
    var onDismiss: (() -> Void)?  // Optional dismiss callback

    /// Computed options - either from PTY payload or standard Yes/No
    private var options: [PTYPromptOption] {
        if let ptyOptions = interaction.ptyOptions, !ptyOptions.isEmpty {
            return ptyOptions
        }
        // Fallback options (first option is selected by default)
        return [
            PTYPromptOption(key: "1", label: "Yes", description: nil, selected: true),
            PTYPromptOption(key: "n", label: "No", description: nil, selected: false)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Divider line
            Rectangle()
                .fill(ColorSystem.textQuaternary.opacity(0.3))
                .frame(height: layout.dividerWidth)

            VStack(spacing: layout.tightSpacing) {
                // Header row with icon and description
                headerRow

                // Options as compact vertical rows
                optionsStack
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, layout.smallPadding)
            .background(ColorSystem.terminalBgElevated)
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: layout.contentSpacing) {
            // Permission icon with type indicator
            ZStack {
                Circle()
                    .fill(Color.warningOrange.opacity(0.15))
                    .frame(width: layout.indicatorSizeSmall + 8, height: layout.indicatorSizeSmall + 8)

                Image(systemName: permissionIcon)
                    .font(.system(size: layout.iconSmall, weight: .semibold))
                    .foregroundStyle(Color.warningOrange)
            }

            // Permission description - truncated
            Text(interaction.description)
                .font(layout.captionFont)
                .foregroundStyle(ColorSystem.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            // Close button to dismiss permission panel
            if let onDismiss = onDismiss {
                Button {
                    onDismiss()
                    Haptics.light()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: layout.iconMedium, weight: .semibold))
                        .foregroundStyle(ColorSystem.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(ColorSystem.terminalBgHighlight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Options Stack

    private var optionsStack: some View {
        VStack(spacing: layout.ultraTightSpacing) {
            ForEach(options) { option in
                PTYOptionRow(
                    option: option,
                    layout: layout,
                    onSelect: { onResponse(option.key) }
                )
            }
        }
    }

    // MARK: - Helpers

    private var permissionIcon: String {
        guard case .ptyPermission(let type, _) = interaction.type else {
            return "lock.shield.fill"
        }
        switch type {
        case .writeFile, .editFile: return "doc.fill"
        case .deleteFile: return "trash.fill"
        case .bashCommand: return "terminal.fill"
        case .mcpTool: return "puzzlepiece.fill"
        case .trustFolder: return "folder.fill"
        case .unknown: return "lock.shield.fill"
        }
    }

    /// Shared color logic for PTY options
    /// Supports both PTY mode keys (1, 2, n) and hook bridge keys (allow_once, allow_session, deny)
    static func buttonColor(for option: PTYPromptOption) -> Color {
        let label = option.label.lowercased()
        let key = option.key.lowercased()

        // Approval options - green
        // PTY keys: 1, 2, y
        // Hook bridge keys: allow_once, allow_session
        if label.contains("yes") || label.contains("allow") ||
           key == "1" || key == "2" || key == "y" ||
           key == "allow_once" || key == "allow_session" {
            return Color.accentGreen
        }

        // Denial options - red
        // PTY keys: n, esc
        // Hook bridge keys: deny
        if label.contains("no") || label.contains("deny") ||
           key == "n" || key == "esc" || key == "deny" {
            return Color.errorRed
        }

        // Input/other options - blue
        if label.contains("type") || key == "3" {
            return Color.primaryBlue
        }

        // Default
        return Color.primaryBlue
    }
}

// MARK: - PTY Option Row

/// A single option row in the PTY permission panel.
/// Large touch targets for quick mobile interaction.
private struct PTYOptionRow: View {
    let option: PTYPromptOption
    let layout: ResponsiveLayout
    let onSelect: () -> Void

    private var color: Color { PTYPermissionPanel.buttonColor(for: option) }

    /// Minimum touch target height (44pt per Apple HIG)
    private var minHeight: CGFloat { layout.isCompact ? 44 : 48 }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: layout.contentSpacing) {
                // Keyboard shortcut badge
                keyBadge

                // Option label - smaller font, 2 lines allowed
                Text(option.label)
                    .font(layout.captionFont)
                    .fontWeight(.medium)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Description (if any) - only show if label is short
                if let description = option.description, !description.isEmpty,
                   option.label.count < 20 {
                    Text(description)
                        .font(.system(size: layout.iconSmall, weight: .regular))
                        .foregroundStyle(ColorSystem.textTertiary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: layout.isCompact ? 100 : 160, alignment: .trailing)
                }

                // Arrow indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: layout.iconSmall, weight: .semibold))
                    .foregroundStyle(color.opacity(0.7))
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, layout.smallPadding)
            .frame(minHeight: minHeight)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .strokeBorder(color.opacity(0.25), lineWidth: layout.borderWidth)
            )
        }
        .buttonStyle(PTYOptionButtonStyle(color: color))
    }

    private var keyBadge: some View {
        Text(formatKey(option.key))
            .font(.system(size: layout.iconMedium, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Format special keys for display
    /// Supports both PTY mode keys and hook bridge keys
    private func formatKey(_ key: String) -> String {
        switch key.lowercased() {
        // PTY mode special keys
        case "esc", "escape": return "⎋"
        case "enter", "return": return "↵"
        case "tab": return "⇥"
        // Hook bridge mode keys - use intuitive symbols
        case "allow_once": return "✓"
        case "allow_session": return "✓+"
        case "deny": return "✗"
        // Default: show key as-is (uppercased if short, or first letter)
        default:
            if key.count <= 2 {
                return key.uppercased()
            } else {
                // For long keys, just show first letter
                return String(key.prefix(1)).uppercased()
            }
        }
    }
}

// MARK: - PTY Option Button Style

/// Custom button style with press feedback for PTY options
private struct PTYOptionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
