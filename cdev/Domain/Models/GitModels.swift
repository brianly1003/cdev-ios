import Foundation

// MARK: - Git File Status

/// Represents a file's git status with staging information
struct GitFileEntry: Identifiable, Equatable, Hashable {
    let id: String
    let path: String
    let status: GitFileStatus
    var isStaged: Bool
    let additions: Int
    let deletions: Int
    let diff: String

    init(
        id: String = UUID().uuidString,
        path: String,
        status: GitFileStatus,
        isStaged: Bool = false,
        additions: Int = 0,
        deletions: Int = 0,
        diff: String = ""
    ) {
        self.id = id
        self.path = path
        self.status = status
        self.isStaged = isStaged
        self.additions = additions
        self.deletions = deletions
        self.diff = diff
    }

    /// File name without path
    var fileName: String {
        (path as NSString).lastPathComponent
    }

    /// Directory path (parent folder)
    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    /// File extension
    var fileExtension: String {
        (path as NSString).pathExtension
    }

    /// Short status code (M, U, D, A, R, C)
    var statusCode: String {
        status.code
    }

    /// Whether file has diff stats
    var hasDiffStats: Bool {
        additions > 0 || deletions > 0
    }

    /// Create from DiffEntry
    static func from(diffEntry: DiffEntry) -> GitFileEntry {
        GitFileEntry(
            id: diffEntry.id,
            path: diffEntry.filePath,
            status: GitFileStatus.from(changeType: diffEntry.changeType, isNew: diffEntry.isNewFile),
            isStaged: false,
            additions: diffEntry.additions,
            deletions: diffEntry.deletions,
            diff: diffEntry.diff
        )
    }

    /// Create from GitStatusResponse.GitFileStatus
    static func from(gitFile: GitStatusResponse.GitFileStatus) -> GitFileEntry {
        GitFileEntry(
            id: gitFile.path,
            path: gitFile.path,
            status: GitFileStatus.from(changeType: gitFile.changeType, isNew: gitFile.isUntracked),
            isStaged: gitFile.isStaged,
            additions: 0,
            deletions: 0,
            diff: ""
        )
    }
}

/// Git file status types
enum GitFileStatus: String, Codable, Equatable, Hashable {
    case modified       // M - Modified
    case added          // A - Added (staged new file)
    case deleted        // D - Deleted
    case renamed        // R - Renamed
    case copied         // C - Copied
    case untracked      // U/? - Untracked (new file not staged)
    case unmerged       // U - Unmerged (conflict)
    case ignored        // ! - Ignored
    case typeChanged    // T - Type changed

    /// Short code for display
    var code: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .untracked: return "U"
        case .unmerged: return "!"
        case .ignored: return "I"
        case .typeChanged: return "T"
        }
    }

    /// Human readable label
    var label: String {
        switch self {
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        case .untracked: return "Untracked"
        case .unmerged: return "Conflict"
        case .ignored: return "Ignored"
        case .typeChanged: return "Type Changed"
        }
    }

    /// Create from FileChangeType
    static func from(changeType: FileChangeType?, isNew: Bool) -> GitFileStatus {
        if isNew { return .untracked }

        switch changeType {
        case .created: return .added
        case .modified: return .modified
        case .deleted: return .deleted
        case .renamed: return .renamed
        case .none: return .modified
        }
    }
}

// MARK: - Branch Information

/// Git branch information
struct GitBranch: Identifiable, Equatable {
    let id: String
    let name: String
    let isRemote: Bool
    let isCurrent: Bool
    let upstream: String?
    let ahead: Int
    let behind: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        isRemote: Bool = false,
        isCurrent: Bool = false,
        upstream: String? = nil,
        ahead: Int = 0,
        behind: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isRemote = isRemote
        self.isCurrent = isCurrent
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }

    /// Display name (without remote prefix)
    var displayName: String {
        if isRemote, name.hasPrefix("origin/") {
            return String(name.dropFirst(7))
        }
        return name
    }

    /// Whether branch has unpushed commits
    var hasUnpushed: Bool { ahead > 0 }

    /// Whether branch is behind remote
    var needsPull: Bool { behind > 0 }

    /// Sync status text
    var syncStatus: String? {
        var parts: [String] = []
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - Repository State

/// Overall repository state for source control
struct RepositoryState: Equatable {
    var currentBranch: GitBranch?
    var stagedFiles: [GitFileEntry]
    var unstagedFiles: [GitFileEntry]
    var untrackedFiles: [GitFileEntry]
    var conflictedFiles: [GitFileEntry]
    var commitMessage: String
    var isLoading: Bool
    var lastError: String?

    init(
        currentBranch: GitBranch? = nil,
        stagedFiles: [GitFileEntry] = [],
        unstagedFiles: [GitFileEntry] = [],
        untrackedFiles: [GitFileEntry] = [],
        conflictedFiles: [GitFileEntry] = [],
        commitMessage: String = "",
        isLoading: Bool = false,
        lastError: String? = nil
    ) {
        self.currentBranch = currentBranch
        self.stagedFiles = stagedFiles
        self.unstagedFiles = unstagedFiles
        self.untrackedFiles = untrackedFiles
        self.conflictedFiles = conflictedFiles
        self.commitMessage = commitMessage
        self.isLoading = isLoading
        self.lastError = lastError
    }

    /// Total staged file count
    var stagedCount: Int { stagedFiles.count }

    /// Total unstaged changes count (modified + untracked)
    var changesCount: Int { unstagedFiles.count + untrackedFiles.count }

    /// Total file count
    var totalCount: Int { stagedCount + changesCount + conflictedFiles.count }

    /// Whether there are staged changes ready to commit
    var canCommit: Bool { !stagedFiles.isEmpty && !commitMessage.isEmpty }

    /// Whether there are any changes
    var hasChanges: Bool { totalCount > 0 }

    /// All unstaged files (modified + untracked) combined
    var allUnstagedFiles: [GitFileEntry] {
        unstagedFiles + untrackedFiles
    }
}

// MARK: - Git Operations

/// Git operation types for API calls
enum GitOperation {
    case stage(paths: [String])
    case unstage(paths: [String])
    case stageAll
    case unstageAll
    case discard(paths: [String])
    case commit(message: String)
    case commitAndPush(message: String)
    case push
    case pull
    case fetch
    case checkout(branch: String)
    case createBranch(name: String, checkout: Bool)
}

// MARK: - API Request/Response Types

/// Request to stage files
struct GitStageRequest: Encodable {
    let paths: [String]
}

/// Request to unstage files
struct GitUnstageRequest: Encodable {
    let paths: [String]
}

/// Request to discard changes
struct GitDiscardRequest: Encodable {
    let paths: [String]
}

/// Request to commit changes
struct GitCommitRequest: Encodable {
    let message: String
    let push: Bool

    init(message: String, push: Bool = false) {
        self.message = message
        self.push = push
    }
}

/// Response from commit operation
struct GitCommitResponse: Decodable {
    let success: Bool
    let sha: String?
    let message: String?
    let filesCommitted: Int?
    let pushed: Bool?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, sha, message, pushed, error
        case filesCommitted = "files_committed"
    }
}

/// Response from push/pull operations
struct GitSyncResponse: Decodable {
    let success: Bool
    let message: String?
    let commitsPushed: Int?
    let commitsPulled: Int?
    let filesChanged: Int?
    let conflictedFiles: [String]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, message, error
        case commitsPushed = "commits_pushed"
        case commitsPulled = "commits_pulled"
        case filesChanged = "files_changed"
        case conflictedFiles = "conflicted_files"
    }
}

/// Response from stage/unstage/discard operations
struct GitOperationResponse: Decodable {
    let success: Bool
    let message: String?
    let stagedCount: Int?
    let unstagedCount: Int?
    let discardedCount: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, message, error
        case stagedCount = "staged_count"
        case unstagedCount = "unstaged_count"
        case discardedCount = "discarded_count"
    }
}

/// Response with branch information
struct GitBranchResponse: Decodable {
    let current: String
    let branches: [BranchInfo]?
    let ahead: Int?
    let behind: Int?
    let upstream: String?

    struct BranchInfo: Decodable {
        let name: String
        let isRemote: Bool?
        let isCurrent: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case isRemote = "is_remote"
            case isCurrent = "is_current"
        }
    }
}

// MARK: - Enhanced Git Status Response

/// Extended git status with staging information
/// Matches the enhanced /api/git/status response from GIT-API.md
struct GitStatusExtendedResponse: Decodable {
    let branch: String?
    let upstream: String?
    let ahead: Int?
    let behind: Int?
    let staged: [GitFileInfo]?
    let unstaged: [GitFileInfo]?
    let untracked: [GitFileInfo]?
    let conflicted: [GitFileInfo]?
    let repoName: String?
    let repoRoot: String?

    enum CodingKeys: String, CodingKey {
        case branch, upstream, ahead, behind
        case staged, unstaged, untracked, conflicted
        case repoName = "repo_name"
        case repoRoot = "repo_root"
    }

    struct GitFileInfo: Decodable {
        let path: String
        let status: String?
        let additions: Int?
        let deletions: Int?

        var fileStatus: GitFileStatus {
            switch status?.uppercased() {
            case "M": return .modified
            case "A": return .added
            case "D": return .deleted
            case "R": return .renamed
            case "C": return .copied
            case "U", "?": return .untracked
            case "!": return .unmerged
            case "T": return .typeChanged
            default: return .modified
            }
        }
    }

    /// Convert to RepositoryState
    func toRepositoryState() -> RepositoryState {
        let currentBranch = branch.map { name in
            GitBranch(
                name: name,
                isCurrent: true,
                upstream: upstream,
                ahead: ahead ?? 0,
                behind: behind ?? 0
            )
        }

        let stagedFiles = (staged ?? []).map { file in
            GitFileEntry(
                id: "staged-\(file.path)",
                path: file.path,
                status: file.fileStatus,
                isStaged: true,
                additions: file.additions ?? 0,
                deletions: file.deletions ?? 0
            )
        }

        let unstagedFiles = (unstaged ?? []).map { file in
            GitFileEntry(
                id: "unstaged-\(file.path)",
                path: file.path,
                status: file.fileStatus,
                isStaged: false,
                additions: file.additions ?? 0,
                deletions: file.deletions ?? 0
            )
        }

        let untrackedFiles = (untracked ?? []).map { file in
            GitFileEntry(
                id: "untracked-\(file.path)",
                path: file.path,
                status: .untracked,
                isStaged: false
            )
        }

        let conflictedFiles = (conflicted ?? []).map { file in
            GitFileEntry(
                id: "conflict-\(file.path)",
                path: file.path,
                status: .unmerged,
                isStaged: false
            )
        }

        return RepositoryState(
            currentBranch: currentBranch,
            stagedFiles: stagedFiles,
            unstagedFiles: unstagedFiles,
            untrackedFiles: untrackedFiles,
            conflictedFiles: conflictedFiles
        )
    }
}
