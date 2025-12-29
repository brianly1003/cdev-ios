import SwiftUI

// MARK: - Git State Badge

/// Compact badge showing workspace git state
/// Colors follow CDEV-COLOR-SYSTEM.md:
/// - Warning (Golden Pulse #F6C85D): noGit, gitInitialized, noRemote, noPush
/// - Success (Terminal Mint #68D391): synced
/// - Info (Stream Blue #63B3ED): diverged
/// - Error (Signal Coral #FC8181): conflict
struct GitStateBadge: View {
    let state: WorkspaceGitState
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.icon)
                .font(.system(size: layout.iconSmall))
            Text(state.shortText)
                .font(Typography.badge)
        }
        .foregroundColor(stateColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(stateColor.opacity(0.15))
        .clipShape(Capsule())
    }

    /// State colors from ColorSystem following CDEV-COLOR-SYSTEM.md
    private var stateColor: Color {
        switch state {
        case .noGit, .gitInitialized, .noRemote, .noPush:
            // Golden Pulse - Warning states requiring action
            return ColorSystem.warning
        case .synced:
            // Terminal Mint - Success/healthy state
            return ColorSystem.success
        case .diverged:
            // Stream Blue - Informational state
            return ColorSystem.info
        case .conflict:
            // Signal Coral - Error state
            return ColorSystem.error
        }
    }
}

// MARK: - Remote URL Input Field

/// Input field for git remote URLs with live validation and paste support
struct RemoteURLInputField: View {
    @Binding var urlString: String
    @State private var parsedURL: GitRemoteURL?
    @State private var isValid: Bool = false
    @FocusState private var isFocused: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Input field
            HStack(spacing: Spacing.xs) {
                TextField("Paste SSH or HTTPS URL...", text: $urlString)
                    .font(Typography.terminal)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($isFocused)
                    .onChange(of: urlString) { _, newValue in
                        validateURL(newValue)
                    }

                // Paste button
                Button {
                    if let clipboard = UIPasteboard.general.string {
                        urlString = clipboard
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: layout.iconMedium))
                        .foregroundStyle(ColorSystem.textSecondary)
                }
                .buttonStyle(.plain)

                // Clear button (always in layout for consistent height, hidden when empty)
                Button {
                    urlString = ""
                    parsedURL = nil
                    isValid = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: layout.iconMedium))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
                .buttonStyle(.plain)
                .opacity(urlString.isEmpty ? 0 : 1)
                .disabled(urlString.isEmpty)
            }
            .padding(Spacing.sm)
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(borderColor, lineWidth: urlString.isEmpty ? 0 : 1.5)
            )

            // Parsed URL preview or error message
            if let parsed = parsedURL {
                ParsedURLPreview(url: parsed)
            } else if !urlString.isEmpty && !isValid {
                Text("Invalid URL format. Use SSH (git@...) or HTTPS (https://...)")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.error)
            } else if urlString.isEmpty {
                Text("Supports GitHub, GitLab, Bitbucket, and custom git servers")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
        }
    }

    private func validateURL(_ value: String) {
        parsedURL = GitRemoteURL.parse(value)
        isValid = parsedURL != nil
    }

    /// Border color based on validation state
    private var borderColor: Color {
        if urlString.isEmpty {
            return .clear
        }
        return isValid ? ColorSystem.success : ColorSystem.error
    }
}

// MARK: - Parsed URL Preview

/// Shows parsed git URL information
struct ParsedURLPreview: View {
    let url: GitRemoteURL

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Provider icon
            Image(systemName: url.provider.icon)
                .font(.system(size: 20))
                .foregroundStyle(url.provider.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.provider.displayName)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text(url.displayName)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Spacer()

            // Protocol badge
            Text(url.protocolText)
                .font(Typography.badge)
                .foregroundStyle(ColorSystem.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ColorSystem.textSecondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(Spacing.sm)
        .background(ColorSystem.success.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

// MARK: - Setup Progress View

/// Visual progress indicator for git setup wizard
struct SetupProgressView: View {
    let steps: [SetupStep]
    let currentStep: SetupStep
    let completedSteps: Set<SetupStep>

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                // Step indicator
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(stepColor(for: step))
                            .frame(width: 24, height: 24)

                        if completedSteps.contains(step) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(step == currentStep ? .white : ColorSystem.textTertiary)
                        }
                    }

                    Text(step.title)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(step.rawValue <= currentStep.rawValue ? ColorSystem.textPrimary : ColorSystem.textTertiary)
                }

                // Connector line
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(completedSteps.contains(step) ? ColorSystem.success : ColorSystem.textQuaternary)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                        .offset(y: -10)
                }
            }
        }
    }

    private func stepColor(for step: SetupStep) -> Color {
        if completedSteps.contains(step) {
            return ColorSystem.success
        } else if step == currentStep {
            return ColorSystem.primary
        } else {
            return ColorSystem.textQuaternary
        }
    }
}

// MARK: - Setup Step

/// Steps in the git setup wizard
enum SetupStep: Int, Comparable, CaseIterable, Hashable {
    case initGit
    case initialCommit
    case addRemote
    case push
    case complete

    var title: String {
        switch self {
        case .initGit: return "Init"
        case .initialCommit: return "Commit"
        case .addRemote: return "Remote"
        case .push: return "Push"
        case .complete: return "Done"
        }
    }

    var description: String {
        switch self {
        case .initGit: return "Initialize git repository"
        case .initialCommit: return "Create initial commit"
        case .addRemote: return "Connect to GitHub/GitLab"
        case .push: return "Push to remote"
        case .complete: return "Setup complete"
        }
    }

    static func < (lhs: SetupStep, rhs: SetupStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Map WorkspaceGitState to the appropriate starting step
    /// - noGit → initGit (Step 1)
    /// - gitInitialized → initialCommit (Step 2)
    /// - noRemote → addRemote (Step 3)
    /// - noPush → push (Step 4)
    static func from(gitState: WorkspaceGitState) -> SetupStep {
        switch gitState {
        case .noGit:
            return .initGit
        case .gitInitialized:
            return .initialCommit
        case .noRemote:
            return .addRemote
        case .noPush:
            return .push
        case .synced, .diverged, .conflict:
            // These states don't need setup, but default to complete
            return .complete
        }
    }
}

// MARK: - Git Setup Error

/// Errors that can occur during git setup
enum GitSetupError: LocalizedError {
    case initFailed(String)
    case commitFailed(String)
    case remoteAddFailed(String)
    case upstreamFailed(String)
    case pushFailed(String)
    case noWorkspace

    var errorDescription: String? {
        switch self {
        case .initFailed(let msg): return "Failed to initialize git: \(msg)"
        case .commitFailed(let msg): return "Failed to create commit: \(msg)"
        case .remoteAddFailed(let msg): return "Failed to add remote: \(msg)"
        case .upstreamFailed(let msg): return msg
        case .pushFailed(let msg): return "Failed to push: \(msg)"
        case .noWorkspace: return "No workspace selected"
        }
    }
}

// MARK: - No Git Empty State

/// Empty state shown when workspace has no git
struct NoGitEmptyState: View {
    let onInitialize: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Warning icon with glow - using ColorSystem.warning (Golden Pulse)
            ZStack {
                Circle()
                    .fill(ColorSystem.warningGlow)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(ColorSystem.warning.opacity(0.2))
                    .frame(width: 64, height: 64)
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundColor(ColorSystem.warning)
            }

            VStack(spacing: Spacing.xs) {
                Text("Not a Git Repository")
                    .font(Typography.bodyBold)
                    .foregroundColor(ColorSystem.textPrimary)

                Text("Initialize git to track changes and sync with remote")
                    .font(Typography.caption1)
                    .foregroundColor(ColorSystem.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Primary button - Terminal Mint success color
            Button {
                Haptics.medium()
                onInitialize()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: layout.iconMedium))
                    Text("Initialize Git")
                        .font(Typography.buttonLabel)
                }
                .foregroundColor(ColorSystem.terminalBg)
                .padding(.horizontal, layout.largePadding)
                .frame(height: layout.buttonHeight + 4)
                .background(ColorSystem.success)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - No Remote Empty State

/// Empty state shown when workspace has git but no remote
struct NoRemoteEmptyState: View {
    let onAddRemote: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Info icon with glow - using ColorSystem.info (Stream Blue)
            ZStack {
                Circle()
                    .fill(ColorSystem.infoGlow)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(ColorSystem.info.opacity(0.2))
                    .frame(width: 64, height: 64)
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(ColorSystem.info)
            }

            VStack(spacing: Spacing.xs) {
                Text("No Remote Configured")
                    .font(Typography.bodyBold)
                    .foregroundColor(ColorSystem.textPrimary)

                Text("Add a remote to sync with GitHub, GitLab, or Bitbucket")
                    .font(Typography.caption1)
                    .foregroundColor(ColorSystem.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Primary button - Cdev Teal primary color
            Button {
                Haptics.medium()
                onAddRemote()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "link")
                        .font(.system(size: layout.iconMedium))
                    Text("Connect Remote")
                        .font(Typography.buttonLabel)
                }
                .foregroundColor(ColorSystem.terminalBg)
                .padding(.horizontal, layout.largePadding)
                .frame(height: layout.buttonHeight + 4)
                .background(ColorSystem.primary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Git State Badges") {
    VStack(spacing: 12) {
        ForEach([WorkspaceGitState.noGit, .gitInitialized, .noRemote, .noPush, .synced, .diverged, .conflict], id: \.self) { state in
            HStack {
                GitStateBadge(state: state)
                Spacer()
                Text(state.statusText)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
            }
        }
    }
    .padding()
    .background(ColorSystem.terminalBg)
}

#Preview("Remote URL Input") {
    struct PreviewWrapper: View {
        @State private var url = ""

        var body: some View {
            VStack {
                RemoteURLInputField(urlString: $url)
                    .padding()

                Spacer()
            }
            .background(ColorSystem.terminalBg)
        }
    }
    return PreviewWrapper()
}

#Preview("Setup Progress") {
    SetupProgressView(
        steps: SetupStep.allCases,
        currentStep: .addRemote,
        completedSteps: [.initGit, .initialCommit]
    )
    .padding()
    .background(ColorSystem.terminalBg)
}
