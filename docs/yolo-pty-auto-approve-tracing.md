# YOLO PTY Auto-Approve Tracing

## Context

When Yolo mode is enabled, LIVE permission prompts (`pty_permission`) should be auto-approved even if the user is currently on `Changes` or `Explorer` tab.

The permission panel is only visible on Terminal (`selectedTab == .logs`), but auto-approve must still run from event handling.

## Relevant Code Paths

- `cdev/Presentation/Screens/Dashboard/DashboardViewModel.swift`
  - `handleEvent(_:)` -> `.ptyPermission` branch
  - `maybeAutoApproveLivePermission(_:)`
  - `respondToPTYPermission(interaction:key:)`
  - `respondToHookBridgePermission(interaction:key:)`
  - `respondToPTYModePermission(interaction:key:)`
  - `clearPendingInteractionIfMatching(_:)`
- `cdev/Presentation/Screens/Dashboard/DashboardView.swift`
  - PTY panel visibility gate: only shown when `selectedTab == .logs`

## Tracing Checkpoints

Use these logs in order:

1. Permission received
   - `[Dashboard] PTY permission received with ...`
2. Auto-approve trigger
   - `[Dashboard] Yolo auto-approving LIVE permission with key '...'`
3. Response dispatch
   - Hook bridge path:
     - `[Dashboard] Hook bridge permission: toolUseId=..., key=..., decision=..., scope=...`
   - PTY path:
     - `[Dashboard] PTY navigation: current=..., target=..., direction=..., presses=...`
4. Response completion
   - Hook bridge:
     - `[Dashboard] Hook bridge permission responded successfully`
   - PTY:
     - `[Dashboard] PTY permission responded: navigated to option '...' and pressed enter`

## Correlation Fields

Track these together during diagnosis:

- `interaction.id`
- `sessionId` (event and interaction)
- `toolUseId` (if present)
- `selectedSessionRuntime`
- `selectedTab`

## Failure Signatures

- Permission arrives but no auto-approve log:
  - Eligibility gate failed (`isYoloModeEnabled`, runtime, option parsing, LIVE classification).
- Auto-approve log exists but no response completion log:
  - Response race, session mismatch, or transport/RPC failure.
- Returning to Terminal shows stale permission panel:
  - Auto-approve did not complete, or pending interaction was not cleared.

## Manual Verification Scenario

1. Enable Yolo mode.
2. Switch to `Changes` or `Explorer`.
3. Trigger a LIVE permission prompt (`pty_permission`).
4. Confirm logs show auto-approve and response completion.
5. Switch back to `Terminal`.
6. Confirm permission panel is not shown for that resolved interaction.

## Notes

- The panel visibility is a UI concern (`selectedTab == .logs`).
- Auto-approve is event-driven and should not depend on current tab visibility.
