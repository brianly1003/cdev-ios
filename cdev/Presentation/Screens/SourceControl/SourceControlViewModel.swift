import Foundation
import Combine

/// ViewModel for Source Control (Changes tab)
@MainActor
final class SourceControlViewModel: ObservableObject {
    // MARK: - Published State

    @Published var state: RepositoryState = RepositoryState() {
        didSet {
            #if DEBUG
            if oldValue.totalCount != state.totalCount || oldValue.isLoading != state.isLoading {
                AppLogger.log("[SourceControlVM] state: total=\(oldValue.totalCount)→\(state.totalCount), loading=\(oldValue.isLoading)→\(state.isLoading)")
            }
            #endif
        }
    }
    @Published var stagedExpanded: Bool = true
    @Published var changesExpanded: Bool = true
    @Published var isCommitting: Bool = false

    // MARK: - Dependencies

    private let agentRepository: AgentRepositoryProtocol
    private let workspaceManager = WorkspaceManagerService.shared
    private let workspaceStore = WorkspaceStore.shared

    // MARK: - Debounce

    /// Last refresh timestamp for debouncing
    private var lastRefreshTime: Date?
    /// Minimum interval between refreshes (500ms)
    private let refreshDebounceInterval: TimeInterval = 0.5
    /// Flag to track if refresh is in progress
    private var isRefreshing: Bool = false

    // MARK: - Workspace Support

    /// Get the current workspace ID if available
    private var currentWorkspaceId: String? {
        workspaceStore.activeWorkspace?.remoteWorkspaceId
    }

    // MARK: - Init

    init(agentRepository: AgentRepositoryProtocol? = nil) {
        self.agentRepository = agentRepository ?? DependencyContainer.shared.agentRepository
    }

    // MARK: - Refresh

    /// Refresh git status from server using enhanced API
    /// Uses workspace-aware API when a workspace is selected
    /// Debounced to prevent rapid successive calls
    func refresh() async {
        AppLogger.log("[SourceControl] refresh() called")

        // Skip if refresh in progress
        guard !isRefreshing else {
            AppLogger.log("[SourceControl] Skipping refresh - already in progress")
            return
        }

        // Debounce: skip if refreshed recently
        if let lastTime = lastRefreshTime,
           Date().timeIntervalSince(lastTime) < refreshDebounceInterval {
            AppLogger.log("[SourceControl] Skipping refresh - debounced (interval: \(Date().timeIntervalSince(lastTime))s)")
            return
        }

        AppLogger.log("[SourceControl] Starting refresh...")
        isRefreshing = true
        lastRefreshTime = Date()
        defer { isRefreshing = false }

        state.isLoading = true
        state.lastError = nil

        // Workspace ID is required for workspace git APIs
        guard let workspaceId = currentWorkspaceId else {
            AppLogger.log("[SourceControl] Cannot refresh - no workspace ID", type: .warning)
            state.isLoading = false
            return
        }

        AppLogger.log("[SourceControl] Using workspace git/status: \(workspaceId)")

        // Use a detached task to prevent SwiftUI from cancelling the request
        // when view state changes (e.g., switching between contentView/emptyStateView)
        let result: Result<GitStatusExtendedResponse, Error> = await Task.detached { [workspaceManager] in
            do {
                let response = try await workspaceManager.getGitStatus(workspaceId: workspaceId)
                return .success(response)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let response):
            AppLogger.log("[SourceControl] Got git status response - branch=\(response.branch ?? "nil"), staged=\(response.staged?.count ?? 0), unstaged=\(response.unstaged?.count ?? 0), untracked=\(response.untracked?.count ?? 0)")

            // Convert response to repository state
            var newState = response.toRepositoryState()
            newState.commitMessage = state.commitMessage
            newState.isLoading = false

            AppLogger.log("[SourceControl] Setting new state - totalCount=\(newState.totalCount), staged=\(newState.stagedCount), changes=\(newState.changesCount)")
            state = newState
            AppLogger.log("[SourceControl] State updated - viewModel.state.totalCount=\(state.totalCount)")

        case .failure(let error):
            if error is CancellationError {
                AppLogger.log("[SourceControl] Git status refresh cancelled")
            } else {
                state.lastError = error.localizedDescription
                AppLogger.error(error, context: "Refresh git status")
            }
        }

        state.isLoading = false
    }

    /// Fallback: Update state from basic git status response
    private func updateStateFromBasicStatus(_ gitStatus: GitStatusResponse) {
        var stagedFiles: [GitFileEntry] = []
        var unstagedFiles: [GitFileEntry] = []
        var untrackedFiles: [GitFileEntry] = []

        for file in gitStatus.files {
            let entry = GitFileEntry.from(gitFile: file)

            if file.isStaged {
                stagedFiles.append(GitFileEntry(
                    id: "staged-\(entry.path)",
                    path: entry.path,
                    status: entry.status,
                    isStaged: true,
                    additions: entry.additions,
                    deletions: entry.deletions,
                    diff: entry.diff
                ))
            } else if file.isUntracked {
                untrackedFiles.append(GitFileEntry(
                    id: "untracked-\(entry.path)",
                    path: entry.path,
                    status: .untracked,
                    isStaged: false
                ))
            } else {
                unstagedFiles.append(GitFileEntry(
                    id: "unstaged-\(entry.path)",
                    path: entry.path,
                    status: entry.status,
                    isStaged: false,
                    additions: entry.additions,
                    deletions: entry.deletions,
                    diff: entry.diff
                ))
            }
        }

        state.stagedFiles = stagedFiles
        state.unstagedFiles = unstagedFiles
        state.untrackedFiles = untrackedFiles

        // Create default branch if not set
        if state.currentBranch == nil {
            state.currentBranch = GitBranch(name: "main", isCurrent: true)
        }
    }

    // MARK: - Stage Operations

    /// Stage specific files
    func stageFiles(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return
        }

        state.isLoading = true
        do {
            let response = try await workspaceManager.gitStage(workspaceId: workspaceId, paths: paths)
            if response.success {
                await refresh()
                Haptics.success()
            } else {
                state.lastError = response.error ?? "Failed to stage files"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        state.isLoading = false
    }

    /// Stage all files (using "." to stage everything)
    func stageAll() async {
        await stageFiles(["."])
    }

    /// Unstage specific files
    func unstageFiles(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return
        }

        state.isLoading = true
        do {
            let response = try await workspaceManager.gitUnstage(workspaceId: workspaceId, paths: paths)
            if response.success {
                await refresh()
                Haptics.success()
            } else {
                state.lastError = response.error ?? "Failed to unstage files"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        state.isLoading = false
    }

    /// Unstage all files (using "." to unstage everything)
    func unstageAll() async {
        await unstageFiles(["."])
    }

    /// Discard changes for specific files
    func discardChanges(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return
        }

        state.isLoading = true
        do {
            let response = try await workspaceManager.gitDiscard(workspaceId: workspaceId, paths: paths)
            if response.success {
                await refresh()
                Haptics.success()
            } else {
                state.lastError = response.error ?? "Failed to discard changes"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        state.isLoading = false
    }

    // MARK: - Commit Operations

    /// Commit staged changes
    func commit() async {
        guard state.canCommit else { return }
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return
        }

        isCommitting = true
        do {
            let response = try await workspaceManager.gitCommit(workspaceId: workspaceId, message: state.commitMessage, push: false)
            if response.success {
                state.commitMessage = ""
                await refresh()
                Haptics.success()
            } else {
                state.lastError = response.error ?? "Failed to commit"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        isCommitting = false
    }

    /// Commit and push
    func commitAndPush() async {
        guard state.canCommit else { return }
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return
        }

        isCommitting = true
        do {
            let response = try await workspaceManager.gitCommit(workspaceId: workspaceId, message: state.commitMessage, push: true)
            if response.success {
                state.commitMessage = ""
                await refresh()
                Haptics.success()
            } else {
                state.lastError = response.error ?? "Failed to commit and push"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        isCommitting = false
    }

    // MARK: - Sync Operations

    /// Push to remote
    func push() async {
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return
        }

        state.isLoading = true
        do {
            let response = try await workspaceManager.gitPush(workspaceId: workspaceId)
            if response.isSuccess {
                await refresh()
                Haptics.success()
            } else {
                state.lastError = response.message ?? "Push failed"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        state.isLoading = false
    }

    /// Pull from remote
    func pull() async {
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return
        }

        state.isLoading = true
        do {
            let response = try await workspaceManager.gitPull(workspaceId: workspaceId)
            if response.isSuccess {
                await refresh()
                Haptics.success()
            } else {
                if let conflicts = response.conflictedFiles, !conflicts.isEmpty {
                    state.lastError = "Merge conflicts in: \(conflicts.joined(separator: ", "))"
                } else {
                    state.lastError = response.error ?? response.message ?? "Pull failed"
                }
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        state.isLoading = false
    }

    // MARK: - Local State Management

    /// Update state from external source (e.g., DiffCache)
    func updateFromDiffs(_ diffs: [DiffEntry]) {
        // Convert DiffEntries to GitFileEntries
        // This is used when we get updates via WebSocket
        var unstagedFiles: [GitFileEntry] = []
        var untrackedFiles: [GitFileEntry] = []

        for diff in diffs {
            let entry = GitFileEntry.from(diffEntry: diff)
            if entry.status == .untracked {
                untrackedFiles.append(entry)
            } else {
                unstagedFiles.append(entry)
            }
        }

        // Only update unstaged - staged files should come from API
        state.unstagedFiles = unstagedFiles
        state.untrackedFiles = untrackedFiles
    }
}
