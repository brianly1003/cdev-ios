# Debugging Framework & Issue Resolution Guide

## Overview

This document provides a systematic approach to debugging issues in the cdev iOS app, based on lessons learned from resolving complex issues like the sheet presentation race condition.

## Issue Classification

### Category 1: UI Presentation Issues
**Symptoms:**
- Sheets/modals not appearing or auto-dismissing
- "Attempt to present while a presentation is in progress" errors
- Views not updating after data changes
- Loading states stuck forever

**Root Cause Patterns:**
- View recreation in paged TabView
- Nested ObservableObject observation failures
- Race conditions between state changes and presentation
- Multiple presentation attempts from different view instances

**Required Debug Info:**
```
1. Exact error message (if any)
2. View hierarchy path (e.g., DashboardView > TabView > ExplorerView > Sheet)
3. Trigger action (e.g., "tap file", "switch workspace", "swipe tab")
4. Timing (immediate, delayed, intermittent)
5. App logs showing view lifecycle events
```

---

### Category 2: State/Data Issues
**Symptoms:**
- Data not refreshing after actions
- Stale data displayed
- Wrong data shown (e.g., previous workspace data)
- Missing data in UI

**Root Cause Patterns:**
- Cache not invalidated on context switch
- ViewModel not reset when expected
- Async operations completing after context changed
- Publisher subscriptions not properly managed

**Required Debug Info:**
```
1. Current state values (workspaceId, sessionId, etc.)
2. Expected vs actual data
3. Sequence of actions before issue
4. Network/WebSocket logs showing requests/responses
5. Cache state (hit/miss logs)
```

---

### Category 3: Network/WebSocket Issues
**Symptoms:**
- Events not received
- Commands not sent
- Connection drops
- Timeout errors

**Root Cause Patterns:**
- WebSocket disconnection
- Missing subscription (workspace/subscribe, session/watch)
- Wrong workspace/session context
- Server-side errors

**Required Debug Info:**
```
1. WebSocket connection state
2. Subscription status (which workspaces/sessions are subscribed)
3. Event flow logs (sent vs received)
4. Error messages from server
5. Network conditions
```

---

### Category 4: Navigation/Flow Issues
**Symptoms:**
- Wrong screen displayed
- Back navigation broken
- Deep links not working
- State lost during navigation

**Root Cause Patterns:**
- Navigation stack corruption
- State not persisted across navigation
- View not properly initialized
- Missing context during navigation

**Required Debug Info:**
```
1. Current navigation stack
2. Expected vs actual destination
3. State before/after navigation
4. Trigger action for navigation
```

---

## Debug Information Template

When reporting or investigating issues, collect this information:

### Essential Info (Always Required)
```markdown
## Issue Report

**Summary:** [One-line description]

**Steps to Reproduce:**
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected Behavior:** [What should happen]

**Actual Behavior:** [What actually happens]

**Frequency:** [Always / Sometimes / Rare]

**Device/OS:** [iPhone 15, iOS 17.4]
```

### Debug Logs (Copy from Debug Logs screen)
```markdown
## Relevant Logs

[Paste timestamped logs here, focusing on:]
- 30 seconds before issue
- The moment of issue
- 10 seconds after issue

Filter by: [WS / HTTP / App / All]
```

### State Snapshot
```markdown
## App State at Time of Issue

- Connection State: [connected / disconnected / reconnecting]
- Current Workspace ID: [uuid or nil]
- Current Session ID: [uuid or nil]
- Active Tab: [terminal / logs / diffs / explorer]
- Claude State: [idle / running / waiting / error]
- Any sheets/modals open: [yes/no, which one]
```

---

## Diagnostic Checklist by Symptom

### "Sheet won't open" or "Sheet auto-dismisses"

- [ ] Is the sheet inside a paged TabView? → **Hoist to parent level**
- [ ] Are there multiple sheet modifiers on the view hierarchy? → **Keep only one**
- [ ] Is the trigger state (@State or @Published) stable? → **Check for rapid changes**
- [ ] Is another presentation (alert, sheet, fullScreenCover) in progress? → **Wait for dismissal**
- [ ] Is the view being recreated? → **Check logs for multiple onChange calls**

```swift
// Add this log to diagnose recreation:
.onChange(of: someState) { old, new in
    AppLogger.log("[ViewName] onChange: \(old) -> \(new)")
}
```

### "Data not updating in UI"

- [ ] Is the property @Published? → **Add @Published if missing**
- [ ] Is it a nested ObservableObject? → **Add direct @ObservedObject reference**
- [ ] Is the view observing the right object? → **Check @StateObject vs @ObservedObject**
- [ ] Is the update happening on MainActor? → **Ensure @MainActor on ViewModel**
- [ ] Is the async task completing? → **Add completion logs**

```swift
// Add this to diagnose observation:
.onReceive(viewModel.$someProperty) { value in
    AppLogger.log("[ViewName] Received: \(value)")
}
```

### "Events not received after workspace switch"

- [ ] Was workspace/subscribe called? → **Check WS logs**
- [ ] Was workspace/session/watch called? → **Check WS logs**
- [ ] Is the workspace ID correct? → **Log current workspace context**
- [ ] Was previous workspace unsubscribed? → **Check for workspace/unsubscribe**
- [ ] Is WebSocket connected? → **Check connection state**

### "Action not working" (button tap, swipe, etc.)

- [ ] Is the gesture being captured by parent? → **Check for .onTapGesture on containers**
- [ ] Is the button disabled? → **Check .disabled() modifier**
- [ ] Is there a blocking overlay? → **Check z-order of views**
- [ ] Is the action async and still running? → **Check for loading states**

---

## Structured Logging Guidelines

### Log Categories
```swift
// Use consistent prefixes for filtering:
[ViewName]           // View lifecycle, UI events
[ViewModelName]      // State changes, business logic
[ServiceName]        // Network, persistence
[WS]                 // WebSocket events
[HTTP]               // HTTP requests/responses
[App]                // App-level events
```

### Log Levels
```swift
AppLogger.log("Normal operation info")           // Info
AppLogger.log("...", type: .warning)             // Warning
AppLogger.log("...", type: .error)               // Error
AppLogger.error(error, context: "...")           // Error with context
```

### Key Events to Log

**View Lifecycle:**
```swift
.onAppear { AppLogger.log("[ViewName] onAppear") }
.onDisappear { AppLogger.log("[ViewName] onDisappear") }
.task { AppLogger.log("[ViewName] task started") }
```

**State Changes:**
```swift
.onChange(of: state) { old, new in
    AppLogger.log("[ViewName] state: '\(old)' -> '\(new)'")
}
```

**Async Operations:**
```swift
AppLogger.log("[Service] Starting operation...")
// ... async work ...
AppLogger.log("[Service] Operation completed: \(result)")
// or
AppLogger.error(error, context: "Operation failed")
```

**Sheet/Modal Presentation:**
```swift
.sheet(item: $item, onDismiss: {
    AppLogger.log("[ViewName] Sheet dismissed")
}) { item in
    AppLogger.log("[ViewName] Presenting sheet for: \(item.id)")
    // ...
}
```

---

## Quick Diagnosis Flowchart

```
Issue Reported
     │
     ▼
┌─────────────────────────────────────┐
│ Can you reproduce it?               │
└─────────────────────────────────────┘
     │                    │
    Yes                   No
     │                    │
     ▼                    ▼
┌──────────────┐    ┌──────────────────────┐
│ Collect logs │    │ Ask for:             │
│ while        │    │ - Exact steps        │
│ reproducing  │    │ - Screenshots/video  │
│              │    │ - Device/OS version  │
└──────────────┘    │ - Frequency          │
     │              └──────────────────────┘
     ▼
┌─────────────────────────────────────┐
│ Check logs for:                     │
│ 1. Error messages                   │
│ 2. Unexpected state changes         │
│ 3. Missing expected events          │
│ 4. Duplicate events (race condition)│
│ 5. Wrong order of events            │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│ Identify component:                 │
│ - View layer? (UI not updating)     │
│ - ViewModel? (state incorrect)      │
│ - Service? (data not fetched)       │
│ - Network? (request failed)         │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│ Check Known Issues docs:            │
│ - docs/issues/*.md                  │
│ - Similar patterns?                 │
│ - Apply known fix?                  │
└─────────────────────────────────────┘
```

---

## Known Issue Patterns Reference

### Pattern: Paged TabView + Sheet = Race Condition
**File:** `docs/issues/file-viewer-presentation-issue.md`

**Symptoms:**
- "Attempt to present while a presentation is in progress"
- Sheet opens then immediately closes
- Sheet only opens after switching tabs

**Solution:** Hoist sheet to parent view outside TabView, use callback pattern.

---

### Pattern: Nested ObservableObject Not Updating
**File:** `docs/issues/file-viewer-presentation-issue.md`

**Symptoms:**
- Child ViewModel property changes not reflected in parent View
- Data loads but UI shows stale/loading state

**Solution:** Add direct `@ObservedObject` reference to nested ViewModel in parent View.

---

### Pattern: Gesture Blocked by Parent Container
**File:** `docs/MULTI-DEVICE-BEST-PRACTICES.md`

**Symptoms:**
- Buttons don't respond to taps
- Works on one device but not another

**Solution:** Use `.simultaneousGesture()` instead of `.onTapGesture` on containers.

---

## Adding New Known Issues

When you resolve a complex issue, document it:

```markdown
# [Issue Title]

## Status: RESOLVED

## Summary
[Brief description of the issue]

## Root Cause Analysis
[What caused the issue at a technical level]

## Solution
[How it was fixed, with code examples]

## Key Learnings
### 1. [Learning Title]
**Not Good:**
[Code example of what NOT to do]

**Best Practice:**
[Code example of the correct approach]

## Related Files
- [List of affected files]
```

Save to: `docs/issues/[descriptive-name].md`

---

## Debug Tools Available

### 1. Debug Logs Screen
- Access: Floating toolkit → Debug icon
- Features: Filter by category, search, copy logs, export

### 2. In-App State Display
- Status bar shows: Connection state, Claude state, workspace info

### 3. Log Detail View
- Tap any log entry for full details
- Copy button for easy sharing
- Payload inspection for WS/HTTP

### 4. Xcode Console
- Full AppLogger output with timestamps
- Filter by `[App]`, `[WS]`, `[HTTP]`, etc.

---

## Escalation Path

1. **Self-Debug** (5-10 min)
   - Check logs for obvious errors
   - Check known issues docs
   - Try to reproduce

2. **Collect Context** (5 min)
   - Fill out issue report template
   - Export relevant logs
   - Note exact reproduction steps

3. **Pattern Match** (5 min)
   - Search codebase for similar issues
   - Check if related to recent changes
   - Review git blame for affected files

4. **Deep Dive** (as needed)
   - Add targeted logging
   - Use debugger breakpoints
   - Create minimal reproduction case

5. **Document** (after resolution)
   - Update known issues if pattern is new
   - Add preventive logging if needed
   - Consider architectural fix if recurring
