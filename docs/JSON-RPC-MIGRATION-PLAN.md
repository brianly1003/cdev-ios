# JSON-RPC 2.0 Migration Plan for cdev-ios

**Version**: 1.0
**Created**: December 2025
**Status**: Planning

## Executive Summary

This document outlines the migration strategy for cdev-ios from the current hybrid HTTP REST + WebSocket protocol to the new unified JSON-RPC 2.0 protocol implemented in cdev-agent.

### Key Benefits
- **Unified Transport**: Single WebSocket connection for all operations
- **Standard Protocol**: JSON-RPC 2.0 is widely supported and well-documented
- **Capability Negotiation**: MCP-inspired `initialize` handshake
- **Better Error Handling**: Standardized error codes and messages
- **Future-Proof**: Supports multi-agent architecture (Claude, Gemini, Codex)

---

## 1. Protocol Comparison

### Current Protocol (HTTP + WebSocket)

| Operation | Transport | Endpoint |
|-----------|-----------|----------|
| Run Claude | HTTP POST | `/api/claude/run` |
| Stop Claude | HTTP POST | `/api/claude/stop` |
| Respond | HTTP POST | `/api/claude/respond` |
| Get Status | HTTP GET | `/api/status` |
| Get Sessions | HTTP GET | `/api/claude/sessions` |
| Git Status | HTTP GET | `/api/git/status` |
| Git Diff | HTTP GET | `/api/git/diff?path=...` |
| Get File | HTTP GET | `/api/file?path=...` |
| Real-time events | WebSocket | Event stream |

### New JSON-RPC 2.0 Protocol

| Operation | Method | Transport |
|-----------|--------|-----------|
| Initialize | `initialize` | WebSocket |
| Run Agent | `agent/run` | WebSocket |
| Stop Agent | `agent/stop` | WebSocket |
| Respond | `agent/respond` | WebSocket |
| Get Status | `status/get` | WebSocket |
| Git Status | `git/status` | WebSocket |
| Git Diff | `git/diff` | WebSocket |
| Get File | `file/get` | WebSocket |
| List Sessions | `session/list` | WebSocket |
| Watch Session | `session/watch` | WebSocket |
| Unwatch Session | `session/unwatch` | WebSocket |
| Real-time events | Notifications | WebSocket |

---

## 2. JSON-RPC 2.0 Message Formats

### Request Format
```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "method": "agent/run",
  "params": {
    "prompt": "Fix the bug",
    "mode": "new"
  }
}
```

### Response Format
```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "result": {
    "status": "started",
    "session_id": "sess_abc123",
    "agent_type": "claude"
  }
}
```

### Error Response Format
```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "error": {
    "code": -32001,
    "message": "An agent is already running"
  }
}
```

### Notification Format (Server → Client, no response expected)
```json
{
  "jsonrpc": "2.0",
  "method": "claude_log",
  "params": {
    "line": "Analyzing codebase...",
    "stream": "stdout"
  }
}
```

---

## 3. Method Mapping

### Current → New Method Mapping

| Current HTTP/WS | New JSON-RPC Method | Notes |
|-----------------|---------------------|-------|
| POST `/api/claude/run` | `agent/run` | Supports `agent_type` param |
| POST `/api/claude/stop` | `agent/stop` | No params |
| POST `/api/claude/respond` | `agent/respond` | Same payload structure |
| GET `/api/status` | `status/get` | Response format same |
| GET `/api/git/status` | `git/status` | No params |
| GET `/api/git/diff?path=X` | `git/diff` | `path` in params |
| GET `/api/file?path=X` | `file/get` | `path` in params |
| GET `/api/claude/sessions` | `session/list` | `limit` param |
| WS `watch_session` | `session/watch` | `session_id` param |
| WS `unwatch_session` | `session/unwatch` | No params |
| - (new) | `initialize` | Capability negotiation |

### Event Type Mapping (Notifications)

| Current Event Type | New Notification Method | Changes |
|--------------------|------------------------|---------|
| `claude_log` | `claude_log` | Same |
| `claude_status` | `claude_status` | Same |
| `claude_waiting` | `claude_waiting` | Same |
| `claude_permission` | `claude_permission` | Same |
| `claude_session_info` | `claude_session_info` | Same |
| `file_changed` | `file_changed` | Same |
| `git_diff` | `git_diff` | Same |
| `session_start` | `session_start` | Same |
| `session_end` | `session_end` | Same |
| `error` | `error` | Same |
| `heartbeat` | `heartbeat` | Same |

---

## 4. Implementation Plan

### Phase 1: Core JSON-RPC Infrastructure

**New Files to Create:**

1. **`cdev/Data/Services/JSONRPC/JSONRPCMessage.swift`**
   - Request, Response, Notification, Error types
   - ID handling (string or int)
   - Encoding/decoding

2. **`cdev/Data/Services/JSONRPC/JSONRPCClient.swift`**
   - Request/response correlation
   - Pending request tracking
   - Timeout handling
   - Notification dispatch

3. **`cdev/Data/Services/JSONRPC/JSONRPCError.swift`**
   - Standard error codes (-32700 to -32600)
   - Custom error codes (-32001 to -32012)

### Phase 2: WebSocket Service Refactor

**Modify:**

1. **`WebSocketService.swift`**
   - Change message handling to detect JSON-RPC format
   - Route responses to pending request handlers
   - Route notifications to event stream
   - Add `initialize` method call on connect

**New Connection Flow:**
```
connect()
  ↓
WebSocket connected
  ↓
Send initialize request
  ↓
Receive initialize response
  ↓
connectionState = .connected(with capabilities)
```

### Phase 3: Command Refactor

**Modify:**

1. **`AgentCommand.swift`**
   - Keep domain model as-is
   - Add method to convert to JSON-RPC request

2. **`AgentRepository.swift`**
   - Replace HTTP calls with JSON-RPC requests
   - Use WebSocket for all operations
   - Keep HTTP as fallback for health checks only

### Phase 4: Backward Compatibility Layer

**For Gradual Migration:**

1. **Protocol Version Detection**
   - Try `initialize` on connect
   - If fails, fall back to current protocol
   - Store capability flags

2. **Dual-Mode Operation**
   - Feature flag: `useJSONRPC: Bool`
   - Can toggle between protocols for testing

---

## 5. New Swift Types

### JSONRPCMessage.swift

```swift
// JSON-RPC 2.0 Version
let jsonRPCVersion = "2.0"

// Request ID (string or int)
enum JSONRPCID: Codable, Hashable {
    case string(String)
    case number(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let num = try? container.decode(Int.self) {
            self = .number(num)
        } else {
            throw DecodingError.typeMismatch(JSONRPCID.self, ...)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        }
    }
}

// JSON-RPC Request
struct JSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc: String = jsonRPCVersion
    let id: JSONRPCID?
    let method: String
    let params: Params?
}

// JSON-RPC Response
struct JSONRPCResponse<Result: Decodable>: Decodable {
    let jsonrpc: String
    let id: JSONRPCID?
    let result: Result?
    let error: JSONRPCError?
}

// JSON-RPC Notification (no id, no response)
struct JSONRPCNotification<Params: Decodable>: Decodable {
    let jsonrpc: String
    let method: String
    let params: Params?
}

// JSON-RPC Error
struct JSONRPCError: Decodable {
    let code: Int
    let message: String
    let data: AnyCodable?  // Optional additional data
}
```

### JSONRPCClient.swift

```swift
actor JSONRPCClient {
    private var pendingRequests: [String: CheckedContinuation<Data, Error>] = [:]
    private var requestCounter: Int = 0
    private let webSocket: WebSocketServiceProtocol

    func request<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params?
    ) async throws -> Result {
        let id = nextRequestId()
        let request = JSONRPCRequest(id: id, method: method, params: params)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id.stringValue] = continuation

            Task {
                do {
                    try await webSocket.send(request)
                } catch {
                    pendingRequests.removeValue(forKey: id.stringValue)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func handleMessage(_ data: Data) {
        // Check if response (has id) or notification (no id)
        if let response = try? JSONDecoder().decode(JSONRPCResponse<AnyCodable>.self, from: data),
           let id = response.id,
           let continuation = pendingRequests.removeValue(forKey: id.stringValue) {
            continuation.resume(returning: data)
        } else {
            // It's a notification - route to event stream
            notificationHandler?(data)
        }
    }
}
```

---

## 6. API Method Implementations

### Initialize

```swift
struct InitializeParams: Encodable {
    let clientInfo: ClientInfo?
    let capabilities: [String: AnyCodable]?

    struct ClientInfo: Encodable {
        let name: String
        let version: String
    }
}

struct InitializeResult: Decodable {
    let serverInfo: ServerInfo
    let capabilities: ServerCapabilities

    struct ServerInfo: Decodable {
        let name: String
        let version: String
    }

    struct ServerCapabilities: Decodable {
        let agents: [String]
        let features: [String]
    }
}

// Usage
let result: InitializeResult = try await rpcClient.request(
    method: "initialize",
    params: InitializeParams(
        clientInfo: .init(name: "cdev-ios", version: "1.0.0"),
        capabilities: [:]
    )
)
```

### Agent Run

```swift
struct AgentRunParams: Encodable {
    let prompt: String
    let mode: String?       // "new" or "continue"
    let sessionId: String?  // for continue mode
    let agentType: String?  // "claude", "gemini", "codex"

    enum CodingKeys: String, CodingKey {
        case prompt, mode
        case sessionId = "session_id"
        case agentType = "agent_type"
    }
}

struct AgentRunResult: Decodable {
    let status: String
    let sessionId: String
    let agentType: String

    enum CodingKeys: String, CodingKey {
        case status
        case sessionId = "session_id"
        case agentType = "agent_type"
    }
}

// Usage
let result: AgentRunResult = try await rpcClient.request(
    method: "agent/run",
    params: AgentRunParams(prompt: "Fix the bug", mode: "new", sessionId: nil, agentType: nil)
)
```

### Status Get

```swift
struct StatusResult: Decodable {
    let sessionId: String?
    let agentSessionId: String?
    let agentState: String
    let agentType: String?
    let connectedClients: Int
    let repoPath: String
    let repoName: String
    let uptimeSeconds: Int
    let version: String
    let watcherEnabled: Bool
    let gitEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agentSessionId = "agent_session_id"
        case agentState = "agent_state"
        case agentType = "agent_type"
        case connectedClients = "connected_clients"
        case repoPath = "repo_path"
        case repoName = "repo_name"
        case uptimeSeconds = "uptime_seconds"
        case version
        case watcherEnabled = "watcher_enabled"
        case gitEnabled = "git_enabled"
    }
}

// Usage
let status: StatusResult = try await rpcClient.request(method: "status/get", params: nil as Empty?)
```

---

## 7. Error Code Reference

### Standard JSON-RPC Errors

| Code | Message | Description |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON |
| -32600 | Invalid Request | Invalid JSON-RPC structure |
| -32601 | Method not found | Unknown method |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Server internal error |

### cdev Custom Errors

| Code | Message | When |
|------|---------|------|
| -32001 | An agent is already running | `agent/run` when busy |
| -32002 | No agent is currently running | `agent/stop` when idle |
| -32003 | Agent execution error | Runtime error |
| -32004 | Agent type not configured | Unsupported agent |
| -32010 | Requested file not found | `file/get` missing file |
| -32011 | Git operation failed | Git error |
| -32012 | Session not found | Invalid session ID |

---

## 8. Migration Checklist

### Phase 1: Infrastructure (Core Types)
- [ ] Create `JSONRPCMessage.swift` with all message types
- [ ] Create `JSONRPCError.swift` with error codes
- [ ] Create `JSONRPCClient.swift` actor for request management
- [ ] Add unit tests for encoding/decoding

### Phase 2: WebSocket Integration
- [ ] Add JSON-RPC message detection in `WebSocketService`
- [ ] Implement request/response correlation
- [ ] Add `initialize` call on connect
- [ ] Route notifications to event stream
- [ ] Update connection state with capabilities

### Phase 3: Repository Refactor
- [ ] Update `runClaude()` to use `agent/run`
- [ ] Update `stopClaude()` to use `agent/stop`
- [ ] Update `respondToClaude()` to use `agent/respond`
- [ ] Update `fetchStatus()` to use `status/get`
- [ ] Update `getGitStatus()` to use `git/status`
- [ ] Update `getGitDiff()` to use `git/diff`
- [ ] Update `getFile()` to use `file/get`
- [ ] Update session methods to use `session/*`

### Phase 4: Event Handling
- [ ] Update event parsing for notification format
- [ ] Keep event payload structures (same format)
- [ ] Test all event types work correctly

### Phase 5: HTTP Fallback (Optional)
- [ ] Keep HTTP for health check only
- [ ] Remove other HTTP endpoints
- [ ] Simplify HTTPService

### Phase 6: Testing & Validation
- [ ] Integration tests with real server
- [ ] Connection stability tests
- [ ] Reconnection handling tests
- [ ] Error handling tests
- [ ] Performance comparison

---

## 9. Rollout Strategy

### Option A: Feature Flag (Recommended)

```swift
// In Settings or Environment
var useJSONRPC: Bool = false

// In AgentRepository
if AppSettings.useJSONRPC {
    try await rpcClient.request(method: "agent/run", params: params)
} else {
    try await httpService.post("/api/claude/run", body: request)
}
```

**Benefits:**
- Safe rollback if issues
- A/B testing capability
- Gradual rollout to users

### Option B: Server Version Detection

```swift
// On connect, check server version
let capabilities = try await initialize()
if capabilities.features.contains("jsonrpc") {
    // Use JSON-RPC
} else {
    // Use legacy HTTP
}
```

**Benefits:**
- Automatic detection
- Works with mixed server versions
- No manual flag needed

### Option C: Hard Switch

Remove HTTP code entirely, require JSON-RPC server.

**Benefits:**
- Cleanest codebase
- No dual-path maintenance

**Risks:**
- Breaking change
- Requires server update first

---

## 10. Estimated Effort

| Phase | Complexity | Files | Estimated Days |
|-------|------------|-------|----------------|
| Phase 1: Core Types | Medium | 3 new | 1-2 |
| Phase 2: WebSocket | High | 1 modify | 2-3 |
| Phase 3: Repository | Medium | 1 modify | 1-2 |
| Phase 4: Events | Low | 1 verify | 0.5 |
| Phase 5: HTTP Cleanup | Low | 1 modify | 0.5 |
| Phase 6: Testing | Medium | Tests | 2-3 |
| **Total** | | | **7-11 days** |

---

## 11. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking changes | High | Feature flag for rollback |
| Connection stability | Medium | Keep existing reconnection logic |
| Event timing | Medium | Thorough testing |
| Server compatibility | Medium | Version detection |
| Performance regression | Low | Benchmark before/after |

---

## 12. Open Questions

1. **Should HTTP be completely removed?**
   - Keep for health check only?
   - Remove entirely for cleaner code?

2. **Timeout handling for RPC requests?**
   - What timeout values?
   - Should different methods have different timeouts?

3. **Batch requests support?**
   - JSON-RPC supports batching
   - Useful for initial data load?

4. **Session history API?**
   - Current: `GET /api/claude/sessions/messages`
   - New protocol equivalent?

---

## Appendix A: Full OpenRPC Schema

See `/Users/brianly/Projects/cdev/api/openrpc/openrpc.json` for the complete API specification.

## Appendix B: Current Protocol Reference

See `CLAUDE.md` in cdev-ios for current HTTP endpoint documentation.
