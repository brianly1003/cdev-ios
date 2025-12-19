import Foundation
import Combine

/// ViewModel for Source Control (Changes tab)
@MainActor
final class SourceControlViewModel: ObservableObject {
    // MARK: - Published State

    @Published var state: RepositoryState = RepositoryState()
    @Published var stagedExpanded: Bool = true
    @Published var changesExpanded: Bool = true
    @Published var isCommitting: Bool = false

    // MARK: - Dependencies

    private let agentRepository: AgentRepositoryProtocol

    // MARK: - Init

    init(agentRepository: AgentRepositoryProtocol? = nil) {
        self.agentRepository = agentRepository ?? DependencyContainer.shared.agentRepository
    }

    // MARK: - Refresh

    /// Refresh git status from server using enhanced API
    func refresh() async {
        state.isLoading = true
        state.lastError = nil

        do {
            // Fetch enhanced git status with staged/unstaged/untracked arrays
            let response = try await agentRepository.getGitStatusExtended()

            // Convert response to repository state
            let newState = response.toRepositoryState()

            // Update state while preserving commit message
            let commitMessage = state.commitMessage
            state = newState
            state.commitMessage = commitMessage

        } catch {
            // Fallback to basic git status if enhanced not available
            do {
                let gitStatus = try await agentRepository.getGitStatus()
                updateStateFromBasicStatus(gitStatus)
            } catch {
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
        state.isLoading = true

        do {
            let response = try await agentRepository.gitStage(paths: paths)
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
        state.isLoading = true

        do {
            let response = try await agentRepository.gitUnstage(paths: paths)
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
        state.isLoading = true

        do {
            let response = try await agentRepository.gitDiscard(paths: paths)
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

        isCommitting = true

        do {
            let response = try await agentRepository.gitCommit(message: state.commitMessage, push: false)
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

        isCommitting = true

        do {
            let response = try await agentRepository.gitCommit(message: state.commitMessage, push: true)
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
        state.isLoading = true

        do {
            let response = try await agentRepository.gitPush()
            if response.success {
                await refresh()
                Haptics.success()
            } else {
                state.lastError = response.error ?? "Push failed"
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
        state.isLoading = true

        do {
            let response = try await agentRepository.gitPull()
            if response.success {
                await refresh()
                Haptics.success()
            } else {
                // Check for conflicts
                if let conflicts = response.conflictedFiles, !conflicts.isEmpty {
                    state.lastError = "Merge conflicts in: \(conflicts.joined(separator: ", "))"
                } else {
                    state.lastError = response.error ?? "Pull failed"
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
