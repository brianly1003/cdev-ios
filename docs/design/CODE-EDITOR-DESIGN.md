# cdev-ios Code Editor: Technical Design Document

## Executive Summary

This document outlines the architecture for implementing a world-class, VS Code-like code editor in cdev-ios. The goal is to enable seamless real-time file editing that synchronizes with cdev-agent and handles concurrent edits from Claude.

---

## 1. Editor Library Analysis

### Option A: Runestone (Recommended)

**[Runestone](https://github.com/simonbs/Runestone)** is a performant plain text editor for iOS with syntax highlighting powered by Tree-sitter.

| Criteria | Score | Notes |
|----------|-------|-------|
| Performance | ⭐⭐⭐⭐⭐ | Incremental parsing, handles large files |
| Syntax Highlighting | ⭐⭐⭐⭐⭐ | Tree-sitter (50+ languages) |
| Native Swift | ⭐⭐⭐⭐⭐ | Pure Swift, no WebView |
| Customization | ⭐⭐⭐⭐ | Themes, fonts, line numbers |
| Memory Usage | ⭐⭐⭐⭐⭐ | Efficient line management |
| Maintenance | ⭐⭐⭐⭐ | Active, used in App Store apps |

**Key Features:**
- Syntax highlighting (Tree-sitter)
- Line numbers with gutter
- Invisible characters display
- Character pair insertion (brackets, quotes)
- Regex search & replace
- Page guide (80/120 column marker)
- Customizable themes
- Undo/redo built-in

**Integration:**
```swift
import Runestone

// SPM: https://github.com/simonbs/Runestone
```

### Option B: CodeMirror 6 via WKWebView

**[CodeMirror-SwiftUI](https://github.com/Pictarine/CodeMirror-SwiftUI)** wraps CodeMirror in WKWebView.

| Criteria | Score | Notes |
|----------|-------|-------|
| Performance | ⭐⭐⭐ | WebView overhead |
| Syntax Highlighting | ⭐⭐⭐⭐⭐ | 100+ languages |
| Native Swift | ⭐⭐ | JavaScript bridge |
| Customization | ⭐⭐⭐⭐⭐ | Full CodeMirror API |
| Memory Usage | ⭐⭐⭐ | WebView memory |
| Maintenance | ⭐⭐⭐ | CodeMirror 5.x (not 6) |

**Pros:** More VS Code-like, richer addons
**Cons:** JS bridge latency, WebView complexity, existing wrappers use CM5 not CM6

### Recommendation: Runestone

Runestone provides the best balance of performance and features for a native iOS experience. CodeMirror 6 would require building a custom wrapper and dealing with WebView complexity.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         cdev-ios                                 │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    CodeEditorView                        │   │
│  │  ┌─────────────────────────────────────────────────────┐│   │
│  │  │              Runestone TextView                      ││   │
│  │  │  • Syntax highlighting (Tree-sitter)                ││   │
│  │  │  • Line numbers                                      ││   │
│  │  │  • Search & replace                                  ││   │
│  │  │  • Undo/redo                                         ││   │
│  │  └─────────────────────────────────────────────────────┘│   │
│  │  ┌─────────────────────────────────────────────────────┐│   │
│  │  │           Code Keyboard Accessory                    ││   │
│  │  │  [ Tab ][ { ][ } ][ ( ][ ) ][ ; ][ : ][ " ][ → ]   ││   │
│  │  └─────────────────────────────────────────────────────┘│   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  EditorSyncService                       │   │
│  │  • Debounced change detection                           │   │
│  │  • Conflict resolution                                   │   │
│  │  • Optimistic updates                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
└──────────────────────────────│───────────────────────────────────┘
                               │
              ┌────────────────┴────────────────┐
              │         WebSocket + HTTP         │
              └────────────────┬────────────────┘
                               │
┌──────────────────────────────│───────────────────────────────────┐
│                         cdev-agent                               │
├──────────────────────────────│───────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   FileEditHandler                        │   │
│  │  • Validate file path within workspace                  │   │
│  │  • Write to filesystem                                   │   │
│  │  • Broadcast file_changed to all clients                │   │
│  │  • Update git status                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    File System                           │   │
│  │  ~/Projects/my-app/src/component.tsx                    │   │
│  └─────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Real-Time Sync Protocol

### 3.1 Sync Strategy: Last-Write-Wins with Conflict Detection

Given cdev-ios is always online when editing, we use a simpler approach than full CRDT:

```
┌─────────────┐                              ┌─────────────┐
│   iOS       │                              │   Agent     │
│   Editor    │                              │   Server    │
└──────┬──────┘                              └──────┬──────┘
       │                                            │
       │  1. GET file content + version             │
       │ ──────────────────────────────────────────►│
       │                                            │
       │  { content, version: 1, hash: "abc" }      │
       │ ◄──────────────────────────────────────────│
       │                                            │
       │  [User edits locally]                      │
       │                                            │
       │  2. PUT file (debounced 500ms)             │
       │  { content, base_version: 1 }              │
       │ ──────────────────────────────────────────►│
       │                                            │
       │  3a. Success: { version: 2 }               │
       │ ◄──────────────────────────────────────────│
       │                                            │
       │  --- OR ---                                │
       │                                            │
       │  3b. Conflict: { conflict: true,           │
       │                  server_version: 2,        │
       │                  server_content: "..." }   │
       │ ◄──────────────────────────────────────────│
       │                                            │
       │  [Show merge dialog]                       │
       │                                            │
```

### 3.2 Handling Claude Edits

When Claude edits a file while user has it open:

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   iOS       │      │   Agent     │      │   Claude    │
│   Editor    │      │   Server    │      │   CLI       │
└──────┬──────┘      └──────┬──────┘      └──────┬──────┘
       │                    │                    │
       │  Viewing file.tsx  │                    │
       │  version: 1        │                    │
       │                    │                    │
       │                    │  Claude edits      │
       │                    │◄───────────────────│
       │                    │                    │
       │  WS: file_changed  │                    │
       │  { path, version:2,│                    │
       │    edited_by:      │                    │
       │    "claude" }      │                    │
       │◄───────────────────│                    │
       │                    │                    │
       │  [Show banner:     │                    │
       │   "Claude edited   │                    │
       │   this file"]      │                    │
       │                    │                    │
       │  [Auto-reload OR   │                    │
       │   show diff]       │                    │
       │                    │                    │
```

### 3.3 WebSocket Events (New)

```typescript
// New event: file_edit_started
{
  "event": "file_edit_started",
  "payload": {
    "path": "src/component.tsx",
    "client_id": "ios-abc123",
    "workspace_id": "..."
  }
}

// New event: file_edit_ended
{
  "event": "file_edit_ended",
  "payload": {
    "path": "src/component.tsx",
    "client_id": "ios-abc123"
  }
}

// Existing event: file_changed (enhanced)
{
  "event": "file_changed",
  "payload": {
    "path": "src/component.tsx",
    "change": "modified",
    "version": 2,
    "edited_by": "claude" | "ios-abc123" | "vscode-xyz",
    "hash": "sha256:..."
  }
}
```

### 3.4 Agent API (New Endpoints)

```go
// GET /api/file/content
// Request:
//   ?path=src/component.tsx
//   &workspace_id=...
// Response:
{
  "path": "src/component.tsx",
  "content": "import React...",
  "version": 1,
  "hash": "sha256:abc123",
  "language": "typescript",
  "size": 1234,
  "readonly": false
}

// PUT /api/file/content
// Request:
{
  "path": "src/component.tsx",
  "content": "import React...",
  "base_version": 1,
  "workspace_id": "..."
}
// Response (success):
{
  "success": true,
  "version": 2,
  "hash": "sha256:def456"
}
// Response (conflict):
{
  "success": false,
  "conflict": true,
  "server_version": 2,
  "server_content": "...",
  "server_hash": "..."
}

// JSON-RPC: file/lock (optional)
// Soft lock to indicate editing
{
  "method": "file/lock",
  "params": {
    "path": "src/component.tsx",
    "workspace_id": "..."
  }
}
```

---

## 4. Code Keyboard Design

### 4.1 Input Accessory View

Custom keyboard row for quick access to code symbols:

```
┌─────────────────────────────────────────────────────────────────┐
│  ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐ │
│  │ Tab │  {  │  }  │  (  │  )  │  [  │  ]  │  ;  │  :  │  =  │ │
│  └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘ │
│  ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐ │
│  │  <  │  >  │  "  │  '  │  `  │  /  │  \  │  |  │  &  │  !  │ │
│  └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘ │
│  ┌───────┬───────┬───────────────────────────┬───────┬───────┐ │
│  │   ←   │   →   │         Dismiss           │  Undo │ Redo  │ │
│  └───────┴───────┴───────────────────────────┴───────┴───────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Implementation

```swift
// CodeKeyboardAccessory.swift
struct CodeKeyboardAccessory: View {
    @Binding var textView: TextView  // Runestone TextView

    private let row1 = ["Tab", "{", "}", "(", ")", "[", "]", ";", ":", "="]
    private let row2 = ["<", ">", "\"", "'", "`", "/", "\\", "|", "&", "!"]

    var body: some View {
        VStack(spacing: 4) {
            // Symbol rows
            HStack(spacing: 4) {
                ForEach(row1, id: \.self) { symbol in
                    SymbolButton(symbol: symbol) {
                        insertSymbol(symbol)
                    }
                }
            }

            HStack(spacing: 4) {
                ForEach(row2, id: \.self) { symbol in
                    SymbolButton(symbol: symbol) {
                        insertSymbol(symbol)
                    }
                }
            }

            // Action row
            HStack(spacing: 8) {
                ActionButton(icon: "arrow.left") { moveCursor(-1) }
                ActionButton(icon: "arrow.right") { moveCursor(1) }

                Spacer()

                Button("Done") { dismissKeyboard() }
                    .font(Typography.buttonLabel)

                Spacer()

                ActionButton(icon: "arrow.uturn.backward") { textView.undoManager?.undo() }
                ActionButton(icon: "arrow.uturn.forward") { textView.undoManager?.redo() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ColorSystem.terminalBgElevated)
    }

    private func insertSymbol(_ symbol: String) {
        let char = symbol == "Tab" ? "\t" : symbol
        textView.insertText(char)
        Haptics.light()
    }
}

struct SymbolButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol == "Tab" ? "⇥" : symbol)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .frame(minWidth: 32, minHeight: 36)
                .background(ColorSystem.terminalBgHighlight)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
```

### 4.3 Swipe Gestures

```swift
// Long-press on symbol shows related symbols
// Example: Long-press "{" shows { } {{ }}

// Swipe left/right on symbol row to show more
// Row 3 (swipe): # $ % ^ * _ + - ~
```

---

## 5. UI/UX Design

### 5.1 Editor Screen Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ ◀ Back    component.tsx    [Claude editing...]    ⋯   [Save]   │
├─────────────────────────────────────────────────────────────────┤
│ ┌───┐                                                           │
│ │ 1 │ import React from 'react';                               │
│ │ 2 │                                                          │
│ │ 3 │ interface Props {                                        │
│ │ 4 │   title: string;                                         │
│ │ 5 │   onClick: () => void;                                   │
│ │ 6 │ }                                                        │
│ │ 7 │                                                          │
│ │ 8 │ export const Button: React.FC<Props> = ({                │
│ │ 9 │   title,                                                 │
│ │10 │   onClick,                                               │
│ │11 │ }) => {                                                  │
│ │12 │   return (                                               │
│ │13 │     <button                                              │
│ │14 │       className="btn-primary"  ← cursor                  │
│ │15 │       onClick={onClick}                                  │
│ │16 │     >                                                    │
│ │17 │       {title}                                            │
│ │18 │     </button>                                            │
│ │19 │   );                                                     │
│ │20 │ };                                                       │
│ └───┘                                                           │
├─────────────────────────────────────────────────────────────────┤
│ Ln 14, Col 28  │  TypeScript  │  UTF-8  │  Modified            │
├─────────────────────────────────────────────────────────────────┤
│  [ Tab ][ { ][ } ][ ( ][ ) ][ ; ][ " ]  │  [Undo] [Redo]       │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Conflict Resolution UI

```
┌─────────────────────────────────────────────────────────────────┐
│                     ⚠️ File Changed                              │
│                                                                  │
│  Claude modified this file while you were editing.              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Your changes          │  Claude's changes              │   │
│  ├─────────────────────────┼───────────────────────────────┤   │
│  │  - const x = 1;         │  - const x = 1;               │   │
│  │  + const x = 2;         │  + const x = 42;              │   │
│  └─────────────────────────┴───────────────────────────────┘   │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │
│  │ Keep Mine   │  │ Use Claude's│  │ Open in Diff View   │    │
│  └─────────────┘  └─────────────┘  └─────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 Status Indicators

```swift
enum EditorStatus {
    case clean                    // No changes
    case modified                 // Local changes, not saved
    case saving                   // Saving to server
    case saved                    // Successfully saved
    case conflict                 // Server has different version
    case claudeEditing            // Claude is currently editing
    case otherDeviceEditing(id)   // Another device editing
    case readonly                 // File is read-only
}
```

---

## 6. Implementation Phases

### Phase 1: Foundation (Week 1-2)
- [ ] Integrate Runestone via SPM
- [ ] Create `CodeEditorView` wrapper for SwiftUI
- [ ] Implement basic file loading from agent
- [ ] Add syntax highlighting for top 10 languages
- [ ] Create code keyboard accessory

### Phase 2: Editing & Sync (Week 3-4)
- [ ] Implement agent `PUT /api/file/content` endpoint
- [ ] Add debounced auto-save (500ms)
- [ ] Handle version conflicts
- [ ] Add file_changed WebSocket handler
- [ ] Show "Claude editing" indicator

### Phase 3: Polish (Week 5-6)
- [ ] Conflict resolution UI
- [ ] Search & replace
- [ ] Go to line
- [ ] Theme support (match app theme)
- [ ] iPad keyboard shortcuts

### Phase 4: Advanced (Future)
- [ ] Mini-map (scroll preview)
- [ ] Multiple file tabs
- [ ] Git gutter (show changed lines)
- [ ] Auto-completion (requires LSP via agent)

---

## 7. File Structure

```
cdev/
├── Presentation/
│   └── Screens/
│       └── Editor/
│           ├── CodeEditorView.swift          # Main editor screen
│           ├── CodeEditorViewModel.swift     # State management
│           ├── RunestoneWrapper.swift        # UIViewRepresentable
│           ├── CodeKeyboardAccessory.swift   # Symbol keyboard
│           ├── ConflictResolutionSheet.swift # Merge UI
│           └── EditorStatusBar.swift         # Line/col info
├── Domain/
│   └── Models/
│       └── FileEdit.swift                    # Edit models
├── Data/
│   └── Services/
│       └── EditorSync/
│           ├── EditorSyncService.swift       # Sync logic
│           └── FileVersionManager.swift      # Version tracking
```

---

## 8. Dependencies

### Swift Package Manager

```swift
// Package.swift additions
dependencies: [
    .package(url: "https://github.com/simonbs/Runestone", from: "0.5.0"),
    .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.53.0"), // Optional: format on save
]
```

### Tree-sitter Languages

Runestone uses Tree-sitter. Languages to include:
- TypeScript/JavaScript (tsx, ts, js, jsx)
- Swift
- Python
- Go
- Rust
- HTML/CSS
- JSON/YAML
- Markdown
- SQL
- Shell/Bash

---

## 9. Performance Considerations

### Large Files

```swift
// For files > 100KB, show warning
if fileSize > 100_000 {
    showLargeFileWarning()
}

// For files > 1MB, offer read-only mode
if fileSize > 1_000_000 {
    offerReadOnlyMode()
}
```

### Debouncing

```swift
// EditorSyncService.swift
class EditorSyncService {
    private var saveTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 0.5

    func contentDidChange(_ content: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await saveToServer(content)
        }
    }
}
```

### Memory Management

```swift
// Release editor resources when backgrounded
NotificationCenter.default.addObserver(
    forName: UIApplication.didEnterBackgroundNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.releaseEditorResources()
}
```

---

## 10. Security Considerations

1. **Path Validation**: Agent must validate file paths are within workspace
2. **No Executable Files**: Prevent editing of .sh, .command files (or warn)
3. **Size Limits**: Enforce max file size (e.g., 5MB)
4. **Rate Limiting**: Limit save frequency to prevent abuse
5. **Audit Log**: Log all file edits with client ID and timestamp

---

## 11. Success Metrics

| Metric | Target |
|--------|--------|
| Editor load time (< 100KB file) | < 200ms |
| Syntax highlight render | < 100ms |
| Save to server round-trip | < 500ms |
| Conflict detection accuracy | 100% |
| Memory usage (1000 line file) | < 50MB |
| Crash rate | < 0.1% |

---

## References

- [Runestone GitHub](https://github.com/simonbs/Runestone)
- [Tree-sitter](https://tree-sitter.github.io/tree-sitter/)
- [CodeMirror-SwiftUI](https://github.com/Pictarine/CodeMirror-SwiftUI)
- [Zed CRDT Blog](https://zed.dev/blog/crdts)
- [Apple Custom Keyboard Docs](https://developer.apple.com/documentation/uikit/keyboards_and_input/creating_a_custom_keyboard/)
- [OT vs CRDT Comparison](https://www.tiny.cloud/blog/real-time-collaboration-ot-vs-crdt/)
