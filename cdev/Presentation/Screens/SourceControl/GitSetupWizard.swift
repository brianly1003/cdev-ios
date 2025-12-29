import SwiftUI

// MARK: - Git Setup ViewModel

@MainActor
final class GitSetupViewModel: ObservableObject {
    // MARK: - Published State

    @Published var currentStep: SetupStep = .initGit
    @Published var isLoading: Bool = false
    @Published var alertConfig: CdevAlertConfig?

    // Step-specific state
    @Published var remoteURL: String = ""
    @Published var remoteName: String = "origin"
    @Published var commitMessage: String = "Initial commit"
    @Published var parsedRemoteURL: GitRemoteURL?

    // Completed steps tracking
    @Published var completedSteps: Set<SetupStep> = []

    // MARK: - Dependencies

    private let workspaceManager: WorkspaceManagerService
    private let workspaceId: String

    /// Workspace name derived from ID (last path component)
    var workspaceName: String {
        // Extract name from workspace ID (could be a path like /users/dev/myproject)
        let name = URL(fileURLWithPath: workspaceId).lastPathComponent
        return name.isEmpty ? "project" : name
    }

    // MARK: - Computed Properties

    var steps: [SetupStep] {
        // Return steps based on initial workspace state
        [.initGit, .initialCommit, .addRemote, .push, .complete]
    }

    var canGoBack: Bool {
        currentStep > .initGit && currentStep != .complete
    }

    var canSkip: Bool {
        currentStep == .addRemote  // Remote is optional
    }

    var canContinue: Bool {
        switch currentStep {
        case .initGit:
            return true
        case .initialCommit:
            return !commitMessage.isEmpty
        case .addRemote:
            return parsedRemoteURL != nil || canSkip
        case .push:
            return true
        case .complete:
            return true
        }
    }

    var isLastStep: Bool {
        currentStep == .complete
    }

    var continueButtonTitle: String {
        switch currentStep {
        case .initGit: return "Initialize Git"
        case .initialCommit: return "Create Commit"
        case .addRemote: return parsedRemoteURL != nil ? "Add Remote" : "Skip"
        case .push: return "Push to Remote"
        case .complete: return "Done"
        }
    }

    // MARK: - Init

    init(workspaceId: String, workspaceManager: WorkspaceManagerService) {
        self.workspaceId = workspaceId
        self.workspaceManager = workspaceManager
    }

    /// Initialize with a specific starting step (for workspaces partially set up)
    init(workspaceId: String, startingStep: SetupStep, workspaceManager: WorkspaceManagerService) {
        self.workspaceId = workspaceId
        self.workspaceManager = workspaceManager
        self.currentStep = startingStep

        // Mark previous steps as completed
        for step in SetupStep.allCases where step.rawValue < startingStep.rawValue {
            completedSteps.insert(step)
        }
    }

    /// Initialize based on workspace git state - starts at the appropriate step
    convenience init(workspaceId: String, gitState: WorkspaceGitState, workspaceManager: WorkspaceManagerService) {
        let startingStep = SetupStep.from(gitState: gitState)
        self.init(workspaceId: workspaceId, startingStep: startingStep, workspaceManager: workspaceManager)
    }

    // MARK: - URL Validation

    func validateRemoteURL() {
        parsedRemoteURL = GitRemoteURL.parse(remoteURL)
    }

    // MARK: - Actions

    func continueToNext() async {
        guard canContinue else { return }

        isLoading = true
        alertConfig = nil

        do {
            switch currentStep {
            case .initGit:
                try await initializeGit()
            case .initialCommit:
                try await createInitialCommit()
            case .addRemote:
                if let url = parsedRemoteURL {
                    try await addRemote(url: url)
                }
            case .push:
                try await pushToRemote()
            case .complete:
                break
            }

            // Only mark as complete if no error was shown
            // (pushToRemote may set alertConfig and return early)
            if alertConfig == nil {
                completedSteps.insert(currentStep)
                moveToNextStep()
                Haptics.success()
            }
        } catch {
            alertConfig = .error(error.localizedDescription)
            Haptics.error()
        }

        isLoading = false
    }

    func goBack() {
        guard canGoBack else { return }
        if let currentIndex = steps.firstIndex(of: currentStep), currentIndex > 0 {
            currentStep = steps[currentIndex - 1]
        }
    }

    func skip() {
        guard canSkip else { return }
        moveToNextStep()
    }

    // MARK: - Private Methods

    private func moveToNextStep() {
        if let currentIndex = steps.firstIndex(of: currentStep),
           currentIndex < steps.count - 1 {
            currentStep = steps[currentIndex + 1]
        }
    }

    private func initializeGit() async throws {
        do {
            let result = try await workspaceManager.gitInit(
                workspaceId: workspaceId,
                initialBranch: "main"
            )
            // Success - check result for any additional info
            if result.isSuccess {
                AppLogger.log("[GitSetup] Git initialized successfully")
            }
        } catch {
            // Handle JSON-RPC 2.0 standard errors
            let errorMessage = error.localizedDescription.lowercased()

            // "Already a git repository" - treat as success
            if errorMessage.contains("already") && errorMessage.contains("git repository") {
                AppLogger.log("[GitSetup] Directory already a git repository - continuing")
                return
            }

            // Re-throw other errors
            throw GitSetupError.initFailed(error.localizedDescription)
        }
    }

    private func createInitialCommit() async throws {
        // Stage all files first
        do {
            _ = try await workspaceManager.gitStage(workspaceId: workspaceId, paths: ["."])
        } catch {
            // Staging errors are usually not fatal, continue to commit
            AppLogger.log("[GitSetup] Stage warning: \(error.localizedDescription)")
        }

        // Create commit
        do {
            let result = try await workspaceManager.gitCommit(
                workspaceId: workspaceId,
                message: commitMessage,
                push: false
            )
            AppLogger.log("[GitSetup] Initial commit created: \(result.sha ?? "unknown")")
        } catch {
            // Handle JSON-RPC 2.0 standard errors
            let errorMessage = error.localizedDescription.lowercased()

            // "Nothing to commit" - treat as success
            if errorMessage.contains("nothing to commit") || errorMessage.contains("no staged changes") {
                AppLogger.log("[GitSetup] Nothing to commit - skipping to next step")
                return
            }

            // Re-throw other errors
            throw GitSetupError.commitFailed(error.localizedDescription)
        }
    }

    private func addRemote(url: GitRemoteURL) async throws {
        do {
            let result = try await workspaceManager.gitRemoteAdd(
                workspaceId: workspaceId,
                name: remoteName,
                url: url.fullURL
            )
            AppLogger.log("[GitSetup] Remote added: \(remoteName) -> \(url.displayName)")

            // Check result for warnings (backward compatibility)
            if !result.isSuccess {
                throw GitSetupError.remoteAddFailed(result.error ?? result.message ?? "Unknown error")
            }
        } catch let error as GitSetupError {
            throw error
        } catch {
            // Handle JSON-RPC 2.0 standard errors
            let errorMessage = error.localizedDescription.lowercased()

            // "Remote already exists" - treat as success
            if errorMessage.contains("already exists") || errorMessage.contains("remote.*exists") {
                AppLogger.log("[GitSetup] Remote already exists - continuing")
                return
            }

            throw GitSetupError.remoteAddFailed(error.localizedDescription)
        }
    }

    private func pushToRemote() async throws {
        // Step 1: Set upstream tracking branch first
        do {
            _ = try await workspaceManager.gitUpstreamSet(
                workspaceId: workspaceId,
                branch: "main",
                upstream: "\(remoteName)/main"
            )
            AppLogger.log("[GitSetup] Upstream set to \(remoteName)/main")
        } catch {
            // Check if this is a skippable error (e.g., already set)
            let errorMessage = error.localizedDescription.lowercased()
            if canSkipUpstreamError(errorMessage) {
                AppLogger.log("[GitSetup] Upstream set skipped: \(error.localizedDescription)")
            } else {
                // Real error - show helpful guidance with code block
                let errorInfo = formatUpstreamError(errorMessage)
                alertConfig = .error(errorInfo.message, codeBlock: errorInfo.codeBlock)
                Haptics.error()
                return  // Don't proceed to push
            }
        }

        // Step 2: Push to remote (only reached if upstream set succeeded or was skipped)
        do {
            let result = try await workspaceManager.gitPush(
                workspaceId: workspaceId,
                force: false,
                setUpstream: true
            )
            AppLogger.log("[GitSetup] Pushed to remote successfully")

            // Check result for warnings (backward compatibility)
            if !result.isSuccess {
                let errorMessage = (result.error ?? result.message ?? "").lowercased()
                if !canSkipPushError(errorMessage) {
                    throw GitSetupError.pushFailed(result.error ?? result.message ?? "Unknown error")
                }
            }
        } catch let error as GitSetupError {
            throw error
        } catch {
            // Handle JSON-RPC 2.0 standard errors
            let errorMessage = error.localizedDescription.lowercased()

            // Check if this error can be skipped
            if canSkipPushError(errorMessage) {
                AppLogger.log("[GitSetup] Push skipped: \(error.localizedDescription)")
                return
            }

            throw GitSetupError.pushFailed(error.localizedDescription)
        }
    }

    /// Check if an upstream set error can be safely skipped
    private func canSkipUpstreamError(_ errorMessage: String) -> Bool {
        // "Already tracking" or similar
        if errorMessage.contains("already") {
            return true
        }
        // "Up to date"
        if errorMessage.contains("up-to-date") || errorMessage.contains("up to date") {
            return true
        }
        return false
    }

    /// Format upstream error with helpful guidance for users
    /// Format upstream error with message and code block
    /// Returns: (message, codeBlock) tuple
    private func formatUpstreamError(_ errorMessage: String) -> (message: String, codeBlock: String) {
        // Branch does not exist - need to create initial commit first
        if errorMessage.contains("does not exist") || errorMessage.contains("refspec") {
            return (
                message: "Branch 'main' does not exist yet.\n\nThis usually means no commits have been made. Please try running these commands on your PC/laptop:",
                codeBlock: "git add .\ngit commit -m \"Initial commit\"\ngit push -u origin main"
            )
        }

        // Authentication or permission error
        if errorMessage.contains("permission") || errorMessage.contains("denied") || errorMessage.contains("authentication") {
            return (
                message: "Authentication failed.\n\nPlease check your credentials and try running this command on your PC/laptop:",
                codeBlock: "git push -u origin main"
            )
        }

        // Remote not found
        if errorMessage.contains("repository not found") || errorMessage.contains("does not appear to be a git repository") {
            return (
                message: "Remote repository not found.\n\nPlease verify the repository URL exists and you have access. Try running on your PC/laptop:",
                codeBlock: "git remote -v\ngit push -u origin main"
            )
        }

        // Default guidance
        return (
            message: "Failed to set upstream branch.\n\nPlease try running this command on your PC/laptop to troubleshoot:",
            codeBlock: "git push -u origin main"
        )
    }

    /// Check if a push error can be safely skipped
    private func canSkipPushError(_ errorMessage: String) -> Bool {
        // "No upstream branch" - already tried with setUpstream
        if errorMessage.contains("no upstream branch") || errorMessage.contains("set-upstream") {
            return true
        }
        // "Everything up-to-date" - nothing to push
        if errorMessage.contains("up-to-date") || errorMessage.contains("up to date") {
            return true
        }
        // "Nothing to push"
        if errorMessage.contains("nothing to push") {
            return true
        }
        return false
    }
}

// MARK: - Git Setup Wizard View

struct GitSetupWizard: View {
    @StateObject var viewModel: GitSetupViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Floating toolkit state
    @State private var showSettings: Bool = false
    @State private var showDebugLogs: Bool = false

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Toolkit items for FloatingToolkitButton
    private var toolkitItems: [ToolkitItem] {
        ToolkitBuilder()
            .add(.settings { showSettings = true })
            .add(.debugLogs { showDebugLogs = true })
            .build()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background color that fills entire view
                ColorSystem.terminalBg
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress steps
                    SetupProgressView(
                        steps: viewModel.steps,
                        currentStep: viewModel.currentStep,
                        completedSteps: viewModel.completedSteps
                    )
                    .padding()
                    .background(ColorSystem.terminalBg)

                    Divider()
                        .overlay(ColorSystem.terminalBgHighlight)

                    // Current step content
                    ScrollView {
                        currentStepContent
                            .padding()
                    }
                    .background(ColorSystem.terminalBg)

                    Divider()
                        .overlay(ColorSystem.terminalBgHighlight)

                    // Actions
                    actionBar
                }

                // Floating toolkit button
                FloatingToolkitButton(items: toolkitItems)
            }
            .navigationTitle("Git Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ColorSystem.terminalBgElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ColorSystem.textSecondary)
                }
            }
            .cdevAlert($viewModel.alertConfig)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .responsiveSheet()
            }
            .sheet(isPresented: $showDebugLogs) {
                AdminToolsView()
                    .responsiveSheet()
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch viewModel.currentStep {
        case .initGit:
            InitGitStepView()
        case .initialCommit:
            InitialCommitStepView(commitMessage: $viewModel.commitMessage, workspaceName: viewModel.workspaceName)
        case .addRemote:
            AddRemoteStepView(
                remoteURL: $viewModel.remoteURL,
                remoteName: $viewModel.remoteName,
                parsedURL: viewModel.parsedRemoteURL,
                onURLChange: { viewModel.validateRemoteURL() }
            )
        case .push:
            PushStepView(parsedURL: viewModel.parsedRemoteURL)
        case .complete:
            CompleteStepView()
        }
    }

    private var actionBar: some View {
        HStack(spacing: layout.contentSpacing) {
            // Back button - secondary style
            if viewModel.canGoBack {
                Button {
                    viewModel.goBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(Typography.buttonLabel)
                    }
                    .foregroundColor(ColorSystem.textSecondary)
                    .padding(.horizontal, layout.standardPadding)
                    .frame(height: layout.buttonHeight)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Skip button - text only
            if viewModel.canSkip && viewModel.parsedRemoteURL == nil {
                Button {
                    viewModel.skip()
                } label: {
                    Text("Skip for Now")
                        .font(Typography.buttonLabel)
                        .foregroundColor(ColorSystem.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // Primary action button - Cdev styled
            Button {
                if viewModel.isLastStep {
                    dismiss()
                } else {
                    Task { await viewModel.continueToNext() }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(ColorSystem.terminalBg)
                    } else {
                        Image(systemName: primaryButtonIcon)
                            .font(.system(size: layout.iconMedium))
                        Text(viewModel.continueButtonTitle)
                            .font(Typography.buttonLabel)
                    }
                }
                .foregroundColor(ColorSystem.terminalBg)
                .padding(.horizontal, layout.standardPadding)
                .frame(height: layout.buttonHeight + 4)
                .background(
                    viewModel.canContinue && !viewModel.isLoading
                        ? ColorSystem.success
                        : ColorSystem.success.opacity(0.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canContinue || viewModel.isLoading)
        }
        .padding(layout.standardPadding)
        .background(ColorSystem.terminalBgElevated)
    }

    private var primaryButtonIcon: String {
        switch viewModel.currentStep {
        case .initGit: return "leaf.fill"
        case .initialCommit: return "checkmark.circle.fill"
        case .addRemote: return viewModel.parsedRemoteURL != nil ? "link" : "arrow.right"
        case .push: return "arrow.up.circle.fill"
        case .complete: return "checkmark"
        }
    }
}

// MARK: - Step Views

private struct InitGitStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Initialize Git Repository", systemImage: "leaf")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)

            Text("This will create a .git folder in your project to start tracking changes.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Default branch: main", systemImage: "arrow.triangle.branch")
                Label("Ignores common patterns (.git, node_modules, etc.)", systemImage: "eye.slash")
            }
            .font(Typography.terminalSmall)
            .foregroundStyle(ColorSystem.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InitialCommitStepView: View {
    @Binding var commitMessage: String
    let workspaceName: String

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Create Initial Commit", systemImage: "checkmark.circle")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)

            Text("Stage all files and create your first commit.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Commit Message")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("Enter commit message...", text: $commitMessage)
                    .font(Typography.terminal)
                    .padding(Spacing.sm)
                    .background(ColorSystem.terminalBgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }

            // GitHub-like tip for empty repos
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: layout.iconSmall))
                        .foregroundStyle(ColorSystem.warning)
                    Text("Tip: Empty folder?")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textSecondary)
                }

                Text("If your folder is empty, create a README.md file first on your PC/laptop:")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)

                // Code block with README creation command
                VStack(alignment: .leading, spacing: 2) {
                    Text("echo \"# \(workspaceName)\" >> README.md")
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(layout.smallPadding)
                .background(ColorSystem.terminalBg)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
            .padding(layout.smallPadding)
            .background(ColorSystem.warning.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddRemoteStepView: View {
    @Binding var remoteURL: String
    @Binding var remoteName: String
    let parsedURL: GitRemoteURL?
    let onURLChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Add Remote Repository", systemImage: "link")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)

            Text("Connect to GitHub, GitLab, or another git server. You can skip this step and add a remote later.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Repository URL")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)

                RemoteURLInputField(urlString: $remoteURL)
                    .onChange(of: remoteURL) { _, _ in
                        onURLChange()
                    }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Remote Name")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("origin", text: $remoteName)
                    .font(Typography.terminal)
                    .padding(Spacing.sm)
                    .background(ColorSystem.terminalBgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PushStepView: View {
    let parsedURL: GitRemoteURL?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Push to Remote", systemImage: "arrow.up.circle")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)

            Text("Push your initial commit to the remote repository.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textSecondary)

            if let url = parsedURL {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label("Destination", systemImage: "server.rack")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)

                    ParsedURLPreview(url: url)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Sets upstream tracking branch", systemImage: "arrow.triangle.branch")
                Label("Enables pull/push without specifying remote", systemImage: "checkmark.circle")
            }
            .font(Typography.terminalSmall)
            .foregroundStyle(ColorSystem.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompleteStepView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(ColorSystem.success)

            VStack(spacing: Spacing.xs) {
                Text("Setup Complete!")
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("Your repository is now configured and synced.")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

// MARK: - Quick Add Remote Sheet

/// Compact sheet for quickly adding a remote
struct QuickAddRemoteSheet: View {
    let workspaceId: String
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)?

    @State private var remoteURL: String = ""
    @State private var remoteName: String = "origin"
    @State private var parsedURL: GitRemoteURL?
    @State private var isLoading: Bool = false
    @State private var error: String?

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }
    private let workspaceManager = WorkspaceManagerService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                RemoteURLInputField(urlString: $remoteURL)
                    .onChange(of: remoteURL) { _, newValue in
                        parsedURL = GitRemoteURL.parse(newValue)
                    }

                HStack {
                    Text("Remote name:")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textSecondary)

                    TextField("origin", text: $remoteName)
                        .font(Typography.terminal)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)

                    Text("(default)")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)

                    Spacer()
                }

                if let error = error {
                    Text(error)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.error)
                }

                Spacer()
            }
            .padding()
            .background(ColorSystem.terminalBg)
            .navigationTitle("Add Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await addRemote() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(parsedURL == nil || isLoading)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addRemote() async {
        guard let url = parsedURL else { return }

        isLoading = true
        error = nil

        do {
            let result = try await workspaceManager.gitRemoteAdd(
                workspaceId: workspaceId,
                name: remoteName.isEmpty ? "origin" : remoteName,
                url: url.fullURL
            )

            if result.isSuccess {
                Haptics.success()
                onSuccess?()
                isPresented = false
            } else {
                error = result.error ?? result.message ?? "Failed to add remote"
                Haptics.error()
            }
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }

        isLoading = false
    }
}

// MARK: - Previews

#Preview("Git Setup Wizard") {
    GitSetupWizard(viewModel: GitSetupViewModel(workspaceId: "test-workspace", workspaceManager: .shared))
}

#Preview("Quick Add Remote") {
    QuickAddRemoteSheet(workspaceId: "test-workspace", isPresented: .constant(true))
}
