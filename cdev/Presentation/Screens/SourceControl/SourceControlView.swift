import SwiftUI

// MARK: - Source Control View (Mini Repo Management)

/// VS Code-inspired source control view for mobile
/// Layout: Branch header → Commit input → Staged → Changes
struct SourceControlView: View {
    @ObservedObject var viewModel: SourceControlViewModel
    let onRefresh: () async -> Void

    // Scroll request (from floating toolkit long-press)
    var scrollRequest: ScrollDirection?

    @State private var selectedFile: GitFileEntry?
    @State private var showCommitSheet = false
    @State private var showDiscardAlert = false
    @State private var fileToDiscard: GitFileEntry?

    // Responsive layout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        horizontalSizeClass == .compact
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
            await onRefresh()
        }
        .sheet(item: $selectedFile) { file in
            DiffDetailSheet(file: file)
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
                        onPull: { Task { await viewModel.pull() } },
                        onPush: { Task { await viewModel.push() } },
                        onRefresh: { Task { await onRefresh() } }
                    )

                    // Commit Input Section
                    CommitInputView(
                        message: $viewModel.state.commitMessage,
                        canCommit: viewModel.state.canCommit,
                        stagedCount: viewModel.state.stagedCount,
                        isLoading: viewModel.isCommitting,
                        onCommit: { Task { await viewModel.commit() } },
                        onCommitAndPush: { Task { await viewModel.commitAndPush() } }
                    )

                    // Staged Changes Section
                    if !viewModel.state.stagedFiles.isEmpty {
                        FileChangesSection(
                            title: "Staged Changes",
                            files: viewModel.state.stagedFiles,
                            isStaged: true,
                            isExpanded: $viewModel.stagedExpanded,
                            onStageAll: nil,
                            onUnstageAll: { Task { await viewModel.unstageAll() } },
                            onFileAction: { file, action in
                                handleFileAction(file: file, action: action)
                            },
                            onFileTap: { file in
                                selectedFile = file
                                Haptics.selection()
                            }
                        )
                    }

                    // Unstaged Changes Section (Modified + Untracked combined)
                    if !viewModel.state.allUnstagedFiles.isEmpty {
                        FileChangesSection(
                            title: "Changes",
                            files: viewModel.state.allUnstagedFiles,
                            isStaged: false,
                            isExpanded: $viewModel.changesExpanded,
                            onStageAll: { Task { await viewModel.stageAll() } },
                            onUnstageAll: nil,
                            onFileAction: { file, action in
                                handleFileAction(file: file, action: action)
                            },
                            onFileTap: { file in
                                selectedFile = file
                                Haptics.selection()
                            }
                        )
                    }

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
                                selectedFile = file
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
                onPull: { Task { await viewModel.pull() } },
                onPush: { Task { await viewModel.push() } },
                onRefresh: { Task { await onRefresh() } }
            )

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
                .refreshable {
                    await onRefresh()
                }
                .onChange(of: scrollRequest) { _, direction in
                    guard let direction = direction else { return }
                    handleScrollRequest(direction: direction, proxy: proxy)
                }
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
                selectedFile = file
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
    let onPull: () -> Void
    let onPush: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Branch name with icon
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))

                Text(branch?.name ?? "main")
                    .font(Typography.terminal)
                    .lineLimit(1)
            }
            .foregroundStyle(ColorSystem.textPrimary)

            Spacer()

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
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button {
                                    isFocused = false
                                } label: {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                        .foregroundStyle(ColorSystem.primary)
                                }
                            }
                        }

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

// MARK: - Preview

#Preview {
    SourceControlView(
        viewModel: SourceControlViewModel(),
        onRefresh: { }
    )
}
