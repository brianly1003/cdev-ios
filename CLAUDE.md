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

## UI Design Principles

**CRITICAL: Compact UI for Developer Productivity**

This app is designed for developers doing "vibe coding" on mobile - monitoring Claude while away from desk.

### Core Principles

1. **Terminal First** - CLI output is the hero, not hidden
2. **Minimal Taps** - One-tap approve/deny, quick prompt input
3. **Information Density** - Show more, chrome less
4. **Real-time** - Auto-scroll logs, instant updates
5. **Glanceable** - Status visible at all times

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
