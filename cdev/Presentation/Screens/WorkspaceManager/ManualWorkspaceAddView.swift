import SwiftUI

// MARK: - Manual Workspace Add View

/// Compact sheet for quickly adding a workspace by path
/// Alternative to Discovery Repos for users who know the exact path
/// Enhanced with git state detection and contextual setup actions
struct ManualWorkspaceAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Callback when workspace is successfully added - returns the workspace
    var onAdd: ((String) async throws -> RemoteWorkspace)?

    /// Callback when user wants to connect immediately after adding
    var onOpenWorkspace: ((RemoteWorkspace) -> Void)?

    /// Callback when user wants to setup git (init/remote/etc)
    var onSetupGit: ((RemoteWorkspace) -> Void)?

    /// Callback when user wants to add remote
    var onAddRemote: ((RemoteWorkspace) -> Void)?

    @State private var path: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    // Success state with git info from response
    @State private var addedWorkspace: RemoteWorkspace?
    @State private var detectedGitState: WorkspaceGitState?

    @FocusState private var isPathFocused: Bool

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }
    private var isCompact: Bool { sizeClass == .compact }

    // MARK: - Validation

    /// Check if path looks valid (basic client-side validation)
    private var isPathValid: Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        // Must start with / (absolute path) and have at least one directory
        return trimmed.hasPrefix("/") && trimmed.count > 1 && !trimmed.contains("//")
    }

    /// Validation message for display
    private var validationHint: String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if !trimmed.hasPrefix("/") {
            return "Path must be absolute (start with /)"
        }
        if trimmed.contains("//") {
            return "Invalid path format"
        }
        return nil
    }

    /// Extract repo name from path for display
    private var derivedName: String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if let workspace = addedWorkspace, let gitState = detectedGitState {
                    // Success view with git state
                    successView(workspace: workspace, gitState: gitState)
                } else {
                    // Input form
                    inputFormView
                }
            }
            .background(ColorSystem.terminalBg)
            .navigationTitle(addedWorkspace != nil ? "Workspace Added" : "Add Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(addedWorkspace != nil ? "Done" : "Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(ColorSystem.textSecondary)
                }
            }
            .onAppear {
                // Auto-focus path field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPathFocused = true
                }
            }
        }
    }

    // MARK: - Input Form View

    private var inputFormView: some View {
        VStack(spacing: 0) {
            // Header info
            headerSection

            Divider()
                .background(ColorSystem.terminalBgHighlight)

            // Main form
            ScrollView {
                VStack(spacing: layout.sectionSpacing) {
                    pathInputSection
                    previewSection
                }
                .padding(layout.standardPadding)
            }

            Divider()
                .background(ColorSystem.terminalBgHighlight)

            // Action buttons
            actionButtons
        }
    }

    // MARK: - Success View

    private func successView(workspace: RemoteWorkspace, gitState: WorkspaceGitState) -> some View {
        ScrollView {
            VStack(spacing: layout.sectionSpacing) {
                // Success header
                VStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(ColorSystem.success.opacity(0.12))
                            .frame(width: 72, height: 72)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(ColorSystem.success)
                    }

                    Text("Workspace Added!")
                        .font(Typography.title3)
                        .foregroundStyle(ColorSystem.textPrimary)
                }
                .padding(.top, layout.sectionSpacing)

                // Git state preview card
                WorkspaceGitStatePreview(
                    workspace: workspace,
                    gitState: gitState,
                    onSetupGit: {
                        dismiss()
                        onSetupGit?(workspace)
                    },
                    onAddRemote: {
                        dismiss()
                        onAddRemote?(workspace)
                    },
                    onPush: {
                        dismiss()
                        onOpenWorkspace?(workspace)
                    },
                    onOpen: {
                        dismiss()
                        onOpenWorkspace?(workspace)
                    }
                )
                .padding(.horizontal, layout.standardPadding)

                Spacer(minLength: layout.sectionSpacing)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: layout.contentSpacing) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: layout.iconLarge))
                .foregroundStyle(ColorSystem.primary)
                .frame(width: 36, height: 36)
                .background(ColorSystem.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Add")
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("Enter the full path to your repository")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            Spacer()
        }
        .padding(layout.standardPadding)
        .background(ColorSystem.terminalBgElevated)
    }

    // MARK: - Path Input Section

    private var pathInputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Label
            Text("Repository Path")
                .font(Typography.caption1)
                .fontWeight(.medium)
                .foregroundStyle(ColorSystem.textSecondary)

            // Input field
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "folder")
                    .font(.system(size: layout.iconMedium))
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("", text: $path, prompt: Text("/Users/you/projects/repo").foregroundStyle(ColorSystem.textQuaternary))
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .focused($isPathFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        if isPathValid && !isLoading {
                            Task { await addWorkspace() }
                        }
                    }

                // Clear button - use iconAction for better tap target
                if !path.isEmpty {
                    Button {
                        path = ""
                        Haptics.light()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: layout.iconAction))
                            .foregroundStyle(ColorSystem.textTertiary)
                            .frame(width: layout.buttonHeightSmall, height: layout.buttonHeightSmall)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, layout.contentSpacing)
            .padding(.vertical, layout.contentSpacing)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(
                        errorMessage != nil ? ColorSystem.error.opacity(0.5) :
                        (isPathFocused ? ColorSystem.primary.opacity(0.5) : .clear),
                        lineWidth: 1
                    )
            )

            // Validation hint or error
            if let error = errorMessage {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(Typography.caption1)
                }
                .foregroundStyle(ColorSystem.error)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let hint = validationHint {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text(hint)
                        .font(Typography.caption1)
                }
                .foregroundStyle(ColorSystem.warning)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: errorMessage)
        .animation(.easeInOut(duration: 0.15), value: validationHint)
    }

    // MARK: - Preview Section

    @ViewBuilder
    private var previewSection: some View {
        if isPathValid && !derivedName.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Preview")
                    .font(Typography.caption1)
                    .fontWeight(.medium)
                    .foregroundStyle(ColorSystem.textSecondary)

                HStack(spacing: layout.contentSpacing) {
                    // Folder icon
                    Image(systemName: "folder.fill")
                        .font(.system(size: layout.iconMedium))
                        .foregroundStyle(ColorSystem.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(derivedName)
                            .font(Typography.bodyBold)
                            .foregroundStyle(ColorSystem.textPrimary)

                        Text(path.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    // Checkmark indicator
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: layout.iconMedium))
                        .foregroundStyle(ColorSystem.success)
                }
                .padding(layout.contentSpacing)
                .background(ColorSystem.terminalBgElevated)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: layout.contentSpacing) {
            // Add button (primary)
            Button {
                Task { await addWorkspace() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: layout.iconMedium))
                    }

                    Text(buttonText)
                        .font(Typography.buttonLabel)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: layout.buttonHeight)
                .background(
                    isPathValid && !isLoading
                        ? ColorSystem.primary
                        : ColorSystem.primary.opacity(0.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)
            .disabled(!isPathValid || isLoading)
        }
        .padding(layout.standardPadding)
        .background(ColorSystem.terminalBgElevated)
    }

    private var buttonText: String {
        if isLoading {
            return "Adding..."
        } else {
            return "Add Workspace"
        }
    }

    // MARK: - Actions

    private func addWorkspace() async {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            // Add workspace and get the result (includes git state from server)
            let workspace = try await onAdd?(trimmedPath)
            Haptics.success()

            if let workspace = workspace {
                // Use git state from response (no separate API calls needed)
                let gitState = workspace.git?.workspaceGitState ?? .noGit

                // Show success view with git state
                withAnimation(.easeInOut(duration: 0.3)) {
                    addedWorkspace = workspace
                    detectedGitState = gitState
                    isLoading = false
                }
            } else {
                // No workspace returned - just dismiss
                dismiss()
            }
        } catch {
            Haptics.error()
            errorMessage = extractErrorMessage(from: error)
            isLoading = false
        }
    }

    /// Extract user-friendly error message
    private func extractErrorMessage(from error: Error) -> String {
        if let wsError = error as? WorkspaceManagerError {
            switch wsError {
            case .rpcError(let code, let message):
                // Clean up common server error messages to be user-friendly
                let lowerMessage = message.lowercased()

                // Path doesn't exist
                if lowerMessage.contains("does not exist") ||
                   lowerMessage.contains("no such file or directory") ||
                   lowerMessage.contains("path not found") {
                    return "This folder doesn't exist. Please check the path and try again."
                }

                // Not a git repository
                if lowerMessage.contains("not a git repository") ||
                   lowerMessage.contains("not a valid git") {
                    return "This folder is not a git repository. Currently only git repositories can be added as workspaces."
                }

                // Already exists
                if lowerMessage.contains("already exists") ||
                   lowerMessage.contains("already registered") ||
                   lowerMessage.contains("duplicate") {
                    return "This workspace has already been added."
                }

                // Permission denied
                if lowerMessage.contains("permission denied") ||
                   lowerMessage.contains("access denied") {
                    return "Permission denied. Make sure you have access to this folder."
                }

                // Internal server error
                if code == -32603 {
                    // Internal error - make the message friendlier
                    if lowerMessage.contains("path") {
                        return "Could not access this path. Please verify it exists and is accessible."
                    }
                    return "Something went wrong on the server. Please try again."
                }

                // If message is technical/short, provide a generic friendly message
                if message.count < 20 || message.contains("error") {
                    return "Could not add workspace: \(message)"
                }

                return message

            case .notConnected:
                return "Not connected to the server. Please check your connection."

            case .timeout:
                return "Request timed out. Please check if the server is running and try again."

            case .encodingFailed:
                return "Failed to send request. Please try again."

            case .noResult:
                return "No response from server. Please try again."

            case .workspaceFailed:
                return "Failed to access workspace. Please try again."

            case .sessionFailed:
                return "Failed to start session. Please try again."
            }
        }

        // Handle generic errors
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("protocol") || errorDescription.contains("decode") {
            return "Communication error with server. Please try again."
        }

        return error.localizedDescription
    }
}

// MARK: - Workspace Git State Preview

/// Shows git state preview after workspace is added
/// Provides contextual actions based on state
struct WorkspaceGitStatePreview: View {
    let workspace: RemoteWorkspace
    let gitState: WorkspaceGitState
    let onSetupGit: () -> Void
    let onAddRemote: () -> Void
    let onPush: () -> Void
    let onOpen: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            // Header with workspace info
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "folder.fill")
                    .font(.system(size: layout.iconLarge))
                    .foregroundStyle(ColorSystem.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(Typography.bodyBold)
                        .foregroundStyle(ColorSystem.textPrimary)
                        .lineLimit(1)

                    Text(workspace.path)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Git state badge
                GitStateBadge(state: gitState)
            }

            Divider()
                .background(ColorSystem.terminalBgHighlight)

            // State-specific content and actions
            stateContent
        }
        .padding(layout.standardPadding)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
    }

    @ViewBuilder
    private var stateContent: some View {
        switch gitState {
        case .noGit:
            noGitContent
        case .gitInitialized:
            gitInitializedContent
        case .noRemote:
            noRemoteContent
        case .noPush:
            noPushContent
        case .synced, .diverged, .conflict:
            syncedContent
        }
    }

    // MARK: - No Git State

    private var noGitContent: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.warning)
                Text("Not a Git Repository")
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Text("Initialize git to track changes and sync with GitHub, GitLab, or other services.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: layout.contentSpacing) {
                Button {
                    onOpen()
                } label: {
                    Text("Open Anyway")
                        .font(Typography.buttonLabel)
                        .foregroundStyle(ColorSystem.textSecondary)
                }
                .buttonStyle(.bordered)

                Button {
                    onSetupGit()
                } label: {
                    Label("Setup Git", systemImage: "leaf")
                        .font(Typography.buttonLabel)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Git Initialized (No Commits)

    private var gitInitializedContent: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "leaf")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.success)
                Text("Git Initialized")
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Text("Make your first commit to start tracking changes.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)

            HStack(spacing: layout.contentSpacing) {
                Button {
                    onOpen()
                } label: {
                    Text("Open Workspace")
                        .font(Typography.buttonLabel)
                        .foregroundStyle(ColorSystem.textSecondary)
                }
                .buttonStyle(.bordered)

                Button {
                    onSetupGit()
                } label: {
                    Label("Continue Setup", systemImage: "arrow.right")
                        .font(Typography.buttonLabel)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - No Remote

    private var noRemoteContent: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.warning)
                Text("No Remote Configured")
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Text("Add a remote to sync your code with GitHub, GitLab, or Bitbucket.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)

            HStack(spacing: layout.contentSpacing) {
                Button {
                    onOpen()
                } label: {
                    Text("Open Workspace")
                        .font(Typography.buttonLabel)
                        .foregroundStyle(ColorSystem.textSecondary)
                }
                .buttonStyle(.bordered)

                Button {
                    onAddRemote()
                } label: {
                    Label("Add Remote", systemImage: "link")
                        .font(Typography.buttonLabel)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - No Push (Remote configured, not pushed)

    private var noPushContent: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.primary)
                Text("Ready to Push")
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Text("Push your code to the remote repository to sync.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)

            HStack(spacing: layout.contentSpacing) {
                Button {
                    onOpen()
                } label: {
                    Text("Open Workspace")
                        .font(Typography.buttonLabel)
                        .foregroundStyle(ColorSystem.textSecondary)
                }
                .buttonStyle(.bordered)

                Button {
                    onPush()
                } label: {
                    Label("Push to Remote", systemImage: "arrow.up")
                        .font(Typography.buttonLabel)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Synced/Ready

    private var syncedContent: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.success)
                Text(gitState == .synced ? "Synced" : gitState.statusText)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Text("Your workspace is ready to use.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)

            Button {
                onOpen()
            } label: {
                Label("Open Workspace", systemImage: "arrow.right.circle")
                    .font(Typography.buttonLabel)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Preview

#Preview {
    ManualWorkspaceAddView()
}

#Preview("With Path") {
    ManualWorkspaceAddView()
}

#Preview("Git State Preview - No Git") {
    WorkspaceGitStatePreview(
        workspace: RemoteWorkspace(id: "1", name: "MyProject", path: "/Users/dev/MyProject"),
        gitState: .noGit,
        onSetupGit: {},
        onAddRemote: {},
        onPush: {},
        onOpen: {}
    )
    .padding()
    .background(ColorSystem.terminalBg)
}

#Preview("Git State Preview - Synced") {
    WorkspaceGitStatePreview(
        workspace: RemoteWorkspace(id: "1", name: "MyProject", path: "/Users/dev/MyProject"),
        gitState: .synced,
        onSetupGit: {},
        onAddRemote: {},
        onPush: {},
        onOpen: {}
    )
    .padding()
    .background(ColorSystem.terminalBg)
}
