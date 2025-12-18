# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Build & Development

Open `cdev.xcodeproj` in Xcode 15+ and build for iOS 17.0+.

```bash
# Open project
open cdev.xcodeproj

# Build from command line (if needed)
xcodebuild -scheme cdev -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Architecture

cdev-ios is an iOS client for cdev-agent following **Clean Architecture + MVVM** pattern.

### Layer Structure

```
cdev/
├── App/                    # DI Container, AppState, Entry Point
├── Core/                   # Utilities, Extensions, Design System
│   ├── Design/            # Colors, Typography, Gradients
│   ├── Extensions/        # View, String, Date extensions
│   ├── Utilities/         # Constants, Spacing, Haptics, Logger
│   ├── Errors/            # AppError types
│   └── Security/          # Atomic wrapper
├── Domain/                 # Business Logic (Pure Swift)
│   ├── Models/            # AgentEvent, AgentCommand, ConnectionInfo
│   ├── Interfaces/        # Protocol definitions
│   └── UseCases/          # Business logic orchestration
├── Data/                   # External Adapters
│   ├── Services/          # WebSocket, HTTP, Keychain, Cache
│   └── Repositories/      # AgentRepository, SessionRepository
└── Presentation/           # UI Layer (SwiftUI + ViewModels)
    ├── Common/Components/ # Reusable UI components
    ├── Navigation/        # RootView, navigation logic
    └── Screens/           # Dashboard, LogViewer, DiffViewer, Pairing
```

### Dependency Flow

```
Presentation → Domain ← Data
              ↓
             Core
```

### Key Patterns

1. **DependencyContainer** (Service Locator) - Single source for all dependencies
2. **@MainActor ViewModels** - Thread-safe UI state management
3. **AsyncStream** - Real-time event streaming from WebSocket
4. **Protocol-based interfaces** - Enables testing and flexibility

## cdev-agent API Communication

### Architecture: HTTP + WebSocket Hybrid

| Operation | Protocol | Endpoint | Reason |
|-----------|----------|----------|--------|
| Run Claude | HTTP POST | `/api/claude/run` | Command with response confirmation |
| Stop Claude | HTTP POST | `/api/claude/stop` | Command with response confirmation |
| Respond to Claude | HTTP POST | `/api/claude/respond` | Interactive response |
| List Sessions | HTTP GET | `/api/claude/sessions` | Data fetch |
| Get Session Messages | HTTP GET | `/api/claude/sessions/messages?session_id=` | History loading |
| Get Status | HTTP GET | `/api/status` | Initial status |
| Get Git Status | HTTP GET | `/api/git/status` | File changes |
| **Real-time logs** | WebSocket | Event stream | Streaming output |
| **Status changes** | WebSocket | Event stream | Push notifications |
| **Permissions** | WebSocket | Event stream | Interactive prompts |

### Session Modes for `/api/claude/run`

```json
// Start new conversation
{"prompt": "Hello", "mode": "new"}

// Continue most recent conversation (no session_id)
{"prompt": "Follow up", "mode": "continue"}

// Continue specific session (with session_id) - RECOMMENDED
{"prompt": "Follow up", "mode": "continue", "session_id": "uuid"}

// Resume specific session by ID
{"prompt": "Continue", "mode": "resume", "session_id": "uuid"}
```

**Best Practice:** Use `mode: "continue"` with `session_id` for explicit session context. The app tracks sessionId from events and passes it automatically.

### WebSocket Events

Events streamed via WebSocket (`ws://host:port/ws`):

| Event Type | Description |
|------------|-------------|
| `claude_log` | Claude CLI output (stdout/stderr) |
| `claude_status` | State changes (idle, running, waiting) |
| `claude_waiting` | Claude asking a question |
| `claude_permission` | Permission request (tool use) |
| `git_diff` | File change with diff content |
| `file_changed` | File modified notification |
| `session_end` | Claude session ended |

### Performance Optimizations

1. **Optimistic UI** - Clear input immediately, show user message before API response
2. **HTTP for commands** - Stateless, reliable, doesn't depend on WebSocket state
3. **WebSocket for streaming** - Low latency push for real-time logs
4. **Background history loading** - Don't block UI on app launch
5. **Continue mode** - Let Claude CLI manage session, no manual tracking

## UI Design Principles

**CRITICAL: Compact UI is HIGH PRIORITY**

This app is designed for developers doing "vibe coding" on mobile - monitoring Claude while away from desk. Every UI element must be as compact as possible while remaining functional.

### Core Principles

1. **Compact First** - Minimize padding, use smaller fonts, single-line where possible
2. **Terminal First** - CLI output is the hero, not hidden
3. **Minimal Taps** - One-tap approve/deny, quick prompt input
4. **Information Density** - Show more data, less chrome
5. **Real-time** - Auto-scroll logs, instant updates
6. **Glanceable** - Status visible at all times

### Compact UI Guidelines

| Element | Guideline |
|---------|-----------|
| Padding | Use `Spacing.xs` (8pt) or smaller, avoid `Spacing.md`+ |
| Fonts | Prefer `Typography.terminal` (12pt) or `terminalSmall` (10pt) |
| Row height | Single line preferred, max 2 lines |
| Icons | 10-14pt, not larger |
| Timestamps | Compact format: "5m", "2h", "3d" not "5 minutes ago" |
| Lists | No separators between items, use subtle background changes |
| Sheets | Use `.presentationDetents([.medium, .large])` for adjustable height |

### UI Hierarchy

1. Status bar (connection + Claude state) - always visible
2. Interaction banner (permissions/questions) - appears when needed
3. Content area (logs/diffs) - swipeable tabs
4. Action bar (prompt input + stop button) - always visible

## Security Rules

**CRITICAL: Never log sensitive data**

```swift
// ✅ DO - Use AppLogger (removed in release)
AppLogger.log("Connected to agent")

// ❌ DON'T - Never use print()
print("Token: \(token)")  // VISIBLE in release builds!
```

**Never log:**
- Session tokens, API keys
- Server URLs with credentials
- User prompts (might contain secrets)
- File contents

## Code Style

### Naming

- ViewModels: `DashboardViewModel`, `PairingViewModel`
- Views: `DashboardView`, `LogListView`
- Use Cases: `SendPromptUseCase`, `ConnectToAgentUseCase`
- Services: `WebSocketService`, `HTTPService`

### SwiftUI

```swift
// Use @StateObject for ViewModels in Views
@StateObject var viewModel: DashboardViewModel

// Use @MainActor for ViewModels
@MainActor
final class DashboardViewModel: ObservableObject { }

// Use Typography enum for fonts
Text("Title").font(Typography.title2)

// Use Spacing enum for padding
.padding(Spacing.md)
```

### Async/Await

```swift
// Always use async/await, not completion handlers
func sendPrompt() async throws { }

// Use Task for UI actions
Button("Send") {
    Task { await viewModel.sendPrompt() }
}
```

## Git Commit Guidelines

**Do NOT commit or push unless explicitly asked.**

When asked to commit, use conventional format:
- `feat: add QR code scanning`
- `fix: handle WebSocket reconnection`
- `refactor: simplify DI container`
- `docs: update design notes`

Do not include Co-Authored-By lines.
