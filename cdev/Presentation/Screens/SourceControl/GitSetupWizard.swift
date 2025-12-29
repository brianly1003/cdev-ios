import SwiftUI

// MARK: - Git Setup ViewModel

@MainActor
final class GitSetupViewModel: ObservableObject {
    // MARK: - Published State

    @Published var currentStep: SetupStep = .initGit
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var showError: Bool = false

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

    init(workspaceId: String, workspaceManager: WorkspaceManagerService = .shared) {
        self.workspaceId = workspaceId
        self.workspaceManager = workspaceManager
    }

    /// Initialize with a specific starting step (for workspaces partially set up)
    init(workspaceId: String, startingStep: SetupStep, workspaceManager: WorkspaceManagerService = .shared) {
        self.workspaceId = workspaceId
        self.workspaceManager = workspaceManager
        self.currentStep = startingStep

        // Mark previous steps as completed
        for step in SetupStep.allCases where step.rawValue < startingStep.rawValue {
            completedSteps.insert(step)
        }
    }

    // MARK: - URL Validation

    func validateRemoteURL() {
        parsedRemoteURL = GitRemoteURL.parse(remoteURL)
    }

    // MARK: - Actions

    func continueToNext() async {
        guard canContinue else { return }

        isLoading = true
        error = nil

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

            completedSteps.insert(currentStep)
            moveToNextStep()
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            self.showError = true
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
        let result = try await workspaceManager.gitInit(
            workspaceId: workspaceId,
            initialBranch: "main"
        )

        // Handle success or "already initialized" cases
        if result.isSuccess {
            AppLogger.log("[GitSetup] Git initialized successfully")
            return
        }

        // If already a git repository, treat as success and continue to next step
        let errorMessage = (result.error ?? result.message ?? "").lowercased()
        if errorMessage.contains("already") && errorMessage.contains("git repository") {
            AppLogger.log("[GitSetup] Directory already a git repository - continuing to next step")
            return
        }

        // Otherwise, throw the error
        throw GitSetupError.initFailed(result.error ?? result.message ?? "Unknown error")
    }

    private func createInitialCommit() async throws {
        // Stage all files first
        _ = try await workspaceManager.gitStage(workspaceId: workspaceId, paths: ["."])

        // Create commit
        let result = try await workspaceManager.gitCommit(
            workspaceId: workspaceId,
            message: commitMessage,
            push: false
        )
        guard result.success else {
            throw GitSetupError.commitFailed(result.error ?? result.message ?? "Unknown error")
        }
        AppLogger.log("[GitSetup] Initial commit created: \(result.sha ?? "unknown")")
    }

    private func addRemote(url: GitRemoteURL) async throws {
        let result = try await workspaceManager.gitRemoteAdd(
            workspaceId: workspaceId,
            name: remoteName,
            url: url.fullURL
        )
        guard result.isSuccess else {
            throw GitSetupError.remoteAddFailed(result.error ?? result.message ?? "Unknown error")
        }
        AppLogger.log("[GitSetup] Remote added: \(remoteName) -> \(url.displayName)")
    }

    private func pushToRemote() async throws {
        let result = try await workspaceManager.gitPush(
            workspaceId: workspaceId,
            force: false,
            setUpstream: true
        )
        guard result.isSuccess else {
            throw GitSetupError.pushFailed(result.message ?? "Unknown error")
        }
        AppLogger.log("[GitSetup] Pushed to remote successfully")
    }
}

// MARK: - Git Setup Wizard View

struct GitSetupWizard: View {
    @StateObject var viewModel: GitSetupViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

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
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.error ?? "An unknown error occurred")
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
            InitialCommitStepView(commitMessage: $viewModel.commitMessage)
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
    GitSetupWizard(viewModel: GitSetupViewModel(workspaceId: "test-workspace"))
}

#Preview("Quick Add Remote") {
    QuickAddRemoteSheet(workspaceId: "test-workspace", isPresented: .constant(true))
}
