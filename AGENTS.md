# AGENTS.md

This file defines coding standards for contributors and coding agents working in `cdev-ios`.

## Scope

- Apply these rules for all changes in this repository.
- Prefer small, testable, and deterministic changes over broad rewrites.

## Swift Standards

- Keep ViewModels `@MainActor`.
- Use `async/await`; do not introduce callback-style async code.
- Keep logic in small helpers when a method becomes hard to scan.
- Avoid duplicate control flow; extract shared behavior into private methods.
- Do not use `print`; use `AppLogger`.
- Do not log secrets (tokens, credentials, raw prompts, file contents).

## Reconnect And Catch-Up Standard

When implementing reconnect/foreground recovery for session-driven screens:

1. Restore workspace context (`listWorkspaces`, re-subscribe workspace events).
2. Reload session messages with reconnect catch-up.
3. Sync runtime state via `session/state`.
4. Re-establish session watch with `force: true`.
5. Refresh status snapshots (`workspace/status`, git UI refresh).

### Message Catch-Up Rules

- Always fetch page 1 first (`offset = 0`, `order = "desc"`).
- For reconnection, fetch additional pages only when needed:
  - previous known total > 0
  - latest total > previous known total
  - session unchanged
- Stop catch-up when missed range is covered or `has_more == false`.
- Update pagination state from the final fetched page set.

### Runtime State Rules

- Map `session/state` (`claude_state`) first.
- Fallback mapping order:
  - `waiting_for_input == true` => `.waiting`
  - `is_running == true` => `.running`
  - else `.idle`
- Clear streaming-only UI (`isStreaming`, spinner, start time) when not running.
- Clear stale pending interaction UI when runtime is not waiting.

## Error Handling

- Treat `session_not_found` as a recoverable state and trigger session cleanup flow.
- Keep reconnect sync best-effort: log warnings and continue where safe.

## Validation

Before finishing a code change:

- Build the app:
  - `xcodebuild -project cdev.xcodeproj -scheme cdev -destination 'generic/platform=iOS Simulator' build`
- Confirm the changed flow compiles and does not introduce new warnings/errors.
