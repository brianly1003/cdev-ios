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
│   ├── Design/            # Colors, Typography, Gradients, ResponsiveLayout
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
7. **Responsive** - Adapt layout for iPhone (compact) and iPad (regular)
8. **Scalable** - Support 100+ items in lists with search and grouping

### Compact UI Guidelines

| Element | Guideline |
|---------|-----------|
| Padding | Use `Spacing.xs` (8pt) or `Spacing.xxs` (4pt), avoid `Spacing.md`+ |
| Fonts | Prefer `Typography.terminal` (12pt) or `terminalSmall` (10pt) |
| Row height | Single line preferred, 28-36pt max height |
| Icons | 9-14pt, not larger |
| Timestamps | Compact format: "5m", "2h", "3d" not "5 minutes ago" |
| Lists | Use `LazyVStack` for performance, no separators, subtle backgrounds |
| Sheets | Use `.presentationDetents([.medium, .large])` for adjustable height |
| Status pills | 8pt monospace font, 3px border radius, minimal padding |

### Responsive Design (iPad/iPhone)

**CRITICAL: Use `ResponsiveLayout` for all new UI components**

The `ResponsiveLayout` system provides centralized, consistent sizing across iPhone and iPad. Always use it instead of manual `isCompact` checks.

```swift
// ✅ CORRECT - Use ResponsiveLayout
struct MyView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        HStack(spacing: layout.contentSpacing) {
            Image(systemName: "star")
                .font(.system(size: layout.iconMedium))

            Text("Title")
                .font(layout.bodyFont)
        }
        .padding(.horizontal, layout.standardPadding)
    }
}

// ❌ WRONG - Manual ternary expressions
.padding(.horizontal, isCompact ? 12 : 16)  // Use layout.standardPadding
.font(.system(size: isCompact ? 12 : 14))   // Use layout.iconMedium
```

**ResponsiveLayout Properties:**

| Category | Properties |
|----------|------------|
| Spacing | `smallPadding`, `standardPadding`, `largePadding`, `contentSpacing`, `sectionSpacing` |
| Icons | `iconSmall` (9/10), `iconMedium` (12/14), `iconLarge` (16/18), `iconXLarge` (24/28) |
| Components | `buttonHeight`, `indicatorSize`, `indicatorSizeSmall`, `dotSize`, `avatarSize` |
| Typography | `bodyFont`, `captionFont`, `labelFont`, `terminalFont` |
| Lines | `borderWidth`, `borderWidthThick`, `shadowRadius`, `shadowRadiusLarge` |

**Quick Reference:**
```swift
layout.standardPadding  // 12pt iPhone, 16pt iPad
layout.iconMedium       // 12pt iPhone, 14pt iPad
layout.indicatorSize    // 32pt iPhone, 36pt iPad
layout.bodyFont         // Typography.body iPhone, Typography.bodyBold iPad
```

See `docs/RESPONSIVE-LAYOUT.md` for full documentation and examples.

**Responsive Patterns:**
- iPhone: Sheets use full width, single-column layouts
- iPad: Side-by-side layouts, keyboard shortcut hints (⌘K)
- Both: Same components, different spacing/sizing via ResponsiveLayout

### Gesture Handling (Multi-Device)

**CRITICAL: Never use `.onTapGesture` on containers with interactive children**

SwiftUI's `.onTapGesture` blocks all taps from reaching child buttons. This causes inconsistent behavior between iPhone and iPad due to different touch handling and layout sizes.

```swift
// ❌ WRONG - Blocks button taps on containers
VStack {
    Text("Header")
    Button("Action") { doSomething() }  // May not receive taps!
}
.onTapGesture {
    dismissKeyboard()
}

// ✅ CORRECT - Use simultaneousGesture for keyboard dismissal
VStack {
    Text("Header")
    Button("Action") { doSomething() }  // Works correctly
}
.simultaneousGesture(
    TapGesture().onEnded { dismissKeyboard() }
)

// ✅ CORRECT - Use .onTapGesture only on leaf views without interactive children
Text("Tap me")
    .onTapGesture { selectItem() }

// ✅ CORRECT - Use Button instead of onTapGesture for interactive rows
Button {
    selectItem()
} label: {
    FileRowView(entry: entry)
}
.buttonStyle(.plain)
```

**When to use each approach:**

| Scenario | Approach |
|----------|----------|
| Keyboard dismissal on container | `.simultaneousGesture(TapGesture())` |
| Making a display-only view tappable | `.onTapGesture` |
| Row selection in lists | `Button` with `.buttonStyle(.plain)` |
| Backdrop dismiss (modal overlay) | `.onTapGesture` (no children) |
| Expand/collapse with buttons inside | `.simultaneousGesture(TapGesture())` |

**The `.dismissKeyboardOnTap()` modifier:**
Uses `.simultaneousGesture` internally - safe to use on any view.

### List Performance (100+ Items)

```swift
// ALWAYS use LazyVStack for lists that may grow
LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
    ForEach(items) { item in
        CompactRow(item: item)
    }
}

// Add search for any list > 10 items
@State private var searchText = ""
private var filteredItems: [Item] {
    guard !searchText.isEmpty else { return items }
    return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
}

// Group by category when multiple sources exist
private var groupedItems: [(category: String, items: [Item])] {
    Dictionary(grouping: filteredItems) { $0.category }
        .map { (category: $0.key, items: $0.value) }
        .sorted { $0.items.count > $1.items.count }
}
```

### UI Hierarchy

1. Status bar (connection + Claude state) - always visible
2. Interaction banner (permissions/questions) - appears when needed
3. Content area (logs/diffs) - swipeable tabs
4. Action bar (prompt input + stop button) - always visible

### Typography Consistency

**CRITICAL: Always use Typography constants - never hardcode fonts**

| Use Case | Typography Constant | Size |
|----------|-------------------|------|
| Page titles | `Typography.title2`, `title3` | System |
| Body text | `Typography.body` | System body |
| Bold body | `Typography.bodyBold` | System body semibold |
| Terminal output | `Typography.terminal` | 12pt mono |
| Small terminal | `Typography.terminalSmall` | 10pt mono |
| Timestamps | `Typography.terminalTimestamp` | 9pt mono |
| Status labels | `Typography.statusLabel` | 10pt rounded semibold |
| Badges/pills | `Typography.badge` | 9pt rounded bold |
| Tab labels | `Typography.tabLabel` | 11pt medium |
| Button labels | `Typography.buttonLabel` | 12pt semibold |
| Captions | `Typography.caption1`, `caption2` | System caption |
| Input fields | `Typography.inputField` | 13pt regular |

**Standard Icon Sizes (match typography):**
| Context | Size | Example |
|---------|------|---------|
| Section headers | 10pt | Settings section icons |
| Row icons | 14pt | Settings row icons |
| Inline icons | 11-12pt | Status indicators |
| Small badges | 8-9pt | Branch icons, chevrons |
| Large icons | 24-28pt | Empty state icons |

**Never use:**
- `.font(.body)` → use `Typography.body`
- `.font(.caption)` → use `Typography.caption1`
- `.font(.system(size: 12))` for text → use `Typography.terminal` or appropriate constant

### Theme Support (ColorSystem)

All colors MUST use `ColorSystem` - never hardcode colors:

```swift
// Backgrounds (dark terminal theme)
ColorSystem.terminalBg          // Main background
ColorSystem.terminalBgElevated  // Cards, sheets
ColorSystem.terminalBgHighlight // Hover, selected states

// Text hierarchy
ColorSystem.textPrimary         // Main content
ColorSystem.textSecondary       // Supporting text
ColorSystem.textTertiary        // Timestamps, hints
ColorSystem.textQuaternary      // Disabled, very subtle

// Semantic colors
ColorSystem.primary             // Actions, links
ColorSystem.success             // Connected, approved
ColorSystem.error               // Disconnected, denied
ColorSystem.warning             // Pending, caution

// Status colors
ColorSystem.Status.color(for: claudeState)  // Dynamic status
```

### Component Patterns

**Compact Row (single line, ~32pt height):**
```swift
HStack(spacing: Spacing.xs) {
    Image(systemName: "folder")
        .font(.system(size: 11))
        .foregroundStyle(ColorSystem.textTertiary)
        .frame(width: 16)

    Text(item.name)
        .font(Typography.body)
        .foregroundStyle(ColorSystem.textPrimary)
        .lineLimit(1)

    Spacer()

    Text(item.timestamp)
        .font(Typography.terminalSmall)
        .foregroundStyle(ColorSystem.textQuaternary)
}
.padding(.horizontal, Spacing.sm)
.padding(.vertical, Spacing.xs)
```

**Status Pill (ultra-compact badge):**
```swift
Text("ON")
    .font(.system(size: 8, weight: .bold, design: .monospaced))
    .foregroundStyle(ColorSystem.success)
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(ColorSystem.success.opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 3))
```

**Search Bar:**
```swift
HStack(spacing: Spacing.xs) {
    Image(systemName: "magnifyingglass")
        .font(.system(size: 14))
        .foregroundStyle(ColorSystem.textTertiary)

    TextField("Search...", text: $searchText)
        .font(Typography.body)
        .focused($isSearchFocused)
        .submitLabel(.search)

    if !text.isEmpty {
        Button { text = "" } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(ColorSystem.textTertiary)
        }
    }
}
.padding(Spacing.sm)
.background(ColorSystem.terminalBgElevated)
.clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
```

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

## Documentation

Additional documentation is available in the `docs/` folder:

| Document | Description |
|----------|-------------|
| `docs/RESPONSIVE-LAYOUT.md` | Complete guide to using ResponsiveLayout for iPhone/iPad |
| `docs/MULTI-DEVICE-BEST-PRACTICES.md` | Best practices for multi-device development (gestures, sheets, layouts) |
| `docs/MESSAGE-TYPE-MAPPING.md` | JSON-RPC message types to iOS ElementContent mapping |
| `docs/GIT-WORKSPACE-SETUP-DESIGN.md` | Git workspace setup wizard design document |

**Known Issues:** See `docs/issues/` folder for documented SwiftUI issues and solutions.

**Key Design System Files:**
- `cdev/Core/Design/ResponsiveLayout.swift` - Centralized responsive sizing
- `cdev/Core/Design/ColorSystem.swift` - Color palette
- `cdev/Core/Design/Typography.swift` - Font definitions
- `cdev/Core/Design/Animations.swift` - Animation presets
- `cdev/Core/Utilities/Spacing.swift` - Base spacing values
