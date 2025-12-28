import Foundation
import SwiftUI

// MARK: - Workspace Git State

/// Represents the overall git state of a workspace
enum WorkspaceGitState: String, Codable {
    case noGit          // No .git folder
    case gitInitialized // Has .git but no commits
    case noRemote       // Has commits but no remote
    case noPush         // Has remote but never pushed (no upstream)
    case synced         // Fully configured
    case diverged       // Has unpushed/unpulled commits
    case conflict       // Has merge conflicts

    var icon: String {
        switch self {
        case .noGit: return "folder"
        case .gitInitialized: return "leaf"
        case .noRemote: return "desktopcomputer"
        case .noPush: return "link"
        case .synced: return "checkmark.circle.fill"
        case .diverged: return "arrow.triangle.2.circlepath"
        case .conflict: return "exclamationmark.triangle.fill"
        }
    }

    var statusText: String {
        switch self {
        case .noGit: return "Not a Git Repository"
        case .gitInitialized: return "Git Initialized"
        case .noRemote: return "No Remote Configured"
        case .noPush: return "Ready to Push"
        case .synced: return "Synced"
        case .diverged: return "Changes to Sync"
        case .conflict: return "Conflicts"
        }
    }

    var shortText: String {
        switch self {
        case .noGit: return "No Git"
        case .gitInitialized: return "Init"
        case .noRemote: return "Local"
        case .noPush: return "Unpushed"
        case .synced: return "Synced"
        case .diverged: return "Diverged"
        case .conflict: return "Conflict"
        }
    }

    var actionRequired: String? {
        switch self {
        case .noGit: return "Initialize Git to start version control"
        case .gitInitialized: return "Make your first commit"
        case .noRemote: return "Add a remote to sync with GitHub/GitLab"
        case .noPush: return "Push to set up tracking"
        case .synced, .diverged, .conflict: return nil
        }
    }

    var needsSetup: Bool {
        switch self {
        case .noGit, .gitInitialized, .noRemote, .noPush:
            return true
        case .synced, .diverged, .conflict:
            return false
        }
    }
}

// MARK: - Git Remote URL Parser

/// Parses and represents a git remote URL (SSH or HTTPS)
struct GitRemoteURL: Equatable {
    let originalURL: String
    let provider: GitProvider
    let host: String
    let owner: String
    let repoName: String
    let isSSH: Bool

    enum GitProvider: String, CaseIterable {
        case github = "github.com"
        case gitlab = "gitlab.com"
        case bitbucket = "bitbucket.org"
        case custom = "custom"

        var displayName: String {
            switch self {
            case .github: return "GitHub"
            case .gitlab: return "GitLab"
            case .bitbucket: return "Bitbucket"
            case .custom: return "Git Server"
            }
        }

        var icon: String {
            switch self {
            case .github: return "link.circle.fill"
            case .gitlab: return "g.square.fill"
            case .bitbucket: return "b.square.fill"
            case .custom: return "server.rack"
            }
        }

        var color: Color {
            switch self {
            case .github: return .primary
            case .gitlab: return .orange
            case .bitbucket: return .blue
            case .custom: return .gray
            }
        }
    }

    /// Parse a git URL string into components
    /// Supports both SSH and HTTPS formats
    static func parse(_ urlString: String) -> GitRemoteURL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // SSH format: git@github.com:username/repo.git
        if trimmed.hasPrefix("git@") {
            return parseSSH(trimmed)
        }

        // HTTPS format: https://github.com/username/repo.git
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            return parseHTTPS(trimmed)
        }

        // Try to auto-detect and fix common mistakes
        // e.g., "github.com/user/repo" without protocol
        if trimmed.contains("/") && !trimmed.contains("@") && trimmed.contains(".") {
            return parseHTTPS("https://\(trimmed)")
        }

        return nil
    }

    private static func parseSSH(_ url: String) -> GitRemoteURL? {
        // Pattern: git@host:owner/repo.git
        // Example: git@github.com:brianly1003/Cdev.git

        let pattern = #"^git@([^:]+):([^/]+)/(.+?)(?:\.git)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              match.numberOfRanges == 4 else {
            return nil
        }

        guard let hostRange = Range(match.range(at: 1), in: url),
              let ownerRange = Range(match.range(at: 2), in: url),
              let repoRange = Range(match.range(at: 3), in: url) else {
            return nil
        }

        let host = String(url[hostRange])
        let owner = String(url[ownerRange])
        let repo = String(url[repoRange])

        let provider = GitProvider.allCases.first { $0.rawValue == host } ?? .custom

        return GitRemoteURL(
            originalURL: url,
            provider: provider,
            host: host,
            owner: owner,
            repoName: repo,
            isSSH: true
        )
    }

    private static func parseHTTPS(_ url: String) -> GitRemoteURL? {
        // Pattern: https://host/owner/repo.git
        // Example: https://github.com/brianly1003/Cdev.git

        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return nil
        }

        let pathComponents = urlObj.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }

        let owner = pathComponents[0]
        var repo = pathComponents[1]

        // Remove .git suffix if present
        if repo.hasSuffix(".git") {
            repo = String(repo.dropLast(4))
        }

        let provider = GitProvider.allCases.first { $0.rawValue == host } ?? .custom

        return GitRemoteURL(
            originalURL: url,
            provider: provider,
            host: host,
            owner: owner,
            repoName: repo,
            isSSH: false
        )
    }

    /// Convert to the other format (SSH ↔ HTTPS)
    var alternateURL: String {
        if isSSH {
            return "https://\(host)/\(owner)/\(repoName).git"
        } else {
            return "git@\(host):\(owner)/\(repoName).git"
        }
    }

    /// Display name for UI
    var displayName: String {
        "\(owner)/\(repoName)"
    }

    /// Full URL for git commands
    var fullURL: String {
        originalURL.hasSuffix(".git") ? originalURL : "\(originalURL).git"
    }

    /// Protocol badge text
    var protocolText: String {
        isSSH ? "SSH" : "HTTPS"
    }
}

// MARK: - Git Remote Info

/// Information about a git remote
struct GitRemoteInfo: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let fetchURL: String
    let pushURL: String?
    let provider: String?
    let trackingBranches: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case fetchURL = "fetch_url"
        case pushURL = "push_url"
        case provider
        case trackingBranches = "tracking_branches"
    }

    /// Parsed remote URL for display
    var parsedURL: GitRemoteURL? {
        GitRemoteURL.parse(fetchURL)
    }
}

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

    /// All files combined (for file explorer git status overlay)
    var allFiles: [GitFileEntry] {
        stagedFiles + unstagedFiles + untrackedFiles + conflictedFiles
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

    /// Memberwise initializer for programmatic creation
    init(success: Bool, commitHash: String? = nil, message: String? = nil, filesCommitted: Int? = nil, pushed: Bool? = nil, error: String? = nil) {
        self.success = success
        self.sha = commitHash
        self.message = message
        self.filesCommitted = filesCommitted
        self.pushed = pushed
        self.error = error
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

    /// Memberwise initializer for programmatic creation
    init(success: Bool, message: String? = nil, commitsPushed: Int? = nil, commitsPulled: Int? = nil, filesChanged: Int? = nil, conflictedFiles: [String]? = nil, error: String? = nil) {
        self.success = success
        self.message = message
        self.commitsPushed = commitsPushed
        self.commitsPulled = commitsPulled
        self.filesChanged = filesChanged
        self.conflictedFiles = conflictedFiles
        self.error = error
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

    /// Memberwise initializer for programmatic creation
    init(success: Bool, message: String? = nil, stagedCount: Int? = nil, unstagedCount: Int? = nil, discardedCount: Int? = nil, error: String? = nil) {
        self.success = success
        self.message = message
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.discardedCount = discardedCount
        self.error = error
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

    /// Memberwise initializer for programmatic creation (e.g., from RPC)
    init(
        branch: String? = nil,
        upstream: String? = nil,
        ahead: Int? = nil,
        behind: Int? = nil,
        staged: [GitFileInfo]? = nil,
        unstaged: [GitFileInfo]? = nil,
        untracked: [GitFileInfo]? = nil,
        conflicted: [GitFileInfo]? = nil,
        repoName: String? = nil,
        repoRoot: String? = nil
    ) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.conflicted = conflicted
        self.repoName = repoName
        self.repoRoot = repoRoot
    }

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

        /// Memberwise initializer for programmatic creation
        init(path: String, status: String? = nil, additions: Int? = nil, deletions: Int? = nil) {
            self.path = path
            self.status = status
            self.additions = additions
            self.deletions = deletions
        }

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
