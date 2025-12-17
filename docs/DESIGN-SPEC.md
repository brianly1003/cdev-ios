# cdev-ios Design Specification

> **Document Type:** Design Specification & Critical Notes
> **Purpose:** Mobile client for cdev-agent - vibe coding companion

---

## Critical Design Principles

### 1. COMPACT UI - Developer Productivity First

This is NOT a typical consumer app. This is a **developer tool** for monitoring AI coding sessions while mobile.

**Core Requirements:**
- **Maximum information density** - developers want to see everything
- **Minimum tap count** - one tap to approve, one tap to deny
- **Terminal-style output** - familiar to developers
- **Real-time updates** - no refresh buttons needed
- **Glanceable status** - know Claude's state at a glance

### 2. UI Hierarchy (Most to Least Important)

```
┌─────────────────────────────────────┐
│ Status Bar: Connected │ Running     │  ← Always visible
├─────────────────────────────────────┤
│ ⚠️ Permission: Edit file.swift      │  ← Appears when needed
│ [Deny]              [Allow]         │
├─────────────────────────────────────┤
│ Terminal │ Changes        [12] [3]  │  ← Tab selector
├─────────────────────────────────────┤
│                                     │
│ 14:32:05  Processing request...     │  ← Main content area
│ 14:32:06  Reading file.swift        │     (scrollable)
│ 14:32:07  Analyzing code...         │
│ 14:32:08  Writing changes...        │
│                                     │
├─────────────────────────────────────┤
│ [⏹] │ Ask Claude...            [↑] │  ← Action bar
└─────────────────────────────────────┘
```

### 3. One-Tap Actions

| Action | Location | Tap Count |
|--------|----------|-----------|
| Approve permission | Banner | 1 tap |
| Deny permission | Banner | 1 tap |
| Send prompt | Action bar | 1 tap (+ typing) |
| Stop Claude | Action bar | 1 tap |
| View diff | Diff list row | 1 tap |
| Clear logs | Toolbar | 1 tap |

### 4. Color Semantics

| Color | Meaning |
|-------|---------|
| Green (#34C759) | Running, Success, Additions |
| Orange (#FF9500) | Waiting, Warning, Attention needed |
| Red (#FF3B30) | Error, Stopped, Deletions |
| Blue (#007AFF) | Primary actions, Info |
| Gray | Idle, Context, Secondary |

---

## Screen Specifications

### Dashboard (Main Screen)

**Purpose:** Central hub for monitoring and interaction

**Components:**
1. **Status Bar** - Connection state, Claude state, repo name
2. **Interaction Banner** - Permissions/questions (conditional)
3. **Tab Selector** - Terminal | Changes with badges
4. **Content Area** - Log list or diff list
5. **Action Bar** - Stop button + prompt input

**States:**
- Disconnected → Show "Offline" status
- Connecting → Show spinner in status
- Connected/Idle → Normal state
- Connected/Running → Show stop button, auto-scroll logs
- Connected/Waiting → Show interaction banner

### Terminal View

**Purpose:** Display Claude CLI output in real-time

**Features:**
- Monospace font (SF Mono)
- Black background (terminal feel)
- Timestamps (toggleable)
- Color-coded: stdout=white, stderr=red, system=blue
- Auto-scroll to bottom
- Text selection enabled

### Changes View

**Purpose:** Display file diffs

**Features:**
- File list with icons by extension
- +/- stats for each file
- Tap to expand full diff
- Syntax-highlighted diff view
- Addition/deletion backgrounds

### Pairing View

**Purpose:** Connect to cdev-agent

**Features:**
- QR code scanner (primary)
- Manual URL entry (fallback)
- Camera permission handling
- Connection status feedback

---

## Technical Specifications

### Network

| Parameter | Value |
|-----------|-------|
| WebSocket Port | 8765 (default) |
| HTTP Port | 8766 (default) |
| Connection Timeout | 10 seconds |
| Request Timeout | 30 seconds |
| Ping Interval | 30 seconds |
| Max Reconnect Attempts | 5 |
| Reconnect Backoff | Exponential (2^n seconds) |

### Caching

| Cache | Max Size | Notes |
|-------|----------|-------|
| Log entries | 1000 lines | FIFO eviction |
| Diff entries | 100 files | Keyed by path |
| Session info | Keychain | Secure storage |

### Events (from Agent)

| Event | Payload | Action |
|-------|---------|--------|
| claude_log | line, stream | Append to log list |
| claude_status | state | Update status bar |
| claude_waiting | question, options | Show interaction banner |
| claude_permission | tool, description | Show permission banner |
| git_diff | file, diff, +/- | Add to diff list |
| error | message | Show error alert |

### Commands (to Agent)

| Command | Payload | Trigger |
|---------|---------|---------|
| run_claude | prompt, mode | Send button |
| stop_claude | - | Stop button |
| respond_to_claude | response, requestId | Banner actions |
| get_status | - | On connect, refresh |

---

## Accessibility

### VoiceOver

- All interactive elements have labels
- Status changes announced
- Permission banners are focus traps

### Dynamic Type

- All text uses system fonts
- Minimum scale factor: 0.8
- No fixed font sizes

### Reduce Motion

- Animations respect system preference
- Tab transitions simplified

---

## Performance Targets

| Metric | Target |
|--------|--------|
| App launch | < 1 second |
| WebSocket connect | < 2 seconds |
| Log render (1000 lines) | < 100ms |
| Memory (idle) | < 50MB |
| Memory (active) | < 100MB |

---

## Future Enhancements (Post-MVP)

1. **Multiple Sessions** - Connect to multiple agents
2. **Session History** - View past sessions
3. **File Browser** - Navigate repo files
4. **Prompt Templates** - Quick-access common prompts
5. **Push Notifications** - Alert when Claude needs input
6. **iPad Split View** - Terminal + diffs side by side
7. **Widgets** - Status on home screen
