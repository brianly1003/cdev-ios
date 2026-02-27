# Git API - Source Control Integration

This document describes the Git API for building iOS/mobile source control features that replicate VS Code's Source Control panel.

## Table of Contents

1. [Overview](#overview)
2. [REST API](#rest-api)
3. [WebSocket Events](#websocket-events)
4. [Data Structures](#data-structures)
5. [iOS Integration](#ios-integration)
6. [Implementation Status](#implementation-status)

---

## Overview

The Git API enables mobile developers to perform common git operations directly from the iOS app, providing a VS Code-like "Changes" tab experience for staging, committing, and syncing code.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   Git Repository            cdev-agent                    iOS App           │
│   (Local .git)              Git Service                   (Source Control)  │
│                                                                              │
│   ┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐       │
│   │ Working      │     │ Git Operations   │     │ SwiftUI Views    │       │
│   │ Directory    │────▶│                  │────▶│                  │       │
│   │              │     │ - git status     │     │ - BranchHeader   │       │
│   │ - Staged     │     │ - git add        │     │ - CommitInput    │       │
│   │ - Unstaged   │     │ - git commit     │     │ - StagedSection  │       │
│   │ - Untracked  │     │ - git push/pull  │     │ - ChangesSection │       │
│   └──────────────┘     └──────────────────┘     └──────────────────┘       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Features

| Feature | Description |
|---------|-------------|
| **File Staging** | Stage/unstage individual files or all at once |
| **Commit** | Commit staged changes with message |
| **Push/Pull** | Sync with remote repository |
| **Discard** | Discard uncommitted changes |
| **Branch Info** | View current branch and sync status |
| **Real-time Updates** | WebSocket events for file changes |

### UI Layout (VS Code-inspired)

```
┌─────────────────────────────────────────────────────────────────┐
│ ⎇ main                              ⟳ Pull  ↑ Push  ↻ Refresh  │ ← Branch Header
├─────────────────────────────────────────────────────────────────┤
│ [Commit message...]                                       [✓]   │ ← Commit Input
│ 2 files staged                                                  │
├─────────────────────────────────────────────────────────────────┤
│ ▼ Staged Changes (2)                           [Unstage All]    │ ← Collapsible
│   │ .gitignore                              M            [−]    │
│   └ src/app.ts                              M            [−]    │
├─────────────────────────────────────────────────────────────────┤
│ ▼ Changes (3)                                  [+ Stage All]    │
│   │ text002.txr                             U         [+] [×]   │ ← Untracked
│   │ text005.txt                             U         [+] [×]   │
│   └ handler.ts                              M         [+] [×]   │ ← Modified
└─────────────────────────────────────────────────────────────────┘
```

---

## REST API

### GET /api/git/status (Enhanced)

Returns comprehensive git status including staging information and branch details.

**Endpoint:** `GET /api/git/status`

**Response:**

```json
{
  "branch": "main",
  "upstream": "origin/main",
  "ahead": 2,
  "behind": 0,
  "staged": [
    {
      "path": ".gitignore",
      "status": "M",
      "additions": 5,
      "deletions": 2
    },
    {
      "path": "src/app.ts",
      "status": "M",
      "additions": 12,
      "deletions": 3
    }
  ],
  "unstaged": [
    {
      "path": "src/handler.ts",
      "status": "M",
      "additions": 8,
      "deletions": 1
    }
  ],
  "untracked": [
    {
      "path": "text002.txr",
      "status": "?"
    },
    {
      "path": "text005.txt",
      "status": "?"
    }
  ],
  "conflicted": [],
  "repo_name": "cdev-ios",
  "repo_root": "/Users/brianly/Projects/cdev-ios"
}
```

**File Status Codes:**

| Code | Meaning | Color |
|------|---------|-------|
| `M` | Modified | Yellow |
| `A` | Added (staged new file) | Green |
| `D` | Deleted | Red |
| `R` | Renamed | Blue |
| `C` | Copied | Blue |
| `?` / `U` | Untracked | Green |
| `!` | Conflict | Red |
| `T` | Type changed | Yellow |

---

### POST /api/git/stage

Stage files for commit.

**Endpoint:** `POST /api/git/stage`

**Request Body:**

```json
{
  "paths": [
    "src/handler.ts",
    "text002.txr"
  ]
}
```

**Alternative - Stage All:**

```json
{
  "paths": ["."]
}
```

**Response:**

```json
{
  "success": true,
  "staged_count": 2,
  "message": "Staged 2 files"
}
```

**Error Response:**

```json
{
  "success": false,
  "error": "Path not found: src/missing.ts"
}
```

---

### POST /api/git/unstage

Remove files from staging area.

**Endpoint:** `POST /api/git/unstage`

**Request Body:**

```json
{
  "paths": [
    ".gitignore",
    "src/app.ts"
  ]
}
```

**Alternative - Unstage All:**

```json
{
  "paths": ["."]
}
```

**Response:**

```json
{
  "success": true,
  "unstaged_count": 2,
  "message": "Unstaged 2 files"
}
```

---

### POST /api/git/discard

Discard uncommitted changes (restore files to last commit state).

**Endpoint:** `POST /api/git/discard`

**Request Body:**

```json
{
  "paths": [
    "src/handler.ts"
  ]
}
```

**Response:**

```json
{
  "success": true,
  "discarded_count": 1,
  "message": "Discarded changes in 1 file"
}
```

**⚠️ Warning:** This operation is destructive and cannot be undone. The iOS app should show a confirmation dialog before calling this endpoint.

---

### POST /api/git/commit

Commit staged changes.

**Endpoint:** `POST /api/git/commit`

**Request Body:**

```json
{
  "message": "feat: add user authentication\n\nImplemented JWT-based auth flow",
  "push": false
}
```

**With Push:**

```json
{
  "message": "fix: resolve login issue",
  "push": true
}
```

**Response (Success):**

```json
{
  "success": true,
  "sha": "abc123def456",
  "message": "Committed: fix: resolve login issue",
  "files_committed": 2
}
```

**Response (Push Success):**

```json
{
  "success": true,
  "sha": "abc123def456",
  "message": "Committed and pushed to origin/main",
  "files_committed": 2,
  "pushed": true
}
```

**Error Response:**

```json
{
  "success": false,
  "error": "Nothing to commit (no staged changes)"
}
```

---

### POST /api/git/push

Push commits to remote.

**Endpoint:** `POST /api/git/push`

**Request Body:**

```json
{}
```

**With Force (use with caution):**

```json
{
  "force": true
}
```

**With Set Upstream:**

```json
{
  "set_upstream": true,
  "remote": "origin",
  "branch": "feature-branch"
}
```

**Response:**

```json
{
  "success": true,
  "message": "Pushed to origin/main",
  "commits_pushed": 2
}
```

**Error Response:**

```json
{
  "success": false,
  "error": "Push rejected: Updates were rejected because the remote contains work that you do not have locally"
}
```

---

### POST /api/git/pull

Pull changes from remote.

**Endpoint:** `POST /api/git/pull`

**Request Body:**

```json
{}
```

**With Rebase:**

```json
{
  "rebase": true
}
```

**Response:**

```json
{
  "success": true,
  "message": "Pulled 3 commits from origin/main",
  "commits_pulled": 3,
  "files_changed": 5
}
```

**Conflict Response:**

```json
{
  "success": false,
  "error": "Merge conflict",
  "conflicted_files": [
    "src/app.ts",
    "package.json"
  ]
}
```

---

### GET /api/git/diff

Get diff for specific file or all changes.

**Endpoint:** `GET /api/git/diff`

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | No | File path (omit for all files) |
| `staged` | boolean | No | Get staged diff (default: false) |

**Example - Single File:**

```
GET /api/git/diff?path=src/app.ts
```

**Example - All Staged:**

```
GET /api/git/diff?staged=true
```

**Response:**

```json
{
  "path": "src/app.ts",
  "additions": 12,
  "deletions": 3,
  "diff": "diff --git a/src/app.ts b/src/app.ts\nindex abc123..def456 100644\n--- a/src/app.ts\n+++ b/src/app.ts\n@@ -4,6 +4,15 @@\n import express from 'express';\n+import { authenticate } from './auth';\n..."
}
```

---

### GET /api/git/branches

List branches with current branch info.

**Endpoint:** `GET /api/git/branches`

**Response:**

```json
{
  "current": "main",
  "upstream": "origin/main",
  "ahead": 2,
  "behind": 0,
  "branches": [
    {
      "name": "main",
      "is_current": true,
      "is_remote": false,
      "upstream": "origin/main",
      "ahead": 2,
      "behind": 0
    },
    {
      "name": "feature/auth",
      "is_current": false,
      "is_remote": false,
      "upstream": null,
      "ahead": 0,
      "behind": 0
    },
    {
      "name": "origin/main",
      "is_current": false,
      "is_remote": true
    }
  ]
}
```

---

### POST /api/git/checkout

Switch branches or create new branch.

**Endpoint:** `POST /api/git/checkout`

**Switch Branch:**

```json
{
  "branch": "feature/auth"
}
```

**Create and Switch:**

```json
{
  "branch": "feature/new-feature",
  "create": true
}
```

**Response:**

```json
{
  "success": true,
  "branch": "feature/auth",
  "message": "Switched to branch 'feature/auth'"
}
```

**Error Response:**

```json
{
  "success": false,
  "error": "Cannot switch branches: You have unstaged changes"
}
```

---

## WebSocket Events

### Event: `git_status_changed`

Emitted when git status changes (file modified, staged, etc.).

**Connection:** `ws://localhost:16180/ws`

**Payload:**

```json
{
  "event": "git_status_changed",
  "timestamp": "2025-12-19T03:00:02Z",
  "payload": {
    "branch": "main",
    "ahead": 2,
    "behind": 0,
    "staged_count": 2,
    "unstaged_count": 3,
    "untracked_count": 1,
    "has_conflicts": false
  }
}
```

---

### Event: `file_changed`

Emitted when a file is modified in the repository.

```json
{
  "event": "file_changed",
  "timestamp": "2025-12-19T03:00:03Z",
  "payload": {
    "path": "src/app.ts",
    "change": "modified"
  }
}
```

**Change Types:**
- `created` - New file added
- `modified` - Existing file changed
- `deleted` - File removed
- `renamed` - File renamed

---

### Event: `git_operation_completed`

Emitted when a git operation (commit, push, pull) completes.

```json
{
  "event": "git_operation_completed",
  "timestamp": "2025-12-19T03:00:04Z",
  "payload": {
    "operation": "commit",
    "success": true,
    "sha": "abc123def456",
    "message": "feat: add user authentication"
  }
}
```

**Operations:**
- `commit`
- `push`
- `pull`
- `stage`
- `unstage`
- `checkout`

---

## Data Structures

### GitFileEntry

Represents a file in the git status.

```json
{
  "path": "src/app.ts",
  "status": "M",
  "is_staged": false,
  "additions": 12,
  "deletions": 3
}
```

| Field | Type | Description |
|-------|------|-------------|
| `path` | string | Relative file path |
| `status` | string | Git status code (M, A, D, R, ?, etc.) |
| `is_staged` | boolean | Whether file is staged |
| `additions` | integer | Lines added (optional) |
| `deletions` | integer | Lines removed (optional) |

---

### GitBranch

Represents a git branch.

```json
{
  "name": "main",
  "is_current": true,
  "is_remote": false,
  "upstream": "origin/main",
  "ahead": 2,
  "behind": 0
}
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Branch name |
| `is_current` | boolean | Whether this is the current branch |
| `is_remote` | boolean | Whether this is a remote branch |
| `upstream` | string? | Upstream tracking branch |
| `ahead` | integer | Commits ahead of upstream |
| `behind` | integer | Commits behind upstream |

---

### GitCommitResult

Response from commit operation.

```json
{
  "success": true,
  "sha": "abc123def456789",
  "message": "Committed: feat: add feature",
  "files_committed": 3,
  "pushed": false
}
```

---

### GitSyncResult

Response from push/pull operations.

```json
{
  "success": true,
  "message": "Pulled 3 commits from origin/main",
  "commits_count": 3,
  "files_changed": 5,
  "conflicted_files": []
}
```

---

## iOS Integration

### SourceControlViewModel

```swift
import Foundation
import Combine

@MainActor
final class SourceControlViewModel: ObservableObject {
    // MARK: - Published State

    @Published var state: RepositoryState = RepositoryState()
    @Published var stagedExpanded: Bool = true
    @Published var changesExpanded: Bool = true
    @Published var isCommitting: Bool = false

    // MARK: - API Methods

    /// Refresh git status
    func refresh() async {
        state.isLoading = true
        do {
            let response = try await agentRepository.getGitStatus()
            // Update state from response...
        } catch {
            state.lastError = error.localizedDescription
        }
        state.isLoading = false
    }

    /// Stage files
    func stageFiles(_ paths: [String]) async {
        try await agentRepository.gitStage(paths: paths)
        await refresh()
    }

    /// Unstage files
    func unstageFiles(_ paths: [String]) async {
        try await agentRepository.gitUnstage(paths: paths)
        await refresh()
    }

    /// Discard changes
    func discardChanges(_ paths: [String]) async {
        try await agentRepository.gitDiscard(paths: paths)
        await refresh()
    }

    /// Commit staged changes
    func commit() async {
        guard state.canCommit else { return }
        isCommitting = true
        try await agentRepository.gitCommit(
            message: state.commitMessage,
            push: false
        )
        state.commitMessage = ""
        await refresh()
        isCommitting = false
    }

    /// Push to remote
    func push() async {
        try await agentRepository.gitPush()
        await refresh()
    }

    /// Pull from remote
    func pull() async {
        try await agentRepository.gitPull()
        await refresh()
    }
}
```

### Repository State Model

```swift
struct RepositoryState: Equatable {
    var currentBranch: GitBranch?
    var stagedFiles: [GitFileEntry] = []
    var unstagedFiles: [GitFileEntry] = []
    var untrackedFiles: [GitFileEntry] = []
    var conflictedFiles: [GitFileEntry] = []
    var commitMessage: String = ""
    var isLoading: Bool = false
    var lastError: String?

    /// Whether there are staged changes ready to commit
    var canCommit: Bool {
        !stagedFiles.isEmpty && !commitMessage.isEmpty
    }

    /// Total file count
    var totalCount: Int {
        stagedFiles.count + unstagedFiles.count +
        untrackedFiles.count + conflictedFiles.count
    }
}
```

### API Request Types

```swift
/// Stage files request
struct GitStageRequest: Encodable {
    let paths: [String]
}

/// Unstage files request
struct GitUnstageRequest: Encodable {
    let paths: [String]
}

/// Discard changes request
struct GitDiscardRequest: Encodable {
    let paths: [String]
}

/// Commit request
struct GitCommitRequest: Encodable {
    let message: String
    let push: Bool
}

/// Commit response
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

/// Sync (push/pull) response
struct GitSyncResponse: Decodable {
    let success: Bool
    let message: String?
    let commitsCount: Int?
    let filesChanged: Int?
    let conflictedFiles: [String]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, message, error
        case commitsCount = "commits_count"
        case filesChanged = "files_changed"
        case conflictedFiles = "conflicted_files"
    }
}
```

### SwiftUI FileChangeRow

```swift
struct FileChangeRow: View {
    let file: GitFileEntry
    let isStaged: Bool
    let onAction: (FileAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Status color bar
            Rectangle()
                .fill(statusColor)
                .frame(width: 3)

            // File icon
            Image(systemName: fileIcon)
                .foregroundStyle(statusColor)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(.body, design: .monospaced))
                if !file.directory.isEmpty {
                    Text(file.directory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Diff stats
            if file.additions > 0 || file.deletions > 0 {
                HStack(spacing: 4) {
                    if file.additions > 0 {
                        Text("+\(file.additions)")
                            .foregroundStyle(.green)
                    }
                    if file.deletions > 0 {
                        Text("-\(file.deletions)")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
            }

            // Status badge
            Text(file.statusCode)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15))
                .cornerRadius(3)

            // Action buttons
            if !isStaged {
                Button { onAction(.stage) } label: {
                    Image(systemName: "plus")
                }
                .foregroundStyle(.green)

                Button { onAction(.discard) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .foregroundStyle(.red)
            } else {
                Button { onAction(.unstage) } label: {
                    Image(systemName: "minus")
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 8)
    }

    var statusColor: Color {
        switch file.status {
        case .modified: return .orange
        case .added, .untracked: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .unmerged: return .red
        default: return .gray
        }
    }
}
```

---

## Implementation Status

### cdev-agent (Backend)

- [x] `GET /api/git/status` - Basic status (existing)
- [ ] `GET /api/git/status` - Enhanced with staging info
- [ ] `POST /api/git/stage` - Stage files
- [ ] `POST /api/git/unstage` - Unstage files
- [ ] `POST /api/git/discard` - Discard changes
- [ ] `POST /api/git/commit` - Commit with push option
- [ ] `POST /api/git/push` - Push to remote
- [ ] `POST /api/git/pull` - Pull from remote
- [ ] `GET /api/git/branches` - List branches
- [ ] `POST /api/git/checkout` - Switch/create branches
- [ ] WebSocket `git_status_changed` event
- [ ] WebSocket `git_operation_completed` event

### cdev-ios (Frontend)

- [x] `GitModels.swift` - Data models
- [x] `SourceControlView.swift` - Main UI
- [x] `SourceControlViewModel.swift` - State management
- [x] `FileChangeRow.swift` - File list item
- [x] `CommitInputView.swift` - Commit message input
- [x] `BranchHeaderView.swift` - Branch & sync status
- [x] API integration (stubs ready for backend)
- [ ] WebSocket event handling for real-time updates
- [ ] Swipe gesture actions
- [ ] Pull-to-refresh

---

## Error Handling

### HTTP Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| 400 | Bad Request | Invalid parameters |
| 404 | Not Found | File or branch doesn't exist |
| 409 | Conflict | Merge conflict or operation in progress |
| 422 | Unprocessable | Git operation failed (e.g., nothing to commit) |
| 500 | Server Error | Internal error |

### Common Error Scenarios

1. **Nothing to commit**
   ```json
   {"success": false, "error": "Nothing to commit (no staged changes)"}
   ```

2. **Merge conflicts**
   ```json
   {"success": false, "error": "Merge conflict", "conflicted_files": ["src/app.ts"]}
   ```

3. **Push rejected**
   ```json
   {"success": false, "error": "Push rejected: Updates were rejected because the remote contains work that you do not have locally"}
   ```

4. **Uncommitted changes blocking checkout**
   ```json
   {"success": false, "error": "Cannot switch branches: You have unstaged changes"}
   ```

---

*Document Version: 1.0*
*Last Updated: 2025-12-19*
