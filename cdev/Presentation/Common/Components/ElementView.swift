import SwiftUI

// MARK: - Element Container View

/// Main container view that renders any ChatElement type
/// Matches Claude Code CLI visual style
struct ElementView: View {
    let element: ChatElement
    let showTimestamp: Bool

    init(element: ChatElement, showTimestamp: Bool = false) {
        self.element = element
        self.showTimestamp = showTimestamp
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timestamp (optional)
            if showTimestamp {
                Text(formattedTime)
                    .font(Typography.terminalTimestamp)
                    .foregroundStyle(ColorSystem.textQuaternary)
                    .frame(width: 50, alignment: .leading)
            }

            // Element content
            elementContent
        }
    }

    @ViewBuilder
    private var elementContent: some View {
        switch element.content {
        case .userInput(let content):
            UserInputElementView(content: content)

        case .assistantText(let content):
            AssistantTextElementView(content: content)

        case .toolCall(let content):
            ToolCallElementView(content: content)

        case .toolResult(let content):
            ToolResultElementView(content: content)

        case .diff(let content):
            DiffElementView(content: content)

        case .thinking(let content):
            ThinkingElementView(content: content)

        case .interrupted(let content):
            InterruptedElementView(content: content)
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: element.timestamp)
    }
}

// MARK: - User Input View

/// User prompt display: > user text
struct UserInputElementView: View {
    let content: UserInputContent

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xxs) {
            // Prompt indicator
            Text(">")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.Log.user)
                .fontWeight(.bold)

            // User text
            Text(content.text)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.Log.user)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Assistant Text View

/// Claude's text response with model badge
struct AssistantTextElementView: View {
    let content: AssistantTextContent

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xxs) {
            // Status dot
            Circle()
                .fill(ColorSystem.primary)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                // Model badge (if available)
                if let model = content.model {
                    Text(shortModelName(model))
                        .font(Typography.badge)
                        .foregroundStyle(ColorSystem.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(ColorSystem.primary.opacity(0.15))
                        .clipShape(Capsule())
                }

                // Response text
                Text(content.text)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.Log.stdout)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func shortModelName(_ model: String) -> String {
        if model.contains("opus") { return "opus" }
        if model.contains("sonnet") { return "sonnet" }
        if model.contains("haiku") { return "haiku" }
        return model.count > 12 ? String(model.prefix(10)) + "..." : model
    }
}

// MARK: - Tool Call View

/// Tool invocation display with status indicator
struct ToolCallElementView: View {
    let content: ToolCallContent

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xxs) {
            // Status indicator
            statusIndicator

            // Tool name
            Text(content.tool)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.Tool.name)
                .fontWeight(.medium)

            // Params display
            Text("(")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)

            Text(displayParams)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(")")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)

            Spacer(minLength: 0)

            // Duration badge
            if let duration = content.durationMs {
                Text("\(duration)ms")
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.textQuaternary)
            }

            // Running spinner
            if content.status == .running {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(ColorSystem.primary)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch content.status {
        case .running:
            Circle()
                .fill(ColorSystem.info)
                .frame(width: 6, height: 6)
        case .completed:
            Circle()
                .fill(ColorSystem.primary)
                .frame(width: 6, height: 6)
        case .error:
            Circle()
                .fill(ColorSystem.error)
                .frame(width: 6, height: 6)
        case .interrupted:
            Circle()
                .fill(ColorSystem.warning)
                .frame(width: 6, height: 6)
        }
    }

    private var displayParams: String {
        // Priority: command > file_path > pattern > args
        if let cmd = content.params["command"] {
            return cmd.count > 50 ? String(cmd.prefix(50)) + "..." : cmd
        }
        if let path = content.params["file_path"] {
            return path
        }
        if let pattern = content.params["pattern"] {
            return "pattern: \"\(pattern)\""
        }
        if let args = content.params["args"] {
            return args.count > 50 ? String(args.prefix(50)) + "..." : args
        }
        return content.display
    }
}

// MARK: - Tool Result View

/// Collapsible tool result with error state
struct ToolResultElementView: View {
    let content: ToolResultContent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Summary row
            Button {
                if content.expandable && content.lineCount > 1 {
                    withAnimation(Animations.stateChange) {
                        isExpanded.toggle()
                    }
                    Haptics.selection()
                }
            } label: {
                HStack(alignment: .top, spacing: Spacing.xxs) {
                    // Result indicator
                    Text("└")
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textQuaternary)

                    // Summary text
                    Text(content.summary)
                        .font(Typography.terminal)
                        .foregroundStyle(content.isError ? ColorSystem.error : ColorSystem.textSecondary)
                        .lineLimit(isExpanded ? nil : 1)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)

                    // Expand indicator
                    if content.expandable && content.lineCount > 1 {
                        Text(isExpanded ? "collapse" : "+\(content.lineCount - 1) lines")
                            .font(Typography.badge)
                            .foregroundStyle(ColorSystem.textQuaternary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded && content.lineCount > 1 {
                Text(content.fullContent)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(content.isError ? ColorSystem.error : ColorSystem.textTertiary)
                    .textSelection(.enabled)
                    .padding(.leading, Spacing.md)
                    .padding(.vertical, Spacing.xxs)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Diff View

/// File diff display with syntax highlighting
struct DiffElementView: View {
    let content: DiffContent
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header
            Button {
                withAnimation(Animations.stateChange) {
                    isExpanded.toggle()
                }
                Haptics.selection()
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(ColorSystem.textQuaternary)

                    Text("└")
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textQuaternary)

                    // Summary with +/- counts
                    HStack(spacing: 4) {
                        Text("+\(content.summary.added)")
                            .foregroundStyle(ColorSystem.Diff.added)
                        Text("-\(content.summary.removed)")
                            .foregroundStyle(ColorSystem.Diff.removed)
                    }
                    .font(Typography.terminalSmall)

                    // File path
                    Text(shortenPath(content.filePath))
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Diff lines
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(content.hunks) { hunk in
                        ForEach(hunk.lines) { line in
                            DiffLineElementView(line: line)
                        }
                    }
                }
                .padding(.leading, Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func shortenPath(_ path: String) -> String {
        // Show last 2 components
        let components = path.components(separatedBy: "/")
        if components.count > 2 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }
}

/// Individual diff line with proper coloring
struct DiffLineElementView: View {
    let line: ElementDiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Line number
            Text(lineNumber)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textQuaternary)
                .frame(width: 28, alignment: .trailing)

            // Change prefix
            Text(prefix)
                .font(Typography.terminalSmall)
                .foregroundStyle(prefixColor)
                .frame(width: 14)

            // Content
            Text(line.content)
                .font(Typography.terminalSmall)
                .foregroundStyle(contentColor)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .background(backgroundColor)
    }

    private var lineNumber: String {
        if let num = line.newLine ?? line.oldLine {
            return String(num)
        }
        return ""
    }

    private var prefix: String {
        switch line.type {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private var prefixColor: Color {
        switch line.type {
        case .added: return ColorSystem.Diff.added
        case .removed: return ColorSystem.Diff.removed
        case .context: return ColorSystem.textQuaternary
        }
    }

    private var contentColor: Color {
        switch line.type {
        case .added: return ColorSystem.Diff.added
        case .removed: return ColorSystem.Diff.removed
        case .context: return ColorSystem.textTertiary
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: return ColorSystem.Diff.addedBg
        case .removed: return ColorSystem.Diff.removedBg
        case .context: return .clear
        }
    }
}

// MARK: - Thinking View

/// Collapsible thinking/reasoning block
struct ThinkingElementView: View {
    let content: ThinkingContent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Toggle button
            Button {
                withAnimation(Animations.stateChange) {
                    isExpanded.toggle()
                }
                Haptics.selection()
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))

                    Image(systemName: "brain")
                        .font(.system(size: 10))

                    Text("Thinking...")
                        .font(Typography.terminalSmall)
                        .italic()
                }
                .foregroundStyle(ColorSystem.primary.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ColorSystem.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Text(content.text)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .italic()
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 4)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.leading, Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Interrupted View

/// User interruption display
struct InterruptedElementView: View {
    let content: InterruptedContent

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Text("└")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textQuaternary)

            Text("Interrupted")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.warning)
                .fontWeight(.medium)

            Text("·")
                .foregroundStyle(ColorSystem.textQuaternary)

            Text(content.message)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textTertiary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Elements List View

/// Scrollable list of chat elements
struct ElementsListView: View {
    let elements: [ChatElement]
    let showTimestamps: Bool
    @Binding var isAutoScrollEnabled: Bool

    @State private var scrollProxy: ScrollViewProxy?

    init(elements: [ChatElement], showTimestamps: Bool = false, isAutoScrollEnabled: Binding<Bool> = .constant(true)) {
        self.elements = elements
        self.showTimestamps = showTimestamps
        self._isAutoScrollEnabled = isAutoScrollEnabled
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(elements) { element in
                        ElementView(element: element, showTimestamp: showTimestamps)
                            .id(element.id)
                    }

                    // Bottom anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xs)
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom()
            }
            .onChange(of: elements.count) { _, _ in
                if isAutoScrollEnabled {
                    scrollToBottom()
                }
            }
        }
        .background(ColorSystem.terminalBg)
    }

    private func scrollToBottom() {
        withAnimation(Animations.logAppear) {
            scrollProxy?.scrollTo("bottom", anchor: .bottom)
        }
    }
}
