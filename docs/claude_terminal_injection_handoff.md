# Claude Terminal Injection Handoff

## User Request

- The user starts Claude Code terminal on laptop (host running cdev agent).
- From `cdev-ios`, sending a message should appear in that already-running Claude terminal.
- Expected behavior is aligned with newer Anthropic Claude Code bridge handling (inbound text injected into active terminal session).

## Problem Observed

- `cdev-ios` sends `session/send` with `permission_mode: "interactive"` and usually `mode: "continue"` with a specific `session_id`.
- Backend LIVE injection could still fail when that `session_id` was stale/non-matching, causing PTY fallback instead of terminal injection.

## Root Cause Summary

1. `GetLiveSession(sessionID)` required session-file existence for the requested `session_id` before returning any LIVE process.
2. Workspace resolution from `session_id` depended on session-file lookup only.
3. If either lookup failed, backend path could skip LIVE injection and spawn/manage PTY instead.

## Changes Made

All code changes were made in `/Users/brianly/Projects/cdev`:

### 1) LIVE-first send path for interactive mode

- File: `/Users/brianly/Projects/cdev/internal/session/manager.go`
- Method: `SendPrompt(...)`
- Behavior:
  - Try LIVE session detection/injection before PTY fallback for **all** permission modes, including `interactive`.
  - If LIVE found, inject prompt with Enter to the terminal app and return.
  - PTY spawn remains fallback when no LIVE process is found.

### 2) LIVE detector fallback for stale `session_id`

- File: `/Users/brianly/Projects/cdev/internal/adapters/live/detector.go`
- Method: `GetLiveSession(sessionID string)`
- Behavior:
  - If `session_id` file does not exist in `~/.claude/projects`, do **not** hard-fail.
  - Fall back to any detected LIVE Claude process in the workspace.
  - Use detected session id as effective session id when needed.

### 3) Workspace resolution fallback via LIVE process detection

- File: `/Users/brianly/Projects/cdev/internal/session/manager.go`
- Method: `findWorkspaceForSession(sessionID string)`
- Behavior:
  - Keep existing session-file workspace lookup.
  - Add fallback: detect LIVE Claude processes per workspace.
  - If exactly one workspace has LIVE sessions, resolve to that workspace.
  - If ambiguous (multiple) or none, return empty as before.

## Validation Performed

Run in `/Users/brianly/Projects/cdev`:

```bash
go test ./internal/adapters/live ./internal/session ./internal/rpc/handler/methods
```

Result: pass.

## Current Git State Notes (cdev repo)

At time of handoff:

- `M internal/adapters/live/detector.go` (new change)
- `MM internal/session/manager.go` (contains existing prior modifications + new change)
- `M internal/rpc/handler/methods/session_manager.go` (pre-existing)
- `M internal/rpc/handler/methods/session_manager_runtime.go` (pre-existing)

## Recommended Next Check

1. Restart/rebuild cdev agent host.
2. Send prompt from `cdev-ios` again.
3. Confirm backend logs include one of:
   - `sending prompt to LIVE session via keystroke injection`
   - `resolved workspace from LIVE session fallback`
4. If still failing, inspect whether multiple workspaces have simultaneous LIVE Claude processes (ambiguous fallback case).
