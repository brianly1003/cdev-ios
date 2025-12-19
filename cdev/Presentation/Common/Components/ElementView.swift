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
        HStack(alignment: .top, spacing: Spacing.xs) {
            // Timestamp (optional) - aligned with content's first line
            if showTimestamp {
                Text(formattedTime)
                    .font(Typography.terminalTimestamp)
                    .foregroundStyle(ColorSystem.textQuaternary)
                    .frame(width: 56, alignment: .trailing)
                    .padding(.top, 5)  // Align with status dot padding in element views
            }

            // Element content - let content determine height, ensure minimum visibility
            elementContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 20)
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
        formatter.dateFormat = "HH:mm:ss"
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
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
        .frame(minHeight: 20)
    }
}

// MARK: - Assistant Text View

/// Claude's text response with model badge
/// Parses <thinking> tags and renders markdown
struct AssistantTextElementView: View {
    let content: AssistantTextContent

    /// Parsed segments from content (thinking blocks and regular text)
    private var segments: [TextSegment] {
        parseThinkingBlocks(from: content.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xxs) {
            // Status dot
            Circle()
                .fill(ColorSystem.primary)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
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

                // Render segments (thinking blocks or regular text with markdown)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .thinking(let text):
                        InlineThinkingView(text: text)
                    case .text(let text):
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            MarkdownTextView(text: text)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
        .frame(minHeight: 20)
    }

    private func shortModelName(_ model: String) -> String {
        if model.contains("opus") { return "opus" }
        if model.contains("sonnet") { return "sonnet" }
        if model.contains("haiku") { return "haiku" }
        return model.count > 12 ? String(model.prefix(10)) + "..." : model
    }

    /// Parse text for <thinking>...</thinking> blocks
    private func parseThinkingBlocks(from text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = text

        let pattern = #"<thinking>([\s\S]*?)</thinking>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.text(text)]
        }

        while let match = regex.firstMatch(in: remaining, options: [], range: NSRange(remaining.startIndex..., in: remaining)) {
            // Text before thinking block
            if let beforeRange = Range(NSRange(location: 0, length: match.range.location), in: remaining) {
                let beforeText = String(remaining[beforeRange])
                if !beforeText.isEmpty {
                    segments.append(.text(beforeText))
                }
            }

            // Thinking content
            if let thinkingRange = Range(match.range(at: 1), in: remaining) {
                let thinkingText = String(remaining[thinkingRange])
                segments.append(.thinking(thinkingText))
            }

            // Move past this match
            if let matchRange = Range(match.range, in: remaining) {
                remaining = String(remaining[matchRange.upperBound...])
            } else {
                break
            }
        }

        // Any remaining text
        if !remaining.isEmpty {
            segments.append(.text(remaining))
        }

        return segments.isEmpty ? [.text(text)] : segments
    }
}

/// Segment type for parsed text
private enum TextSegment {
    case text(String)
    case thinking(String)
}

/// Inline collapsible thinking block (within assistant text)
private struct InlineThinkingView: View {
    let text: String
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
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .italic()
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 4)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Markdown-enabled text view with heading support
private struct MarkdownTextView: View {
    let text: String

    /// Parsed lines with heading detection
    private var parsedLines: [MarkdownLine] {
        text.components(separatedBy: "\n").map { line in
            parseMarkdownLine(line)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(parsedLines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let level, let content):
                    headingView(level: level, content: content)
                case .text(let content):
                    if !content.isEmpty {
                        inlineMarkdownText(content)
                    } else {
                        Text(" ")  // Preserve empty lines
                            .font(Typography.terminal)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func headingView(level: Int, content: String) -> some View {
        let font: Font = switch level {
        case 1: .system(size: 18, weight: .bold, design: .monospaced)
        case 2: .system(size: 15, weight: .bold, design: .monospaced)
        case 3: .system(size: 13, weight: .semibold, design: .monospaced)
        default: Typography.terminal
        }

        Text(inlineMarkdown(content))
            .font(font)
            .foregroundStyle(ColorSystem.textPrimary)
            .padding(.top, level == 1 ? 4 : 2)
    }

    private func inlineMarkdownText(_ content: String) -> some View {
        Text(inlineMarkdown(content))
            .font(Typography.terminal)
            .foregroundStyle(ColorSystem.Log.stdout)
    }

    /// Parse inline markdown (bold, italic, code, links)
    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }

    /// Parse a line to detect headings
    private func parseMarkdownLine(_ line: String) -> MarkdownLine {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Check for heading patterns: # ## ###
        if trimmed.hasPrefix("###") {
            let content = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return .heading(level: 3, content: content)
        } else if trimmed.hasPrefix("##") {
            let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return .heading(level: 2, content: content)
        } else if trimmed.hasPrefix("#") && !trimmed.hasPrefix("#!") {
            // Avoid matching shebang (#!) as heading
            let content = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            return .heading(level: 1, content: content)
        }

        return .text(line)
    }
}

/// Parsed markdown line type
private enum MarkdownLine {
    case heading(level: Int, content: String)
    case text(String)
}

// MARK: - Tool Call View

/// Tool invocation display with status indicator
struct ToolCallElementView: View {
    let content: ToolCallContent

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xxs) {
            // Status indicator
            statusIndicator
                .padding(.top, 5)

            // Tool name and params combined (no spaces around parentheses)
            Text(toolDisplay)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.Tool.name)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // Running spinner
            if content.status == .running {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(ColorSystem.primary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .frame(minHeight: 20)
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

    private var toolDisplay: String {
        let params = displayParams
        if params.isEmpty {
            return content.tool
        }
        return "\(content.tool)(\(params))"
    }

    private var displayParams: String {
        // Priority: command > file_path > pattern > args
        if let cmd = content.params["command"] {
            return cmd
        }
        if let path = content.params["file_path"] {
            return path
        }
        if let pattern = content.params["pattern"] {
            return "pattern: \"\(pattern)\""
        }
        if let args = content.params["args"] {
            return args
        }
        if !content.display.isEmpty {
            return content.display
        }
        return ""
    }
}

// MARK: - Tool Result View

/// Collapsible tool result with error state
struct ToolResultElementView: View {
    let content: ToolResultContent
    @State private var isExpanded = false

    private let previewLineCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Summary/Preview row (always visible)
            Button {
                if hasMoreLines {
                    withAnimation(Animations.stateChange) {
                        isExpanded.toggle()
                    }
                    Haptics.selection()
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    // Preview lines with indicator
                    HStack(alignment: .top, spacing: Spacing.xxs) {
                        Text("⎿")
                            .font(Typography.terminal)
                            .foregroundStyle(ColorSystem.textQuaternary)

                        Text(previewText.isEmpty ? "(empty)" : previewText)
                            .font(Typography.terminal)
                            .foregroundStyle(content.isError ? ColorSystem.error : ColorSystem.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 20)

                    // Expand indicator (if more lines available)
                    if hasMoreLines && !isExpanded {
                        HStack(spacing: Spacing.xxs) {
                            Text("…")
                                .font(Typography.terminal)
                                .foregroundStyle(ColorSystem.textQuaternary)

                            Text("+\(content.lineCount - previewLineCount) lines (tap to expand)")
                                .font(Typography.terminalSmall)
                                .foregroundStyle(ColorSystem.textQuaternary)
                        }
                        .padding(.leading, Spacing.sm)
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Text(content.fullContent)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(content.isError ? ColorSystem.error : ColorSystem.textTertiary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Collapse button
                    Button {
                        withAnimation(Animations.stateChange) {
                            isExpanded = false
                        }
                        Haptics.selection()
                    } label: {
                        Text("collapse")
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textQuaternary)
                    }
                    .padding(.top, Spacing.xxs)
                }
                .padding(.leading, Spacing.md)
                .padding(.vertical, Spacing.xxs)
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Spacing.xxs)
        .frame(minHeight: 20)
    }

    private var hasMoreLines: Bool {
        content.lineCount > previewLineCount
    }

    private var previewText: String {
        guard !content.fullContent.isEmpty else { return "" }
        let lines = content.fullContent.components(separatedBy: "\n")
        return lines.prefix(previewLineCount).joined(separator: "\n")
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
        .frame(minHeight: 20)
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
        .frame(minHeight: 14)
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
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 4)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.leading, Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, Spacing.xxs)
        .frame(minHeight: 20)
    }
}

// MARK: - Interrupted View

/// User interruption display
struct InterruptedElementView: View {
    let content: InterruptedContent

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Text("⎿")
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
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
        .frame(minHeight: 20)
    }
}

// MARK: - Elements List View

/// Scrollable list of chat elements
struct ElementsListView: View {
    let elements: [ChatElement]
    let showTimestamps: Bool
    @Binding var isAutoScrollEnabled: Bool

    @State private var scrollProxy: ScrollViewProxy?
    @State private var scrollTask: Task<Void, Never>?
    @State private var lastScrolledCount = 0

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
                scheduleScrollToBottom()
            }
            .onChange(of: elements.count) { oldCount, newCount in
                guard isAutoScrollEnabled, newCount > oldCount, newCount != lastScrolledCount else { return }
                scheduleScrollToBottom()
            }
        }
        .background(ColorSystem.terminalBg)
    }

    /// Debounced scroll to prevent multiple updates per frame
    private func scheduleScrollToBottom() {
        guard !elements.isEmpty else { return }

        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else { return }

            lastScrolledCount = elements.count
            withAnimation(Animations.logAppear) {
                scrollProxy?.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
