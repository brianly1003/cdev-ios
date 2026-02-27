# API Migration Guide

> **Current Version:** 2.0 (Session-based Multi-Workspace)
> **Last Updated:** December 2024

This guide documents the API architecture and helps with future migrations.

---

## API Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        cdev-ios App                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Presentation Layer                         │   │
│  │  DashboardViewModel → Uses UseCases                          │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                      Domain Layer                             │   │
│  │  UseCases (SendPromptUseCase, RespondToClaudeUseCase)        │   │
│  │     → Uses AgentRepositoryProtocol                           │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                       Data Layer                              │   │
│  │                                                               │   │
│  │  ┌─────────────────────┐  ┌─────────────────────────────┐    │   │
│  │  │  AgentRepository    │  │  WorkspaceManagerService   │    │   │
│  │  │  (session/* APIs)   │──▶│  (workspace/* & session/*) │    │   │
│  │  └─────────────────────┘  └─────────────────────────────┘    │   │
│  │            │                           │                      │   │
│  │            └───────────┬───────────────┘                      │   │
│  │                        ▼                                       │   │
│  │  ┌──────────────────────────────────────────────────────┐    │   │
│  │  │                JSONRPCClient                          │    │   │
│  │  │  (WebSocket-based JSON-RPC 2.0)                       │    │   │
│  │  └──────────────────────────────────────────────────────┘    │   │
│  │                        │                                       │   │
│  └────────────────────────┼──────────────────────────────────────┘   │
│                           ▼                                          │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            │ WebSocket (port 16180)
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      cdev Server                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Current API Methods

### Session Control (Multi-Workspace)

| Method | Purpose | Parameters |
|--------|---------|------------|
| `session/start` | Start Claude for a workspace | `workspace_id` |
| `session/send` | Send prompt to Claude | `session_id`, `prompt`, `mode` |
| `session/stop` | Stop Claude session | `session_id` |
| `session/respond` | Respond to permission/question | `session_id`, `type`, `response` |
| `session/state` | Get runtime state (reconnection) | `session_id` |
| `session/active` | List active sessions | `workspace_id?` |

### Workspace Operations

| Method | Purpose | Parameters |
|--------|---------|------------|
| `workspace/list` | List all workspaces | - |
| `workspace/get` | Get workspace details | `workspace_id` |
| `workspace/add` | Register new workspace | `path`, `name?` |
| `workspace/remove` | Unregister workspace | `workspace_id` |
| `workspace/subscribe` | Filter events by workspace | `workspace_id` |
| `workspace/unsubscribe` | Stop filtering | `workspace_id` |

### Legacy APIs (Deprecated)

| Method | Replacement | Notes |
|--------|-------------|-------|
| `agent/run` | `session/start` + `session/send` | Uses config.yaml path (single-workspace) |
| `agent/stop` | `session/stop` | |
| `agent/respond` | `session/respond` | |
| `agent/status` | `session/state` | |

---

## Key Files for API Changes

### 1. JSONRPCMethods.swift
**Location:** `cdev/Data/Services/JSONRPC/JSONRPCMethods.swift`

This file defines:
- Method name constants (e.g., `sessionStart = "session/start"`)
- Request parameter types (e.g., `SessionStartParams`)
- Response result types (e.g., `SessionStartResult`)

**When adding new methods:**
1. Add method constant to `JSONRPCMethod` enum
2. Add parameter struct (if needed)
3. Add result struct (if needed)

### 2. AgentRepository.swift
**Location:** `cdev/Data/Repositories/AgentRepository.swift`

This is the main interface for Claude control. It:
- Implements `AgentRepositoryProtocol`
- Uses `WorkspaceManagerService` for session/* APIs
- Falls back to legacy agent/* APIs when no session context

**Key flag:** `useSessionAPIs: Bool = true`
- Set to `false` to revert to legacy APIs (for debugging)

### 3. WorkspaceManagerService.swift
**Location:** `cdev/Data/Services/WorkspaceManager/WorkspaceManagerService.swift`

Handles:
- Workspace listing/management
- Session start/stop/send/respond
- Event subscriptions

### 4. RemoteWorkspace.swift
**Location:** `cdev/Domain/Models/RemoteWorkspace.swift`

Defines:
- `RemoteWorkspace` - workspace from server
- `Session` - active Claude instance
- Response types for workspace/session APIs

---

## Migration Checklist

When the server API changes:

### 1. Update Types
- [ ] Add/modify types in `JSONRPCMethods.swift`
- [ ] Update response types in `RemoteWorkspace.swift` if needed

### 2. Update Services
- [ ] Update method calls in `WorkspaceManagerService.swift`
- [ ] Update `AgentRepository.swift` if Claude control changes

### 3. Update UI (if needed)
- [ ] Update `DashboardViewModel.swift` for new flows
- [ ] Update workspace management views

### 4. Test
- [ ] Build project (`xcodebuild -scheme cdev`)
- [ ] Test on simulator
- [ ] Test on device

---

## Session Flow (Current Implementation)

```swift
// 1. User connects to remote workspace
AppState.connectToRemoteWorkspace(workspace, host)
    ↓
WorkspaceManagerService.shared.subscribe(workspaceId)
    ↓
WorkspaceManagerService.shared.startSession(workspaceId)
    ↓
// Session created, events start flowing

// 2. User sends prompt
DashboardViewModel.submitPrompt(text)
    ↓
SendPromptUseCase.execute(prompt, mode, sessionId)
    ↓
AgentRepository.runClaude(prompt, mode, sessionId)
    ↓
WorkspaceManagerService.shared.sendPrompt(sessionId, prompt, mode)
    ↓
// JSON-RPC: session/send

// 3. User responds to permission
DashboardViewModel.approve()
    ↓
RespondToClaudeUseCase.handlePermission(requestId, approved)
    ↓
AgentRepository.respondToClaude(response, requestId, approved)
    ↓
WorkspaceManagerService.shared.respond(sessionId, "permission", "yes")
    ↓
// JSON-RPC: session/respond
```

---

## Adding a New API Method

Example: Adding `session/pause` method

### Step 1: Add method constant
```swift
// JSONRPCMethods.swift
enum JSONRPCMethod {
    // ...existing methods...
    static let sessionPause = "session/pause"
}
```

### Step 2: Add parameter type (if needed)
```swift
// JSONRPCMethods.swift
struct SessionPauseParams: Codable, Sendable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}
```

### Step 3: Add result type
```swift
// JSONRPCMethods.swift
struct SessionPauseResult: Codable, Sendable {
    let status: String
}
```

### Step 4: Add method to service
```swift
// WorkspaceManagerService.swift
func pauseSession(sessionId: String) async throws {
    guard let ws = webSocketService else {
        throw WorkspaceManagerError.notConnected
    }

    let client = ws.getJSONRPCClient()
    let _: SessionPauseResult = try await client.request(
        method: JSONRPCMethod.sessionPause,
        params: SessionPauseParams(sessionId: sessionId)
    )

    AppLogger.log("[WorkspaceManager] Paused session: \(sessionId)")
}
```

### Step 5: Expose through repository (if needed)
```swift
// AgentRepository.swift (or create new method)
func pauseClaude() async throws {
    let sessionId = await MainActor.run { self.currentSessionId }
    guard let sid = sessionId else {
        throw WorkspaceManagerError.notConnected
    }
    try await WorkspaceManagerService.shared.pauseSession(sessionId: sid)
}
```

---

## Troubleshooting

### "Method not found" error
- Check server logs for available methods
- Verify method name matches exactly (case-sensitive)
- Check if server has the feature enabled

### Session ID nil
- Ensure workspace has active session (`workspace.hasActiveSession`)
- Check `WorkspaceStore.shared.activeWorkspace?.sessionId`
- Verify `WorkspaceManagerService.shared.workspaces` is populated

### Events not received
- Check `workspace/subscribe` was called
- Verify WebSocket is connected
- Check server event filtering settings

---

## Version History

| Version | Changes |
|---------|---------|
| 2.0 | Single-port (16180), session-based multi-workspace |
| 1.x | Multi-port, agent/* APIs, single workspace |
