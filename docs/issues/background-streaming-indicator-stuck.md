# Background Resume: Thinking/Stop Indicator Stuck

## Summary
When the app is backgrounded (screen off or user switches apps) while Claude is streaming, iOS often suspends the WebSocket. If streaming finishes while the app is inactive, the client misses the final `stream_read_complete` / `pty_spinner` / `claude_message` events. On return to foreground, the UI still shows **Thinking…** and the red stop button even though Claude is already idle.

## Symptoms
- After resuming the app, **Thinking…** stays visible.
- The red stop indicator remains in the Action Bar.
- No new events arrive to clear UI state.

## Root Cause
iOS does not guarantee background WebSocket delivery. The app can’t reliably receive heartbeat or stream completion events while backgrounded. The UI state is left “running” because it never receives the “done” event.

## Fix (Foreground Reconciliation + Watchdog)
Implemented a two-part solution:

1. **Foreground Reconciliation**
   - On scene `.active`, call `status/get` and reconcile `claudeState`.
   - If status is not `.running`, clear `isStreaming`, `spinnerMessage`, and pending UI state.
   - Reload session history and re-watch session to backfill missed messages.

2. **Stream Watchdog (Foreground Only)**
   - Track the last stream event timestamp (`claude_message`, `pty_spinner`, `pty_state`, `stream_read_complete`).
   - If no stream events for ~20s while running, call `status/get` and reconcile state.

## Files Updated
- `cdev/Presentation/Screens/Dashboard/DashboardViewModel.swift`
  - Added lifecycle hooks, reconciliation, and stream watchdog.
- `cdev/Presentation/Navigation/RootView.swift`
  - Triggers foreground/background hooks.

## Notes
Background heartbeats are not reliable on iOS without special background modes. We intentionally avoid those to keep app store compliance and battery usage reasonable.
