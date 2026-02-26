# Agent Event Routing and Permission Flow

This document captures the current event-routing and permission-handling logic
implemented in the iOS dashboard layer.

## Scope

- Runtime-safe event routing for Claude/Codex.
- Session-safe window routing (buffering/quarantine behavior).
- PTY permission processing, including Yolo auto-approve.
- UI visibility rules for permission surfaces.

## Primary Source Files

- `cdev/Presentation/Screens/Dashboard/DashboardViewModel.swift`
- `cdev/Presentation/Screens/Dashboard/DashboardView.swift`
- `cdev/Domain/Models/AgentStatus.swift`
- `cdev/Domain/Models/AgentEvent.swift`

## Runtime Routing

The dashboard routes live events by runtime before applying business logic:

- Uses `event.matchesRuntime(selectedSessionRuntime)`.
- Allows selective bypass for runtime-agnostic lifecycle events in
  `shouldBypassRuntimeRouting(for:)`.
- Legacy untyped-event fallback is intentionally disabled in
  `shouldAcceptLegacyUntypedEvent(_:)`.

Design intent:
- Prevent cross-runtime contamination (Claude vs Codex).
- Keep recovery events (`session_id_failed`, `session_id_resolved`,
  `pty_permission_resolved`) unblocked.

## Session and Window Routing

Session-scoped events are routed with active-window awareness:

- `shouldRouteEventBySession(_:)` marks session-bound event types.
- `shouldBufferEventForInactiveWindow(_:)` buffers events that target another
  open window session.
- Unknown/mismatched sessions are quarantined (not rendered into foreground).

Design intent:
- Prevent cross-tab/session bleed.
- Preserve events for inactive windows and replay on activation.

## PTY Permission Lifecycle

PTY permission events (`pty_permission`) are validated and converted into
`PendingInteraction` models.

- `PendingInteraction.isPTYMode` identifies PTY permission interactions.
- `PendingInteraction.isHookBridgeMode` detects hook-bridge mode via `toolUseId`.
- Options are validated before UI state is updated.

Response paths:

1. Hook bridge mode
   - Uses RPC `permission/respond` (`respondToHookBridgePermission`).
2. PTY interactive mode
   - Uses `session/input` navigation + `enter`
     (`respondToPTYModePermission`).

## Yolo LIVE Auto-Approve

Auto-approve is evaluated immediately when a PTY permission is accepted:

- `maybeAutoApproveLivePermission(_:)` requires:
  - `isYoloModeEnabled == true`
  - `selectedSessionRuntime == .claude`
  - interaction classified as LIVE (`isLivePermissionInteraction`)
  - de-dup guard on interaction id
- Auto-approve dispatch now uses captured interaction state:
  - `respondToPTYPermission(interaction:key:)`

Interaction clearing is id-safe:

- `clearPendingInteractionIfMatching(_:)` only clears if pending interaction id
  matches the completed request.

Design intent:
- Avoid races when tab/window state changes between receipt and response.

## UI Behavior Rules

- Permission panel visibility is terminal-tab scoped:
  - `DashboardView`: panel is shown only when `selectedTab == .logs`.
- Session-tab selection forces terminal tab visibility:
  - If user is in `Changes` or `Explorer` and selects another terminal window,
    `selectedTab` is switched to `.logs` before activation.

Design intent:
- Keep permission interaction UI in the terminal context.
- Ensure session switching returns to the interaction surface.

## Trace and Diagnostics

Use this runbook for deep troubleshooting:

- `yolo-pty-auto-approve-tracing.md`

Key fields to correlate:

- `interaction.id`
- `sessionId`
- `toolUseId`
- `selectedSessionRuntime`
- `selectedTab`
