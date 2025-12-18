import SwiftUI

/// Pulse Terminal Log Viewer - optimized for developer productivity
/// Supports both legacy LogEntry display and new ChatElement display
struct LogListView: View {
    let logs: [LogEntry]
    let elements: [ChatElement]  // NEW: Elements API style display
    let onClear: () -> Void
    var isVisible: Bool = true  // Track if tab is visible

    @AppStorage(Constants.UserDefaults.showTimestamps) private var showTimestamps = true
    @AppStorage(Constants.UserDefaults.useElementsView) private var useElementsView = true  // Feature flag

    init(logs: [LogEntry], elements: [ChatElement] = [], onClear: @escaping () -> Void, isVisible: Bool = true) {
        self.logs = logs
        self.elements = elements
        self.onClear = onClear
        self.isVisible = isVisible
    }

    var body: some View {
        Group {
            if elements.isEmpty && logs.isEmpty {
                EmptyStateView(
                    icon: Icons.terminal,
                    title: "No Output",
                    subtitle: "Claude's output will appear here"
                )
            } else if useElementsView && !elements.isEmpty {
                // NEW: Sophisticated Elements API view
                elementsListView
            } else if !logs.isEmpty {
                // Legacy: LogEntry-based view
                logsListView
            } else {
                EmptyStateView(
                    icon: Icons.terminal,
                    title: "No Output",
                    subtitle: "Claude's output will appear here"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBg)
    }

    // MARK: - Elements List View (NEW)

    @ViewBuilder
    private var elementsListView: some View {
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
                guard !elements.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: elements.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                withAnimation(Animations.logAppear) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onKeyboardShow {
                guard !elements.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: isVisible) { _, visible in
                guard visible, !elements.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Legacy Logs List View

    @ViewBuilder
    private var logsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(logs.enumerated()), id: \.element.id) { index, entry in
                        let previousEntry = index > 0 ? logs[index - 1] : nil
                        let showTime = shouldShowTimestamp(for: entry, previous: previousEntry)
                        LogEntryRow(
                            entry: entry,
                            showTimestamp: showTimestamps && showTime,
                            timestampsEnabled: showTimestamps
                        )
                        .id(entry.id)
                    }
                    // Bottom anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xs)
            }
            .onAppear {
                guard !logs.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: logs.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                withAnimation(Animations.logAppear) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onKeyboardShow {
                guard !logs.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: isVisible) { _, visible in
                guard visible, !logs.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    /// Show timestamp if time is different OR stream type changed (user <-> assistant)
    private func shouldShowTimestamp(for entry: LogEntry, previous: LogEntry?) -> Bool {
        guard let previous = previous else { return true }

        // Always show timestamp when stream type changes (user -> assistant or vice versa)
        if entry.stream != previous.stream {
            return true
        }

        // Otherwise, only show if time is different
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp) != formatter.string(from: previous.timestamp)
    }
}

// MARK: - Pulse Terminal Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry
    let showTimestamp: Bool
    let timestampsEnabled: Bool  // Global setting - controls whether to reserve space
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timestamp column - only show/reserve space if timestamps are globally enabled
            if timestampsEnabled {
                if showTimestamp {
                    Text(compactTimestamp)
                        .font(Typography.lineNumber)
                        .foregroundStyle(ColorSystem.Log.timestamp)
                        .frame(width: 52, alignment: .trailing)
                        .padding(.trailing, Spacing.xs)
                } else {
                    // Empty spacer to maintain alignment with timestamped entries
                    Spacer()
                        .frame(width: 52 + Spacing.xs)
                }
            }

            // Rich content based on type
            RichLogContent(
                entry: entry,
                isExpanded: $isExpanded,
                baseColor: streamColor
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.content
                Haptics.selection()
            } label: {
                Label("Copy", systemImage: Icons.copy)
            }
        }
    }

    private var compactTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp)
    }

    private var streamColor: Color {
        switch entry.stream {
        case .stdout: return ColorSystem.Log.stdout
        case .stderr: return ColorSystem.Log.stderr
        case .system: return ColorSystem.Log.system
        case .user: return ColorSystem.Log.user
        }
    }
}

// MARK: - Rich Log Content

private struct RichLogContent: View {
    let entry: LogEntry
    @Binding var isExpanded: Bool
    let baseColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch entry.contentType {
            case .userPrompt:
                UserPromptRow(content: entry.content)

            case .toolUse(let name):
                ToolUseRow(
                    name: name,
                    content: entry.content,
                    isExpanded: $isExpanded
                )

            case .toolResult:
                ToolResultRow(content: entry.content, isExpanded: $isExpanded)

            case .thinking:
                ThinkingRow(content: entry.content)

            case .fileOperation(let op, let path):
                FileOperationRow(operation: op, path: path, content: entry.content)

            case .command(let cmd):
                CommandRow(command: cmd, content: entry.content, isExpanded: $isExpanded)

            case .error:
                ErrorRow(content: entry.content)

            case .systemMessage:
                SystemMessageRow(content: entry.content)

            case .text:
                // Default text rendering
                Text(entry.content)
                    .font(Typography.terminal)
                    .foregroundStyle(baseColor)
                    .textSelection(.enabled)
                    .lineSpacing(1)
            }
        }
    }
}

// MARK: - User Prompt Row

private struct UserPromptRow: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ColorSystem.Log.user)

            Text(content.hasPrefix("> ") ? String(content.dropFirst(2)) : content)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.Log.user)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Tool Use Row

private struct ToolUseRow: View {
    let name: String
    let content: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Tool header - tappable
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

                    Text(name)
                        .font(Typography.terminalSmall)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(ColorSystem.warning)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ColorSystem.warning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Text(content)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 4)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.leading, Spacing.sm)
            }
        }
    }
}

// MARK: - Tool Result Row

private struct ToolResultRow: View {
    let content: String
    @Binding var isExpanded: Bool

    private var isLongContent: Bool { content.count > 100 }
    private var displayContent: String {
        if isLongContent && !isExpanded {
            return String(content.prefix(100)) + "..."
        }
        return content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: content.hasPrefix("✗") ? "xmark.circle" : "checkmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(content.hasPrefix("✗") ? ColorSystem.error : ColorSystem.success)

                Text(displayContent)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.Log.stdout)
                    .textSelection(.enabled)

                if isLongContent {
                    Button {
                        withAnimation { isExpanded.toggle() }
                        Haptics.selection()
                    } label: {
                        Text(isExpanded ? "less" : "more")
                            .font(Typography.badge)
                            .foregroundStyle(ColorSystem.primary)
                    }
                }
            }
        }
    }
}

// MARK: - Thinking Row

private struct ThinkingRow: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "brain")
                .font(.system(size: 9))
                .foregroundStyle(ColorSystem.primary.opacity(0.7))

            Text(content)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)
                .italic()
                .textSelection(.enabled)
        }
    }
}

// MARK: - File Operation Row

private struct FileOperationRow: View {
    let operation: String
    let path: String
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: operationIcon)
                .font(.system(size: 9))
                .foregroundStyle(operationColor)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(operation)
                        .font(Typography.terminalSmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(operationColor)

                    Text(path)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textPrimary)
                }

                if content.count > (operation.count + path.count + 10) {
                    Text(content)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                        .lineLimit(2)
                }
            }
            .textSelection(.enabled)
        }
    }

    private var operationIcon: String {
        switch operation {
        case "Read": return "doc.text"
        case "Write", "Create": return "doc.badge.plus"
        case "Edit", "Modify": return "pencil"
        case "Delete": return "trash"
        default: return "doc"
        }
    }

    private var operationColor: Color {
        switch operation {
        case "Delete": return ColorSystem.error
        case "Create", "Write": return ColorSystem.success
        case "Edit", "Modify": return ColorSystem.warning
        default: return ColorSystem.primary
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: String
    let content: String
    @Binding var isExpanded: Bool

    private var isLongContent: Bool { content.count > 80 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Command header
            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .font(.system(size: 9))
                    .foregroundStyle(ColorSystem.success)

                Text(command)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.success)
                    .lineLimit(isExpanded ? nil : 1)

                if isLongContent {
                    Spacer()
                    Button {
                        withAnimation { isExpanded.toggle() }
                        Haptics.selection()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(ColorSystem.textQuaternary)
                    }
                }
            }
            .textSelection(.enabled)

            // Full content when expanded
            if isExpanded && content != command {
                Text(content)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .textSelection(.enabled)
                    .padding(.leading, Spacing.sm)
            }
        }
    }
}

// MARK: - Error Row

private struct ErrorRow: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(ColorSystem.error)

            Text(content)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.Log.stderr)
                .textSelection(.enabled)
        }
    }
}

// MARK: - System Message Row

private struct SystemMessageRow: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 9))
                .foregroundStyle(ColorSystem.Log.system)

            Text(content)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.Log.system)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Pulse Terminal Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(ColorSystem.textQuaternary)

            Text(title)
                .font(Typography.bannerTitle)
                .foregroundStyle(ColorSystem.textSecondary)

            Text(subtitle)
                .font(Typography.bannerBody)
                .foregroundStyle(ColorSystem.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
        .background(ColorSystem.terminalBg)
    }
}
