# Disconnect Hang / Deadlock Issue

**Date:** 2024-12-27
**Severity:** Critical (UI completely frozen)
**Status:** Resolved

## Summary

Clicking "Disconnect" button (in Settings or WorkspaceManager) caused the app to hang completely. The UI became unresponsive and the disconnect operation never completed.

## Root Causes (Multiple Issues)

### 1. AsyncStream Continuation Deadlock

**Location:** `WebSocketService.finishAllContinuations()`

The original code held a lock while calling `continuation.finish()`:

```swift
// BAD - Holding lock while calling finish() can deadlock
continuationsLock.withLock {
    for continuation in stateStreamContinuations.values {
        continuation.finish()  // Can trigger code that needs this lock!
    }
    stateStreamContinuations.removeAll()
}
```

`continuation.finish()` can trigger subscriber code that might try to acquire the same lock, causing a deadlock.

**Fix:** Copy continuations out of lock before finishing:

```swift
// GOOD - Release lock before calling finish()
let continuations = continuationsLock.withLock {
    let copy = Array(stateStreamContinuations.values)
    stateStreamContinuations.removeAll()
    return copy
}
for continuation in continuations {
    continuation.finish()  // Safe - no lock held
}
```

### 2. Missing Explicit Disconnect Flag

**Location:** `DashboardViewModel.disconnect()` and `RootView`

RootView checks `wasExplicitDisconnect` to decide whether to navigate away or attempt reconnection. Without setting this flag, RootView thought the disconnect was accidental and tried to reconnect, causing a loop.

```swift
// BAD - Missing flag, RootView doesn't know disconnect is intentional
func disconnect() async {
    await stopWatchingSession()
    webSocketService.disconnect()
    // ... RootView will try to reconnect!
}
```

**Fix:** Set the flag before disconnecting:

```swift
// GOOD - Mark explicit disconnect so RootView navigates away
func disconnect() async {
    appState?.markExplicitDisconnect()  // Tell RootView this is intentional
    await stopWatchingSession()
    webSocketService.disconnect()
    // ... RootView will navigate to WorkspaceManager
}
```

### 3. Auto-Reconnection After Disconnect

**Location:** `DashboardViewModel.disconnect()` and `WorkspaceManagerView`

After disconnect, WorkspaceManagerView appeared but immediately auto-connected because `ManagerStore` still had saved credentials.

```swift
// BAD - Only clearing workspace, not manager credentials
func disconnect() async {
    webSocketService.disconnect()
    WorkspaceStore.shared.clearActive()
    // ManagerStore still has saved host - WorkspaceManagerView will auto-connect!
}
```

**Fix:** Clear all connection state:

```swift
// GOOD - Clear everything to prevent auto-reconnection
func disconnect() async {
    webSocketService.disconnect()
    WorkspaceStore.shared.clearActive()
    ManagerStore.shared.clear()           // Clear saved host
    WorkspaceManagerService.shared.reset() // Reset service state
}
```

## Best Practices

### Lock Management

```swift
// BAD - Calling external code while holding lock
lock.withLock {
    for item in items {
        item.callback()  // Callback might need same lock = DEADLOCK
    }
}

// GOOD - Copy data out, release lock, then call external code
let itemsCopy = lock.withLock { Array(items) }
for item in itemsCopy {
    item.callback()  // Safe - no lock held
}
```

### AsyncStream Continuations

```swift
// BAD - finish() inside lock
continuationsLock.withLock {
    continuation.finish()  // Triggers subscriber code
}

// GOOD - finish() outside lock
let cont = continuationsLock.withLock {
    let c = continuation
    continuation = nil
    return c
}
cont?.finish()
```

### State Flags for Navigation

```swift
// BAD - Navigation logic guessing intent
case .disconnected:
    // Is this intentional disconnect or network failure?
    // Guessing wrong causes reconnection loops

// GOOD - Explicit flags for navigation decisions
appState.markExplicitDisconnect()  // Before disconnect
// ...
case .disconnected:
    if appState.wasExplicitDisconnect {
        navigateAway()  // User intended this
    } else {
        attemptReconnection()  // Might be network issue
    }
```

### Complete State Cleanup

```swift
// BAD - Partial cleanup causes auto-reconnection
func disconnect() {
    webSocketService.disconnect()
    WorkspaceStore.shared.clearActive()
    // Forgot ManagerStore - view will auto-connect!
}

// GOOD - Clean ALL related state
func disconnect() {
    webSocketService.disconnect()
    WorkspaceStore.shared.clearActive()
    ManagerStore.shared.clear()
    WorkspaceManagerService.shared.reset()
    appState?.clearHTTPState()
}
```

## Debugging Approach Used

### 1. Add Granular Logging

Added step-by-step logging to narrow down exact hang location:

```swift
AppLogger.log("[Dashboard] Calling webSocketService.disconnect()")
webSocketService.disconnect()
AppLogger.log("[Dashboard] webSocketService.disconnect() completed")  // Never appeared!

AppLogger.webSocket("Disconnecting - finishing continuations")
finishAllContinuations()
AppLogger.webSocket("Disconnecting - continuations finished")  // Never appeared!
```

### 2. Binary Search for Hang Location

The last log that appeared indicated where the hang occurred:
- `"Disconnecting - finishing continuations"` appeared
- `"Disconnecting - continuations finished"` never appeared
- **Conclusion:** Hang is inside `finishAllContinuations()`

### 3. Analyze Lock Usage

Once we knew it was in `finishAllContinuations()`, we examined the lock pattern and identified the deadlock potential.

## Prevention Checklist

For any disconnect/cleanup operation:

- [ ] Set explicit flags BEFORE disconnecting (`markExplicitDisconnect`)
- [ ] Clear ALL related stores (WorkspaceStore, ManagerStore, etc.)
- [ ] Never call external code while holding locks
- [ ] Copy data out of locks before operating on it
- [ ] Add step-by-step logging for complex operations
- [ ] Test disconnect from multiple entry points (Settings, WorkspaceManager, etc.)

## Files Modified

- `DashboardViewModel.swift` - Added markExplicitDisconnect, manager store cleanup
- `WebSocketService.swift` - Fixed finishAllContinuations deadlock
- `SettingsView.swift` - Removed dismiss() after disconnect (let navigation handle it)
- `WorkspaceManagerView.swift` - Added onDisconnect callback
- `WorkspaceManagerViewModel.swift` - Split resetManager into resetManager + resetManagerState

## Related Issues

- Navigation state management across views
- WebSocket lifecycle management
- Multi-step async operations with proper cleanup
