import Foundation

/// Unified chat message model for Terminal and History views
/// Supports both real-time WebSocket events (claude_message) and session history API
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let type: MessageType
    let sessionId: String?
    let model: String?
    let contentBlocks: [ContentBlock]
    let usage: TokenUsage?

    enum MessageType: String {
        case user
        case assistant
        case system
    }

    struct TokenUsage: Equatable {
        let inputTokens: Int
        let outputTokens: Int
    }

    /// Content block for structured rendering
    struct ContentBlock: Identifiable, Equatable {
        let id: String
        let type: BlockType
        let content: String
        let toolName: String?
        let toolInput: String?
        let isError: Bool

        enum BlockType: String {
            case text
            case thinking
            case toolUse = "tool_use"
            case toolResult = "tool_result"
        }

        init(
            id: String = UUID().uuidString,
            type: BlockType,
            content: String,
            toolName: String? = nil,
            toolInput: String? = nil,
            isError: Bool = false
        ) {
            self.id = id
            self.type = type
            self.content = content
            self.toolName = toolName
            self.toolInput = toolInput
            self.isError = isError
        }
    }

    /// Primary text content (combined text blocks)
    var textContent: String {
        if type == .user {
            return contentBlocks
                .filter { $0.type == .text || $0.type == .toolResult }
                .map { $0.content }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        }

        return contentBlocks
            .filter { $0.type == .text }
            .map { $0.content }
            .joined(separator: "\n")
    }

    /// Tool use blocks only
    var toolBlocks: [ContentBlock] {
        contentBlocks.filter { $0.type == .toolUse || $0.type == .toolResult }
    }

    /// Thinking blocks only
    var thinkingBlocks: [ContentBlock] {
        contentBlocks.filter { $0.type == .thinking }
    }

    /// Whether message has tool calls
    var hasToolCalls: Bool {
        !toolBlocks.isEmpty
    }

    /// Whether message has thinking content
    var hasThinking: Bool {
        !thinkingBlocks.isEmpty
    }
}

// MARK: - Factory Methods

extension ChatMessage {
    /// Create from claude_message WebSocket event payload
    static func from(payload: ClaudeMessagePayload) -> ChatMessage? {
        guard let uuid = payload.uuid,
              let message = payload.message,
              payload.messageKind != .meta else { return nil }

        // Parse timestamp
        let timestamp: Date
        if let timestampStr = payload.timestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: timestampStr) ?? Date()
        } else {
            timestamp = Date()
        }

        // Parse message type
        let messageType: MessageType
        switch payload.type ?? message.role ?? "assistant" {
        case "user": messageType = .user
        case "assistant": messageType = .assistant
        default: messageType = .system
        }

        // Parse content blocks
        var blocks: [ContentBlock] = []
        if let content = message.content {
            switch content {
            case .text(let text):
                blocks.append(ContentBlock(type: .text, content: text))

            case .blocks(let contentBlocks):
                for block in contentBlocks {
                    let blockType: ContentBlock.BlockType
                    switch block.type {
                    case "text": blockType = .text
                    case "thinking": blockType = .thinking
                    case "tool_use": blockType = .toolUse
                    case "tool_result": blockType = .toolResult
                    default: blockType = .text
                    }

                    // Format tool input as string
                    var toolInputStr: String?
                    if let input = block.input {
                        let pairs = input.map { "\($0.key): \($0.value.stringValue)" }
                        toolInputStr = pairs.joined(separator: "\n")
                    }

                    let normalizedBlockType: ContentBlock.BlockType =
                        (messageType == .user && blockType == .toolResult) ? .text : blockType

                    blocks.append(ContentBlock(
                        id: block.blockId ?? UUID().uuidString,
                        type: normalizedBlockType,
                        content: block.text ?? block.content ?? "",
                        toolName: block.name,
                        toolInput: toolInputStr,
                        isError: block.isError ?? false
                    ))
                }
            }
        }

        return ChatMessage(
            id: uuid,
            timestamp: timestamp,
            type: messageType,
            sessionId: payload.sessionId,
            model: message.model,
            contentBlocks: blocks,
            usage: nil  // WebSocket events don't include usage
        )
    }

    /// Create from session message (history API)
    static func from(sessionMessage: SessionMessagesResponse.SessionMessage) -> ChatMessage {
        // Parse timestamp
        let timestamp: Date
        if let timestampStr = sessionMessage.timestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: timestampStr) ?? Date()
        } else {
            timestamp = Date()
        }

        // Parse message type
        let messageType: MessageType
        switch sessionMessage.type {
        case "user": messageType = .user
        case "assistant": messageType = .assistant
        default: messageType = .system
        }

        // Parse content blocks
        var blocks: [ContentBlock] = []
        if let content = sessionMessage.message.content {
            switch content {
            case .string(let text):
                blocks.append(ContentBlock(type: .text, content: text))

            case .blocks(let contentBlocks):
                for block in contentBlocks {
                    let blockType: ContentBlock.BlockType
                    switch block.type {
                    case "text": blockType = .text
                    case "thinking": blockType = .thinking
                    case "tool_use": blockType = .toolUse
                    case "tool_result": blockType = .toolResult
                    default: blockType = .text
                    }

                    // For tool_use, use block.id; for tool_result, use block.toolUseId
                    let blockId = block.id ?? block.toolUseId ?? UUID().uuidString

                    // Format tool input as string for display
                    var toolInputStr: String?
                    if let input = block.input {
                        let pairs = input.map { "\($0.key): \($0.value.stringValue)" }
                        toolInputStr = pairs.joined(separator: "\n")
                    }

                    let normalizedBlockType: ContentBlock.BlockType =
                        (messageType == .user && blockType == .toolResult) ? .text : blockType

                    blocks.append(ContentBlock(
                        id: blockId,
                        type: normalizedBlockType,
                        content: block.text ?? block.content ?? "",
                        toolName: block.name,
                        toolInput: toolInputStr,
                        isError: block.isError ?? false
                    ))
                }
            }
        }

        // Parse token usage
        var usage: TokenUsage?
        if let msgUsage = sessionMessage.message.usage,
           let input = msgUsage.inputTokens,
           let output = msgUsage.outputTokens {
            usage = TokenUsage(inputTokens: input, outputTokens: output)
        }

        return ChatMessage(
            id: sessionMessage.id,
            timestamp: timestamp,
            type: messageType,
            sessionId: sessionMessage.sessionId,
            model: sessionMessage.message.model,
            contentBlocks: blocks,
            usage: usage
        )
    }

    /// Create user message (for optimistic UI)
    static func userMessage(content: String, sessionId: String? = nil) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            timestamp: Date(),
            type: .user,
            sessionId: sessionId,
            model: nil,
            contentBlocks: [ContentBlock(type: .text, content: content)],
            usage: nil
        )
    }
}
