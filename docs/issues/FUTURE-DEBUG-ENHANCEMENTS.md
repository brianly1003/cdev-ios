# Future Debug Enhancements

## Priority 1: Enhanced Logging (High Impact, Low Effort)

### 1.1 View Lifecycle Logging
Add automatic logging for SwiftUI view lifecycle in debug builds:

```swift
// ViewLifecycleModifier.swift
struct ViewLifecycleLogger: ViewModifier {
    let viewName: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                #if DEBUG
                AppLogger.log("[\(viewName)] onAppear")
                #endif
            }
            .onDisappear {
                #if DEBUG
                AppLogger.log("[\(viewName)] onDisappear")
                #endif
            }
    }
}

extension View {
    func logLifecycle(_ name: String) -> some View {
        modifier(ViewLifecycleLogger(viewName: name))
    }
}

// Usage:
ExplorerView(...)
    .logLifecycle("ExplorerView")
```

### 1.2 State Change Logging
Auto-log @Published property changes:

```swift
// In ViewModels:
@Published var selectedFile: FileEntry? {
    didSet {
        #if DEBUG
        AppLogger.log("[ExplorerVM] selectedFile: '\(oldValue?.path ?? "nil")' → '\(selectedFile?.path ?? "nil")'")
        #endif
    }
}
```

### 1.3 Sheet Presentation Logging
Create a logged sheet modifier:

```swift
extension View {
    func loggedSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        name: String,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        self.sheet(item: item, onDismiss: {
            AppLogger.log("[\(name)] Sheet dismissed")
        }) { item in
            content(item)
                .onAppear {
                    AppLogger.log("[\(name)] Sheet presented: \(item.id)")
                }
        }
    }
}
```

---

## Priority 2: Debug State Inspector (Medium Impact, Medium Effort)

### 2.1 State Snapshot Feature
Add ability to capture and export current app state:

```swift
struct AppStateSnapshot: Codable {
    let timestamp: Date
    let connectionState: String
    let workspaceId: String?
    let sessionId: String?
    let claudeState: String
    let activeTab: String
    let presentedSheets: [String]
    let viewModelStates: [String: String]
}

// Export as JSON for bug reports
```

### 2.2 Debug Overlay
Add shake-to-show debug overlay:

```
┌─────────────────────────────────┐
│ 🔧 Debug Info                   │
├─────────────────────────────────┤
│ Connection: ● Connected         │
│ Workspace: abc123...            │
│ Session: def456...              │
│ Claude: idle                    │
│ Tab: explorer                   │
│ Sheets: FileViewer              │
├─────────────────────────────────┤
│ [Copy State] [Export Logs]      │
└─────────────────────────────────┘
```

---

## Priority 3: Issue Detection Patterns (High Impact, High Effort)

### 3.1 Automatic Race Condition Detection
Detect multiple presentation attempts:

```swift
class PresentationTracker {
    static let shared = PresentationTracker()

    private var activePresentations: [String: Date] = [:]
    private let threshold: TimeInterval = 0.5

    func willPresent(_ identifier: String) -> Bool {
        let now = Date()

        // Check if another presentation is in progress
        for (id, time) in activePresentations {
            if now.timeIntervalSince(time) < threshold {
                AppLogger.log("[RACE DETECTED] Attempted to present '\(identifier)' while '\(id)' is presenting", type: .warning)
                return false
            }
        }

        activePresentations[identifier] = now
        return true
    }

    func didDismiss(_ identifier: String) {
        activePresentations.removeValue(forKey: identifier)
    }
}
```

### 3.2 Event Sequence Validator
Validate expected event sequences:

```swift
// Define expected sequences
let workspaceSwitchSequence = [
    "workspace/unsubscribe",
    "workspace/session/unwatch",
    "workspace/subscribe",
    "workspace/session/watch"
]

// Track and validate
class EventSequenceTracker {
    func trackEvent(_ event: String) {
        // Log if event is out of expected order
        // Alert if expected event is missing
    }
}
```

### 3.3 Stuck State Detection
Detect and alert on stuck states:

```swift
// Detect loading states that take too long
class StuckStateDetector {
    func monitorLoadingState<T>(_ binding: Binding<Bool>, context: String, timeout: TimeInterval = 10) {
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if binding.wrappedValue {
                AppLogger.log("[STUCK STATE] \(context) loading for >\(timeout)s", type: .warning)
            }
        }
    }
}
```

---

## Priority 4: User-Facing Debug Tools (Medium Impact, Medium Effort)

### 4.1 "Report Issue" Feature
One-tap issue reporting:

```swift
struct IssueReport {
    let description: String
    let stateSnapshot: AppStateSnapshot
    let recentLogs: [DebugLogEntry]  // Last 100 logs
    let deviceInfo: DeviceInfo
    let timestamp: Date
}

// Generates markdown report ready to paste into GitHub issue
```

### 4.2 Debug Log Export Enhancements
- Export filtered logs (e.g., "last 5 minutes of WS logs")
- Export as JSON for programmatic analysis
- Include state snapshots at key moments

### 4.3 Reproduction Mode
Record user actions for replay:

```swift
// Records tap locations, timing, and state changes
// Generates step-by-step reproduction instructions
```

---

## Implementation Roadmap

### Phase 1 (Quick Wins) - 1-2 days
- [ ] Add ViewLifecycle logging modifier
- [ ] Add @Published didSet logging to key ViewModels
- [ ] Create loggedSheet modifier
- [ ] Document logging conventions

### Phase 2 (State Visibility) - 3-5 days
- [ ] Implement AppStateSnapshot
- [ ] Add debug overlay (shake to show)
- [ ] Enhance log export with state context

### Phase 3 (Auto-Detection) - 1-2 weeks
- [ ] Implement PresentationTracker
- [ ] Add event sequence validation
- [ ] Create stuck state detection

### Phase 4 (User Tools) - 2-3 weeks
- [x] Build "Report Issue" feature *(Completed: IssueReportGenerator + AdminToolsView share sheet)*
- [ ] Add reproduction mode
- [ ] Create debug dashboard view

### Phase 5 (Deadlock & Hang Prevention) - Completed 2024-12-27
*Added after disconnect-hang-deadlock incident*

- [x] **Step-by-step logging in critical operations**
  - Added granular logging to `DashboardViewModel.disconnect()`
  - Added granular logging to `WebSocketService.disconnect()`
  - Pattern: `AppLogger.log("[Component] Step X - START/COMPLETE")`

- [x] **Lock safety: Copy before callback**
  - Fixed `finishAllContinuations()` to copy continuations out of lock before calling `finish()`
  - Prevents deadlock when `finish()` triggers code that needs same lock

- [x] **Complete state cleanup on disconnect**
  - `WorkspaceStore.shared.clearActive()`
  - `ManagerStore.shared.clear()` *(was missing - caused auto-reconnect)*
  - `WorkspaceManagerService.shared.reset()`
  - `appState?.clearHTTPState()`

- [x] **Explicit disconnect flag**
  - Added `appState?.markExplicitDisconnect()` before disconnect
  - RootView now knows disconnect is intentional vs network failure

- [x] **Consolidated disconnect flow**
  - Settings and WorkspaceManager both call `DashboardViewModel.disconnect()`
  - Added `onDisconnect` callback to `WorkspaceManagerView`
  - Split `resetManager()` into `resetManager()` + `resetManagerState()`

### Remaining (Not Yet Implemented)
- [ ] SafeLock wrapper with timeout detection
- [ ] HangDetector service for stuck operations
- [ ] ContinuationTracker for leak detection
- [ ] DisconnectValidator for automated state validation
- [ ] State machine visualization

---

## Log Analysis Tips

### Finding Race Conditions
```bash
# Look for duplicate events within short time window
grep -E "\[.*View\] (onAppear|presenting)" logs.txt |
  awk '{print $1, $2}' |
  uniq -d
```

### Finding State Mismatches
```bash
# Look for unexpected state transitions
grep -E "selectedFile.*->|fileToDisplay.*->" logs.txt
```

### Finding Missing Events
```bash
# Check workspace switch sequence
grep -E "workspace/(subscribe|unsubscribe|session)" logs.txt
```

---

## Priority 5: Deadlock & Hang Detection (Critical - Learned from disconnect-hang-deadlock)

### 5.1 Lock Timeout Wrapper

Detect deadlocks by adding timeout to lock operations:

```swift
// SafeLock.swift
final class SafeLock {
    private let lock = NSLock()
    private let name: String
    private let timeout: TimeInterval

    init(name: String, timeout: TimeInterval = 5.0) {
        self.name = name
        self.timeout = timeout
    }

    func withLock<T>(_ block: () -> T) -> T {
        let acquired = lock.lock(before: Date().addingTimeInterval(timeout))
        if !acquired {
            AppLogger.log("[DEADLOCK] Failed to acquire \(name) lock after \(timeout)s", type: .error)
            // In debug: crash with stack trace
            // In release: log and attempt recovery
            #if DEBUG
            fatalError("Deadlock detected: \(name)")
            #endif
        }
        defer { lock.unlock() }
        return block()
    }
}

// Usage:
private let continuationsLock = SafeLock(name: "continuationsLock", timeout: 2.0)
```

### 5.2 Async Operation Hang Detection

Detect operations that take too long:

```swift
// HangDetector.swift
actor HangDetector {
    static let shared = HangDetector()

    private var operations: [String: Date] = [:]
    private let threshold: TimeInterval = 10.0

    func startOperation(_ name: String) {
        operations[name] = Date()

        Task {
            try? await Task.sleep(nanoseconds: UInt64(threshold * 1_000_000_000))
            if operations[name] != nil {
                AppLogger.log("[HANG DETECTED] '\(name)' running for >\(threshold)s", type: .error)
                await captureStackTrace(for: name)
            }
        }
    }

    func endOperation(_ name: String) {
        operations.removeValue(forKey: name)
    }
}

// Usage:
func disconnect() async {
    await HangDetector.shared.startOperation("DashboardViewModel.disconnect")
    defer { Task { await HangDetector.shared.endOperation("DashboardViewModel.disconnect") } }

    // ... disconnect logic
}
```

### 5.3 Continuation Lifecycle Tracking

Track all AsyncStream continuations to detect leaks and deadlocks:

```swift
// ContinuationTracker.swift
final class ContinuationTracker {
    static let shared = ContinuationTracker()

    private var activeContinuations: [String: (created: Date, stack: String)] = [:]
    private let lock = NSLock()

    func register(_ id: String) {
        lock.withLock {
            activeContinuations[id] = (Date(), Thread.callStackSymbols.joined(separator: "\n"))
        }
        AppLogger.log("[Continuation] Created: \(id)")
    }

    func finish(_ id: String) {
        lock.withLock {
            if let info = activeContinuations.removeValue(forKey: id) {
                let duration = Date().timeIntervalSince(info.created)
                AppLogger.log("[Continuation] Finished: \(id) (lived \(duration)s)")
            }
        }
    }

    func reportLeaks() {
        lock.withLock {
            for (id, info) in activeContinuations {
                let age = Date().timeIntervalSince(info.created)
                if age > 60 {
                    AppLogger.log("[Continuation LEAK] \(id) alive for \(age)s", type: .warning)
                }
            }
        }
    }
}
```

### 5.4 State Cleanup Validator

Ensure all related state is cleaned during disconnect:

```swift
// DisconnectValidator.swift
struct DisconnectValidator {
    static func validate() -> [String] {
        var issues: [String] = []

        // Check WebSocket state
        if DependencyContainer.shared.webSocketService.isConnected {
            issues.append("WebSocket still connected after disconnect")
        }

        // Check workspace store
        if WorkspaceStore.shared.activeWorkspace != nil {
            issues.append("activeWorkspace not cleared")
        }

        // Check manager store
        if ManagerStore.shared.hasManager {
            issues.append("ManagerStore not cleared - will auto-reconnect!")
        }

        // Check session repository
        if DependencyContainer.shared.sessionRepository.selectedSessionId != nil {
            issues.append("selectedSessionId not cleared")
        }

        if !issues.isEmpty {
            AppLogger.log("[Disconnect Validation] Issues: \(issues)", type: .warning)
        }

        return issues
    }
}

// Usage in disconnect():
func disconnect() async {
    // ... cleanup

    #if DEBUG
    let issues = DisconnectValidator.validate()
    assert(issues.isEmpty, "Disconnect incomplete: \(issues)")
    #endif
}
```

---

## Priority 6: Binary Search Debugging Pattern

When UI hangs, use this systematic approach:

### 6.1 Step-by-Step Logging Template

```swift
// Add logging after EVERY line in suspected function
func problematicFunction() async {
    AppLogger.log("[Func] Step 1: Starting")
    step1()
    AppLogger.log("[Func] Step 1: Complete")

    AppLogger.log("[Func] Step 2: Starting")
    await step2()
    AppLogger.log("[Func] Step 2: Complete")

    // Last log that appears = step before hang
    // No log appears = hang is in step that follows
}
```

### 6.2 Lock Instrumentation

```swift
// Wrap all lock operations with logging
private func finishAllContinuations() {
    AppLogger.log("[WS] finishAllContinuations - acquiring lock 1")
    let stateCont = continuationsLock.withLock {
        AppLogger.log("[WS] finishAllContinuations - lock 1 acquired")
        let copy = Array(stateStreamContinuations.values)
        stateStreamContinuations.removeAll()
        return copy
    }
    AppLogger.log("[WS] finishAllContinuations - lock 1 released")

    AppLogger.log("[WS] finishAllContinuations - finishing \(stateCont.count) continuations")
    for (i, cont) in stateCont.enumerated() {
        AppLogger.log("[WS] finishAllContinuations - finishing continuation \(i)")
        cont.finish()
        AppLogger.log("[WS] finishAllContinuations - continuation \(i) finished")
    }
}
```

---

## Best Practices Summary (from disconnect-hang-deadlock)

### NEVER Do This:
```swift
// BAD: Call external code while holding lock
lock.withLock {
    externalCallback()  // May need same lock = DEADLOCK
}

// BAD: Forget to set navigation flags
func disconnect() {
    webSocketService.disconnect()
    // RootView doesn't know this is intentional!
}

// BAD: Partial state cleanup
func disconnect() {
    WorkspaceStore.shared.clearActive()
    // Forgot ManagerStore - auto-reconnection!
}
```

### ALWAYS Do This:
```swift
// GOOD: Copy data out, release lock, then call external code
let items = lock.withLock { Array(collection) }
for item in items { item.callback() }

// GOOD: Set flags before state changes
appState.markExplicitDisconnect()
webSocketService.disconnect()

// GOOD: Clear ALL related state
WorkspaceStore.shared.clearActive()
ManagerStore.shared.clear()
WorkspaceManagerService.shared.reset()
appState?.clearHTTPState()
```

---

## Metrics to Track

1. **Issue Resolution Time**
   - Time from report to root cause identified
   - Time from root cause to fix deployed

2. **Issue Categories**
   - Track which categories are most common
   - Prioritize framework improvements

3. **Root Cause Patterns**
   - Track recurring patterns
   - Build automated detection for common patterns

4. **Hang/Deadlock Incidents** (NEW)
   - Track lock contention issues
   - Monitor async operation durations
   - Detect continuation leaks

---

## Technical Leadership Analysis: Faster Root Cause Detection

### The Problem We Faced (disconnect-hang-deadlock case study)

This issue took significant debugging time because:
1. **UI freeze = no obvious error** - No crash, no error message, just frozen
2. **Multiple root causes** - Lock deadlock + missing flag + incomplete cleanup
3. **Symptoms appeared far from root cause** - "App hangs" vs "lock held during continuation.finish()"
4. **Binary search debugging** - Had to add logging line-by-line to narrow down

### Recommendations for Future (Priority Order)

#### 1. Immediate: Add SafeLock Wrapper (1 day effort)

Replace all `NSLock().withLock {}` with a timeout-aware version:

```swift
// If lock not acquired in 2 seconds, log error with stack trace
private let continuationsLock = SafeLock(name: "continuations", timeout: 2.0)
```

**Impact:** Would have immediately shown "DEADLOCK: continuationsLock" in logs instead of silent hang.

#### 2. Short-term: Disconnect Flow Test (2 days effort)

Create an automated test that validates the complete disconnect flow:

```swift
func testDisconnectCleansAllState() async {
    // Setup: Connect to workspace
    await appState.connect(...)

    // Act: Disconnect
    await dashboardViewModel.disconnect()

    // Assert: ALL state is clean
    XCTAssertFalse(webSocketService.isConnected)
    XCTAssertNil(WorkspaceStore.shared.activeWorkspace)
    XCTAssertFalse(ManagerStore.shared.hasManager)
    XCTAssertNil(sessionRepository.selectedSessionId)
}
```

**Impact:** Would have caught the "ManagerStore not cleared" issue immediately.

#### 3. Medium-term: Hang Detection Service (1 week effort)

Background watchdog that detects stuck operations:

```swift
// In AppDelegate/SceneDelegate
HangDetector.shared.startMonitoring()

// Any operation >10s triggers warning in debug console
// Any operation >30s captures stack trace and shows alert
```

**Impact:** User would see "Disconnect operation stuck for 10s" instead of wondering what happened.

#### 4. Long-term: State Machine Visualization (2-3 weeks)

Create a debug view showing:
- Current app state (connected, disconnecting, disconnected)
- Expected vs actual state after operations
- State transition history

```
[Connected] → [Disconnecting] → [Disconnected]
                     ↓
              Expected: WorkspaceStore.clear ✓
              Expected: ManagerStore.clear ✗ ← MISSING!
              Expected: WebSocket.disconnect ✓
```

**Impact:** Visual representation makes state bugs obvious.

### Quick Wins for AI/Developer Productivity

1. **Standardized Logging Format**
   ```swift
   // Every async operation should have this pattern:
   AppLogger.log("[Component] operationName - START")
   defer { AppLogger.log("[Component] operationName - END") }
   ```

2. **Debug Commands**
   Add `/debug disconnect` command that:
   - Shows all state that will be cleared
   - Validates all cleanup happened
   - Reports any issues

3. **Issue Template**
   When users report "app hangs", auto-collect:
   - Last 100 log lines
   - Current state snapshot
   - Active operations list

### Enhancement Priority Matrix

| Enhancement | Effort | Impact | Would Have Helped This Issue? |
|-------------|--------|--------|-------------------------------|
| SafeLock with timeout | 1 day | Immediate deadlock detection | YES - "DEADLOCK: continuationsLock" |
| Disconnect flow test | 2 days | Catches incomplete cleanup | YES - "ManagerStore not cleared" |
| HangDetector service | 1 week | Alerts on stuck operations | YES - "Disconnect stuck for 10s" |
| State machine viz | 3 weeks | Visual state debugging | YES - Missing state transitions |

### Key Insight

**Silent hangs are the hardest bugs.** Every lock and async operation should have timeout detection in debug builds. The goal is to convert "app froze, no idea why" into "DEADLOCK: continuationsLock after 2s" or "HANG: disconnect() running for 10s".
