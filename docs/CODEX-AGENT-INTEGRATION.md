# Codex Agent Integration (cdev-ios)

This document captures runtime integration requirements for Codex in cdev-ios
and defines the pattern for adding future agent runtimes (Gemini, etc.).

## Current status

- Runtime selector supports `claude` and `codex`.
- Event routing is runtime-safe via `agent_type` matching.
- Session control RPCs are runtime-scoped and send `agent_type`:
  - `session/start`
  - `session/send`
  - `session/stop`
  - `session/input`
  - `session/respond`
- Session history/data APIs are workspace-scoped and runtime-routed via `agent_type`:
  - Claude: `workspace/session/history`, `workspace/session/messages`
  - Codex: `workspace/session/history`, `workspace/session/messages`
- Live watch routing is workspace-scoped and runtime-routed via `agent_type`:
  - Claude: `workspace/session/watch`, `workspace/session/unwatch`
  - Codex: `workspace/session/watch`, `workspace/session/unwatch`

## Runtime strategy model

`AgentRuntime` is the single source of truth for transport behavior:

- `sessionListSource`: `workspaceHistory` vs `runtimeScoped`
- `sessionMessagesSource`: `workspaceScoped` vs `runtimeScoped`
- `sessionWatchSource`: `workspaceScoped` vs `runtimeScoped`
- `requiresWorkspaceActivationOnResume`
- `requiresSessionResolutionOnNewSession`

`DashboardViewModel` now uses centralized runtime helpers to avoid scattered
`if runtime == .codex` branches:

- session page loading
- message page loading
- session validation
- latest-session lookup
- delete one/delete all

## Integration contract (future runtimes)

To add a new runtime (for example `gemini`), follow this checklist:

1. Add a new case to `AgentRuntime`.
2. Configure runtime strategy metadata in `AgentRuntime`:
   - session list/messages/watch source
   - resume/new-session behavior flags
3. Add UI metadata (display name, icon, capabilities).
4. Pass `agent_type=<runtime>` on all runtime-scoped RPC methods.
5. Verify `WorkspaceManagerService.startSession` passes `agent_type`.
6. Ensure dashboard permission/input/stop/send flows pass selected runtime.

## RPC rules

- Always include `agent_type` for runtime-routed methods.
- Do not assume Claude as implicit fallback in client logic.
- For Claude and Codex in cdev-ios, prefer workspace-scoped session methods:
  - `workspace/session/history`
  - `workspace/session/messages`
  - `workspace/session/watch`
  - `workspace/session/unwatch`
  - `workspace/session/delete`
- Keep runtime-scoped methods (`session/list`, `session/messages`, `session/watch`) available for future runtimes that opt into `runtimeScoped` strategies.

## Codex resume parity

- Codex interactive resume aligns with CLI `codex resume <SESSION_ID> [query]`.
- Codex non-interactive resume aligns with `codex exec resume <SESSION_ID>`.
- cdev-ios should treat Codex history sessions as resumable (`supportsResume = true`)
  and route follow-up prompts through runtime-scoped `session/send`.

## Testing checklist

- Switch runtime between Claude and Codex without losing app state.
- Connect workspace and verify `session/start` includes selected runtime.
- Resume session from picker for both runtimes.
- Send prompts in `new` and `continue` modes for both runtimes.
- Verify `session/input` and `session/respond` include runtime routing.
- Verify incoming events are filtered by `agent_type` in dashboard.
