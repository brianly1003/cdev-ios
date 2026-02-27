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
    var spinnerMessage: String?  // Custom message from pty_spinner events

    // Pull-to-refresh for loading more messages
    var hasMoreMessages: Bool = false
    var isLoadingMore: Bool = false
    var onLoadMore: (() async -> Void)?

    // Search state - individual values for reactivity
    var searchText: String = ""
    var matchingElementIds: [String] = []
    var currentMatchIndex: Int = 0

    // Scroll request (from floating toolkit long-press)
    var scrollRequest: ScrollDirection?

    @AppStorage(Constants.UserDefaults.showTimestamps) private var showTimestamps = true
    @AppStorage(Constants.UserDefaults.useElementsView) private var useElementsView = true  // Feature flag

    init(logs: [LogEntry], elements: [ChatElement] = [], onClear: @escaping () -> Void, isVisible: Bool = true, isInputFocused: Bool = false, isStreaming: Bool = false, spinnerMessage: String? = nil, hasMoreMessages: Bool = false, isLoadingMore: Bool = false, onLoadMore: (() async -> Void)? = nil, searchText: String = "", matchingElementIds: [String] = [], currentMatchIndex: Int = 0, scrollRequest: ScrollDirection? = nil) {
        self.logs = logs
        self.elements = elements
        self.onClear = onClear
        self.isVisible = isVisible
        self.isInputFocused = isInputFocused
        self.isStreaming = isStreaming
        self.spinnerMessage = spinnerMessage
        self.hasMoreMessages = hasMoreMessages
        self.isLoadingMore = isLoadingMore
        self.onLoadMore = onLoadMore
        self.searchText = searchText
        self.matchingElementIds = matchingElementIds
        self.currentMatchIndex = currentMatchIndex
        self.scrollRequest = scrollRequest
    }

    var body: some View {
        let _ = AppLogger.log("[LogListView] Rendering: elements=\(elements.count), logs=\(logs.count), useElementsView=\(useElementsView)")
        Group {
            if elements.isEmpty && logs.isEmpty {
                // Empty state with pull-to-refresh support
                emptyStateView
            } else if useElementsView && !elements.isEmpty {
                // NEW: Sophisticated Elements API view
                elementsListView
            } else if !logs.isEmpty {
                // Legacy: LogEntry-based view
                logsListView
            } else {
                // Empty state with pull-to-refresh support
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBg)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isStreaming {
                // Keep streaming status pinned above the action bar instead of in the scroll flow.
                StreamingIndicatorView(message: spinnerMessage)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.top, Spacing.xxxs)
                    .padding(.bottom, Spacing.xxxs)
                    .background(ColorSystem.terminalBg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Empty State View (with pull-to-refresh)

    @ViewBuilder
    private var emptyStateView: some View {
        ScrollView {
            EmptyStateView(
                icon: Icons.terminal,
                title: "No Output",
                subtitle: "Claude's output will appear here"
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        }
        .refreshable {
            // Pull-to-refresh triggers load more (older messages)
            if let onLoadMore = onLoadMore {
                AppLogger.log("[LogListView] Empty state pull-to-refresh triggered")
                await withCheckedContinuation { continuation in
                    Task.detached {
                        await onLoadMore()
                        continuation.resume()
                    }
                }
            }
        }
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
            spinnerMessage: spinnerMessage,
            hasMoreMessages: hasMoreMessages,
            isLoadingMore: isLoadingMore,
            onLoadMore: onLoadMore,
            searchText: searchText,
            matchingElementIds: matchingElementIds,
            currentMatchIndex: currentMatchIndex,
            scrollRequest: scrollRequest
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
        let cleanContent = content.hasPrefix("> ") ? String(content.dropFirst(2)) : content
        let isBashCommand = cleanContent.hasPrefix("!")
        let promptColor = isBashCommand ? ColorSystem.success : ColorSystem.Log.user
        // Strip leading "!" from text if it's a bash command (we show it as prompt symbol)
        let displayText = isBashCommand ? String(cleanContent.dropFirst()).trimmingCharacters(in: .whitespaces) : cleanContent

        HStack(alignment: .top, spacing: 4) {
            if isBashCommand {
                // Bash command - show "!" in green
                Text("!")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(promptColor)
            } else {
                // Regular user message - show chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(promptColor)
            }

            Text(displayText)
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
    var spinnerMessage: String?  // Custom message from pty_spinner events

    // Pull-to-refresh for loading more messages
    let hasMoreMessages: Bool
    let isLoadingMore: Bool
    let onLoadMore: (() async -> Void)?

    // Search support - pass values directly for reactivity
    var searchText: String = ""
    var matchingElementIds: [String] = []
    var currentMatchIndex: Int = 0

    // Scroll request (from floating toolkit long-press)
    var scrollRequest: ScrollDirection?

    @State private var scrollTask: Task<Void, Never>?
    @State private var lastScrolledCount = 0
    @State private var didTriggerLoadMore = false  // Track if we triggered load more (persists across re-renders)
    @State private var needsCatchUpScrollOnVisible = false

    /// Current highlighted element ID
    private var currentMatchId: String? {
        guard !matchingElementIds.isEmpty, currentMatchIndex < matchingElementIds.count else { return nil }
        return matchingElementIds[currentMatchIndex]
    }

    /// Check if an element is a search match
    private func isMatch(_ element: ChatElement) -> Bool {
        matchingElementIds.contains(element.id)
    }

    var body: some View {
        let _ = AppLogger.log("[ElementsScrollView] Rendering \(elements.count) elements, isStreaming=\(isStreaming), hasMore=\(hasMoreMessages)")
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Top anchor - always present for stable scroll-to-top
                    Color.clear
                        .frame(height: 1)
                        .id("top")

                    // Load more indicator at top (pull down to load older messages)
                    if hasMoreMessages {
                        LoadMoreIndicator(isLoading: isLoadingMore)
                            .id("loadMore")
                    }

                    ForEach(elements) { element in
                        ElementView(
                            element: element,
                            showTimestamp: showTimestamps,
                            searchText: searchText,
                            isCurrentMatch: element.id == currentMatchId,
                            isMatch: isMatch(element)
                        )
                        .id(element.id)
                    }

                    // Bottom anchor - always present for stable scroll-to-bottom
                    // Height ensures comfortable spacing below last message when auto-scrolled
                    Color.clear
                        .frame(height: Spacing.md)
                        .id("bottom")
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xl)
            }
            .refreshable {
                // Pull-to-refresh triggers load more (older messages) or refreshes latest.
                // Use detached task to prevent cancellation when refresh gesture ends.
                if let onLoadMore = onLoadMore {
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
                AppLogger.log("[ElementsScrollView] onAppear - elementsCount=\(elements.count), isLoadingMore=\(isLoadingMore), isVisible=\(isVisible)")
                // IMPORTANT: Skip scroll if tab is not visible
                // This prevents LazyVStack content disappearing bug - see handleScrollRequest docs
                guard isVisible else {
                    AppLogger.log("[ElementsScrollView] Skipping onAppear scroll - tab not visible")
                    return
                }
                // Skip auto-scroll if we're in the middle of loading more messages
                guard !isLoadingMore && !didTriggerLoadMore else {
                    AppLogger.log("[ElementsScrollView] Skipping onAppear scroll during load more")
                    return
                }
                scheduleScroll(proxy: proxy, animated: false)
            }
            .onDisappear {
                AppLogger.log("[ElementsScrollView] onDisappear - elementsCount=\(elements.count)")
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

                guard isVisible else {
                    needsCatchUpScrollOnVisible = true
                    AppLogger.log("[ElementsScrollView] Deferring auto-scroll while hidden (\(oldCount) -> \(newCount))")
                    return
                }
                scheduleScroll(proxy: proxy, animated: true)
            }
            .onChange(of: isVisible) { oldVisible, newVisible in
                AppLogger.log("[ElementsScrollView] isVisible changed - old=\(oldVisible), new=\(newVisible), elementsCount=\(elements.count)")
                if !newVisible {
                    scrollTask?.cancel()
                    return
                }

                // If messages were appended while hidden, perform one safe catch-up scroll.
                if needsCatchUpScrollOnVisible {
                    needsCatchUpScrollOnVisible = false
                    guard !isLoadingMore && !didTriggerLoadMore else {
                        AppLogger.log("[ElementsScrollView] Catch-up scroll deferred during load more")
                        return
                    }
                    scheduleScroll(proxy: proxy, animated: false)
                }
            }
            .onChange(of: isInputFocused) { _, focused in
                // Auto-scroll when keyboard appears or dismisses
                guard isVisible, !elements.isEmpty else { return }
                if focused {
                    scheduleScrollForKeyboard(proxy: proxy)
                } else {
                    // Re-adjust scroll when keyboard dismisses to remove extra space
                    scheduleScrollAfterKeyboardDismiss(proxy: proxy)
                }
            }
            .onChange(of: isStreaming) { _, streaming in
                // Auto-scroll when streaming starts to show indicator
                // NOTE: Use non-animated scroll to prevent AttributeGraph cycle
                guard streaming else { return }
                guard isVisible else {
                    needsCatchUpScrollOnVisible = true
                    AppLogger.log("[ElementsScrollView] Deferring streaming auto-scroll while hidden")
                    return
                }
                scheduleScroll(proxy: proxy, animated: false)
            }
            .onChange(of: currentMatchIndex) { _, _ in
                // Scroll to current search match
                if isVisible, let matchId = currentMatchId {
                    scrollToMatch(proxy: proxy, matchId: matchId)
                }
            }
            .onChange(of: scrollRequest) { oldValue, newValue in
                // Handle scroll request from floating toolkit
                AppLogger.log("[ElementsScrollView] scrollRequest onChange - old=\(String(describing: oldValue)), new=\(String(describing: newValue))")
                guard let direction = newValue else {
                    AppLogger.log("[ElementsScrollView] scrollRequest is nil, ignoring")
                    return
                }
                guard isVisible else {
                    AppLogger.log("[ElementsScrollView] Ignoring scrollRequest while hidden")
                    return
                }
                handleScrollRequest(direction: direction, proxy: proxy)
            }
        }
    }

    /// Debounced scroll - cancels previous scroll task and schedules new one
    private func scheduleScroll(proxy: ScrollViewProxy, animated: Bool) {
        AppLogger.log("[ElementsScrollView] scheduleScroll called - animated=\(animated), elementsCount=\(elements.count), isStreaming=\(isStreaming)")
        guard !elements.isEmpty else {
            AppLogger.log("[ElementsScrollView] scheduleScroll - SKIPPED (elements empty)")
            return
        }

        // Cancel any pending scroll
        scrollTask?.cancel()

        // Schedule new scroll after brief delay to coalesce multiple updates
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else {
                AppLogger.log("[ElementsScrollView] scheduleScroll task cancelled")
                return
            }

            lastScrolledCount = elements.count

            // Prefer the last element ID to avoid LazyVStack anchor overshoot on first load.
            // Use the bottom anchor only when streaming so the extra padding is respected.
            let targetId: String = {
                if isStreaming {
                    return "bottom"
                }
                return elements.last?.id ?? "bottom"
            }()
            AppLogger.log("[ElementsScrollView] scheduleScroll executing - targetId=\(targetId), animated=\(animated), elementsCount=\(elements.count), isStreaming=\(isStreaming)")
            if animated {
                withAnimation(Animations.logAppear) {
                    proxy.scrollTo(targetId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(targetId, anchor: .bottom)
            }
            AppLogger.log("[ElementsScrollView] scheduleScroll completed")
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

            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    /// Scroll to a specific search match
    private func scrollToMatch(proxy: ScrollViewProxy, matchId: String) {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(matchId, anchor: .center)
            }
        }
    }

    /// Handle scroll request from floating toolkit long-press
    ///
    /// # Known Issue: LazyVStack + ScrollViewReader Animation Bug (December 2024)
    ///
    /// ## Problem
    /// When using `withAnimation` with `proxy.scrollTo()` on a LazyVStack, the view content
    /// can disappear completely. This happens because:
    /// 1. LazyVStack only realizes (renders) content that's visible in the viewport
    /// 2. Animated scrollTo with certain anchors can cause the scroll position to overshoot
    /// 3. When scroll overshoots past content bounds, LazyVStack has nothing to render
    /// 4. Additionally, calling scrollTo when `isVisible=false` (tab not shown) causes issues
    ///
    /// ## Solutions Applied
    /// 1. **Use element IDs instead of anchors**: Scroll to `elements.first?.id` or `elements.last?.id`
    ///    instead of "top"/"bottom" anchors. This forces content realization.
    /// 2. **Spring animation with no bounce**: Use `dampingFraction: 1.0` to prevent overshoot
    /// 3. **Proper anchor selection**: Use `.top` for scroll-to-top, `.bottom` for scroll-to-bottom
    /// 4. **Check isVisible before scrolling**: Skip scroll in `onAppear` if tab is not visible
    ///
    /// ## What Didn't Work
    /// - Using Color.clear anchors with `.id("bottom")` - LazyVStack doesn't realize content
    /// - easeInOut animation - can overshoot on long scrolls
    /// - `.top` anchor for scroll-to-bottom - positions last element at top, can overshoot below
    ///
    private func handleScrollRequest(direction: ScrollDirection, proxy: ScrollViewProxy) {
        AppLogger.log("[ElementsScrollView] handleScrollRequest called - direction=\(direction), elementsCount=\(elements.count)")

        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else {
                AppLogger.log("[ElementsScrollView] Scroll task was cancelled")
                return
            }

            AppLogger.log("[ElementsScrollView] Executing scroll - direction=\(direction)")

            // Use spring animation without bounce to prevent overshoot
            let scrollAnimation = Animation.spring(response: 0.35, dampingFraction: 1.0, blendDuration: 0)

            switch direction {
            case .top:
                // Always scroll to "top" anchor (before the top padding)
                AppLogger.log("[ElementsScrollView] Scrolling to TOP - anchor=.top, elementsCount=\(elements.count)")
                withAnimation(scrollAnimation) {
                    proxy.scrollTo("top", anchor: .top)
                }
                AppLogger.log("[ElementsScrollView] scrollTo completed for TOP")

            case .bottom:
                // Always scroll to "bottom" anchor (after the bottom padding)
                AppLogger.log("[ElementsScrollView] Scrolling to BOTTOM - anchor=.bottom, elementsCount=\(elements.count)")
                withAnimation(scrollAnimation) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                AppLogger.log("[ElementsScrollView] scrollTo completed for BOTTOM")
            }

            // Log state after scroll
            AppLogger.log("[ElementsScrollView] Post-scroll state - elementsCount=\(elements.count), hasMore=\(hasMoreMessages)")
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
    @State private var needsCatchUpScrollOnVisible = false

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
                    // Bottom anchor - height ensures comfortable spacing
                    Color.clear
                        .frame(height: Spacing.md)
                        .id("bottom")
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xs)
            }
            .onAppear {
                guard isVisible else { return }
                scheduleScroll(proxy: proxy, animated: false)
            }
            .onChange(of: logs.count) { oldCount, newCount in
                // Only scroll if count actually increased and we haven't just scrolled
                guard newCount > oldCount, newCount != lastScrolledCount else { return }
                guard isVisible else {
                    needsCatchUpScrollOnVisible = true
                    return
                }
                scheduleScroll(proxy: proxy, animated: true)
            }
            .onChange(of: isVisible) { _, visible in
                if !visible {
                    scrollTask?.cancel()
                    return
                }
                if needsCatchUpScrollOnVisible {
                    needsCatchUpScrollOnVisible = false
                    scheduleScroll(proxy: proxy, animated: false)
                }
            }
            .onChange(of: isInputFocused) { _, focused in
                // Auto-scroll when keyboard appears (input focused)
                guard isVisible, focused, !logs.isEmpty else { return }
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
/// Displays the spinner message from Claude's PTY (e.g., "Vibing… (thought for 2s)")
///
/// Note: Timer-based elapsed time tracking was removed because:
/// 1. Claude's PTY spinner already includes timing in the message
/// 2. The Timer caused @State writes during view updates, triggering AttributeGraph cycles
/// 3. See docs/issues/streaming-indicator-animation-cycle.md for details
struct StreamingIndicatorView: View {
    var message: String?  // Custom message from pty_spinner (e.g., "Vibing…")

    private var displayParts: (main: String, hint: String?) {
        let fallback = "Thinking…"
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = (trimmed?.isEmpty == false) ? (trimmed ?? fallback) : fallback

        // Split into:
        // - main: "Thinking..." / "Vibing..."
        // - hint: "(tap stop to interrupt)" (lighter)
        if let hintStart = raw.range(of: " (") {
            let main = String(raw[..<hintStart.lowerBound]).trimmingCharacters(in: .whitespaces)
            let hint = String(raw[hintStart.lowerBound...]).trimmingCharacters(in: .whitespaces)
            if !main.isEmpty, !hint.isEmpty {
                return (main, hint)
            }
        }

        return (raw, nil)
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Pulsing brain icon
            Image(systemName: "brain")
                .font(.system(size: 10))
                .foregroundStyle(ColorSystem.primary)
                .symbolEffect(.pulse)

            if let hint = displayParts.hint {
                (
                    Text(displayParts.main)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ColorSystem.textSecondary)
                    + Text(" ")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textSecondary)
                    + Text(hint)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                )
            } else {
                Text(displayParts.main)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, Spacing.xs)
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
