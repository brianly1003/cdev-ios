# cdev-ios Architecture

> Technical architecture documentation for the cdev-ios mobile client

---

## Overview

cdev-ios is an iOS client for cdev-agent that enables developers to monitor and interact with Claude Code CLI sessions from mobile devices. The architecture prioritizes:

1. **Real-time Communication** - WebSocket for streaming, HTTP for commands
2. **Connection Stability** - Robust handling of network changes and app lifecycle
3. **Performance** - Debounced updates to prevent UI lag
4. **Clean Architecture** - Separation of concerns with MVVM pattern

---

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ DashboardView│  │ LogListView │  │ DiffListView│   ...   │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                  │
│  ┌──────▼──────────────────────────────────▼──────┐         │
│  │              DashboardViewModel                 │         │
│  │   @Published logs, diffs, connectionState      │         │
│  └──────────────────┬─────────────────────────────┘         │
└─────────────────────┼───────────────────────────────────────┘
                      │
┌─────────────────────┼───────────────────────────────────────┐
│                     │      Domain Layer                      │
│  ┌──────────────────▼──────────────────┐                    │
│  │           Use Cases                  │                    │
│  │  SendPromptUseCase                   │                    │
│  │  RespondToClaudeUseCase              │                    │
│  └──────────────────┬──────────────────┘                    │
│                     │                                        │
│  ┌──────────────────▼──────────────────┐                    │
│  │           Protocols                  │                    │
│  │  AgentRepositoryProtocol             │                    │
│  │  WebSocketServiceProtocol            │                    │
│  │  HTTPServiceProtocol                 │                    │
│  └─────────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
                      │
┌─────────────────────┼───────────────────────────────────────┐
│                     │       Data Layer                       │
│  ┌──────────────────▼──────────────────┐                    │
│  │         AgentRepository              │                    │
│  │  - Coordinates HTTP + WebSocket      │                    │
│  │  - Manages connection state          │                    │
│  └───────┬─────────────────┬───────────┘                    │
│          │                 │                                 │
│  ┌───────▼───────┐ ┌───────▼───────┐                        │
│  │ WebSocketService│ │ HTTPService  │                        │
│  │  - Event stream │ │ - REST calls │                        │
│  │  - Heartbeats   │ │ - Commands   │                        │
│  └───────────────┘ └───────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Communication Architecture

### Hybrid Protocol Strategy

cdev-ios uses a **hybrid HTTP + WebSocket** approach for reliability:

| Operation | Protocol | Rationale |
|-----------|----------|-----------|
| Run/Stop Claude | HTTP POST | Command needs response confirmation |
| Respond to prompts | HTTP POST | Critical action, must not be lost |
| List sessions | HTTP GET | Standard data fetch |
| Get session messages | HTTP GET | History loading |
| **Real-time logs** | WebSocket | Low-latency streaming |
| **Status updates** | WebSocket | Push notifications |
| **Permissions** | WebSocket | Interactive prompts |
| **Heartbeats** | WebSocket | Connection health monitoring |

### Why Hybrid?

1. **HTTP for Commands**: Stateless, reliable, works even during WebSocket reconnection
2. **WebSocket for Streaming**: Low latency for real-time log output
3. **Decoupled Failure**: HTTP continues working if WebSocket drops temporarily

---

## WebSocket Stability Architecture

### Connection State Machine

```
                    ┌──────────────┐
                    │ Disconnected │◄─────────────────┐
                    └──────┬───────┘                  │
                           │ connect()                │
                           ▼                          │
                    ┌──────────────┐                  │
                    │  Connecting  │──────────────────┤
                    └──────┬───────┘                  │
                           │ onOpen                   │ timeout/error
                           ▼                          │
                    ┌──────────────┐                  │
           ┌───────►│  Connected   │─────────────────►│
           │        └──────┬───────┘                  │
           │               │                          │
           │               │ network change /         │
           │               │ heartbeat timeout /      │
           │               │ app background           │
           │               ▼                          │
           │        ┌──────────────┐                  │
           └────────│ Reconnecting │──────────────────┘
                    └──────────────┘
                           │
                    exponential backoff
                    1s → 2s → 4s → 8s → 16s → 30s (max)
```

### Stability Features

#### 1. Heartbeat Monitoring

The server sends heartbeat events every **30 seconds**. The client tracks activity:

```swift
// WebSocketService.swift
private var lastActivityTime: Date?

// Updated on ANY received message (not just heartbeats)
private func handleMessage(_ text: String) {
    lastActivityTime = Date()
    // ... process message
}

// Check every 45 seconds for activity timeout
private func startHeartbeatCheckTimer() {
    // If no activity in 45s, trigger reconnection
    if let lastActivity = lastActivityTime,
       Date().timeIntervalSince(lastActivity) > Constants.Network.heartbeatTimeout {
        scheduleReconnect()
    }
}
```

**Key Insight**: Track ANY message activity, not just heartbeat events, because:
- Server starts heartbeat from server start time, not connection time
- Other events (logs, status) also indicate healthy connection

#### 2. Network Change Detection

Uses `NWPathMonitor` to detect WiFi ↔ Cellular transitions:

```swift
// WebSocketService.swift
private var networkMonitor: NWPathMonitor?

private func startNetworkMonitoring() {
    networkMonitor = NWPathMonitor()
    networkMonitor?.pathUpdateHandler = { [weak self] path in
        if path.status == .satisfied {
            // Network available - attempt reconnect if needed
            self?.scheduleReconnect()
        } else {
            // Network lost - mark disconnected
            self?.updateState(.disconnected)
        }
    }
    networkMonitor?.start(queue: .global(qos: .utility))
}
```

#### 3. App Lifecycle Handling

Handles iOS background/foreground transitions via `scenePhase`:

```swift
// cdevApp.swift
@Environment(\.scenePhase) private var scenePhase

.onChange(of: scenePhase) { _, newPhase in
    switch newPhase {
    case .active:
        container.webSocketService.handleAppDidBecomeActive()
    case .background:
        container.webSocketService.handleAppWillResignActive()
    default:
        break
    }
}
```

```swift
// WebSocketService.swift
func handleAppDidBecomeActive() {
    // Check if reconnection needed after background
    if connectionState != .connected {
        scheduleReconnect(delay: 0.5)  // Small delay for network to stabilize
    }
}

func handleAppWillResignActive() {
    // Stop timers (iOS may kill them in background anyway)
    stopTimers()
}
```

#### 4. Exponential Backoff

Prevents server hammering during outages:

```swift
private func calculateBackoffDelay() -> TimeInterval {
    // Exponential: 1s, 2s, 4s, 8s, 16s, 30s (max)
    let delay = min(
        pow(2.0, Double(reconnectAttempt)) * Constants.Network.reconnectDelay,
        Constants.Network.maxReconnectDelay
    )
    return delay
}
```

---

## HTTP Service Configuration

### Adaptive Timeouts

Different timeouts for local vs remote (dev tunnel) connections:

```swift
// HTTPService.swift
private var isRemoteConnection: Bool {
    guard let host = baseURL?.host else { return false }
    return host != "localhost" &&
           host != "127.0.0.1" &&
           !host.hasPrefix("192.168.")
}

// Local: 30s, Remote: 120s
let timeout = isLocal
    ? Constants.Network.requestTimeoutLocal
    : Constants.Network.requestTimeout
```

### Retry Logic

Automatic retry for transient network errors:

```swift
// Retryable error codes
let retryableCodes: Set<Int> = [
    NSURLErrorNetworkConnectionLost,     // -1005
    NSURLErrorNotConnectedToInternet,    // -1009
    NSURLErrorTimedOut,                  // -1001
    NSURLErrorCannotConnectToHost,       // -1004
    NSURLErrorCannotFindHost,            // -1003
]

// Exponential backoff: 1s, 2s, 4s (local) or 2s, 4s, 8s (remote)
```

---

## Performance Optimizations

### 1. Debounced UI Updates

Rapid log events can block the main thread. Solution: coalesce updates:

```swift
// DashboardViewModel.swift
private var logUpdateScheduled = false

private func scheduleLogUpdate() {
    guard !logUpdateScheduled else { return }  // Skip if update pending
    logUpdateScheduled = true

    Task { [weak self] in
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        guard let self = self else { return }
        self.logUpdateScheduled = false
        self.logs = await self.logCache.getAll()  // Single batch update
    }
}
```

**Result**: Multiple rapid events coalesce into single UI update every 100ms.

### 2. Race Condition Prevention

Initial load could trigger parallel API calls. Solution: guard flags:

```swift
// DashboardViewModel.swift
private var isInitialLoadInProgress = false
private var hasCompletedInitialLoad = false

private func loadRecentSessionHistory() async {
    guard !isInitialLoadInProgress else { return }  // Prevent duplicate
    isInitialLoadInProgress = true

    defer {
        isInitialLoadInProgress = false
        hasCompletedInitialLoad = true
    }

    // ... load history
}

func refreshStatus() async {
    // Only refresh git status if initial load is done
    if hasCompletedInitialLoad {
        await refreshGitStatus()
    }
}
```

### 3. Optimistic UI

Show user actions immediately, don't wait for server:

```swift
func sendPrompt() async {
    let userMessage = promptText
    promptText = ""  // Clear immediately

    // Add to UI before API call
    let userEntry = LogEntry(content: "> \(userMessage)", stream: .user)
    await logCache.add(userEntry)
    await forceLogUpdate()  // Immediate update for user action

    // Then make API call
    try await sendPromptUseCase.execute(...)
}
```

---

## Session Management

### Session Flow

```
App Launch
    │
    ▼
┌─────────────────────────────────┐
│ Check connection state          │
│ If connected → load history     │
│ If not → wait for connection    │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│ GET /api/claude/sessions        │
│ → Get list of available sessions│
│ → Find current or most recent   │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│ GET /api/claude/sessions/messages│
│ → Load message history          │
│ → Convert to LogEntries         │
│ → Display in terminal view      │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│ WebSocket streams new events    │
│ → claude_log events appended    │
│ → sessionId captured from events│
└─────────────────────────────────┘
```

### Session Modes

```swift
// POST /api/claude/run
{
    "prompt": "...",
    "mode": "new"       // Start new session
}

{
    "prompt": "...",
    "mode": "continue", // Continue session
    "session_id": "uuid"
}
```

### Built-in Commands

| Command | Action |
|---------|--------|
| `/resume` | Show session picker |
| `/new` | Start fresh conversation |
| `/clear` | Clear logs and start new |
| `/help` | Show available commands |

---

## Caching Architecture

### Log Cache

```swift
actor LogCache {
    private var entries: [LogEntry] = []
    private let maxEntries = 1000  // FIFO eviction

    func add(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst()
        }
    }

    func getAll() -> [LogEntry] {
        return entries
    }
}
```

### Diff Cache

```swift
actor DiffCache {
    private var entries: [String: DiffEntry] = [:]  // Keyed by file path

    func add(_ entry: DiffEntry) {
        entries[entry.path] = entry  // Overwrites existing
    }
}
```

---

## Event Handling

### WebSocket Event Types

| Event | Payload | Action |
|-------|---------|--------|
| `heartbeat` | server_time, sequence | Update lastActivityTime |
| `claude_log` | line, stream, session_id | Append to log cache |
| `claude_status` | state, session_id | Update Claude state |
| `claude_waiting` | question, options, request_id | Show question banner |
| `claude_permission` | tool, description, request_id | Show permission banner |
| `git_diff` | file, diff, additions, deletions | Add to diff cache |
| `file_changed` | path, change | Update diff cache |
| `session_end` | session_id | Mark session complete |
| `error` | message, code | Show error alert |

### Event Processing Flow

```
WebSocket Message
        │
        ▼
┌───────────────────┐
│ Update lastActivity│
│ (any message)      │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Parse JSON to     │
│ AgentEvent        │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Emit to eventStream│
│ (AsyncStream)      │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ DashboardViewModel│
│ handleEvent()     │
│ - Update state    │
│ - Schedule UI     │
└───────────────────┘
```

---

## Dependency Injection

### DependencyContainer

```swift
@MainActor
final class DependencyContainer: ObservableObject {
    // Services (singletons)
    let webSocketService: WebSocketServiceProtocol
    let httpService: HTTPServiceProtocol
    let keychainService: KeychainServiceProtocol

    // Repositories
    let agentRepository: AgentRepositoryProtocol

    // Use Cases
    let sendPromptUseCase: SendPromptUseCase
    let respondToClaudeUseCase: RespondToClaudeUseCase

    // Caches
    let logCache: LogCache
    let diffCache: DiffCache

    init() {
        // Wire up dependencies...
    }
}
```

### ViewModels

ViewModels receive dependencies via constructor injection:

```swift
@MainActor
final class DashboardViewModel: ObservableObject {
    init(
        webSocketService: WebSocketServiceProtocol,
        agentRepository: AgentRepositoryProtocol,
        sendPromptUseCase: SendPromptUseCase,
        respondToClaudeUseCase: RespondToClaudeUseCase,
        logCache: LogCache,
        diffCache: DiffCache
    ) { ... }
}
```

---

## Constants Reference

```swift
struct Constants {
    struct Network {
        static let connectionTimeout: TimeInterval = 30
        static let requestTimeout: TimeInterval = 120      // Remote
        static let requestTimeoutLocal: TimeInterval = 30  // Local
        static let heartbeatTimeout: TimeInterval = 45
        static let pingInterval: TimeInterval = 30
        static let reconnectDelay: TimeInterval = 1
        static let maxReconnectDelay: TimeInterval = 30
        static let maxReconnectAttempts = 10
        static let httpMaxRetries = 3
        static let httpRetryDelay: TimeInterval = 0.5
    }
}
```

---

## Logging

All logs are **DEBUG only** (removed in release builds):

```swift
enum AppLogger {
    static func log(_ message: String, type: LogType = .info)
    static func network(_ message: String, type: LogType = .info)
    static func webSocket(_ message: String, type: LogType = .info)  // Prefixed with [WS]
    static func ui(_ message: String, type: LogType = .info)
    static func error(_ error: Error, context: String? = nil)
}
```

**Security**: Never log sensitive data (tokens, passwords, user prompts with secrets).

---

## Testing Considerations

### Protocol-Based Design

All services implement protocols, enabling test doubles:

```swift
protocol WebSocketServiceProtocol: AnyObject {
    var connectionState: ConnectionState { get }
    var connectionStateStream: AsyncStream<ConnectionState> { get }
    var eventStream: AsyncStream<AgentEvent> { get }
    func connect(host: String, httpPort: Int?, wsPort: Int?) async throws
    func disconnect()
    func handleAppDidBecomeActive()
    func handleAppWillResignActive()
}
```

### Actor-Based Caches

Caches use Swift actors for thread-safe testing:

```swift
actor LogCache {
    func add(_ entry: LogEntry)
    func getAll() -> [LogEntry]
    func clear()
}
```

---

## Related Documentation

- [CLAUDE.md](../CLAUDE.md) - Development guidelines
- [DESIGN-SPEC.md](DESIGN-SPEC.md) - UI/UX specifications
- [cdev-agent API Reference](https://github.com/brianly1003/cdev-agent/docs/API-REFERENCE.md)
