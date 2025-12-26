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
- [ ] Build "Report Issue" feature
- [ ] Add reproduction mode
- [ ] Create debug dashboard view

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
