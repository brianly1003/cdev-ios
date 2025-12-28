import SwiftUI

// MARK: - Source Control View (Mini Repo Management)

/// VS Code-inspired source control view for mobile
/// Layout: Branch header → Commit input → Staged → Changes
struct SourceControlView: View {
    @ObservedObject var viewModel: SourceControlViewModel
    let onRefresh: () async -> Void

    // Scroll request (from floating toolkit long-press)
    var scrollRequest: ScrollDirection?

    // Callback to present diff viewer (hoisted to DashboardView to avoid TabView recreation issues)
    var onPresentDiff: ((GitFileEntry) -> Void)?

    @State private var showCommitSheet = false
    @State private var showDiscardAlert = false
    @State private var fileToDiscard: GitFileEntry?
    @State private var showBranchSwitcher = false
    @State private var showGitSetupWizard = false
    @State private var showAddRemoteSheet = false
    @State private var showCommitHistory = false

    // Responsive layout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    /// Get current workspace ID
    private var currentWorkspaceId: String? {
        WorkspaceStore.shared.activeWorkspace?.remoteWorkspaceId
    }

    var body: some View {
        Group {
            // Only switch views based on totalCount - NOT isLoading
            // This prevents the CommitInputView from flashing when refreshing from empty state
            // Both views have .refreshable which shows loading feedback
            if viewModel.state.totalCount == 0 {
                emptyStateView
            } else {
                contentView
            }
        }
        .background(ColorSystem.terminalBg)
        .refreshable {
            AppLogger.log("[SourceControlView] Pull-to-refresh triggered, calling onRefresh...")
            await onRefresh()
            AppLogger.log("[SourceControlView] onRefresh completed, state.totalCount=\(viewModel.state.totalCount)")
        }
        // Note: Diff sheet is hoisted to DashboardView to avoid TabView recreation issues
        .sheet(isPresented: $showBranchSwitcher) {
            BranchSwitcherSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showGitSetupWizard) {
            if let workspaceId = currentWorkspaceId {
                GitSetupWizard(viewModel: GitSetupViewModel(workspaceId: workspaceId))
                    .onDisappear {
                        Task { await onRefresh() }
                    }
            }
        }
        .sheet(isPresented: $showAddRemoteSheet) {
            if let workspaceId = currentWorkspaceId {
                QuickAddRemoteSheet(
                    workspaceId: workspaceId,
                    isPresented: $showAddRemoteSheet,
                    onSuccess: {
                        Task { await onRefresh() }
                    }
                )
            }
        }
        .sheet(isPresented: $showCommitHistory) {
            if let workspaceId = currentWorkspaceId {
                CommitHistoryView(workspaceId: workspaceId)
            }
        }
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                if let file = fileToDiscard {
                    Task { await viewModel.discardChanges([file.path]) }
                }
            }
        } message: {
            if let file = fileToDiscard {
                Text("This will discard all changes to \(file.fileName). This cannot be undone.")
            }
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Top anchor for scroll to top
                    Color.clear
                        .frame(height: 1)
                        .id("sourceControlTop")

                    // Branch & Sync Header
                    BranchHeaderView(
                        branch: viewModel.state.currentBranch,
                        gitState: viewModel.gitState,
                        onBranchTap: { showBranchSwitcher = true },
                        onSetupTap: { showGitSetupWizard = true },
                        onAddRemoteTap: { showAddRemoteSheet = true },
                        onHistoryTap: { showCommitHistory = true },
                        onPull: { Task { await viewModel.pull() } },
                        onPush: { Task { await viewModel.push() } },
                        onRefresh: { Task { await onRefresh() } }
                    )

                    // Error Banner (if any)
                    if let error = viewModel.state.lastError {
                        GitErrorBanner(
                            message: error,
                            onDismiss: { viewModel.state.lastError = nil }
                        )
                    }

                    // Commit Input Section
                    CommitInputView(
                        message: $viewModel.state.commitMessage,
                        canCommit: viewModel.state.canCommit,
                        stagedCount: viewModel.state.stagedCount,
                        isLoading: viewModel.isCommitting,
                        onCommit: { Task { await viewModel.commit() } },
                        onCommitAndPush: { Task { await viewModel.commitAndPush() } }
                    )

                    // Staged Changes Section (always visible)
                    FileChangesSection(
                        title: "Staged Changes",
                        files: viewModel.state.stagedFiles,
                        isStaged: true,
                        isExpanded: $viewModel.stagedExpanded,
                        onStageAll: nil,
                        onUnstageAll: viewModel.state.stagedFiles.isEmpty ? nil : { Task { await viewModel.unstageAll() } },
                        onFileAction: { file, action in
                            handleFileAction(file: file, action: action)
                        },
                        onFileTap: { file in
                            onPresentDiff?(file)
                            Haptics.selection()
                        }
                    )

                    // Unstaged Changes Section (always visible)
                    FileChangesSection(
                        title: "Changes",
                        files: viewModel.state.allUnstagedFiles,
                        isStaged: false,
                        isExpanded: $viewModel.changesExpanded,
                        onStageAll: viewModel.state.allUnstagedFiles.isEmpty ? nil : { Task { await viewModel.stageAll() } },
                        onUnstageAll: nil,
                        onFileAction: { file, action in
                            handleFileAction(file: file, action: action)
                        },
                        onFileTap: { file in
                            onPresentDiff?(file)
                            Haptics.selection()
                        }
                    )

                    // Conflicts Section (if any)
                    if !viewModel.state.conflictedFiles.isEmpty {
                        FileChangesSection(
                            title: "Merge Conflicts",
                            files: viewModel.state.conflictedFiles,
                            isStaged: false,
                            isExpanded: .constant(true),
                            isConflict: true,
                            onStageAll: nil,
                            onUnstageAll: nil,
                            onFileAction: { file, action in
                                handleFileAction(file: file, action: action)
                            },
                            onFileTap: { file in
                                onPresentDiff?(file)
                                Haptics.selection()
                            }
                        )
                    }

                    // Bottom spacing
                    Color.clear.frame(height: Spacing.xl)
                        .id("sourceControlBottom")
                }
            }
            .onChange(of: scrollRequest) { _, direction in
                guard let direction = direction else { return }
                handleScrollRequest(direction: direction, proxy: proxy)
            }
        }
    }

    // MARK: - Scroll Request Handler

    private func handleScrollRequest(direction: ScrollDirection, proxy: ScrollViewProxy) {
        switch direction {
        case .top:
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo("sourceControlTop", anchor: .top)
            }
        case .bottom:
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo("sourceControlBottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            // Always show branch header with push/pull buttons
            BranchHeaderView(
                branch: viewModel.state.currentBranch,
                gitState: viewModel.gitState,
                onBranchTap: { showBranchSwitcher = true },
                onSetupTap: { showGitSetupWizard = true },
                onAddRemoteTap: { showAddRemoteSheet = true },
                onHistoryTap: { showCommitHistory = true },
                onPull: { Task { await viewModel.pull() } },
                onPush: { Task { await viewModel.push() } },
                onRefresh: { Task { await onRefresh() } }
            )

            // Error Banner (if any)
            if let error = viewModel.state.lastError {
                GitErrorBanner(
                    message: error,
                    onDismiss: { viewModel.state.lastError = nil }
                )
            }

            // Show appropriate content based on git state
            switch viewModel.gitState {
            case .noGit:
                NoGitEmptyState(onInitialize: { showGitSetupWizard = true })
            case .noRemote:
                NoRemoteEmptyState(onAddRemote: { showAddRemoteSheet = true })
            case .noPush:
                noPushEmptyState
            default:
                noChangesEmptyState
            }
        }
    }

    /// Empty state when there's no remote push yet
    private var noPushEmptyState: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Color.clear.frame(height: 1).id("sourceControlTop")

                    Spacer(minLength: 60)

                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(ColorSystem.primary)

                    Text("Ready to Push")
                        .font(Typography.title3)
                        .foregroundStyle(ColorSystem.textPrimary)

                    Text("Your repository has a remote configured but hasn't been pushed yet")
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)

                    Button {
                        Task { await viewModel.push() }
                    } label: {
                        Label("Push to Remote", systemImage: "arrow.up")
                            .font(Typography.buttonLabel)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Spacing.sm)

                    Spacer()

                    Color.clear.frame(height: 1).id("sourceControlBottom")
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
            .onChange(of: scrollRequest) { _, direction in
                guard let direction = direction else { return }
                handleScrollRequest(direction: direction, proxy: proxy)
            }
        }
    }

    /// Empty state when working directory is clean
    private var noChangesEmptyState: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Top anchor for scroll to top
                    Color.clear
                        .frame(height: 1)
                        .id("sourceControlTop")

                    Spacer(minLength: 60)

                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(ColorSystem.success)

                    Text("No Changes")
                        .font(Typography.title3)
                        .foregroundStyle(ColorSystem.textPrimary)

                    Text("Your working directory is clean")
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textTertiary)

                    // Sync status hint
                    if let branch = viewModel.state.currentBranch {
                        if branch.ahead > 0 {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 14))
                                Text("\(branch.ahead) commit\(branch.ahead == 1 ? "" : "s") to push")
                                    .font(Typography.terminal)
                            }
                            .foregroundStyle(ColorSystem.primary)
                            .padding(.top, Spacing.sm)
                        }
                        if branch.behind > 0 {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 14))
                                Text("\(branch.behind) commit\(branch.behind == 1 ? "" : "s") to pull")
                                    .font(Typography.terminal)
                            }
                            .foregroundStyle(ColorSystem.info)
                            .padding(.top, Spacing.xs)
                        }
                    }

                    Spacer()

                    // Bottom anchor for scroll to bottom
                    Color.clear
                        .frame(height: 1)
                        .id("sourceControlBottom")
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
            // Note: Don't add .refreshable here - use the outer Group's refreshable
            // Having two refreshable modifiers can cause race conditions
            .onChange(of: scrollRequest) { _, direction in
                guard let direction = direction else { return }
                handleScrollRequest(direction: direction, proxy: proxy)
            }
        }
    }

    // MARK: - File Actions

    private func handleFileAction(file: GitFileEntry, action: FileAction) {
        Task {
            switch action {
            case .stage:
                await viewModel.stageFiles([file.path])
            case .unstage:
                await viewModel.unstageFiles([file.path])
            case .discard:
                fileToDiscard = file
                showDiscardAlert = true
            case .viewDiff:
                onPresentDiff?(file)
            }
        }
    }
}

// MARK: - File Action Type

enum FileAction {
    case stage
    case unstage
    case discard
    case viewDiff
}

// MARK: - Branch Header View

struct BranchHeaderView: View {
    let branch: GitBranch?
    var gitState: WorkspaceGitState?
    var onBranchTap: (() -> Void)?
    var onSetupTap: (() -> Void)?
    var onAddRemoteTap: (() -> Void)?
    var onHistoryTap: (() -> Void)?
    let onPull: () -> Void
    let onPush: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Branch name with icon - tappable to switch branches
            Button {
                onBranchTap?()
                Haptics.selection()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .semibold))

                    Text(branch?.name ?? "main")
                        .font(Typography.terminal)
                        .lineLimit(1)

                    // Chevron to indicate tappable
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(ColorSystem.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Git state badge (if needs setup)
            if let state = gitState, state.needsSetup {
                Button {
                    switch state {
                    case .noGit, .gitInitialized:
                        onSetupTap?()
                    case .noRemote:
                        onAddRemoteTap?()
                    case .noPush:
                        // Push is already available via push button
                        break
                    default:
                        break
                    }
                    Haptics.selection()
                } label: {
                    GitStateBadge(state: state)
                }
                .buttonStyle(.plain)
            }

            // Sync status badges
            if let branch = branch {
                if branch.behind > 0 {
                    SyncBadge(count: branch.behind, direction: .pull)
                }
                if branch.ahead > 0 {
                    SyncBadge(count: branch.ahead, direction: .push)
                }
            }

            // Action buttons
            HStack(spacing: Spacing.xs) {
                // History button
                if let onHistoryTap = onHistoryTap {
                    Button(action: onHistoryTap) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorSystem.textSecondary)
                    }
                    .pressEffect()
                }

                // Pull button
                Button(action: onPull) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(branch?.needsPull == true ? ColorSystem.info : ColorSystem.textSecondary)
                }
                .pressEffect()

                // Push button
                Button(action: onPush) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(branch?.hasUnpushed == true ? ColorSystem.primary : ColorSystem.textSecondary)
                }
                .pressEffect()

                // Refresh button
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(ColorSystem.textSecondary)
                }
                .pressEffect()
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Sync Badge

struct SyncBadge: View {
    let count: Int
    let direction: SyncDirection

    enum SyncDirection {
        case push, pull
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: direction == .push ? "arrow.up" : "arrow.down")
                .font(.system(size: 8, weight: .bold))
            Text("\(count)")
                .font(Typography.badge)
        }
        .foregroundStyle(direction == .push ? ColorSystem.primary : ColorSystem.info)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            (direction == .push ? ColorSystem.primary : ColorSystem.info).opacity(0.15)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Commit Input View

struct CommitInputView: View {
    @Binding var message: String
    let canCommit: Bool
    let stagedCount: Int
    let isLoading: Bool
    let onCommit: () -> Void
    let onCommitAndPush: () -> Void

    @FocusState private var isFocused: Bool
    @State private var showCommitOptions = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                // Commit message input
                HStack(spacing: Spacing.xs) {
                    TextField("Commit message", text: $message, axis: .vertical)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textPrimary)
                        .lineLimit(1...3)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .padding(.vertical, Spacing.xs)
                        .padding(.leading, Spacing.sm)

                    // Commit button / menu
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(ColorSystem.primary)
                            .padding(.trailing, Spacing.sm)
                    } else {
                        Menu {
                            Button {
                                onCommit()
                            } label: {
                                Label("Commit", systemImage: "checkmark")
                            }
                            .disabled(!canCommit)

                            Button {
                                onCommitAndPush()
                            } label: {
                                Label("Commit & Push", systemImage: "arrow.up")
                            }
                            .disabled(!canCommit)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(canCommit ? ColorSystem.primary : ColorSystem.textQuaternary)
                                .symbolEffect(.bounce, value: canCommit)
                        }
                        .disabled(!canCommit && message.isEmpty)
                        .padding(.trailing, Spacing.xs)
                    }
                }
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)

            // Staged count hint
            if stagedCount > 0 {
                HStack {
                    Text("\(stagedCount) file\(stagedCount == 1 ? "" : "s") staged")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xs)
            }
        }
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - File Changes Section

struct FileChangesSection: View {
    let title: String
    let files: [GitFileEntry]
    let isStaged: Bool
    @Binding var isExpanded: Bool
    var isConflict: Bool = false
    let onStageAll: (() -> Void)?
    let onUnstageAll: (() -> Void)?
    let onFileAction: (GitFileEntry, FileAction) -> Void
    let onFileTap: (GitFileEntry) -> Void

    var body: some View {
        Section {
            if isExpanded {
                ForEach(files) { file in
                    FileChangeRow(
                        file: file,
                        isStaged: isStaged,
                        isConflict: isConflict,
                        onAction: { action in
                            onFileAction(file, action)
                        },
                        onTap: {
                            onFileTap(file)
                        }
                    )
                }
            }
        } header: {
            sectionHeader
        }
    }

    private var sectionHeader: some View {
        Button {
            withAnimation(Animations.stateChange) {
                isExpanded.toggle()
            }
            Haptics.selection()
        } label: {
            HStack(spacing: Spacing.xs) {
                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(width: 16)

                // Section title
                Text(title)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)

                // Count badge
                Text("\(files.count)")
                    .font(Typography.badge)
                    .foregroundStyle(isConflict ? ColorSystem.error : ColorSystem.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (isConflict ? ColorSystem.error : ColorSystem.textSecondary).opacity(0.15)
                    )
                    .clipShape(Capsule())

                Spacer()

                // Bulk action buttons
                if isExpanded {
                    if let onStageAll = onStageAll {
                        Button {
                            onStageAll()
                            Haptics.light()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Stage All")
                                    .font(Typography.badge)
                            }
                            .foregroundStyle(ColorSystem.primary)
                        }
                    }

                    if let onUnstageAll = onUnstageAll {
                        Button {
                            onUnstageAll()
                            Haptics.light()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "minus")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Unstage All")
                                    .font(Typography.badge)
                            }
                            .foregroundStyle(ColorSystem.warning)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(ColorSystem.terminalBgElevated)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Change Row

struct FileChangeRow: View {
    let file: GitFileEntry
    let isStaged: Bool
    var isConflict: Bool = false
    let onAction: (FileAction) -> Void
    let onTap: () -> Void

    var body: some View {
        // Main content with action buttons (no swipe gestures)
        fileContent
            .frame(height: 44)
    }

    private var fileContent: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                // Status indicator bar
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 3)

                // File icon
                Image(systemName: Icons.fileType(for: file.fileExtension))
                    .font(.system(size: 14))
                    .foregroundStyle(statusColor)
                    .frame(width: 20)

                // File info
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.fileName)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textPrimary)
                        .lineLimit(1)

                    if !file.directory.isEmpty {
                        Text(file.directory)
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textQuaternary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Diff stats or status badge
                if file.hasDiffStats {
                    HStack(spacing: 4) {
                        if file.additions > 0 {
                            Text("+\(file.additions)")
                                .font(Typography.terminalSmall)
                                .foregroundStyle(ColorSystem.Diff.addedText)
                        }
                        if file.deletions > 0 {
                            Text("-\(file.deletions)")
                                .font(Typography.terminalSmall)
                                .foregroundStyle(ColorSystem.Diff.removedText)
                        }
                    }
                }

                // Status code badge
                Text(file.statusCode)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .frame(width: 16, height: 16)
                    .background(statusColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                // Action buttons (visible, no swipe needed)
                HStack(spacing: 4) {
                    if !isStaged {
                        // Stage button
                        Button {
                            onAction(.stage)
                            Haptics.light()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ColorSystem.success)
                                .frame(width: 24, height: 24)
                                .background(ColorSystem.success.opacity(0.15))
                                .clipShape(Circle())
                        }

                        // Discard button
                        Button {
                            onAction(.discard)
                            Haptics.warning()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ColorSystem.error)
                                .frame(width: 24, height: 24)
                                .background(ColorSystem.error.opacity(0.15))
                                .clipShape(Circle())
                        }
                    } else {
                        // Unstage button
                        Button {
                            onAction(.unstage)
                            Haptics.light()
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ColorSystem.warning)
                                .frame(width: 24, height: 24)
                                .background(ColorSystem.warning.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background(ColorSystem.terminalBg)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        if isConflict { return ColorSystem.error }

        switch file.status {
        case .modified: return ColorSystem.FileChange.modified
        case .added: return ColorSystem.FileChange.added
        case .deleted: return ColorSystem.FileChange.deleted
        case .untracked: return ColorSystem.FileChange.untracked
        case .renamed: return ColorSystem.FileChange.renamed
        case .unmerged: return ColorSystem.error
        default: return ColorSystem.textSecondary
        }
    }

}

// MARK: - Diff Detail Sheet

struct DiffDetailSheet: View {
    let file: GitFileEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // Reuse existing DiffDetailView
            DiffDetailView(diff: DiffEntry(
                id: file.id,
                filePath: file.path,
                diff: file.diff,
                additions: file.additions,
                deletions: file.deletions,
                changeType: FileChangeType(rawValue: file.status.rawValue)
            ))
        }
    }
}

// MARK: - Git Error Banner

/// Compact error banner for git operations - consistent with terminal theme
struct GitErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(ColorSystem.error)

            Text(message)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Spacing.xs)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.error.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(ColorSystem.error)
                .frame(width: 3),
            alignment: .leading
        )
    }
}

// MARK: - Branch Switcher Sheet

struct BranchSwitcherSheet: View {
    @ObservedObject var viewModel: SourceControlViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    @State private var searchText = ""
    @State private var showCreateBranch = false
    @State private var newBranchName = ""
    @State private var branchToDelete: WorkspaceGitBranchInfo?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var localExpanded = true
    @State private var remoteExpanded = true
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isNewBranchFocused: Bool

    private var filteredBranches: [WorkspaceGitBranchInfo] {
        let allBranches = viewModel.branches
        guard !searchText.isEmpty else { return allBranches }
        return allBranches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var localBranches: [WorkspaceGitBranchInfo] {
        filteredBranches.filter { $0.isRemote != true }
    }

    private var remoteBranches: [WorkspaceGitBranchInfo] {
        filteredBranches.filter { $0.isRemote == true }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search and create bar
                searchAndCreateBar

                if viewModel.isLoadingBranches {
                    loadingView
                } else if filteredBranches.isEmpty {
                    emptyView
                } else {
                    branchList
                }
            }
            .background(ColorSystem.terminalBg)
            .navigationTitle("Branches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateBranch = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: layout.iconMedium))
                    }
                }
            }
            .alert("Create Branch", isPresented: $showCreateBranch) {
                TextField("Branch name", text: $newBranchName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {
                    newBranchName = ""
                }
                Button("Create") {
                    let name = newBranchName
                    newBranchName = ""
                    Task {
                        let success = await viewModel.createBranch(name: name)
                        if success { dismiss() }
                    }
                }
                .disabled(newBranchName.isEmpty)
            } message: {
                Text("Enter a name for the new branch")
            }
            .confirmationDialog(
                "Delete Branch",
                isPresented: $showDeleteConfirmation,
                presenting: branchToDelete
            ) { branch in
                Button("Delete Local Only", role: .destructive) {
                    Task { await performDelete(branch: branch, deleteRemote: false) }
                }
                if branch.upstream != nil {
                    Button("Delete Local & Remote", role: .destructive) {
                        Task { await performDelete(branch: branch, deleteRemote: true) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    branchToDelete = nil
                }
            } message: { branch in
                if viewModel.state.currentBranch?.name == branch.name {
                    Text("Cannot delete the current branch. Switch to a different branch first.")
                } else if let upstream = branch.upstream {
                    Text("Delete '\(branch.name)'?\nThis branch tracks '\(upstream)'.")
                } else {
                    Text("Delete local branch '\(branch.name)'?")
                }
            }
            .alert("Delete Failed", isPresented: .init(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK") { deleteError = nil }
            } message: {
                if let error = deleteError {
                    Text(error)
                }
            }
            .task {
                await viewModel.fetchBranches()
            }
        }
        .presentationDetents(ResponsiveLayout.isIPad ? [.large] : [.medium, .large])
    }

    private func performDelete(branch: WorkspaceGitBranchInfo, deleteRemote: Bool) async {
        isDeleting = true
        let result = await viewModel.deleteBranch(
            branch: branch.name,
            force: false,
            deleteRemote: deleteRemote
        )
        isDeleting = false

        if !result.success {
            deleteError = result.error
        }
        branchToDelete = nil
    }

    // MARK: - Search & Create Bar

    private var searchAndCreateBar: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("Search branches...", text: $searchText)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(ColorSystem.textTertiary)
                    }
                }
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, Spacing.md)
            .background(ColorSystem.terminalBgElevated)

            Divider().background(ColorSystem.terminalBgHighlight)
        }
    }

    // MARK: - Loading & Empty Views

    private var loadingView: some View {
        VStack(spacing: Spacing.sm) {
            Spacer()
            ProgressView()
            Text("Loading...")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 40))
                .foregroundStyle(ColorSystem.textQuaternary)

            if searchText.isEmpty {
                Text("No branches")
                    .font(.system(size: 15))
                    .foregroundStyle(ColorSystem.textSecondary)
            } else {
                Text("No match for '\(searchText)'")
                    .font(.system(size: 15))
                    .foregroundStyle(ColorSystem.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Branch List

    private var branchList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Local branches section
                if !localBranches.isEmpty {
                    Section {
                        if localExpanded {
                            ForEach(localBranches, id: \.name) { branch in
                                CompactBranchRow(
                                    branch: branch,
                                    isCurrent: viewModel.state.currentBranch?.name == branch.name,
                                    isLoading: viewModel.isCheckingOut || isDeleting,
                                    onSelect: {
                                        Task {
                                            let success = await viewModel.checkout(branch: branch.name)
                                            if success { dismiss() }
                                        }
                                    },
                                    onDelete: viewModel.state.currentBranch?.name != branch.name ? {
                                        branchToDelete = branch
                                        showDeleteConfirmation = true
                                    } : nil
                                )
                            }
                        }
                    } header: {
                        collapsibleHeader(
                            title: "Local",
                            count: localBranches.count,
                            icon: "arrow.triangle.branch",
                            isExpanded: $localExpanded
                        )
                    }
                }

                // Remote branches section
                if !remoteBranches.isEmpty {
                    Section {
                        if remoteExpanded {
                            ForEach(remoteBranches, id: \.name) { branch in
                                CompactBranchRow(
                                    branch: branch,
                                    isCurrent: false,
                                    isLoading: viewModel.isCheckingOut || isDeleting,
                                    onSelect: {
                                        // Extract branch name without origin/
                                        let localName = branch.name.hasPrefix("origin/")
                                            ? String(branch.name.dropFirst(7))
                                            : branch.name
                                        Task {
                                            let success = await viewModel.checkout(branch: localName)
                                            if success { dismiss() }
                                        }
                                    },
                                    onDelete: nil
                                )
                            }
                        }
                    } header: {
                        collapsibleHeader(
                            title: "Remote",
                            count: remoteBranches.count,
                            icon: "cloud",
                            isExpanded: $remoteExpanded
                        )
                    }
                }
            }
        }
    }

    private func collapsibleHeader(title: String, count: Int, icon: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(width: 14)

                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.textSecondary)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, Spacing.sm)
            .background(ColorSystem.terminalBgElevated)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Branch Row

/// Branch row for branch lists
struct CompactBranchRow: View {
    let branch: WorkspaceGitBranchInfo
    let isCurrent: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Extract display name (remove origin/ prefix for remotes)
    private var displayName: String {
        if branch.isRemote == true, branch.name.hasPrefix("origin/") {
            return String(branch.name.dropFirst(7))
        }
        return branch.name
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Current branch indicator
                Circle()
                    .fill(isCurrent ? ColorSystem.primary : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(isCurrent ? Color.clear : ColorSystem.textQuaternary, lineWidth: 1.5)
                    )

                // Branch name
                Text(displayName)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(isCurrent ? ColorSystem.primary : ColorSystem.textPrimary)
                    .lineLimit(1)

                // Tracking info (inline)
                if let upstream = branch.upstream {
                    Text("→")
                        .font(.system(size: 12))
                        .foregroundStyle(ColorSystem.textQuaternary)
                    Text(upstream.replacingOccurrences(of: "origin/", with: ""))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ColorSystem.textQuaternary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Current checkmark
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ColorSystem.primary)
                }

                // Delete button (only for local non-current branches)
                if let onDelete = onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorSystem.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(ColorSystem.terminalBgHighlight)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, 12)
            .background(isCurrent ? ColorSystem.primary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isCurrent)
    }
}

// MARK: - Preview

#Preview {
    SourceControlView(
        viewModel: SourceControlViewModel(),
        onRefresh: { }
    )
}
