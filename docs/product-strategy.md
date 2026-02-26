# cdev-ios Product Strategy

## Strategy Goal

Build a reliable mobile control plane for AI coding sessions, optimized for:

- Session visibility in real time
- Fast permission handling
- Multi-workspace operational control
- High-confidence handoff between desktop and mobile

## Current Product Position

`cdev-ios` is currently a companion runtime client to `cdev-agent`, not a
standalone local coding runtime. This means product priorities should align
with remote-session orchestration, not on-device code execution.

## Priority Themes

1. Runtime Reliability
- Keep event routing isolated by runtime and session.
- Prevent cross-window/session contamination.
- Improve reconnect and recovery observability.

2. Permission UX and Safety
- Preserve one-tap response paths for pending interactions.
- Maintain deterministic Yolo auto-approve behavior for eligible LIVE prompts.
- Keep resolution state synchronized across devices.

3. Workspace Productivity
- Faster workspace switching and status clarity.
- Better file and git context visibility for active sessions.
- Stronger debug/tracing workflows for field issues.

4. Mobile-First Operator Experience
- Reduce interaction latency for common operations.
- Improve notification-to-action flows.
- Keep critical context visible when moving between tabs and sessions.

## Non-Goals (Current Horizon)

- Running Claude/Codex directly on-device without agent infrastructure.
- Replacing desktop IDE workflows for full local development.

## Success Metrics

- Permission resolution latency (event received -> action resolved).
- Session-switch correctness (no wrong-session rendering events).
- Reconnect recovery success rate.
- Daily active users who complete core loop: monitor -> approve/respond -> continue.

## Related Docs

- `agent-event-routing-and-permissions.md`
- `yolo-pty-auto-approve-tracing.md`
- `architecture.md`
