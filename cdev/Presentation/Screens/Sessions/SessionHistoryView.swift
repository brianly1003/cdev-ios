import SwiftUI

/// Session History View - Claude Code CLI-style chat history viewer
/// Displays conversation messages in a terminal-like format with tool use blocks
struct SessionHistoryView: View {
    let session: SessionsResponse.SessionInfo
    let runtime: AgentRuntime
    let workspaceId: String?
    let onResume: (() -> Void)?
    @StateObject private var viewModel: SessionHistoryViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        session: SessionsResponse.SessionInfo,
        runtime: AgentRuntime,
        agentRepository: AgentRepositoryProtocol,
        workspaceId: String? = nil,
        onResume: (() -> Void)? = nil
    ) {
        self.session = session
        self.runtime = runtime
        self.workspaceId = workspaceId
        self.onResume = onResume
        _viewModel = StateObject(wrappedValue: SessionHistoryViewModel(
            sessionId: session.sessionId,
            runtime: runtime,
            workspaceId: workspaceId,
            agentRepository: agentRepository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Session header
            SessionHeaderView(session: session)

            // Messages content
            if viewModel.isLoading {
                LoadingStateView()
            } else if let _ = viewModel.error {
                ErrorStateView {
                    Task { await viewModel.loadMessages() }
                }
            } else if viewModel.messages.isEmpty {
                EmptyMessagesView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.chatMessages) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                            }

                            // Bottom anchor - extra space for Resume button
                            Color.clear
                                .frame(height: onResume != nil ? 60 : 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xs)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .background(ColorSystem.terminalBg)
            }
        }
        .background(ColorSystem.terminalBg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("History")
                    .font(Typography.title3)
                    .fontWeight(.semibold)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let onResume = onResume {
                ResumeSessionButton(onResume: onResume)
            }
        }
        .task {
            await viewModel.loadMessages()
        }
    }
}

// MARK: - Resume Session Button

private struct ResumeSessionButton: View {
    let onResume: () -> Void

    var body: some View {
        Button {
            Haptics.medium()
            onResume()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .bold))
                Text("Resume Session")
                    .font(Typography.buttonLabel)
                    .fontWeight(.bold)
            }
            .foregroundStyle(ColorSystem.terminalBg)  // Dark text on bright bg
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                LinearGradient(
                    colors: [ColorSystem.primary, ColorSystem.primaryDim],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .shadow(color: ColorSystem.primaryGlow, radius: 8, y: 2)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Session Header View

private struct SessionHeaderView: View {
    let session: SessionsResponse.SessionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Summary
            Text(session.summary)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textPrimary)
                .lineLimit(2)

            // Metadata row
            HStack(spacing: Spacing.sm) {
                // Message count
                HStack(spacing: 3) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 9))
                    Text("\(session.messageCount)")
                        .font(Typography.terminalSmall)
                }
                .foregroundStyle(ColorSystem.textTertiary)

                // Branch badge (if available)
                if let branch = session.branch {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(branch)
                            .font(Typography.terminalSmall)
                    }
                    .foregroundStyle(ColorSystem.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(Capsule())
                }

                Spacer()

                // Time
                Text(session.compactTime)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Chat Message Row

struct ChatMessageRow: View {
    let message: SessionMessagesResponse.SessionMessage
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Role header with timestamp
            HStack(spacing: Spacing.xs) {
                roleIndicator
                    .font(Typography.terminalSmall)

                Spacer()

                if let timestamp = formattedTime {
                    Text(timestamp)
                        .font(Typography.terminalTimestamp)
                        .foregroundStyle(ColorSystem.textQuaternary)
                }
            }

            // Content based on role
            Group {
                switch message.role {
                case "user":
                    UserMessageContent(message: message)
                case "assistant":
                    AssistantMessageContent(message: message, isExpanded: $isExpanded)
                default:
                    // Tool result or other message types
                    GenericMessageContent(message: message)
                }
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
        switch message.role {
        case "user":
            let isBashCommand = message.textContent.hasPrefix("!")
            let iconColor = isBashCommand ? ColorSystem.success : ColorSystem.Log.user

            HStack(spacing: 3) {
                if isBashCommand {
                    // Bash command - show "!" in green
                    Text("!")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(iconColor)
                } else {
                    // Regular user message - show chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(iconColor)
                }
                Text("you")
                    .fontWeight(.semibold)
                    .foregroundStyle(ColorSystem.Log.user)
            }

        case "assistant":
            HStack(spacing: 3) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8))
                Text("claude")
                    .fontWeight(.semibold)

                // Model badge
                if let model = message.message.model {
                    Text(shortModelName(model))
                        .font(Typography.badge)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(ColorSystem.primary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(ColorSystem.primary)

        default:
            HStack(spacing: 3) {
                Image(systemName: "gearshape")
                    .font(.system(size: 8))
                Text(message.type)
            }
            .foregroundStyle(ColorSystem.textTertiary)
        }
    }

    private var formattedTime: String? {
        guard let timestamp = message.timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: timestamp) else { return nil }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        return timeFormatter.string(from: date)
    }

    private func shortModelName(_ model: String) -> String {
        if model.contains("opus") { return "opus" }
        if model.contains("sonnet") { return "sonnet" }
        if model.contains("haiku") { return "haiku" }
        // Truncate long model names
        if model.count > 12 {
            return String(model.prefix(10)) + "..."
        }
        return model
    }
}

// MARK: - User Message Content

private struct UserMessageContent: View {
    let message: SessionMessagesResponse.SessionMessage

    var body: some View {
        let isBashCommand = message.textContent.hasPrefix("!")
        // Strip leading "!" from text if it's a bash command (shown in role indicator)
        let displayText = isBashCommand ? String(message.textContent.dropFirst()).trimmingCharacters(in: .whitespaces) : message.textContent

        Text(displayText)
            .font(Typography.terminal)
            .foregroundStyle(ColorSystem.Log.user)
            .textSelection(.enabled)
            .padding(.leading, Spacing.sm)
    }
}

// MARK: - Assistant Message Content

private struct AssistantMessageContent: View {
    let message: SessionMessagesResponse.SessionMessage
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Text content
            if !message.textContent.isEmpty {
                Text(message.textContent)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.Log.stdout)
                    .textSelection(.enabled)
                    .padding(.leading, Spacing.sm)
            }

            // Tool use blocks (if any)
            if let blocks = toolUseBlocks, !blocks.isEmpty {
                ToolUseSection(blocks: blocks, isExpanded: $isExpanded)
            }

            // Token usage (if available)
            if let usage = message.message.usage,
               let inputTokens = usage.inputTokens,
               let outputTokens = usage.outputTokens {
                HStack(spacing: Spacing.xs) {
                    Spacer()
                    TokenBadge(label: "in", count: inputTokens)
                    TokenBadge(label: "out", count: outputTokens)
                }
                .padding(.top, 2)
            }
        }
    }

    private var toolUseBlocks: [SessionMessagesResponse.SessionMessage.ContentType.ContentBlock]? {
        guard case .blocks(let blocks) = message.message.content else { return nil }
        return blocks.filter { $0.type == "tool_use" || $0.type == "tool_result" }
    }
}

// MARK: - Tool Use Section

private struct ToolUseSection: View {
    let blocks: [SessionMessagesResponse.SessionMessage.ContentType.ContentBlock]
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

                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 9))

                    Text("\(blocks.count) tool\(blocks.count == 1 ? "" : "s")")
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
                    ForEach(blocks.indices, id: \.self) { index in
                        ToolBlockRow(block: blocks[index])
                    }
                }
                .padding(.leading, Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Tool Block Row

private struct ToolBlockRow: View {
    let block: SessionMessagesResponse.SessionMessage.ContentType.ContentBlock
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

                    if block.type == "tool_use" {
                        Text(block.name ?? "tool")
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.warning)
                    } else {
                        Text("result")
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.success)
                    }
                }
            }
            .buttonStyle(.plain)

            // Content
            if showContent {
                if let content = block.content ?? block.text {
                    Text(content.prefix(500) + (content.count > 500 ? "..." : ""))
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

// MARK: - Generic Message Content

private struct GenericMessageContent: View {
    let message: SessionMessagesResponse.SessionMessage

    var body: some View {
        if !message.textContent.isEmpty {
            Text(message.textContent)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)
                .textSelection(.enabled)
                .padding(.leading, Spacing.sm)
        }
    }
}

// MARK: - Loading State

private struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(ColorSystem.primary)

            Text("Loading history...")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBg)
    }
}

// MARK: - Error State

private struct ErrorStateView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(ColorSystem.warning)

            Text("Failed to load history")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textTertiary)

            Button(action: onRetry) {
                Text("Retry")
                    .font(Typography.buttonLabel)
                    .foregroundStyle(ColorSystem.primary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(ColorSystem.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBg)
    }
}

// MARK: - Empty Messages

private struct EmptyMessagesView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32))
                .foregroundStyle(ColorSystem.textQuaternary)

            Text("No messages")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textTertiary)

            Text("This session has no messages yet")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textQuaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBg)
    }
}

// MARK: - View Model

@MainActor
final class SessionHistoryViewModel: ObservableObject {
    @Published var messages: [SessionMessagesResponse.SessionMessage] = []
    @Published var isLoading = false
    @Published var error: AppError?

    private let sessionId: String
    private let runtime: AgentRuntime
    private let workspaceId: String?
    private let agentRepository: AgentRepositoryProtocol

    /// Converted ChatMessages for unified rendering
    var chatMessages: [ChatMessage] {
        messages.map { ChatMessage.from(sessionMessage: $0) }
    }

    init(sessionId: String, runtime: AgentRuntime, workspaceId: String?, agentRepository: AgentRepositoryProtocol) {
        self.sessionId = sessionId
        self.runtime = runtime
        self.workspaceId = workspaceId
        self.agentRepository = agentRepository
    }

    func loadMessages() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: SessionMessagesResponse = try await withThrowingTaskGroup(of: SessionMessagesResponse.self) { group in
                group.addTask {
                    switch self.runtime.sessionMessagesSource {
                    case .runtimeScoped:
                        return try await self.agentRepository.getAgentSessionMessages(
                            runtime: self.runtime,
                            sessionId: self.sessionId,
                            limit: 20,
                            offset: 0,
                            order: "desc"
                        )
                    case .workspaceScoped:
                        guard let workspaceId = self.workspaceId, !workspaceId.isEmpty else {
                            throw AppError.workspaceIdRequired
                        }
                        return try await self.agentRepository.getSessionMessages(
                            runtime: self.runtime,
                            sessionId: self.sessionId,
                            workspaceId: workspaceId,
                            limit: 20,
                            offset: 0,
                            order: "desc"
                        )
                    }
                }
                // 30-second timeout: server can be slow when codex session index is being rebuilt
                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    throw AppError.httpTimeout
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }

            // Reverse to show oldest at top, newest at bottom (chronological order)
            let filtered = response.messages.filter { message in
                !ChatContentFilter.shouldHideInternalMessage(message.textContent)
            }
            messages = filtered.reversed()
            AppLogger.log("[SessionHistory] Loaded \(response.count) of \(response.total) messages for session \(sessionId)\(workspaceId != nil ? " (workspace: \(workspaceId!))" : "")")
        } catch is CancellationError {
            // View dismissed - no error to show
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
            AppLogger.error(error, context: "Load session messages")
        }
    }
}
