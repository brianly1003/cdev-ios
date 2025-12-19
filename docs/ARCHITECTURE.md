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

## File Explorer Architecture

### Overview

The File Explorer tab allows users to browse repository source code remotely. It uses a **cache-first strategy** with lazy loading for performance.

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                   ExplorerView                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │BreadcrumbBar│  │DirectoryList│  │FileViewerView│         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         └────────────────┼────────────────┘                 │
│                          │                                   │
│                   ┌──────▼──────┐                           │
│                   │ExplorerViewModel│                        │
│                   │ - currentPath    │                       │
│                   │ - entries        │                       │
│                   │ - navigationStack│                       │
│                   └──────┬──────┘                           │
└──────────────────────────┼──────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────┐
│                          │      Data Layer                   │
│                   ┌──────▼──────┐                           │
│                   │FileRepository │                          │
│                   │ - useMockData │                          │
│                   └──────┬──────┘                           │
│                          │                                   │
│          ┌───────────────┼───────────────┐                  │
│   ┌──────▼──────┐                 ┌──────▼──────┐           │
│   │  FileCache   │                 │ HTTPService │           │
│   │ (Actor LRU)  │                 │  /api/...   │           │
│   │ 50 dirs      │                 │             │           │
│   │ 20 files     │                 │             │           │
│   └─────────────┘                 └─────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

### Caching Strategy

```swift
actor FileCache {
    // LRU cache limits
    let maxDirectories: Int = 50     // Cache 50 directory listings
    let maxContents: Int = 20        // Cache 20 file contents
    let maxContentSize: Int = 100_000 // Don't cache files > 100KB
}
```

| Operation | Cache Behavior |
|-----------|----------------|
| List directory | Check cache → API if miss → cache result |
| Read file | Check cache → API if miss → cache if < 100KB |
| Navigate back | Served from cache (instant) |
| Pull to refresh | Invalidate path → reload |

---

## File Explorer Backend API Integration

> **Status**: ✅ Fully Integrated with cdev-agent

The File Explorer uses the following cdev-agent Repository API endpoints:

### 1. Directory Listing Endpoint

**Endpoint**: `GET /api/repository/files/list`

**Query Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `directory` | string | No | Directory path. Empty = root directory |
| `limit` | int | No | Maximum results (default: 100, max: 1000) |
| `offset` | int | No | Pagination offset |
| `recursive` | bool | No | Include subdirectories (default: false) |
| `sort` | string | No | Sort by: `name`, `size`, `modified` |
| `order` | string | No | Sort order: `asc`, `desc` |

**Response** (200 OK):
```json
{
  "directory": "cdev/Domain/Models",
  "files": [
    {
      "path": "cdev/Domain/Models/AgentEvent.swift",
      "name": "AgentEvent.swift",
      "directory": "cdev/Domain/Models",
      "extension": "swift",
      "size_bytes": 12450,
      "modified_at": "2025-01-15T10:30:00Z",
      "is_binary": false,
      "is_sensitive": false,
      "git_tracked": true
    }
  ],
  "directories": [
    {
      "path": "cdev/Domain/Models/Interfaces",
      "name": "Interfaces",
      "file_count": 5,
      "total_size_bytes": 24680
    }
  ],
  "total_files": 8,
  "total_directories": 2,
  "pagination": {
    "limit": 100,
    "offset": 0,
    "has_more": false
  }
}
```

**Response Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `directory` | string | Current directory path |
| `files` | array | List of files in directory |
| `directories` | array | List of subdirectories |
| `total_files` | int | Total file count |
| `total_directories` | int | Total directory count |
| `pagination` | object | Pagination metadata |

**File Entry Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `path` | string | Full relative path |
| `name` | string | File name |
| `directory` | string | Parent directory |
| `extension` | string? | File extension |
| `size_bytes` | int64 | Size in bytes |
| `modified_at` | string? | ISO 8601 timestamp |
| `is_binary` | bool | Whether file is binary |
| `is_sensitive` | bool | Whether file contains secrets |
| `git_tracked` | bool | Whether tracked by git |

**Directory Entry Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `path` | string | Full relative path |
| `name` | string | Directory name |
| `file_count` | int | Number of files inside |
| `total_size_bytes` | int64 | Total size of contents |

**Error Responses**:
| Status | Description |
|--------|-------------|
| 503 | Repository indexer not available |

### 2. File Search Endpoint

**Endpoint**: `GET /api/repository/search`

**Query Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `q` | string | Yes | Search query |
| `mode` | string | No | `fuzzy`, `exact`, `prefix`, `extension` (default: fuzzy) |
| `limit` | int | No | Maximum results (default: 50, max: 500) |
| `exclude_binaries` | bool | No | Exclude binary files (default: true) |

**Response** (200 OK):
```json
{
  "query": "ViewModel",
  "mode": "fuzzy",
  "results": [
    {
      "path": "cdev/Presentation/Screens/Dashboard/DashboardViewModel.swift",
      "name": "DashboardViewModel.swift",
      "directory": "cdev/Presentation/Screens/Dashboard",
      "extension": "swift",
      "size_bytes": 15420,
      "match_score": 0.95
    }
  ],
  "total": 12,
  "elapsed_ms": 5
}
```

### 3. File Content Endpoint

**Endpoint**: `GET /api/file`

> Used by File Explorer to read file contents.

**Query Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | Yes | Relative file path |

**Response** (200 OK):
```json
{
  "path": "cdev/App/AppState.swift",
  "content": "import Foundation\n\n/// App state...",
  "encoding": "utf-8",
  "size": 5280,
  "truncated": false
}
```

### Backend Implementation Notes

#### Go Implementation Example

```go
// handlers/files.go

type FileEntry struct {
    Name          string  `json:"name"`
    Type          string  `json:"type"`            // "file" or "directory"
    Size          *int64  `json:"size,omitempty"`  // bytes, files only
    Modified      *string `json:"modified,omitempty"`
    ChildrenCount *int    `json:"children_count,omitempty"` // directories only
}

type DirectoryListingResponse struct {
    Path       string      `json:"path"`
    Entries    []FileEntry `json:"entries"`
    TotalCount int         `json:"total_count"`
}

func ListDirectory(w http.ResponseWriter, r *http.Request) {
    path := r.URL.Query().Get("path")

    // Security: Validate path is within repo root
    absPath := filepath.Join(repoRoot, path)
    if !strings.HasPrefix(absPath, repoRoot) {
        http.Error(w, "Path outside repository", http.StatusForbidden)
        return
    }

    // Read directory
    dirEntries, err := os.ReadDir(absPath)
    if err != nil {
        http.Error(w, "Directory not found", http.StatusNotFound)
        return
    }

    var entries []FileEntry
    for _, entry := range dirEntries {
        // Skip hidden files
        if strings.HasPrefix(entry.Name(), ".") {
            continue
        }

        info, _ := entry.Info()
        fe := FileEntry{
            Name: entry.Name(),
            Type: entryType(entry),
        }

        if entry.IsDir() {
            count := countChildren(filepath.Join(absPath, entry.Name()))
            fe.ChildrenCount = &count
        } else {
            size := info.Size()
            fe.Size = &size
        }

        if info != nil {
            mod := info.ModTime().Format(time.RFC3339)
            fe.Modified = &mod
        }

        entries = append(entries, fe)
    }

    // Sort: directories first, then alphabetically
    sort.Slice(entries, func(i, j int) bool {
        if entries[i].Type != entries[j].Type {
            return entries[i].Type == "directory"
        }
        return strings.ToLower(entries[i].Name) < strings.ToLower(entries[j].Name)
    })

    response := DirectoryListingResponse{
        Path:       path,
        Entries:    entries,
        TotalCount: len(entries),
    }

    json.NewEncoder(w).Encode(response)
}
```

#### Security Considerations

1. **Path Traversal Prevention**: Always validate resolved path is within repo root
2. **Hidden Files**: Filter out `.git`, `.DS_Store`, etc. by default
3. **Size Limits**: Consider limiting response to max 500 entries for large directories
4. **Symlink Handling**: Be cautious with symlinks that could escape repo

#### Performance Considerations

1. **Lazy Loading**: Only fetch directory when user navigates to it
2. **Parallel stat()**: Use goroutines for file info if directory has many files
3. **Pagination**: For very large directories (future enhancement)

### iOS Integration

The File Explorer is fully integrated via `DependencyContainer`:

```swift
// DependencyContainer.swift
lazy var fileRepository: FileRepositoryProtocol = FileRepository(
    httpService: httpService,
    cache: fileCache,
    useMockData: false  // Uses real cdev-agent API
)
```

**FileRepository Implementation:**

```swift
// FileRepository.swift
private func fetchRemoteDirectory(path: String) async throws -> [FileEntry] {
    var queryItems: [URLQueryItem] = []
    if !path.isEmpty {
        queryItems.append(URLQueryItem(name: "directory", value: path))
    }
    queryItems.append(URLQueryItem(name: "limit", value: "500"))

    let response: RepositoryFileListResponse = try await httpService.get(
        path: "/api/repository/files/list",
        queryItems: queryItems
    )

    // Combine directories and files
    var entries: [FileEntry] = []
    for dirDTO in response.directories {
        entries.append(FileEntry(from: dirDTO))
    }
    for fileDTO in response.files {
        entries.append(FileEntry(from: fileDTO))
    }
    return entries
}
```

**DTO Models:**

```swift
// Matches cdev-agent response format
struct RepositoryFileListResponse: Codable {
    let directory: String
    let files: [FileInfoDTO]
    let directories: [DirectoryInfoDTO]
    let totalFiles: Int
    let totalDirectories: Int
    let pagination: PaginationDTO
}

struct FileInfoDTO: Codable {
    let path: String
    let name: String
    let directory: String
    let ext: String?           // "extension" key
    let sizeBytes: Int64       // "size_bytes" key
    let modifiedAt: String?    // "modified_at" key
    let isBinary: Bool
    let isSensitive: Bool
    let gitTracked: Bool?
}

struct DirectoryInfoDTO: Codable {
    let path: String
    let name: String
    let fileCount: Int         // "file_count" key
    let totalSizeBytes: Int64  // "total_size_bytes" key
}
```

---

## Related Documentation

- [CLAUDE.md](../CLAUDE.md) - Development guidelines
- [DESIGN-SPEC.md](DESIGN-SPEC.md) - UI/UX specifications
- [cdev-agent API Reference](https://github.com/brianly1003/cdev-agent/docs/API-REFERENCE.md)
