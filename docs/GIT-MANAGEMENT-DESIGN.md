# Git Management Design Document

This document outlines the git management features for cdev-ios, including current implementation status, missing features, required backend APIs, and UI designs for advanced features like git graph visualization.

## Table of Contents

1. [Current Implementation](#current-implementation)
2. [Missing Features](#missing-features)
3. [Required Backend APIs](#required-backend-apis)
4. [Git Graph Visualization](#git-graph-visualization)
5. [Commit History View](#commit-history-view)
6. [Stash Management](#stash-management)
7. [Event-Driven Updates](#event-driven-updates)
8. [Implementation Roadmap](#implementation-roadmap)

---

## Current Implementation

### Feature Matrix

| Feature | Status | Location |
|---------|--------|----------|
| Git Status | ✅ Complete | `SourceControlView.swift` |
| Stage/Unstage Files | ✅ Complete | `SourceControlViewModel.swift` |
| Discard Changes | ✅ Complete | `SourceControlViewModel.swift` |
| Commit | ✅ Complete | `SourceControlViewModel.swift` |
| Commit & Push | ✅ Complete | `SourceControlViewModel.swift` |
| Push (auto set-upstream) | ✅ Complete | `SourceControlViewModel.swift` |
| Pull | ✅ Complete | `SourceControlViewModel.swift` |
| List Branches | ✅ Complete | `BranchSwitcherSheet` |
| Switch Branch | ✅ Complete | `BranchSwitcherSheet` |
| Create Branch | ✅ Complete | `BranchSwitcherSheet` |
| View Diff | ✅ Complete | `DiffDetailView` |

### Architecture

```
SourceControlView.swift          # UI Layer
    ├── BranchHeaderView         # Branch name, push/pull buttons
    ├── CommitInputView          # Commit message input
    ├── FileChangesSection       # Staged/unstaged files
    ├── BranchSwitcherSheet      # Branch list & switching
    └── DiffDetailSheet          # File diff viewer

SourceControlViewModel.swift     # State Management
    ├── state: RepositoryState   # Git status data
    ├── branches: [BranchInfo]   # Branch list
    └── Methods: refresh, stage, unstage, commit, push, pull, checkout

WorkspaceManagerService.swift    # API Layer
    └── JSON-RPC methods for workspace/git/*

GitModels.swift                  # Domain Models
    ├── GitFileEntry
    ├── GitBranch
    ├── RepositoryState
    └── API Request/Response types
```

---

## Missing Features

### High Priority

| Feature | Use Case | Complexity |
|---------|----------|------------|
| **Delete Branch** | Clean up merged branches | Low |
| **Fetch** | Check remote changes without merging | Low |
| **Commit History** | Browse past commits | Medium |
| **Git Graph** | Visualize branch topology | High |
| **Stash** | Save work-in-progress | Medium |

### Medium Priority

| Feature | Use Case | Complexity |
|---------|----------|------------|
| **Merge Branch** | Integrate feature branches | Medium |
| **Rename Branch** | Fix naming mistakes | Low |
| **Abort Merge** | Cancel failed merge | Low |
| **Conflict Resolution** | Resolve merge conflicts | High |

### Low Priority

| Feature | Use Case | Complexity |
|---------|----------|------------|
| **Rebase** | Clean up history | High |
| **Cherry-Pick** | Apply specific commits | Medium |
| **Tags** | Mark releases | Low |
| **Remote Management** | Add/remove remotes | Low |
| **Reset** | Undo commits | Medium (dangerous) |

---

## Required Backend APIs

### Branch Operations

#### Delete Branch
```json
// Request
{
  "method": "workspace/git/branch/delete",
  "params": {
    "workspace_id": "uuid",
    "branch": "feature/old-branch",
    "force": false
  }
}

// Response
{
  "success": true,
  "branch": "feature/old-branch",
  "message": "Deleted branch feature/old-branch"
}
```

#### Rename Branch
```json
// Request
{
  "method": "workspace/git/branch/rename",
  "params": {
    "workspace_id": "uuid",
    "old_name": "feature/typo",
    "new_name": "feature/fixed"
  }
}
```

### Merge Operations

#### Merge Branch
```json
// Request
{
  "method": "workspace/git/merge",
  "params": {
    "workspace_id": "uuid",
    "branch": "feature/x",
    "no_ff": false,
    "message": "Merge feature/x into main"
  }
}

// Response
{
  "success": true,
  "merge_commit": "abc123",
  "fast_forward": false,
  "conflicts": []
}

// Or with conflicts
{
  "success": false,
  "conflicts": ["src/file.swift", "src/other.swift"],
  "error": "Merge conflict"
}
```

#### Abort Merge
```json
{
  "method": "workspace/git/merge/abort",
  "params": { "workspace_id": "uuid" }
}
```

### Fetch Operation

```json
// Request
{
  "method": "workspace/git/fetch",
  "params": {
    "workspace_id": "uuid",
    "remote": "origin",
    "prune": true
  }
}

// Response
{
  "success": true,
  "new_commits": 5,
  "new_branches": ["origin/feature/new"],
  "pruned_branches": ["origin/feature/deleted"]
}
```

### Commit History / Log

```json
// Request
{
  "method": "workspace/git/log",
  "params": {
    "workspace_id": "uuid",
    "limit": 50,
    "offset": 0,
    "branch": "main",
    "path": null,
    "author": null,
    "since": null,
    "until": null,
    "graph": true
  }
}

// Response
{
  "commits": [
    {
      "sha": "abc123def456",
      "short_sha": "abc123d",
      "message": "feat: add new feature",
      "body": "Detailed description...",
      "author": {
        "name": "John Doe",
        "email": "john@example.com"
      },
      "date": "2025-12-29T10:30:00Z",
      "parents": ["def456abc789"],
      "refs": ["HEAD", "main", "origin/main"],
      "graph_position": {
        "column": 0,
        "lines": [
          { "from": 0, "to": 0, "type": "straight" }
        ]
      }
    },
    {
      "sha": "def456abc789",
      "short_sha": "def456a",
      "message": "Merge branch 'feature/x'",
      "parents": ["ghi789jkl012", "mno345pqr678"],
      "graph_position": {
        "column": 0,
        "lines": [
          { "from": 0, "to": 0, "type": "merge_left" },
          { "from": 1, "to": 0, "type": "merge_right" }
        ]
      }
    }
  ],
  "total_count": 1234,
  "has_more": true
}
```

### Stash Operations

#### Create Stash
```json
{
  "method": "workspace/git/stash",
  "params": {
    "workspace_id": "uuid",
    "message": "WIP: working on feature",
    "include_untracked": true
  }
}
```

#### List Stashes
```json
// Request
{
  "method": "workspace/git/stash/list",
  "params": { "workspace_id": "uuid" }
}

// Response
{
  "stashes": [
    {
      "index": 0,
      "message": "WIP: working on feature",
      "branch": "feature/x",
      "date": "2025-12-29T10:00:00Z",
      "files_changed": 3
    }
  ]
}
```

#### Apply/Pop Stash
```json
{
  "method": "workspace/git/stash/apply",
  "params": {
    "workspace_id": "uuid",
    "index": 0,
    "pop": true
  }
}
```

#### Drop Stash
```json
{
  "method": "workspace/git/stash/drop",
  "params": {
    "workspace_id": "uuid",
    "index": 0
  }
}
```

---

## Git Graph Visualization

### Overview

A git graph shows the commit history as a visual tree/DAG (Directed Acyclic Graph), similar to SourceTree, GitKraken, or VS Code's Git Graph extension.

### Mobile Considerations

| Challenge | Solution |
|-----------|----------|
| Small screen | Horizontal scroll for wide graphs |
| Touch targets | 44pt minimum tap areas |
| Performance | Virtualized list, lazy loading |
| Complexity | Simplified graph (max 3-4 columns) |

### Graph Components

```
┌─────────────────────────────────────────────────────────────┐
│  Git History                                    🔍 Search   │
├─────────────────────────────────────────────────────────────┤
│  Branch: main ▼    Author: All ▼    Date: All ▼            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ●──── abc123d  feat: add branch switching      2h ago     │
│  │     John Doe                                 HEAD main  │
│  │                                                          │
│  ●──── def456a  fix: LIVE mode spinner          3h ago     │
│  │     John Doe                                             │
│  │                                                          │
│  ●──┬─ ghi789j  Merge branch 'feature/x'        1d ago     │
│  │  │  John Doe                                             │
│  │  │                                                       │
│  │  ●  jkl012m  feat: feature x part 2          1d ago     │
│  │  │  Jane Smith                               feature/x   │
│  │  │                                                       │
│  │  ●  mno345p  feat: feature x part 1          2d ago     │
│  │ /   Jane Smith                                           │
│  │/                                                         │
│  ●──── pqr678s  refactor: cleanup code          3d ago     │
│  │     John Doe                                             │
│  │                                                          │
│  ●──── stu901v  initial commit                  1w ago     │
│       John Doe                                   v1.0.0     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Data Model

```swift
// MARK: - Commit Graph Models

struct CommitNode: Identifiable {
    let id: String  // SHA
    let shortSha: String
    let message: String
    let body: String?
    let author: CommitAuthor
    let date: Date
    let parents: [String]
    let refs: [GitRef]
    let graphPosition: GraphPosition
}

struct CommitAuthor {
    let name: String
    let email: String

    var avatarURL: URL? {
        // Gravatar URL from email hash
        let hash = email.lowercased().md5Hash
        return URL(string: "https://gravatar.com/avatar/\(hash)?s=40&d=identicon")
    }
}

struct GitRef {
    let name: String
    let type: RefType

    enum RefType {
        case head           // HEAD
        case localBranch    // main, feature/x
        case remoteBranch   // origin/main
        case tag            // v1.0.0
    }

    var color: Color {
        switch type {
        case .head: return .orange
        case .localBranch: return .green
        case .remoteBranch: return .blue
        case .tag: return .yellow
        }
    }
}

struct GraphPosition {
    let column: Int         // X position (0-based)
    let lines: [GraphLine]  // Lines to draw
}

struct GraphLine {
    let fromColumn: Int
    let toColumn: Int
    let type: LineType

    enum LineType {
        case straight       // │
        case mergeLeft      // ╯ or ┘
        case mergeRight     // ╰ or └
        case branchLeft     // ╮ or ┐
        case branchRight    // ╭ or ┌
        case cross          // ┼
        case horizontal     // ─
    }
}
```

### SwiftUI Implementation

```swift
// MARK: - Git Graph View

struct GitGraphView: View {
    @StateObject private var viewModel: GitGraphViewModel

    @State private var selectedCommit: CommitNode?
    @State private var searchText = ""
    @State private var selectedBranch: String?

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            GitGraphFilterBar(
                searchText: $searchText,
                selectedBranch: $selectedBranch,
                branches: viewModel.branches
            )

            // Graph content
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(viewModel.commits) { commit in
                        GitGraphRow(
                            commit: commit,
                            maxColumns: viewModel.maxColumns,
                            isSelected: selectedCommit?.id == commit.id
                        )
                        .onTapGesture {
                            selectedCommit = commit
                            Haptics.selection()
                        }
                    }

                    // Load more
                    if viewModel.hasMore {
                        ProgressView()
                            .onAppear {
                                Task { await viewModel.loadMore() }
                            }
                    }
                }
            }
        }
        .sheet(item: $selectedCommit) { commit in
            CommitDetailSheet(commit: commit)
        }
    }
}

// MARK: - Graph Row

struct GitGraphRow: View {
    let commit: CommitNode
    let maxColumns: Int
    let isSelected: Bool

    private let columnWidth: CGFloat = 20
    private let nodeSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            // Graph visualization
            graphView
                .frame(width: CGFloat(maxColumns) * columnWidth + 12)

            // Commit info
            commitInfo

            Spacer()

            // Refs (tags, branches)
            refsView

            // Relative date
            Text(commit.date.relativeFormatted)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(isSelected ? ColorSystem.primary.opacity(0.1) : Color.clear)
    }

    // MARK: - Graph Visualization

    private var graphView: some View {
        Canvas { context, size in
            let rowHeight = size.height
            let midY = rowHeight / 2

            // Draw lines
            for line in commit.graphPosition.lines {
                drawLine(context: context, line: line, midY: midY, rowHeight: rowHeight)
            }

            // Draw node (commit dot)
            let nodeX = CGFloat(commit.graphPosition.column) * columnWidth + columnWidth / 2
            let nodeRect = CGRect(
                x: nodeX - nodeSize / 2,
                y: midY - nodeSize / 2,
                width: nodeSize,
                height: nodeSize
            )

            // Node style based on commit type
            if commit.parents.count > 1 {
                // Merge commit - hollow circle
                context.stroke(Circle().path(in: nodeRect), with: .color(nodeColor), lineWidth: 2)
            } else {
                // Regular commit - filled circle
                context.fill(Circle().path(in: nodeRect), with: .color(nodeColor))
            }
        }
    }

    private func drawLine(context: GraphicsContext, line: GraphLine, midY: CGFloat, rowHeight: CGFloat) {
        let fromX = CGFloat(line.fromColumn) * columnWidth + columnWidth / 2
        let toX = CGFloat(line.toColumn) * columnWidth + columnWidth / 2

        var path = Path()

        switch line.type {
        case .straight:
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addLine(to: CGPoint(x: toX, y: rowHeight))

        case .mergeLeft, .mergeRight:
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: toX, y: midY),
                control: CGPoint(x: fromX, y: midY)
            )

        case .branchLeft, .branchRight:
            path.move(to: CGPoint(x: fromX, y: midY))
            path.addQuadCurve(
                to: CGPoint(x: toX, y: rowHeight),
                control: CGPoint(x: toX, y: midY)
            )

        case .horizontal:
            path.move(to: CGPoint(x: fromX, y: midY))
            path.addLine(to: CGPoint(x: toX, y: midY))

        case .cross:
            // Vertical
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addLine(to: CGPoint(x: fromX, y: rowHeight))
            // Horizontal
            path.move(to: CGPoint(x: min(fromX, toX), y: midY))
            path.addLine(to: CGPoint(x: max(fromX, toX), y: midY))
        }

        context.stroke(path, with: .color(lineColor(for: line.fromColumn)), lineWidth: 2)
    }

    private var nodeColor: Color {
        branchColor(for: commit.graphPosition.column)
    }

    private func lineColor(for column: Int) -> Color {
        branchColor(for: column)
    }

    private func branchColor(for column: Int) -> Color {
        let colors: [Color] = [
            ColorSystem.primary,      // Column 0 - main branch
            ColorSystem.success,      // Column 1
            ColorSystem.info,         // Column 2
            ColorSystem.warning,      // Column 3
            .purple,                  // Column 4+
            .pink
        ]
        return colors[column % colors.count]
    }

    // MARK: - Commit Info

    private var commitInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Commit message (first line)
            Text(commit.message.components(separatedBy: "\n").first ?? commit.message)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textPrimary)
                .lineLimit(1)

            // Author
            Text(commit.author.name)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
        }
    }

    // MARK: - Refs View

    private var refsView: some View {
        HStack(spacing: 4) {
            ForEach(commit.refs.prefix(3), id: \.name) { ref in
                RefBadge(ref: ref)
            }

            if commit.refs.count > 3 {
                Text("+\(commit.refs.count - 3)")
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
        }
    }
}

// MARK: - Ref Badge

struct RefBadge: View {
    let ref: GitRef

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.system(size: 8))
            Text(displayName)
                .font(Typography.badge)
        }
        .foregroundStyle(ref.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(ref.color.opacity(0.15))
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch ref.type {
        case .head: return "arrow.right"
        case .localBranch: return "arrow.triangle.branch"
        case .remoteBranch: return "cloud"
        case .tag: return "tag"
        }
    }

    private var displayName: String {
        switch ref.type {
        case .head: return "HEAD"
        case .remoteBranch:
            // Remove "origin/" prefix for display
            if ref.name.hasPrefix("origin/") {
                return String(ref.name.dropFirst(7))
            }
            return ref.name
        default:
            return ref.name
        }
    }
}
```

### Graph Algorithm

The backend should compute graph positions using a lane-based algorithm:

```python
# Pseudocode for graph layout algorithm

def compute_graph_layout(commits):
    lanes = []  # Active lanes (branches)

    for commit in commits:
        # Find or create lane for this commit
        if commit.sha in lanes:
            commit.column = lanes.index(commit.sha)
        else:
            # New branch - find empty lane or create new one
            commit.column = find_empty_lane(lanes) or len(lanes)
            lanes.insert(commit.column, commit.sha)

        # Compute lines from parents
        for parent_sha in commit.parents:
            if parent_sha in lanes:
                parent_col = lanes.index(parent_sha)
            else:
                parent_col = commit.column
                lanes[commit.column] = parent_sha

            # Determine line type
            if parent_col == commit.column:
                line_type = "straight"
            elif parent_col < commit.column:
                line_type = "merge_left"
            else:
                line_type = "merge_right"

            commit.lines.append(GraphLine(parent_col, commit.column, line_type))

        # Close lane if no more parents use it
        if commit.column not in [line.from for line in future_lines]:
            lanes[commit.column] = None

    return commits
```

### Performance Optimizations

1. **Pagination**: Load 50 commits at a time
2. **Lazy Loading**: Use `LazyVStack` for virtualization
3. **Canvas Rendering**: Draw graph with `Canvas` (GPU-accelerated)
4. **Pre-computed Layout**: Backend computes graph positions
5. **Caching**: Cache commit data in memory

---

## Commit History View

### Simple List View (Alternative to Graph)

For simpler use cases, provide a list view option:

```
┌─────────────────────────────────────────────────────────────┐
│  Commit History                           📊 Graph | 📋 List│
├─────────────────────────────────────────────────────────────┤
│  🔍 Search commits...                                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ abc123d                                      2h ago │   │
│  │ feat: add branch switching                          │   │
│  │ John Doe                              main HEAD     │   │
│  │ +376 -8  2 files                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ def456a                                      3h ago │   │
│  │ fix: LIVE mode spinner issue                        │   │
│  │ John Doe                                            │   │
│  │ +21 -8  2 files                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Commit Detail View

```
┌─────────────────────────────────────────────────────────────┐
│  ←  Commit abc123d                              ⋯ Actions   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  feat: add branch switching in Changes tab                  │
│                                                             │
│  - Add BranchSwitcherSheet with search                      │
│  - Support local and remote branches                        │
│  - Add create new branch functionality                      │
│                                                             │
│  ───────────────────────────────────────────────────────    │
│                                                             │
│  👤 John Doe <john@example.com>                             │
│  📅 Dec 29, 2025 at 10:30 AM                               │
│  🔗 Parent: def456a                                         │
│                                                             │
│  ───────────────────────────────────────────────────────    │
│                                                             │
│  📁 Changed Files (2)                           +376 -8     │
│                                                             │
│  M  SourceControlView.swift              +320 -6           │
│  M  SourceControlViewModel.swift          +56 -2           │
│                                                             │
│  ───────────────────────────────────────────────────────    │
│                                                             │
│  [View Diff]  [Cherry-Pick]  [Revert]  [Create Branch]     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Stash Management

### Stash List View

```
┌─────────────────────────────────────────────────────────────┐
│  Stashes                                        + New Stash │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ stash@{0}                                    2h ago │   │
│  │ WIP: working on feature x                           │   │
│  │ On branch: feature/x                                │   │
│  │ 3 files changed                                     │   │
│  │                                    [Apply] [Drop]   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ stash@{1}                                    1d ago │   │
│  │ On feature/y: debugging issue                       │   │
│  │ On branch: feature/y                                │   │
│  │ 5 files changed                                     │   │
│  │                                    [Apply] [Drop]   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Create Stash Dialog

```
┌─────────────────────────────────────────────────────────────┐
│  Create Stash                                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Message (optional):                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ WIP: working on feature                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ☑ Include untracked files                                  │
│  ☐ Keep staged changes                                      │
│                                                             │
│  Files to stash:                                            │
│  • M  src/FeatureView.swift                                │
│  • M  src/FeatureViewModel.swift                           │
│  • ?  src/NewFile.swift                                    │
│                                                             │
│                              [Cancel]    [Create Stash]    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Event-Driven Updates

### Events to Subscribe

| Event | Trigger | Action |
|-------|---------|--------|
| `git_status_changed` | File modified/staged | Refresh status |
| `git_operation_completed` | Push/pull/commit done | Show toast, refresh |
| `git_branch_changed` | Branch switched | Update header |
| `git_merge_conflict` | Merge has conflicts | Show warning |
| `git_stash_changed` | Stash created/applied | Refresh stash list |

### Event Payloads

```swift
// MARK: - Git Events

struct GitStatusChangedPayload: Codable {
    let workspaceId: String
    let branch: String
    let ahead: Int
    let behind: Int
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let conflictedCount: Int
    let changedFiles: [String]?
}

struct GitOperationCompletedPayload: Codable {
    let workspaceId: String
    let operation: GitOperationType
    let success: Bool
    let message: String?
    let sha: String?        // For commits
    let branch: String?     // For checkout
    let error: String?

    enum GitOperationType: String, Codable {
        case commit, push, pull, fetch, checkout, merge, rebase, stash
    }
}

struct GitBranchChangedPayload: Codable {
    let workspaceId: String
    let fromBranch: String
    let toBranch: String
    let sessionId: String  // Who switched
}

struct GitMergeConflictPayload: Codable {
    let workspaceId: String
    let sourceBranch: String
    let targetBranch: String
    let conflictedFiles: [String]
}
```

### Event Handler Integration

```swift
// In DashboardViewModel or dedicated GitEventHandler

func handleGitEvent(_ event: AgentEvent) async {
    switch event.payload {
    case .gitStatusChanged(let payload):
        // Check if it's for our workspace
        guard payload.workspaceId == currentWorkspaceId else { return }
        // Refresh source control
        await sourceControlViewModel.refresh()

    case .gitOperationCompleted(let payload):
        guard payload.workspaceId == currentWorkspaceId else { return }
        if payload.success {
            showToast(payload.message ?? "\(payload.operation) completed")
        } else {
            showError(payload.error ?? "\(payload.operation) failed")
        }
        await sourceControlViewModel.refresh()

    case .gitBranchChanged(let payload):
        guard payload.workspaceId == currentWorkspaceId else { return }
        // Another device switched branches
        if payload.sessionId != currentSessionId {
            showToast("Branch changed to \(payload.toBranch) from another device")
        }
        await sourceControlViewModel.refresh()

    case .gitMergeConflict(let payload):
        guard payload.workspaceId == currentWorkspaceId else { return }
        showConflictWarning(payload.conflictedFiles)
    }
}
```

---

## Implementation Roadmap

### Phase 1: Core Missing Features (Week 1-2)

1. **Fetch Operation**
   - Backend: Add `workspace/git/fetch` RPC
   - iOS: Add fetch button to branch header
   - iOS: Show "X commits behind" after fetch

2. **Delete Branch**
   - Backend: Add `workspace/git/branch/delete` RPC
   - iOS: Add swipe-to-delete in branch list
   - iOS: Add confirmation alert

3. **Simple Commit History**
   - Backend: Add `workspace/git/log` RPC
   - iOS: Create `CommitHistoryView` (list mode)
   - iOS: Add navigation from branch header

### Phase 2: Stash & Merge (Week 3-4)

1. **Stash Operations**
   - Backend: Add stash RPC methods
   - iOS: Create `StashManagerView`
   - iOS: Add "Stash" button in source control header

2. **Merge Branch**
   - Backend: Add `workspace/git/merge` RPC
   - iOS: Add merge option in branch actions
   - iOS: Handle conflict UI

3. **Abort Merge/Rebase**
   - Backend: Add abort RPC methods
   - iOS: Show abort button during conflicts

### Phase 3: Git Graph (Week 5-6)

1. **Graph Layout Backend**
   - Backend: Compute graph positions in `git/log`
   - Backend: Return lane/column data

2. **Graph UI**
   - iOS: Create `GitGraphView`
   - iOS: Implement Canvas-based graph rendering
   - iOS: Add commit selection & detail sheet

3. **Performance Optimization**
   - iOS: Implement pagination
   - iOS: Add caching layer
   - iOS: Profile and optimize rendering

### Phase 4: Polish & Advanced Features (Week 7-8)

1. **Commit Detail View**
   - iOS: Create comprehensive detail sheet
   - iOS: Add actions (cherry-pick, revert, etc.)

2. **Search & Filter**
   - iOS: Add commit search
   - iOS: Add author/date filters

3. **Event Integration**
   - Backend: Emit git events
   - iOS: Handle real-time updates

---

## File Locations

| Component | Location |
|-----------|----------|
| Source Control UI | `cdev/Presentation/Screens/SourceControl/` |
| Git Models | `cdev/Domain/Models/GitModels.swift` |
| RPC Methods | `cdev/Data/Services/JSONRPC/JSONRPCMethods.swift` |
| Workspace Manager | `cdev/Data/Services/WorkspaceManager/WorkspaceManagerService.swift` |
| Events | `cdev/Domain/Models/AgentEvent.swift` |

---

## References

- [SourceTree](https://www.sourcetreeapp.com/) - Desktop git client with graph
- [GitKraken](https://www.gitkraken.com/) - Cross-platform git client
- [VS Code Git Graph](https://marketplace.visualstudio.com/items?itemName=mhutchie.git-graph) - VS Code extension
- [Working Copy](https://workingcopyapp.com/) - iOS git client (inspiration for mobile UX)
