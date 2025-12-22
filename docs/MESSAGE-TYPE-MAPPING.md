# Message Type Mapping

This document describes how cdev-agent JSON-RPC messages map to iOS app `ElementContent` types for Terminal display.

## Message Structure Overview

Messages from `session/messages` API have this structure:

```json
{
  "id": 11751,
  "session_id": "uuid",
  "type": "assistant",        // "user" or "assistant"
  "uuid": "message-uuid",
  "timestamp": "2025-12-22T03:14:37.482Z",
  "git_branch": "main",
  "message": {
    "model": "claude-opus-4-5-20251101",  // Only for assistant
    "role": "assistant",                   // "user" or "assistant"
    "content": [...]                       // Array of content blocks
  }
}
```

## Content Block Types

Each message contains a `content` array with one or more blocks. Each block has a `type` field that determines how it maps to iOS `ElementContent`.

### 1. Text Block → `assistantText` / `userInput`

**JSON Structure:**
```json
{
  "type": "text",
  "text": "All tests pass. Here's a summary..."
}
```

**iOS Mapping:**
- If `role == "assistant"` → `ElementContent.assistantText(AssistantTextContent)`
- If `role == "user"` → `ElementContent.userInput(UserInputContent)`

**View:** `AssistantTextElementView` / `UserInputElementView`

---

### 2. Thinking Block → `thinking`

**JSON Structure:**
```json
{
  "type": "thinking",
  "thinking": "Let me analyze this code...",
  "signature": "base64-signature..."
}
```

**iOS Mapping:** `ElementContent.thinking(ThinkingContent)`

**View:** `ThinkingElementView` (collapsible brain icon)

---

### 3. Tool Use Block → `toolCall` / `editDiff`

**JSON Structure:**
```json
{
  "type": "tool_use",
  "id": "toolu_01WsXSkUTbZZEMNZH8bzDsVy",
  "name": "Bash",
  "input": {
    "command": "go test ./...",
    "description": "Run all tests"
  }
}
```

**iOS Mapping:**
- If `name == "Edit"` with `old_string` and `new_string` → `ElementContent.editDiff(EditDiffContent)`
- Otherwise → `ElementContent.toolCall(ToolCallContent)`

**View:** `ToolCallElementView` / `EditDiffElementView`

#### Tool Types and Display

| Tool Name | Input Fields | Display |
|-----------|-------------|---------|
| `Bash` | `command`, `description` | `Bash(command)` |
| `Read` | `file_path`, `offset`, `limit` | `Read(file_path)` |
| `Write` | `file_path`, `content` | `Write(file_path)` |
| `Edit` | `file_path`, `old_string`, `new_string` | Diff view with +/- lines |
| `Glob` | `pattern`, `path` | `Glob(pattern: "...")` |
| `Grep` | `pattern`, `path` | `Grep(pattern: "...")` |
| `TodoWrite` | `todos` | `TodoWrite(...)` |

---

### 4. Tool Result Block → `toolResult`

**JSON Structure:**
```json
{
  "tool_use_id": "toolu_01WsXSkUTbZZEMNZH8bzDsVy",
  "type": "tool_result",
  "content": "=== RUN TestSessionMessageJSON\n--- PASS...",
  "is_error": false
}
```

**iOS Mapping:** `ElementContent.toolResult(ToolResultContent)`

**View:** `ToolResultElementView` (collapsible output with preview)

**Note:** Tool results appear in **user** messages (role="user") as responses to assistant tool_use blocks.

---

## Message Flow Example

A typical tool execution flow:

```
1. assistant: thinking → "Let me run the tests"
2. assistant: tool_use → Bash("go test ./...")
3. user:      tool_result → "PASS: TestSessionMessageJSON..."
4. assistant: thinking → "All tests pass"
5. assistant: text → "Here's a summary of the changes..."
```

## iOS Element Types Summary

| ElementType | Source Block | Role | View |
|-------------|--------------|------|------|
| `userInput` | `text` | user | `UserInputElementView` |
| `assistantText` | `text` | assistant | `AssistantTextElementView` |
| `toolCall` | `tool_use` | assistant | `ToolCallElementView` |
| `toolResult` | `tool_result` | user | `ToolResultElementView` |
| `editDiff` | `tool_use` (Edit) | assistant | `EditDiffElementView` |
| `thinking` | `thinking` | assistant | `ThinkingElementView` |
| `diff` | git_diff event | - | `DiffElementView` |
| `interrupted` | interrupt event | - | `InterruptedElementView` |
| `contextCompaction` | compaction event | - | `ContextCompactionElementView` |

## Special Cases

### Edit Tool → Diff Display

When `tool_use.name == "Edit"`, the app creates an `EditDiffContent` that computes a visual diff:

```json
{
  "type": "tool_use",
  "name": "Edit",
  "input": {
    "file_path": "/path/to/file.go",
    "old_string": "expectedFields := []string{\"session_id\"}",
    "new_string": "expectedFields := []string{\"session_id\", \"is_meta\"}"
  }
}
```

**Display:**
```
● Update(.../file.go)     Added 16 lines, removed 2 lines
  238 - expectedFields := []string{"session_id"}
  238 + expectedFields := []string{"session_id", "is_meta"}
```

### Context Compaction

When `is_context_compaction: true` on a message:

```json
{
  "type": "user",
  "is_context_compaction": true,
  "message": {
    "role": "user",
    "content": [{ "type": "text", "text": "Summary of conversation..." }]
  }
}
```

**iOS Mapping:** `ElementContent.contextCompaction(ContextCompactionContent)`

### Caveat Messages (Filtered)

Messages starting with "Caveat: The messages below were generated by the user..." are internal Claude Code messages and are filtered out (not displayed).

## Parsing Code Location

- **ChatElement.swift**: `ChatElement.from(payload:)` - Main parsing logic
- **AgentEvent.swift**: `ClaudeMessagePayload`, `ContentBlock` - Data models
- **ElementView.swift**: All `*ElementView` structs - UI rendering
