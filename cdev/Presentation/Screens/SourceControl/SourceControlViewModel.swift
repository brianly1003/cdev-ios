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
    @Published var branches: [WorkspaceGitBranchInfo] = []
    @Published var isLoadingBranches: Bool = false
    @Published var isCheckingOut: Bool = false
    @Published var remotes: [WorkspaceGitRemoteInfo] = []
    @Published var gitState: WorkspaceGitState = .synced

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
    /// - Parameter setUpstream: If true, sets upstream for new branches. Auto-detected if nil.
    func push(setUpstream: Bool? = nil) async {
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return
        }

        state.isLoading = true
        do {
            // Auto-detect if we need to set upstream:
            // If branch has no upstream tracking, we need --set-upstream
            let needsUpstream = setUpstream ?? (state.currentBranch?.upstream == nil)

            let response = try await workspaceManager.gitPush(
                workspaceId: workspaceId,
                force: false,
                setUpstream: needsUpstream
            )
            if response.isSuccess {
                await refresh()
                Haptics.success()
                if needsUpstream {
                    AppLogger.log("[SourceControl] Pushed with --set-upstream for new branch")
                }
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

    // MARK: - Branch Operations

    /// Fetch all branches
    func fetchBranches() async {
        guard let workspaceId = currentWorkspaceId else {
            AppLogger.log("[SourceControl] Cannot fetch branches - no workspace ID", type: .warning)
            return
        }

        isLoadingBranches = true
        do {
            let result = try await workspaceManager.getBranches(workspaceId: workspaceId)
            branches = result.branches ?? []
            AppLogger.log("[SourceControl] Fetched \(branches.count) branches, current: \(result.current ?? "nil")")
        } catch {
            AppLogger.error(error, context: "Fetch branches")
            state.lastError = "Failed to load branches"
        }
        isLoadingBranches = false
    }

    /// Fetch remotes and update git state
    func fetchRemotes() async {
        guard let workspaceId = currentWorkspaceId else {
            return
        }

        do {
            let result = try await workspaceManager.getRemotes(workspaceId: workspaceId)
            remotes = result.safeRemotes
            AppLogger.log("[SourceControl] Fetched \(remotes.count) remotes")
        } catch {
            AppLogger.error(error, context: "Fetch remotes")
        }
    }

    /// Fetch git state from the server
    func fetchGitState() async {
        guard let workspaceId = currentWorkspaceId else {
            gitState = .noGit
            return
        }

        do {
            let result = try await workspaceManager.getGitState(workspaceId: workspaceId)
            gitState = result.gitState
            AppLogger.log("[SourceControl] Git state: \(gitState.rawValue)")
        } catch {
            // Fallback to local detection
            updateGitStateLocally()
            AppLogger.error(error, context: "Fetch git state")
        }
    }

    /// Update git state based on current status (fallback)
    private func updateGitStateLocally() {
        // Determine git state from available data
        if state.currentBranch == nil && state.totalCount == 0 {
            // No branch info could mean no git or not initialized
            // We'll rely on the WorkspaceStatus gitTrackerState for accurate detection
            gitState = .noGit
        } else if remotes.isEmpty {
            gitState = .noRemote
        } else if state.currentBranch?.upstream == nil {
            gitState = .noPush
        } else if !state.conflictedFiles.isEmpty {
            gitState = .conflict
        } else if state.currentBranch?.ahead ?? 0 > 0 || state.currentBranch?.behind ?? 0 > 0 {
            gitState = .diverged
        } else {
            gitState = .synced
        }
    }

    /// Initialize git for current workspace
    func initializeGit() async -> Bool {
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return false
        }

        state.isLoading = true
        do {
            let result = try await workspaceManager.gitInit(workspaceId: workspaceId)
            if result.isSuccess {
                AppLogger.log("[SourceControl] Git initialized successfully")
                await refresh()
                Haptics.success()
                state.isLoading = false
                return true
            } else {
                state.lastError = result.error ?? result.message ?? "Failed to initialize git"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        state.isLoading = false
        return false
    }

    /// Add a remote to current workspace
    func addRemote(name: String, url: String) async -> Bool {
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return false
        }

        state.isLoading = true
        do {
            let result = try await workspaceManager.gitRemoteAdd(workspaceId: workspaceId, name: name, url: url)
            if result.isSuccess {
                AppLogger.log("[SourceControl] Remote added: \(name)")
                await fetchRemotes()
                Haptics.success()
                state.isLoading = false
                return true
            } else {
                state.lastError = result.error ?? result.message ?? "Failed to add remote"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        state.isLoading = false
        return false
    }

    /// Checkout a branch
    func checkout(branch: String) async -> Bool {
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return false
        }

        // Don't checkout if already on this branch
        if state.currentBranch?.name == branch {
            AppLogger.log("[SourceControl] Already on branch: \(branch)")
            return true
        }

        isCheckingOut = true
        do {
            let result = try await workspaceManager.gitCheckout(workspaceId: workspaceId, branch: branch)
            if result.isSuccess {
                AppLogger.log("[SourceControl] Checked out branch: \(branch)")
                await refresh()
                Haptics.success()
                isCheckingOut = false
                return true
            } else {
                state.lastError = result.error ?? result.message ?? "Failed to checkout branch"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        isCheckingOut = false
        return false
    }

    /// Create and checkout a new branch
    func createBranch(name: String) async -> Bool {
        guard let workspaceId = currentWorkspaceId else {
            state.lastError = "No workspace selected"
            Haptics.error()
            return false
        }

        isCheckingOut = true
        do {
            let result = try await workspaceManager.gitCheckout(workspaceId: workspaceId, branch: name, create: true)
            if result.isSuccess {
                AppLogger.log("[SourceControl] Created and checked out branch: \(name)")
                await refresh()
                await fetchBranches()
                Haptics.success()
                isCheckingOut = false
                return true
            } else {
                state.lastError = result.error ?? result.message ?? "Failed to create branch"
                Haptics.error()
            }
        } catch {
            state.lastError = error.localizedDescription
            Haptics.error()
        }
        isCheckingOut = false
        return false
    }

    /// Delete a branch (local and optionally remote)
    /// - Parameters:
    ///   - branch: Branch name to delete
    ///   - force: Force delete even if not fully merged
    ///   - deleteRemote: Also delete from remote (origin)
    /// - Returns: Success result with optional error message
    func deleteBranch(branch: String, force: Bool = false, deleteRemote: Bool = false) async -> (success: Bool, error: String?) {
        guard let workspaceId = currentWorkspaceId else {
            Haptics.error()
            return (false, "No workspace selected")
        }

        // Cannot delete current branch
        if state.currentBranch?.name == branch {
            Haptics.error()
            return (false, "Cannot delete the current branch. Switch to a different branch first.")
        }

        do {
            let result = try await workspaceManager.gitBranchDelete(
                workspaceId: workspaceId,
                branch: branch,
                force: force,
                deleteRemote: deleteRemote
            )

            if result.success == true {
                AppLogger.log("[SourceControl] Deleted branch: \(branch), remote: \(result.deletedRemote ?? false)")
                await fetchBranches()
                Haptics.success()
                return (true, nil)
            } else {
                let errorMsg = result.error ?? result.message ?? "Failed to delete branch"
                Haptics.error()
                return (false, errorMsg)
            }
        } catch {
            Haptics.error()
            return (false, error.localizedDescription)
        }
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
