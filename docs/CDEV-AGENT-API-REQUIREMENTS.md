# cdev-agent API Requirements for Git Setup Flow

This document outlines the API changes needed in cdev-agent to support the iOS app's git workspace setup flow, enabling users to add non-git folders and walk through initialization.

**Last Updated:** December 2024

---

## Overview

The iOS app needs cdev-agent to:
1. **Accept non-git folders** in `workspace/add` ✅ IMPLEMENTED
2. **Create new folders** with `create_if_missing` ✅ IMPLEMENTED
3. **Report git state** in workspace responses ✅ IMPLEMENTED
4. **Support git initialization** for new projects

---

## 1. Enhanced `workspace/add` API ✅ IMPLEMENTED

### Changes Made (cdev-agent)

- **workspace_config.go**: Added `create_if_missing` parameter
- **config_manager.go**: New `AddWorkspaceWithOptions` method that creates directories when needed
- Response now includes `is_git_repo` and `git_state` fields at the top level

### Request

```json
{
  "method": "workspace/add",
  "params": {
    "name": "MyProject",
    "path": "/Users/dev/Projects/MyProject",
    "create_if_missing": true    // NEW: Create directory if it doesn't exist
  }
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Display name for workspace |
| `path` | string | Yes | Absolute path to folder |
| `create_if_missing` | boolean | No | Create directory if it doesn't exist (default: false) |

### Response

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "MyProject",
  "path": "/Users/dev/Projects/MyProject",
  "is_git_repo": false,
  "git_state": "no_git",
  "sessions": []
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Workspace UUID |
| `name` | string | Display name |
| `path` | string | Absolute path |
| `is_git_repo` | boolean | Whether `.git` folder exists |
| `git_state` | string | Git configuration state (see below) |
| `sessions` | array | Active Claude sessions |

### Git State Values

| State | Description |
|-------|-------------|
| `no_git` | Folder has no `.git` directory |
| `git_initialized` | Has `.git` but no commits |
| `no_remote` | Has commits but no remote configured |
| `no_push` | Has remote but no upstream tracking (never pushed) |
| `synced` | Fully configured with upstream |
| `diverged` | Has unpushed/unpulled commits |
| `conflict` | Has merge conflicts |

### iOS Client Update Needed

Update `AddWorkspaceParams` in `WorkspaceManagerService.swift` to include `create_if_missing`:

```swift
private struct AddWorkspaceParams: Encodable {
    let path: String
    let name: String
    let createIfMissing: Bool?

    enum CodingKeys: String, CodingKey {
        case path, name
        case createIfMissing = "create_if_missing"
    }
}
```

Update `addWorkspace` method signature:

```swift
func addWorkspace(path: String, name: String? = nil, createIfMissing: Bool = false) async throws -> RemoteWorkspace
```

---

## 2. `workspace/git/state` API

Returns the overall git configuration state for a workspace. Lighter weight than `workspace/git/status` (no file lists).

**Status:** Needs Implementation

**Request:**
```json
{
  "method": "workspace/git/state",
  "params": {
    "workspace_id": "uuid"
  }
}
```

**Response:**
```json
{
  "state": "no_remote",
  "is_git_repo": true,
  "has_commits": true,
  "has_remote": false,
  "has_upstream": false,
  "has_conflicts": false,
  "branch": "main",
  "commit_count": 5,
  "remotes": []
}
```

**iOS Implementation Reference:**
- `WorkspaceManagerService.getGitState(workspaceId:)` - Line 880
- `WorkspaceGitStateResult` struct - JSONRPCMethods.swift:1887

---

## 3. `workspace/git/init` API

Initialize a git repository in a workspace folder.

**Status:** Needs Implementation

**Request:**
```json
{
  "method": "workspace/git/init",
  "params": {
    "workspace_id": "uuid",
    "initial_branch": "main",
    "initial_commit": true,
    "commit_message": "Initial commit"
  }
}
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `workspace_id` | string | Yes | - | Workspace UUID |
| `initial_branch` | string | No | "main" | Name of initial branch |
| `initial_commit` | boolean | No | false | Create initial commit with all files |
| `commit_message` | string | No | "Initial commit" | Message for initial commit |

**Response:**
```json
{
  "success": true,
  "branch": "main",
  "commit_sha": "abc123def456...",
  "files_committed": 15
}
```

**Error Response:**
```json
{
  "success": false,
  "error": "Git is already initialized in this workspace"
}
```

**iOS Implementation Reference:**
- `WorkspaceManagerService.gitInit(...)` - Line 813
- `WorkspaceGitInitParams` struct - JSONRPCMethods.swift:1715
- `WorkspaceGitInitResult` struct - JSONRPCMethods.swift:1737

---

## 4. Remote Management APIs

### 4.1 `workspace/git/remote/add`

**Status:** Needs Implementation

**Request:**
```json
{
  "method": "workspace/git/remote/add",
  "params": {
    "workspace_id": "uuid",
    "name": "origin",
    "url": "git@github.com:user/repo.git",
    "fetch": true
  }
}
```

**Response:**
```json
{
  "success": true,
  "remote": {
    "name": "origin",
    "fetch_url": "git@github.com:user/repo.git",
    "push_url": "git@github.com:user/repo.git",
    "provider": "github"
  },
  "fetched_branches": ["main", "develop"]
}
```

### 4.2 `workspace/git/remote/list`

**Status:** Needs Implementation

**Request:**
```json
{
  "method": "workspace/git/remote/list",
  "params": {
    "workspace_id": "uuid"
  }
}
```

**Response:**
```json
{
  "remotes": [
    {
      "name": "origin",
      "fetch_url": "git@github.com:user/repo.git",
      "push_url": "git@github.com:user/repo.git",
      "provider": "github",
      "tracking_branches": ["main"]
    }
  ]
}
```

### 4.3 `workspace/git/remote/remove`

**Status:** Needs Implementation

**Request:**
```json
{
  "method": "workspace/git/remote/remove",
  "params": {
    "workspace_id": "uuid",
    "name": "origin"
  }
}
```

**Response:**
```json
{
  "success": true
}
```

---

## 5. Enhanced `workspace/git/push` for First Push

When pushing for the first time (no upstream), the push should automatically set upstream.

**Status:** Needs Verification (may already work)

**Request:**
```json
{
  "method": "workspace/git/push",
  "params": {
    "workspace_id": "uuid",
    "set_upstream": true,
    "force": false
  }
}
```

**Response:**
```json
{
  "success": true,
  "pushed": true,
  "commits_pushed": 3,
  "upstream_set": true,
  "upstream": "origin/main",
  "message": "Branch 'main' set up to track 'origin/main'"
}
```

---

## 6. Implementation Status

| API | Status | Notes |
|-----|--------|-------|
| `workspace/add` with `create_if_missing` | ✅ **DONE** | Creates folders, returns git state |
| `workspace/add` returns `is_git_repo` | ✅ **DONE** | In response |
| `workspace/add` returns `git_state` | ✅ **DONE** | In response |
| `workspace/git/state` | ⏳ Pending | Lightweight git state check |
| `workspace/git/init` | ⏳ Pending | Initialize git in folders |
| `workspace/git/remote/add` | ⏳ Pending | Add GitHub/GitLab remotes |
| `workspace/git/remote/list` | ⏳ Pending | View configured remotes |
| `workspace/git/remote/remove` | ⏳ Pending | Remove remotes |
| `workspace/git/push` with `set_upstream` | ⏳ Verify | First-time push support |

---

## 7. User Flow Example

### New Project Setup Flow (with create_if_missing)

```
1. User wants to create new project "MyNewApp"
2. User opens cdev-ios, connects to agent
3. User taps "Create Workspace" → enters name and path
4. iOS calls: workspace/add {
     name: "MyNewApp",
     path: "/Users/dev/Projects/MyNewApp",
     create_if_missing: true
   }
5. Agent creates directory and returns: { is_git_repo: false, git_state: "no_git" }
6. iOS shows "Initialize Git" button
7. User taps → iOS calls: workspace/git/init { workspace_id, initial_commit: true }
8. Agent returns: { success: true, branch: "main", commit_sha: "abc..." }
9. iOS shows "Add Remote" prompt
10. User pastes GitHub URL → iOS calls: workspace/git/remote/add { url: "git@github.com:..." }
11. Agent returns: { success: true, remote: {...} }
12. iOS shows "Push to Remote" button
13. User taps → iOS calls: workspace/git/push { set_upstream: true }
14. Agent returns: { success: true, upstream_set: true }
15. Workspace is fully synced!
```

### Existing Non-Git Folder Flow

```
1. User has existing folder /Users/dev/Projects/OldProject (no git)
2. User opens cdev-ios, discovers folder via workspace/discover
3. User taps to add → iOS calls: workspace/add { path: "...", name: "OldProject" }
4. Agent returns: { is_git_repo: false, git_state: "no_git" }
5. iOS shows Git Setup wizard
6. (same steps 7-15 as above)
```

---

## 8. Error Handling

All APIs should return consistent error responses:

```json
{
  "success": false,
  "error": "Human readable error message",
  "error_code": "GIT_INIT_FAILED",
  "details": {
    "path": "/Users/dev/MyApp",
    "reason": "Permission denied"
  }
}
```

**Common Error Codes:**

| Code | Description |
|------|-------------|
| `NOT_A_DIRECTORY` | Path is not a valid directory |
| `PERMISSION_DENIED` | Cannot access/modify directory |
| `DIRECTORY_EXISTS` | Directory already exists (when create_if_missing=true) |
| `GIT_ALREADY_INITIALIZED` | Git already exists in workspace |
| `GIT_NOT_INITIALIZED` | Workspace is not a git repository |
| `REMOTE_ALREADY_EXISTS` | Remote with this name already exists |
| `REMOTE_NOT_FOUND` | Remote with this name doesn't exist |
| `INVALID_REMOTE_URL` | Cannot parse remote URL |
| `PUSH_REJECTED` | Push was rejected by remote |
| `NO_COMMITS` | Cannot push - no commits exist |

---

## 9. iOS Code References

Key files in cdev-ios implementing this:

| File | Purpose |
|------|---------|
| `WorkspaceManagerService.swift` | Main service with all git operations |
| `JSONRPCMethods.swift` | API method names and param/result types |
| `GitModels.swift` | `WorkspaceGitState` enum and related types |
| `GitSetupWizard.swift` | UI for step-by-step git setup |
| `GitSetupComponents.swift` | Reusable UI components |
| `docs/GIT-WORKSPACE-SETUP-DESIGN.md` | Full design document |

---

## 10. Next Steps

### iOS Updates Needed

1. Update `AddWorkspaceParams` to include `createIfMissing` parameter
2. Update `addWorkspace()` method signature
3. Handle `is_git_repo` and `git_state` in `RemoteWorkspace` model
4. Show Git Setup UI when `git_state == "no_git"`

### Agent Updates Needed

1. Implement `workspace/git/state` API
2. Implement `workspace/git/init` API
3. Implement `workspace/git/remote/add` API
4. Implement `workspace/git/remote/list` API
5. Verify `workspace/git/push` with `set_upstream` works correctly

---

## Summary

The `workspace/add` API has been enhanced to:
- Accept any folder path (not just git repositories) ✅
- Create directories with `create_if_missing: true` ✅
- Return `is_git_repo` and `git_state` in response ✅

This enables the iOS app to guide users through the full setup flow:

```
📁 Create Folder → 🌱 Git Init → 💬 Commit → 🔗 Remote → ☁️ Push → ✅ Synced
```

The iOS client needs minor updates to use `create_if_missing` and handle the git state fields.
