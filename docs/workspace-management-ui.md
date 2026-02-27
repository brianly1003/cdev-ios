# Workspace Management UI Design

## Overview

Sophisticated workspace management system for developers working with multiple repositories simultaneously. Optimized for both iPad Pro (primary) and iPhone with focus on speed, visibility, and efficiency.

## Design Goals

1. **Speed** - Switch workspaces in < 1 second
2. **Visibility** - See all workspace states at a glance
3. **Efficiency** - Minimize taps for common workflows
4. **Scalability** - Handle 50+ workspaces smoothly
5. **Multi-Device** - iPad Pro first, iPhone optimized

## Core Features

### 1. Global Quick Switcher (⌘K)

**Concept**: Spotlight-style overlay for instant workspace switching

**Trigger**:
- iPad: `⌘K` keyboard shortcut
- iPhone: Long press on workspace badge in status bar

**Layout**:
```
┌─────────────────────────────────────────────────┐
│  ⌘K Quick Switch                          ESC   │
├─────────────────────────────────────────────────┤
│  🔍 Type to search...                           │
│                                                  │
│  📁 cdev-ios              [RUNNING] [IDLE]   ⌘1 │
│     localhost:16180 • main • 2m ago              │
│                                                  │
│  📁 messenger-integrator  [STOPPED]          ⌘2 │
│     localhost:8767 • feat/qr • 5h ago           │
│                                                  │
│  📁 LazyBot               [RUNNING] [BUSY]   ⌘3 │
│     192.168.1.100:16180 • dev • 10m ago          │
└─────────────────────────────────────────────────┘
```

**Features**:
- Fuzzy search (type "mes" finds "messenger-integrator")
- Keyboard navigation (↑↓ arrows)
- Quick number shortcuts (⌘1-9 for first 9)
- Live status badges
- Recent workspaces prioritized

**Interaction**:
- `Enter` - Switch to workspace
- `⌘Enter` - Switch and run Claude immediately
- `ESC` - Close switcher
- `⌘⌫` - Remove workspace from list

---

### 2. iPad Sidebar Layout (3-Column)

**Concept**: Always-visible workspace list in sidebar (no modal needed)

**Layout**:
```
┌──────────────────────────────────────────────────────┐
│  Workspaces (12)              Dashboard             │
├──────────┬───────────────┬───────────────────────────┤
│          │               │                           │
│ RECENT   │  cdev-ios     │  📊 Terminal              │
│ ──────── │               │                           │
│ •cdev-ios│  Status: ✓    │  > ! git status           │
│  LazyBot │  Claude: IDLE │  On branch main           │
│ messenger│  Branch: main │  ...                      │
│          │               │                           │
│ ALL (47) │  Quick Actions│  📁 Files Changed (3)     │
│ ──────── │  ▶ Run Claude │  - package.json           │
│  backend │  ⏸ Stop       │  - README.md              │
│  frontend│  🔄 Restart   │                           │
│  ...     │  📋 Sessions  │  💬 Sessions (5)          │
│          │               │  - Session 1 (2h ago)     │
│  [+ Add] │  Git Info     │  - Session 2 (1d ago)     │
│          │  • 3 changed  │  ...                      │
└──────────┴───────────────┴───────────────────────────┘
```

**Columns**:
1. **Workspace List** (200pt) - Always visible, scrollable
2. **Workspace Details** (250pt) - Selected workspace info + actions
3. **Main Content** (flex) - Terminal/Sessions/Files

**Benefits**:
- Single-click workspace switching
- Preview workspace state before switching
- Quick actions without modal interruption
- Optimized for iPad screen real estate

---

### 3. iPhone Compact Card Carousel

**Concept**: Swipeable cards for mobile-friendly workspace switching

**Layout**:
```
┌──────────────────────────────┐
│    Workspaces     [12]  ✕    │
├──────────────────────────────┤
│                              │
│   ┌────────────────────┐     │
│   │  📁 cdev-ios       │     │← Swipe cards
│   │  ────────────────  │     │
│   │  ✓ Running • Idle  │     │
│   │  localhost:16180    │     │
│   │  main • 2m ago     │     │
│   │                    │     │
│   │  [Switch] [•••]    │     │
│   └────────────────────┘     │
│                              │
│   Page indicators: ● ○ ○     │
│                              │
│   ──────────────────────     │
│   🔍 Search all...           │
│   ──────────────────────     │
│                              │
│   Recent (tap to expand)     │
│   • messenger-integrator     │
│   • LazyBot                  │
└──────────────────────────────┘
```

**Features**:
- Large tap targets (44pt minimum)
- Horizontal swipe between recent 3 workspaces
- Search fallback for full list
- Context menu on long press

---

### 4. Status Bar Workspace Indicator

**Always-visible workspace status and quick access**

**iPhone**:
```
[📁 cdev-ios ▼] [✓] [●]
 └─Tap opens────┘  │   └─Claude state
     switcher      └─Connection status
```

**iPad**:
```
[📁 cdev-ios ⌘K] [✓ localhost:16180] [● IDLE]
```

**Color Coding**:
- 🟢 Green dot = Claude idle
- 🟡 Yellow dot = Claude busy/running
- 🔴 Red dot = Disconnected
- 🔵 Blue pulse = Waiting for response

---

### 5. Workspace Health Dashboard (iPad)

**Concept**: Overview of all workspace states

**Trigger**: `⌘⇧H` or Settings → Workspace Health

**Layout**:
```
┌────────────────────────────────────────────┐
│  Workspace Health                    ⌘⇧H  │
├────────────────────────────────────────────┤
│  🟢 Running (3)          🔴 Stopped (9)    │
│  ──────────────          ──────────────    │
│  cdev-ios (2m)           backend (1d)      │
│  LazyBot (10m)           frontend (3h)     │
│  messenger (5h)          ...               │
│                                            │
│  ⚠️  Issues (1)                            │
│  ──────────────                            │
│  api-service: Port 16180 in use             │
│  [Resolve] [Ignore]                        │
│                                            │
│  📊 Activity (last 24h)                    │
│  ──────────────────────                    │
│  cdev-ios:    ████████░░ 8h active         │
│  LazyBot:     ███░░░░░░░ 3h active         │
└────────────────────────────────────────────┘
```

---

### 6. Quick Actions Menu

**Trigger**: Long press / Right click on workspace

**Actions**:
```
▶ Switch & Run Claude   ⌘R
👁 Preview Sessions     ⌘P
📋 Copy Session ID
🔗 Copy WebSocket URL
🗂 Open in Finder       ⌘O
──────────────────────────
🔄 Restart Server       ⌘⇧R
⏸ Stop Server          ⌘⇧S
──────────────────────────
📌 Pin to Top
🏷 Add Tags...
🗑 Remove               ⌘⌫
```

---

## Responsive Design System

| Element | iPhone | iPad |
|---------|--------|------|
| **Layout** | Modal sheet | Sidebar + Detail |
| **Search** | Top bar | Floating (⌘K) |
| **Row height** | 60pt | 44pt |
| **Cards** | Full width | Grid 2-3 columns |
| **Icons** | 14pt | 12pt |
| **Quick switch** | 3-swipe gesture | ⌘K + keyboard |
| **Status bar** | Compact badge | Full details |

---

## Keyboard Shortcuts (iPad)

| Shortcut | Action |
|----------|--------|
| **⌘K** | Open quick switcher |
| **⌘1-9** | Switch to workspace 1-9 |
| **⌘⇧K** | Show all workspaces |
| **⌘R** | Run Claude in current workspace |
| **⌘⇧R** | Restart workspace server |
| **⌘⇧S** | Stop workspace server |
| **⌘P** | Preview sessions |
| **⌘F** | Focus search |
| **↑↓** | Navigate list |
| **Enter** | Switch to selected |
| **⌘Enter** | Switch & run Claude |
| **ESC** | Close switcher |
| **⌘⌫** | Remove workspace |

---

## Color System

```swift
extension ColorSystem {
    enum Workspace {
        static let running = Color.green
        static let stopped = Color(white: 0.5)
        static let error = Color.red
        static let starting = Color.orange

        enum Claude {
            static let idle = Color.green
            static let busy = Color.yellow
            static let waiting = Color.blue
            static let error = Color.red
        }
    }
}
```

---

## Typography

### iPhone
- Workspace name: 13pt System Regular
- Host/Branch: 10pt Monospace
- Status: 8pt System Bold
- Line limit: 1 (with ellipsis)

### iPad
- Workspace name: 12pt System Regular
- Host/Branch: 9pt Monospace
- Status: 8pt System Bold
- Line limit: 2 (show more info)

---

## Animation Timing

```swift
// Workspace switch
Duration: 0.25s
Curve: .easeInOut

// Status update
Duration: 0.15s
Curve: .linear

// Card flip (iPhone)
Duration: 0.3s
Curve: .spring(dampingFraction: 0.8)

// Sidebar expand/collapse (iPad)
Duration: 0.2s
Curve: .easeOut
```

---

## Performance Optimizations

### 1. Lazy Loading
Only render visible workspaces + 10 buffer items:
```swift
LazyVStack {
    ForEach(workspaces.prefix(50)) { workspace in
        WorkspaceRow(workspace)
    }
}
```

### 2. Workspace State Caching
Cache workspace states for 30 seconds to reduce API calls:
```swift
class WorkspaceStateCache {
    private let cacheTimeout: TimeInterval = 30
    func get(_ id: UUID) -> WorkspaceState?
}
```

### 3. Connection Pool
Keep 5 most recent workspace connections warm:
```swift
class WorkspaceConnectionPool {
    private let maxConnections = 5
    func warmUp(workspaces: [Workspace])
}
```

---

## Performance Targets

| Metric | Target | Current |
|--------|--------|---------|
| **Switch time** | < 1s | ~2-3s |
| **Search latency** | < 50ms | ~100ms |
| **List scroll FPS** | 60 FPS | ~45 FPS |
| **Memory per workspace** | < 5MB | ~8MB |
| **UI responsiveness** | < 16ms | ~25ms |

---

## Implementation Phases

### Phase 1: Core Enhancements (Week 1)
- [x] Documentation complete
- [ ] ⌘K Quick Switcher
- [ ] iPad Sidebar Layout
- [ ] Keyboard shortcuts infrastructure
- [ ] Status bar indicator enhancements
- [ ] Workspace state caching

### Phase 2: Advanced Features (Week 2)
- [ ] Workspace Health Dashboard
- [ ] Quick Actions Menu
- [ ] Card Carousel (iPhone)
- [ ] Workspace state preview
- [ ] Connection pooling

### Phase 3: Polish (Week 3)
- [ ] Animations & transitions
- [ ] Haptic feedback refinement
- [ ] Accessibility labels
- [ ] Dark/light mode refinement
- [ ] Performance profiling & optimization

---

## Technical Architecture

### Component Structure
```
WorkspaceManagement/
├── QuickSwitcher/
│   ├── QuickSwitcherView.swift
│   ├── QuickSwitcherViewModel.swift
│   └── KeyboardHandler.swift
├── Sidebar/
│   ├── WorkspaceSidebarView.swift
│   ├── WorkspaceDetailView.swift
│   └── WorkspaceListRow.swift
├── Mobile/
│   ├── WorkspaceCarousel.swift
│   └── WorkspaceCard.swift
├── StatusBar/
│   └── WorkspaceStatusIndicator.swift
└── Shared/
    ├── WorkspaceStateCache.swift
    ├── ConnectionPool.swift
    └── WorkspaceHealthMonitor.swift
```

### Data Flow
```
WorkspaceStore (Singleton)
    ↓
WorkspaceStateCache (30s cache)
    ↓
UI Components (SwiftUI @ObservedObject)
    ↓
User Actions → ViewModel → WebSocket/HTTP
```

---

## Accessibility

- **VoiceOver** labels for all interactive elements
- **Dynamic Type** support (respect user font size)
- **Reduce Motion** - disable animations if enabled
- **High Contrast** mode support
- **Keyboard navigation** - full support without mouse

---

## Testing Strategy

### Unit Tests
- WorkspaceStore CRUD operations
- Fuzzy search algorithm
- State caching logic
- Connection pool management

### UI Tests
- Quick switcher keyboard navigation
- Workspace switching flow
- Search functionality
- Context menu actions

### Performance Tests
- List scroll performance (60 FPS)
- Search latency (< 50ms)
- Switch time (< 1s)
- Memory usage per workspace (< 5MB)

---

## Future Enhancements

1. **Smart Suggestions** - ML-based workspace recommendations
2. **Workspace Snapshots** - Save/restore workspace state
3. **Parallel View** - iPad split view for 2 workspaces
4. **Remote Workspaces** - Connect to cdev-agent on other machines
5. **Workspace Groups** - Organize related projects
6. **Workspace Templates** - Quick-start configurations
7. **Activity Heatmap** - Visual workspace usage over time
8. **Collaboration** - Share workspace access with team

---

## References

- [Multi-Workspace Architecture](/Users/brianly/Projects/cdev/docs/architecture/MULTI-WORKSPACE-DESIGN.md)
- [Responsive Layout Guide](RESPONSIVE-LAYOUT.md)
- [Multi-Device Best Practices](MULTI-DEVICE-BEST-PRACTICES.md)
