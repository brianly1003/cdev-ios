import SwiftUI

/// Pulse Terminal Log Viewer - optimized for developer productivity
/// Supports both legacy LogEntry display and new ChatElement display
struct LogListView: View {
    let logs: [LogEntry]
    let elements: [ChatElement]  // NEW: Elements API style display
    let onClear: () -> Void
    var isVisible: Bool = true  // Track if tab is visible
    var isInputFocused: Bool = false  // Track if input field is focused (for auto-scroll)
    var isStreaming: Bool = false  // Whether Claude is actively thinking/streaming
    var streamingStartTime: Date?  // When streaming started (for duration display)

    // Pull-to-refresh for loading more messages
    var hasMoreMessages: Bool = false
    var isLoadingMore: Bool = false
    var onLoadMore: (() async -> Void)?

    @AppStorage(Constants.UserDefaults.showTimestamps) private var showTimestamps = true
    @AppStorage(Constants.UserDefaults.useElementsView) private var useElementsView = true  // Feature flag

    init(logs: [LogEntry], elements: [ChatElement] = [], onClear: @escaping () -> Void, isVisible: Bool = true, isInputFocused: Bool = false, isStreaming: Bool = false, streamingStartTime: Date? = nil, hasMoreMessages: Bool = false, isLoadingMore: Bool = false, onLoadMore: (() async -> Void)? = nil) {
        self.logs = logs
        self.elements = elements
        self.onClear = onClear
        self.isVisible = isVisible
        self.isInputFocused = isInputFocused
        self.isStreaming = isStreaming
        self.streamingStartTime = streamingStartTime
        self.hasMoreMessages = hasMoreMessages
        self.isLoadingMore = isLoadingMore
        self.onLoadMore = onLoadMore
    }

    var body: some View {
        let _ = AppLogger.log("[LogListView] Rendering: elements=\(elements.count), logs=\(logs.count), useElementsView=\(useElementsView)")
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
        ElementsScrollView(
            elements: elements,
            showTimestamps: showTimestamps,
            isVisible: isVisible,
            isInputFocused: isInputFocused,
            isStreaming: isStreaming,
            streamingStartTime: streamingStartTime,
            hasMoreMessages: hasMoreMessages,
            isLoadingMore: isLoadingMore,
            onLoadMore: onLoadMore
        )
    }

    // MARK: - Legacy Logs List View

    @ViewBuilder
    private var logsListView: some View {
        LogsScrollView(logs: logs, showTimestamps: showTimestamps, isVisible: isVisible, isInputFocused: isInputFocused, shouldShowTimestamp: shouldShowTimestamp)
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

// MARK: - Elements Scroll View (Debounced)

/// Separate view to properly manage scroll state and prevent multiple updates per frame
private struct ElementsScrollView: View {
    let elements: [ChatElement]
    let showTimestamps: Bool
    let isVisible: Bool
    let isInputFocused: Bool
    let isStreaming: Bool
    let streamingStartTime: Date?

    // Pull-to-refresh for loading more messages
    let hasMoreMessages: Bool
    let isLoadingMore: Bool
    let onLoadMore: (() async -> Void)?

    @State private var scrollTask: Task<Void, Never>?
    @State private var lastScrolledCount = 0
    @State private var didTriggerLoadMore = false  // Track if we triggered load more (persists across re-renders)

    var body: some View {
        let _ = AppLogger.log("[ElementsScrollView] Rendering \(elements.count) elements, isStreaming=\(isStreaming), hasMore=\(hasMoreMessages)")
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Load more indicator at top (pull down to load older messages)
                        if hasMoreMessages {
                            LoadMoreIndicator(isLoading: isLoadingMore)
                                .id("loadMore")
                        }

                        ForEach(elements) { element in
                            ElementView(element: element, showTimestamp: showTimestamps)
                                .id(element.id)
                        }

                        // Extra padding at bottom when streaming indicator is visible
                        if isStreaming {
                            Color.clear
                                .frame(height: 40)
                        }

                        // Bottom anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xs)
                }
                .refreshable {
                    // Pull-to-refresh triggers load more (older messages)
                    // Use detached task to prevent cancellation when refresh gesture ends
                    if hasMoreMessages, let onLoadMore = onLoadMore {
                        AppLogger.log("[ElementsScrollView] Pull-to-refresh triggered")
                        didTriggerLoadMore = true  // Set flag before loading
                        await withCheckedContinuation { continuation in
                            Task.detached {
                                await onLoadMore()
                                continuation.resume()
                            }
                        }
                        AppLogger.log("[ElementsScrollView] Load more completed")
                    }
                }
                .onAppear {
                    AppLogger.log("[ElementsScrollView] onAppear with \(elements.count) elements, isLoadingMore=\(isLoadingMore)")
                    // Skip auto-scroll if we're in the middle of loading more messages
                    guard !isLoadingMore && !didTriggerLoadMore else {
                        AppLogger.log("[ElementsScrollView] Skipping onAppear scroll during load more")
                        return
                    }
                    scheduleScroll(proxy: proxy, animated: false)
                }
                .onChange(of: elements.count) { oldCount, newCount in
                    // Only scroll if count actually increased and we haven't just scrolled
                    guard newCount > oldCount, newCount != lastScrolledCount else { return }

                    // Skip auto-scroll when loading older messages (pull-to-refresh)
                    if didTriggerLoadMore {
                        AppLogger.log("[ElementsScrollView] Skipping auto-scroll after load more (\(oldCount) -> \(newCount))")
                        didTriggerLoadMore = false  // Reset flag after handling
                        return
                    }
                    scheduleScroll(proxy: proxy, animated: true)
                }
                .onChange(of: isVisible) { _, visible in
                    guard visible, !elements.isEmpty else { return }
                    scheduleScroll(proxy: proxy, animated: false)
                }
                .onChange(of: isInputFocused) { _, focused in
                    // Auto-scroll when keyboard appears or dismisses
                    guard !elements.isEmpty else { return }
                    if focused {
                        scheduleScrollForKeyboard(proxy: proxy)
                    } else {
                        // Re-adjust scroll when keyboard dismisses to remove extra space
                        scheduleScrollAfterKeyboardDismiss(proxy: proxy)
                    }
                }
                .onChange(of: isStreaming) { _, streaming in
                    // Auto-scroll when streaming starts to show indicator
                    guard streaming else { return }
                    scheduleScroll(proxy: proxy, animated: true)
                }
            }

            // Streaming indicator - fixed at bottom
            if isStreaming {
                StreamingIndicatorView(startTime: streamingStartTime)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, Spacing.xs)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: isStreaming)
            }
        }
    }

    /// Debounced scroll - cancels previous scroll task and schedules new one
    private func scheduleScroll(proxy: ScrollViewProxy, animated: Bool) {
        guard !elements.isEmpty else { return }

        // Cancel any pending scroll
        scrollTask?.cancel()

        // Schedule new scroll after brief delay to coalesce multiple updates
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else { return }

            lastScrolledCount = elements.count
            if animated {
                withAnimation(Animations.logAppear) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    /// Scroll for keyboard appearance - longer delay to wait for keyboard animation
    private func scheduleScrollForKeyboard(proxy: ScrollViewProxy) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            // Wait for keyboard animation to complete (300ms)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    /// Scroll adjustment after keyboard dismisses - removes extra space
    private func scheduleScrollAfterKeyboardDismiss(proxy: ScrollViewProxy) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            // Wait for keyboard dismiss animation to complete (250ms)
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            // Scroll to bottom to adjust content position
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - Logs Scroll View (Debounced)

/// Separate view to properly manage scroll state and prevent multiple updates per frame
private struct LogsScrollView: View {
    let logs: [LogEntry]
    let showTimestamps: Bool
    let isVisible: Bool
    let isInputFocused: Bool
    let shouldShowTimestamp: (LogEntry, LogEntry?) -> Bool

    @State private var scrollTask: Task<Void, Never>?
    @State private var lastScrolledCount = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(logs.enumerated()), id: \.element.id) { index, entry in
                        let previousEntry = index > 0 ? logs[index - 1] : nil
                        let showTime = shouldShowTimestamp(entry, previousEntry)
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
                scheduleScroll(proxy: proxy, animated: false)
            }
            .onChange(of: logs.count) { oldCount, newCount in
                // Only scroll if count actually increased and we haven't just scrolled
                guard newCount > oldCount, newCount != lastScrolledCount else { return }
                scheduleScroll(proxy: proxy, animated: true)
            }
            .onChange(of: isVisible) { _, visible in
                guard visible, !logs.isEmpty else { return }
                scheduleScroll(proxy: proxy, animated: false)
            }
            .onChange(of: isInputFocused) { _, focused in
                // Auto-scroll when keyboard appears (input focused)
                guard focused, !logs.isEmpty else { return }
                scheduleScrollForKeyboard(proxy: proxy)
            }
        }
    }

    /// Debounced scroll - cancels previous scroll task and schedules new one
    private func scheduleScroll(proxy: ScrollViewProxy, animated: Bool) {
        guard !logs.isEmpty else { return }

        // Cancel any pending scroll
        scrollTask?.cancel()

        // Schedule new scroll after brief delay to coalesce multiple updates
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else { return }

            lastScrolledCount = logs.count
            if animated {
                withAnimation(Animations.logAppear) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    /// Scroll for keyboard appearance - longer delay to wait for keyboard animation
    private func scheduleScrollForKeyboard(proxy: ScrollViewProxy) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            // Wait for keyboard animation to complete (300ms)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - Streaming Indicator

/// Shows when Claude is actively thinking/streaming
/// Similar to Claude CLI's "Concocting... (esc to interrupt · thought for 2s)"
struct StreamingIndicatorView: View {
    let startTime: Date?

    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Pulsing brain icon
            Image(systemName: "brain")
                .font(.system(size: 10))
                .foregroundStyle(ColorSystem.primary)
                .symbolEffect(.pulse)

            Text("Thinking...")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textSecondary)

            if elapsedSeconds > 0 {
                Text("(\(elapsedSeconds)s)")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: startTime) { _, _ in
            elapsedSeconds = 0
            startTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        updateElapsed()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateElapsed()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateElapsed() {
        guard let startTime = startTime else {
            elapsedSeconds = 0
            return
        }
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(startTime)))
    }
}

// MARK: - Load More Indicator

/// Shows at top of list when more messages are available
/// Tappable to load older messages, or use pull-to-refresh
private struct LoadMoreIndicator: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(ColorSystem.textTertiary)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10))
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            Text(isLoading ? "Loading..." : "Pull to load more")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
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
