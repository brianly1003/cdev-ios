import Foundation

// MARK: - Element Types (matching Elements API spec)

/// UI Element types from cdev-agent Elements API
/// These map directly to SwiftUI view components
enum ElementType: String, Codable {
    case userInput = "user_input"
    case assistantText = "assistant_text"
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case diff = "diff"
    case thinking = "thinking"
    case interrupted = "interrupted"
    case contextCompaction = "context_compaction"  // Claude Code context window compacted
}

/// Tool execution status
enum ToolStatus: String, Codable {
    case running
    case completed
    case error
    case interrupted
}

/// Diff line type for syntax highlighting (Elements API specific)
/// Note: Different from DiffLineType in DiffEntry.swift which uses addition/deletion
enum ElementDiffLineType: String, Codable, Equatable {
    case context
    case added
    case removed
}

// MARK: - Chat Element

/// UI-ready element for Terminal/Chat view
/// Matches the Elements API structure for future compatibility
struct ChatElement: Codable, Identifiable, Equatable {
    let id: String
    let type: ElementType
    let timestamp: Date
    let content: ElementContent

    init(id: String = UUID().uuidString, type: ElementType, timestamp: Date = Date(), content: ElementContent) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case id, type, timestamp, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.type = try container.decode(ElementType.self, forKey: .type)

        // Parse timestamp
        if let timestampStr = try? container.decode(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.timestamp = formatter.date(from: timestampStr) ?? Date()
        } else {
            self.timestamp = Date()
        }

        // Decode content based on type
        self.content = try ElementContent.decode(from: container, type: self.type)
    }
}

// MARK: - Element Content

/// Union type for element content
enum ElementContent: Codable, Equatable {
    case userInput(UserInputContent)
    case assistantText(AssistantTextContent)
    case toolCall(ToolCallContent)
    case toolResult(ToolResultContent)
    case diff(DiffContent)
    case thinking(ThinkingContent)
    case interrupted(InterruptedContent)
    case contextCompaction(ContextCompactionContent)

    static func decode(from container: KeyedDecodingContainer<ChatElement.CodingKeys>, type: ElementType) throws -> ElementContent {
        let nestedDecoder = try container.superDecoder(forKey: .content)

        switch type {
        case .userInput:
            return .userInput(try UserInputContent(from: nestedDecoder))
        case .assistantText:
            return .assistantText(try AssistantTextContent(from: nestedDecoder))
        case .toolCall:
            return .toolCall(try ToolCallContent(from: nestedDecoder))
        case .toolResult:
            return .toolResult(try ToolResultContent(from: nestedDecoder))
        case .diff:
            return .diff(try DiffContent(from: nestedDecoder))
        case .thinking:
            return .thinking(try ThinkingContent(from: nestedDecoder))
        case .interrupted:
            return .interrupted(try InterruptedContent(from: nestedDecoder))
        case .contextCompaction:
            return .contextCompaction(try ContextCompactionContent(from: nestedDecoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .userInput(let content): try container.encode(content)
        case .assistantText(let content): try container.encode(content)
        case .toolCall(let content): try container.encode(content)
        case .toolResult(let content): try container.encode(content)
        case .diff(let content): try container.encode(content)
        case .thinking(let content): try container.encode(content)
        case .interrupted(let content): try container.encode(content)
        case .contextCompaction(let content): try container.encode(content)
        }
    }
}

// MARK: - Content Types

struct UserInputContent: Codable, Equatable {
    let text: String
}

struct AssistantTextContent: Codable, Equatable {
    let text: String
    let model: String?

    init(text: String, model: String? = nil) {
        self.text = text
        self.model = model
    }
}

struct ToolCallContent: Codable, Equatable {
    let tool: String
    let toolId: String?
    let display: String
    let params: [String: String]
    var status: ToolStatus
    var durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case tool
        case toolId = "tool_id"
        case display
        case params
        case status
        case durationMs = "duration_ms"
    }

    init(tool: String, toolId: String? = nil, display: String, params: [String: String] = [:], status: ToolStatus = .running, durationMs: Int? = nil) {
        self.tool = tool
        self.toolId = toolId
        self.display = display
        self.params = params
        self.status = status
        self.durationMs = durationMs
    }
}

struct ToolResultContent: Codable, Equatable {
    let toolCallId: String
    let toolName: String
    let isError: Bool
    let errorCode: Int?
    let summary: String
    let fullContent: String
    let lineCount: Int
    let expandable: Bool
    let truncated: Bool

    enum CodingKeys: String, CodingKey {
        case toolCallId = "tool_call_id"
        case toolName = "tool_name"
        case isError = "is_error"
        case errorCode = "error_code"
        case summary
        case fullContent = "full_content"
        case lineCount = "line_count"
        case expandable
        case truncated
    }

    init(
        toolCallId: String,
        toolName: String,
        isError: Bool = false,
        errorCode: Int? = nil,
        summary: String,
        fullContent: String,
        lineCount: Int? = nil,
        expandable: Bool = true,
        truncated: Bool = false
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.isError = isError
        self.errorCode = errorCode
        self.summary = summary
        self.fullContent = fullContent
        self.lineCount = lineCount ?? max(1, fullContent.components(separatedBy: "\n").count)
        self.expandable = expandable
        self.truncated = truncated
    }
}

struct DiffContent: Codable, Equatable {
    let toolCallId: String
    let filePath: String
    let summary: DiffSummary
    let hunks: [ElementDiffHunk]

    enum CodingKeys: String, CodingKey {
        case toolCallId = "tool_call_id"
        case filePath = "file_path"
        case summary
        case hunks
    }
}

struct DiffSummary: Codable, Equatable {
    let added: Int
    let removed: Int
    let display: String
}

struct ElementDiffHunk: Codable, Equatable, Identifiable {
    var id: String { header }

    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [ElementDiffLine]

    enum CodingKeys: String, CodingKey {
        case header
        case oldStart = "old_start"
        case oldCount = "old_count"
        case newStart = "new_start"
        case newCount = "new_count"
        case lines
    }
}

struct ElementDiffLine: Codable, Equatable, Identifiable {
    var id: String { "\(oldLine ?? 0)-\(newLine ?? 0)-\(content.hashValue)" }

    let type: ElementDiffLineType
    let oldLine: Int?
    let newLine: Int?
    let content: String

    enum CodingKeys: String, CodingKey {
        case type
        case oldLine = "old_line"
        case newLine = "new_line"
        case content
    }
}

struct ThinkingContent: Codable, Equatable {
    let text: String
    var collapsed: Bool

    init(text: String, collapsed: Bool = true) {
        self.text = text
        self.collapsed = collapsed
    }
}

struct InterruptedContent: Codable, Equatable {
    let toolCallId: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case toolCallId = "tool_call_id"
        case message
    }
}

/// Context compaction content - shown when Claude Code compacts conversation
/// This is auto-generated when context window reaches limit
struct ContextCompactionContent: Codable, Equatable {
    let summary: String       // The auto-generated summary text
    var isExpanded: Bool      // Whether to show full summary

    init(summary: String, isExpanded: Bool = false) {
        self.summary = summary
        self.isExpanded = isExpanded
    }
}

// MARK: - Factory Methods

extension ChatElement {
    /// Create from user prompt
    static func userInput(_ text: String) -> ChatElement {
        ChatElement(
            type: .userInput,
            content: .userInput(UserInputContent(text: text))
        )
    }

    /// Create from assistant text
    static func assistantText(_ text: String, model: String? = nil) -> ChatElement {
        ChatElement(
            type: .assistantText,
            content: .assistantText(AssistantTextContent(text: text, model: model))
        )
    }

    /// Create from tool call
    static func toolCall(
        tool: String,
        toolId: String? = nil,
        display: String,
        params: [String: String] = [:],
        status: ToolStatus = .running
    ) -> ChatElement {
        ChatElement(
            type: .toolCall,
            content: .toolCall(ToolCallContent(
                tool: tool,
                toolId: toolId,
                display: display,
                params: params,
                status: status
            ))
        )
    }

    /// Create from tool result
    static func toolResult(
        toolCallId: String,
        toolName: String,
        isError: Bool = false,
        summary: String,
        fullContent: String
    ) -> ChatElement {
        ChatElement(
            type: .toolResult,
            content: .toolResult(ToolResultContent(
                toolCallId: toolCallId,
                toolName: toolName,
                isError: isError,
                summary: summary,
                fullContent: fullContent
            ))
        )
    }

    /// Create thinking element
    static func thinking(_ text: String) -> ChatElement {
        ChatElement(
            type: .thinking,
            content: .thinking(ThinkingContent(text: text))
        )
    }

    /// Create context compaction element
    static func contextCompaction(summary: String) -> ChatElement {
        ChatElement(
            type: .contextCompaction,
            content: .contextCompaction(ContextCompactionContent(summary: summary))
        )
    }

    /// Create from ClaudeMessagePayload (WebSocket event)
    /// Supports both cdev-agent format (content at payload level) and API format (content in message)
    static func from(payload: ClaudeMessagePayload) -> [ChatElement] {
        var elements: [ChatElement] = []

        // Use unified accessors for role and content
        let effectiveRole = payload.effectiveRole
        guard let effectiveContent = payload.effectiveContent else { return elements }

        // Get model from message if available
        let model = payload.message?.model

        // Parse timestamp
        let timestamp: Date
        if let timestampStr = payload.timestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: timestampStr) ?? Date()
        } else {
            timestamp = Date()
        }

        // User message - simple text
        if effectiveRole == "user" {
            let text = effectiveContent.textContent
            if !text.isEmpty {
                elements.append(ChatElement(
                    id: payload.uuid ?? UUID().uuidString,
                    type: .userInput,
                    timestamp: timestamp,
                    content: .userInput(UserInputContent(text: text))
                ))
            }
            return elements
        }

        // Assistant message - may have multiple content blocks
        let baseId = payload.uuid ?? UUID().uuidString

        switch effectiveContent {
        case .text(let text):
            if !text.isEmpty {
                elements.append(ChatElement(
                    id: "\(baseId)-text-0",
                    type: .assistantText,
                    timestamp: timestamp,
                    content: .assistantText(AssistantTextContent(text: text, model: model))
                ))
            }

        case .blocks(let blocks):
            for (index, block) in blocks.enumerated() {
                let blockId = block.effectiveId

                switch block.type {
                case "text":
                    if let text = block.text, !text.isEmpty {
                        // Use baseId + index for unique ID (text blocks may not have unique IDs)
                        let textId = "\(baseId)-text-\(index)"
                        elements.append(ChatElement(
                            id: textId,
                            type: .assistantText,
                            timestamp: timestamp,
                            content: .assistantText(AssistantTextContent(text: text, model: model))
                        ))
                    }

                case "thinking":
                    if let text = block.text, !text.isEmpty {
                        // Use baseId + index for unique ID
                        let thinkingId = "\(baseId)-thinking-\(index)"
                        elements.append(ChatElement(
                            id: thinkingId,
                            type: .thinking,
                            timestamp: timestamp,
                            content: .thinking(ThinkingContent(text: text))
                        ))
                    }

                case "tool_use":
                    // Use unified accessors for tool name and input
                    let toolName = block.effectiveName ?? "tool"
                    var params: [String: String] = [:]
                    if let input = block.effectiveInput {
                        for (key, value) in input {
                            params[key] = value.stringValue
                        }
                    }

                    // Create display string
                    let display = formatToolDisplay(tool: toolName, params: params)

                    elements.append(ChatElement(
                        id: blockId,
                        type: .toolCall,
                        timestamp: timestamp,
                        content: .toolCall(ToolCallContent(
                            tool: toolName,
                            toolId: block.effectiveId,
                            display: display,
                            params: params,
                            status: .completed
                        ))
                    ))

                case "tool_result":
                    let resultContent = block.content ?? block.text ?? ""
                    let isError = block.isError ?? false
                    let lines = resultContent.components(separatedBy: "\n")
                    let summary = lines.prefix(3).joined(separator: "\n")

                    // Use tool_use_id + "-result" suffix to avoid collision with tool_use element
                    let toolResultId = (block.toolUseId ?? blockId) + "-result"

                    elements.append(ChatElement(
                        id: toolResultId,
                        type: .toolResult,
                        timestamp: timestamp,
                        content: .toolResult(ToolResultContent(
                            toolCallId: block.toolUseId ?? "",
                            toolName: block.effectiveName ?? "tool",
                            isError: isError,
                            summary: summary,
                            fullContent: resultContent
                        ))
                    ))

                default:
                    break
                }
            }
        }

        return elements
    }

    /// Create from LogEntry (legacy format)
    /// Note: claude_log events are plain text - we preserve them as-is without aggressive pattern matching
    static func from(logEntry: LogEntry) -> ChatElement {
        let text = logEntry.content

        // Only detect user input (starts with > or ❯ prompt)
        if logEntry.stream == .user || text.hasPrefix("> ") || text.hasPrefix("❯ ") {
            let userText = text
                .trimmingCharacters(in: CharacterSet.whitespaces)
                .replacingOccurrences(of: "^[>❯]\\s*", with: "", options: .regularExpression)
            return ChatElement(
                id: logEntry.id,
                type: .userInput,
                timestamp: logEntry.timestamp,
                content: .userInput(UserInputContent(text: userText))
            )
        }

        // Stderr goes as error/tool result
        if logEntry.stream == .stderr {
            return ChatElement(
                id: logEntry.id,
                type: .toolResult,
                timestamp: logEntry.timestamp,
                content: .toolResult(ToolResultContent(
                    toolCallId: "",
                    toolName: "",
                    isError: true,
                    summary: text,
                    fullContent: text
                ))
            )
        }

        // System messages
        if logEntry.stream == .system {
            return ChatElement(
                id: logEntry.id,
                type: .assistantText,
                timestamp: logEntry.timestamp,
                content: .assistantText(AssistantTextContent(text: text))
            )
        }

        // Default: treat as assistant text (plain stdout from claude_log)
        // Don't try to parse tool calls from plain text - that's for structured claude_message events
        return ChatElement(
            id: logEntry.id,
            type: .assistantText,
            timestamp: logEntry.timestamp,
            content: .assistantText(AssistantTextContent(text: text))
        )
    }
}

// MARK: - Helper Functions

private func formatToolDisplay(tool: String, params: [String: String]) -> String {
    switch tool {
    case "Bash":
        if let cmd = params["command"] {
            let truncated = cmd.count > 60 ? String(cmd.prefix(60)) + "..." : cmd
            return "\(tool)(\(truncated))"
        }
    case "Read", "Write":
        if let path = params["file_path"] {
            return "\(tool)(\(path))"
        }
    case "Edit":
        if let path = params["file_path"] {
            return "\(tool)(\(path))"
        }
    case "Glob", "Grep":
        if let pattern = params["pattern"] {
            return "\(tool)(pattern: \"\(pattern)\")"
        }
    default:
        break
    }

    // Generic fallback
    let paramStr = params.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    if paramStr.isEmpty {
        return tool
    }
    return "\(tool)(\(paramStr.prefix(50)))"
}

private func extractToolCall(from text: String) -> (tool: String, params: [String: String])? {
    // Pattern: ● ToolName(params) or ToolName(params)
    let pattern = #"●?\s*(\w+)\(([^)]*)\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
        return nil
    }

    let toolRange = Range(match.range(at: 1), in: text)!
    let tool = String(text[toolRange])

    let paramsRange = Range(match.range(at: 2), in: text)!
    let paramsStr = String(text[paramsRange])

    // Simple param extraction
    var params: [String: String] = [:]
    if tool == "Bash" {
        params["command"] = paramsStr
    } else if tool == "Read" || tool == "Write" || tool == "Edit" {
        params["file_path"] = paramsStr
    } else {
        params["args"] = paramsStr
    }

    return (tool, params)
}
