import SwiftUI

/// Unified chat message view for Terminal and History
/// Renders messages with tool calls, thinking blocks, and token usage consistently
struct ChatMessageView: View {
    let message: ChatMessage
    let showTimestamp: Bool
    let runtime: AgentRuntime?
    @State private var isToolsExpanded = false
    @State private var isThinkingExpanded = false

    init(message: ChatMessage, showTimestamp: Bool = true, runtime: AgentRuntime? = nil) {
        self.message = message
        self.showTimestamp = showTimestamp
        self.runtime = runtime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Role header with timestamp
            HStack(spacing: Spacing.xs) {
                roleIndicator

                Spacer()

                if showTimestamp {
                    Text(formattedTime)
                        .font(Typography.terminalTimestamp)
                        .foregroundStyle(ColorSystem.textQuaternary)
                }
            }

            // Content based on message type
            switch message.type {
            case .user:
                UserContent(message: message)

            case .assistant:
                AssistantContent(
                    message: message,
                    isToolsExpanded: $isToolsExpanded,
                    isThinkingExpanded: $isThinkingExpanded
                )

            case .system:
                SystemContent(message: message)
            }
        }
        .padding(.vertical, Spacing.xs)
        .overlay(
            Rectangle()
                .fill(ColorSystem.terminalBgHighlight.opacity(0.5))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var roleIndicator: some View {
        switch message.type {
        case .user:
            HStack(spacing: 3) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                Text("you")
                    .font(Typography.terminalSmall)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(ColorSystem.Log.user)

        case .assistant:
            let agentColor = runtime.map { ColorSystem.Agent.color(for: $0) } ?? ColorSystem.primary
            let agentTint = runtime.map { ColorSystem.Agent.tint(for: $0) } ?? ColorSystem.primary.opacity(0.15)
            let agentIcon = runtime?.iconName ?? "sparkle"
            let agentLabel = runtime?.displayName.lowercased() ?? "claude"

            HStack(spacing: 3) {
                Image(systemName: agentIcon)
                    .font(.system(size: 8))
                Text(agentLabel)
                    .font(Typography.terminalSmall)
                    .fontWeight(.semibold)

                // Model badge
                if let model = message.model {
                    Text(shortModelName(model))
                        .font(Typography.badge)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(agentTint)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(agentColor)

        case .system:
            HStack(spacing: 3) {
                Image(systemName: "info.circle")
                    .font(.system(size: 8))
                Text("system")
                    .font(Typography.terminalSmall)
            }
            .foregroundStyle(ColorSystem.Log.system)
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: message.timestamp)
    }

    private func shortModelName(_ model: String) -> String {
        // Claude model names
        if model.contains("opus") { return "opus" }
        if model.contains("sonnet") { return "sonnet" }
        if model.contains("haiku") { return "haiku" }
        // Codex CLI model variants (gpt-5.x-codex-*) — preserve version + variant
        if model.contains("codex-spark") { return model.replacingOccurrences(of: "gpt-", with: "") }
        if model.contains("codex-mini") { return model.replacingOccurrences(of: "gpt-", with: "") }
        if model.contains("codex-max") { return model.replacingOccurrences(of: "gpt-", with: "") }
        if model.contains("codex") { return model.replacingOccurrences(of: "gpt-", with: "") }
        // Generic GPT-5 model names — strip "gpt-" prefix to save space
        if model.contains("gpt-5") { return model.replacingOccurrences(of: "gpt-", with: "") }
        if model.contains("o3-mini") { return "o3-mini" }
        if model.contains("o3") { return "o3" }
        if model.contains("o1") { return "o1" }
        if model.contains("gpt-4o") { return "4o" }
        if model.contains("gpt-4") { return "gpt-4" }
        // Truncate unknown long model names
        if model.count > 12 {
            return String(model.prefix(10)) + "..."
        }
        return model
    }
}

// MARK: - User Content

private struct UserContent: View {
    let message: ChatMessage

    var body: some View {
        contentView(for: UserInputElementView.parseBashTags(from: message.textContent))
    }

    @ViewBuilder
    private func contentView(for segs: [BashSegment]) -> some View {
        if segs.isEmpty {
            EmptyView()
        } else if segs.count == 1, case .text(let rawText) = segs[0], rawText == message.textContent {
            // Plain user text — no bash tags
            Text(message.textContent)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.Log.user)
                .textSelection(.enabled)
                .padding(.leading, Spacing.sm)
        } else {
            // Bash/command segments — render with CLI-style formatting
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                    segmentView(for: seg)
                }
            }
            .padding(.leading, Spacing.sm)
        }
    }

    @ViewBuilder
    private func segmentView(for segment: BashSegment) -> some View {
        switch segment {
        case .bashInput(let command):
            BashInputSegmentView(command: command)
        case .bashStdout(let output):
            BashOutputSegmentView(output: output, isError: false)
        case .bashStderr(let output):
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                BashOutputSegmentView(output: output, isError: true)
            }
        case .localCommandStdout(let output):
            LocalCommandOutputView(output: output)
        case .commandMessage(let name, let msg):
            CommandMessageView(name: name, message: msg)
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.Log.user)
                    .textSelection(.enabled)
            }
        case .noContent:
            BashNoContentView()
        }
    }
}

// MARK: - Assistant Content

private struct AssistantContent: View {
    let message: ChatMessage
    @Binding var isToolsExpanded: Bool
    @Binding var isThinkingExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Thinking section (collapsible)
            if message.hasThinking {
                ThinkingSection(
                    blocks: message.thinkingBlocks,
                    isExpanded: $isThinkingExpanded
                )
            }

            // Tool calls section (collapsible)
            if message.hasToolCalls {
                ToolCallsSection(
                    blocks: message.toolBlocks,
                    isExpanded: $isToolsExpanded
                )
            }

            // Text content
            if !message.textContent.isEmpty {
                Text(message.textContent)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.Log.stdout)
                    .textSelection(.enabled)
                    .padding(.leading, Spacing.sm)
            }

            // Token usage
            if let usage = message.usage {
                HStack(spacing: Spacing.xs) {
                    Spacer()
                    TokenBadge(label: "in", count: usage.inputTokens)
                    TokenBadge(label: "out", count: usage.outputTokens)
                }
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - System Content

private struct SystemContent: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 9))
                .foregroundStyle(ColorSystem.Log.system)

            Text(message.textContent)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.Log.system)
                .textSelection(.enabled)
        }
        .padding(.leading, Spacing.sm)
    }
}

// MARK: - Thinking Section

private struct ThinkingSection: View {
    let blocks: [ChatMessage.ContentBlock]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Toggle button
            Button {
                withAnimation(Animations.stateChange) {
                    isExpanded.toggle()
                }
                Haptics.selection()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))

                    Image(systemName: "brain")
                        .font(.system(size: 9))

                    Text("thinking")
                        .font(Typography.terminalSmall)
                }
                .foregroundStyle(ColorSystem.primary.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ColorSystem.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .padding(.leading, Spacing.sm)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(blocks) { block in
                        Text(block.content)
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textTertiary)
                            .italic()
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 4)
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.leading, Spacing.md)
            }
        }
    }
}

// MARK: - Tool Calls Section

private struct ToolCallsSection: View {
    let blocks: [ChatMessage.ContentBlock]
    @Binding var isExpanded: Bool

    private var toolCount: Int {
        blocks.filter { $0.type == .toolUse }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Toggle button
            Button {
                withAnimation(Animations.stateChange) {
                    isExpanded.toggle()
                }
                Haptics.selection()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))

                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 9))

                    Text("\(toolCount) tool\(toolCount == 1 ? "" : "s")")
                        .font(Typography.terminalSmall)
                }
                .foregroundStyle(ColorSystem.warning)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ColorSystem.warning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .padding(.leading, Spacing.sm)

            // Expanded tool details
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(blocks) { block in
                        ToolBlockView(block: block)
                    }
                }
                .padding(.leading, Spacing.md)
            }
        }
    }
}

// MARK: - Tool Block View

private struct ToolBlockView: View {
    let block: ChatMessage.ContentBlock
    @State private var showContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Tool header
            Button {
                withAnimation(Animations.stateChange) {
                    showContent.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showContent ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(ColorSystem.textQuaternary)

                    if block.type == .toolUse {
                        Text(block.toolName ?? "tool")
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.warning)
                    } else {
                        Image(systemName: block.isError ? "xmark.circle" : "checkmark.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(block.isError ? ColorSystem.error : ColorSystem.success)
                        Text("result")
                            .font(Typography.terminalSmall)
                            .foregroundStyle(block.isError ? ColorSystem.error : ColorSystem.success)
                    }
                }
            }
            .buttonStyle(.plain)

            // Content
            if showContent {
                let displayContent = block.type == .toolUse
                    ? toolUseDisplayContent
                    : block.content

                if !displayContent.isEmpty {
                    Text(displayContent.prefix(500) + (displayContent.count > 500 ? "..." : ""))
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                        .textSelection(.enabled)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 3)
                        .background(ColorSystem.terminalBgHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.leading, Spacing.sm)
                }
            }
        }
    }

    private var toolUseDisplayContent: String {
        let raw = block.toolInput ?? block.content
        guard let toolName = block.toolName?.lowercased() else { return raw }

        if toolName == "apply_patch" {
            return summarizeApplyPatch(raw)
        }

        return raw
    }

    private func summarizeApplyPatch(_ input: String) -> String {
        let patchStart = input.range(of: "*** Begin Patch")
        let patch = patchStart.map { String(input[$0.lowerBound...]) } ?? input

        struct PatchFileChange {
            var action: String
            var path: String
            var added: Int
            var removed: Int
        }

        var changes: [PatchFileChange] = []
        var current: PatchFileChange?

        func flushCurrent() {
            guard let current else { return }
            changes.append(current)
        }

        for line in patch.components(separatedBy: "\n") {
            if line.hasPrefix("*** Add File: ") {
                flushCurrent()
                current = PatchFileChange(
                    action: "Added",
                    path: String(line.dropFirst("*** Add File: ".count)).trimmingCharacters(in: .whitespaces),
                    added: 0,
                    removed: 0
                )
                continue
            }

            if line.hasPrefix("*** Update File: ") {
                flushCurrent()
                current = PatchFileChange(
                    action: "Updated",
                    path: String(line.dropFirst("*** Update File: ".count)).trimmingCharacters(in: .whitespaces),
                    added: 0,
                    removed: 0
                )
                continue
            }

            if line.hasPrefix("*** Delete File: ") {
                flushCurrent()
                current = PatchFileChange(
                    action: "Deleted",
                    path: String(line.dropFirst("*** Delete File: ".count)).trimmingCharacters(in: .whitespaces),
                    added: 0,
                    removed: 0
                )
                continue
            }

            guard var working = current else { continue }
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                working.added += 1
                current = working
                continue
            }

            if line.hasPrefix("-") && !line.hasPrefix("---") {
                working.removed += 1
                current = working
            }
        }

        flushCurrent()

        if changes.isEmpty {
            return "Applied patch"
        }

        return changes.map { change in
            if change.action == "Deleted" {
                return "\(change.action) \(change.path)"
            }
            return "\(change.action) \(change.path) (+\(change.added) -\(change.removed))"
        }.joined(separator: "\n")
    }
}

// MARK: - Token Badge

private struct TokenBadge: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(Typography.badge)
                .foregroundStyle(ColorSystem.textQuaternary)
            Text(formatTokenCount(count))
                .font(Typography.badge)
                .foregroundStyle(ColorSystem.textTertiary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(Capsule())
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count)"
    }
}
