import SwiftUI

/// Admin Tools View - Debug log viewer for developers
/// Sophisticated, responsive, theme-aware UI for tracing HTTP/WebSocket/App events
struct AdminToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var logStore = DebugLogStore.shared

    @State private var selectedCategory: DebugLogCategory = .all
    @State private var searchText = ""
    @State private var selectedLog: DebugLogEntry?

    /// Filtered logs based on category and search
    private var filteredLogs: [DebugLogEntry] {
        var logs = logStore.logs(for: selectedCategory)

        if !searchText.isEmpty {
            logs = logs.filter { log in
                log.title.localizedCaseInsensitiveContains(searchText) ||
                log.subtitle?.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        return logs.reversed() // Most recent first
    }

    /// Adaptive column layout for iPad
    private var isCompact: Bool {
        sizeClass == .compact
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter bar
                CategoryFilterBar(
                    selectedCategory: $selectedCategory,
                    logCounts: logCounts
                )

                // Control bar with search and actions
                ControlBar(
                    searchText: $searchText,
                    isPaused: $logStore.isPaused,
                    autoScroll: $logStore.autoScroll,
                    onClear: { logStore.clear(category: selectedCategory) },
                    onExport: exportLogs
                )

                // Main content
                if filteredLogs.isEmpty {
                    EmptyLogsView(category: selectedCategory, isSearching: !searchText.isEmpty)
                } else {
                    if isCompact {
                        // iPhone: Full width log list with sheet detail
                        DebugLogListView(
                            logs: filteredLogs,
                            selectedLog: $selectedLog,
                            autoScroll: logStore.autoScroll
                        )
                    } else {
                        // iPad: Split view with side-by-side detail
                        HStack(spacing: 0) {
                            DebugLogListView(
                                logs: filteredLogs,
                                selectedLog: $selectedLog,
                                autoScroll: logStore.autoScroll
                            )
                            .frame(maxWidth: 400)

                            Divider()
                                .background(ColorSystem.terminalBgHighlight)

                            // Detail pane
                            if let log = selectedLog {
                                DebugLogDetailView(entry: log)
                            } else {
                                DetailPlaceholderView()
                            }
                        }
                    }
                }
            }
            .background(ColorSystem.terminalBg)
            .floatingKeyboardDismissButton()
            .navigationTitle("Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Typography.buttonLabel)
                }
            }
            .sheet(item: $selectedLog) { log in
                if isCompact {
                    NavigationStack {
                        DebugLogDetailView(entry: log)
                            .navigationTitle("Log Detail")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") {
                                        selectedLog = nil
                                    }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    /// Log counts per category
    private var logCounts: [DebugLogCategory: Int] {
        var counts: [DebugLogCategory: Int] = [:]
        counts[.all] = logStore.logs.count
        counts[.http] = logStore.logs(for: .http).count
        counts[.websocket] = logStore.logs(for: .websocket).count
        counts[.app] = logStore.logs(for: .app).count
        return counts
    }

    /// Export logs to clipboard
    private func exportLogs() {
        let text = logStore.exportLogs(category: selectedCategory)
        UIPasteboard.general.string = text
        Haptics.success()
    }
}

// MARK: - Category Filter Bar

private struct CategoryFilterBar: View {
    @Binding var selectedCategory: DebugLogCategory
    let logCounts: [DebugLogCategory: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(DebugLogCategory.allCases) { category in
                    CategoryPill(
                        category: category,
                        count: logCounts[category] ?? 0,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(Animations.stateChange) {
                            selectedCategory = category
                        }
                        Haptics.selection()
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .background(ColorSystem.terminalBgElevated)
    }
}

private struct CategoryPill: View {
    let category: DebugLogCategory
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: category.icon)
                    .font(.system(size: 10, weight: .semibold))

                Text(category.rawValue)
                    .font(Typography.tabLabel)

                if count > 0 {
                    Text("\(min(count, 999))")
                        .font(Typography.badge)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            isSelected
                                ? category.color.opacity(0.3)
                                : ColorSystem.terminalBgHighlight
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .foregroundStyle(isSelected ? category.color : ColorSystem.textSecondary)
            .background(
                isSelected
                    ? category.color.opacity(0.15)
                    : ColorSystem.terminalBgHighlight
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? category.color.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Control Bar

private struct ControlBar: View {
    @Binding var searchText: String
    @Binding var isPaused: Bool
    @Binding var autoScroll: Bool
    let onClear: () -> Void
    let onExport: () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Search field
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("Filter logs...", text: $searchText)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ColorSystem.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
            .frame(height: 28)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

            // Control buttons
            HStack(spacing: Spacing.xxs) {
                // Pause/Resume
                ControlButton(
                    icon: isPaused ? "play.fill" : "pause.fill",
                    color: isPaused ? ColorSystem.warning : ColorSystem.textSecondary,
                    isActive: isPaused
                ) {
                    isPaused.toggle()
                    Haptics.light()
                }

                // Auto-scroll
                ControlButton(
                    icon: "arrow.down.to.line",
                    color: autoScroll ? ColorSystem.primary : ColorSystem.textSecondary,
                    isActive: autoScroll
                ) {
                    autoScroll.toggle()
                    Haptics.light()
                }

                // Export
                ControlButton(
                    icon: "doc.on.clipboard",
                    color: ColorSystem.textSecondary,
                    isActive: false
                ) {
                    onExport()
                }

                // Clear
                ControlButton(
                    icon: "trash",
                    color: ColorSystem.error,
                    isActive: false
                ) {
                    onClear()
                    Haptics.warning()
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
    }
}

private struct ControlButton: View {
    let icon: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(
                    isActive
                        ? color.opacity(0.15)
                        : ColorSystem.terminalBgHighlight
                )
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Debug Log List View

private struct DebugLogListView: View {
    let logs: [DebugLogEntry]
    @Binding var selectedLog: DebugLogEntry?
    let autoScroll: Bool

    @State private var scrollTask: Task<Void, Never>?
    @State private var lastScrolledCount = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(logs) { log in
                        DebugLogRowView(
                            entry: log,
                            isSelected: selectedLog?.id == log.id
                        ) {
                            selectedLog = log
                        }
                        .id(log.id)

                        Divider()
                            .background(ColorSystem.terminalBgHighlight.opacity(0.5))
                    }
                }
            }
            .onChange(of: logs.count) { oldCount, newCount in
                guard autoScroll, newCount > oldCount, newCount != lastScrolledCount else { return }
                scheduleScroll(proxy: proxy)
            }
        }
        .background(ColorSystem.terminalBg)
    }

    /// Debounced scroll to prevent multiple updates per frame
    private func scheduleScroll(proxy: ScrollViewProxy) {
        guard !logs.isEmpty, let firstLog = logs.first else { return }

        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else { return }

            lastScrolledCount = logs.count
            withAnimation {
                proxy.scrollTo(firstLog.id, anchor: .top)
            }
        }
    }
}

// MARK: - Debug Log Row View (Compact)

private struct DebugLogRowView: View {
    let entry: DebugLogEntry
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                // Category indicator
                CategoryIndicator(category: entry.category, level: entry.level)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    // Title row
                    HStack(spacing: Spacing.xxs) {
                        Text(entry.title)
                            .font(Typography.terminal)
                            .foregroundStyle(entry.level.color)
                            .lineLimit(1)

                        Spacer()

                        // Status badge for HTTP
                        if case .http(let details) = entry.details {
                            if let status = details.responseStatus {
                                StatusBadge(status: status)
                            }
                        }

                        // Timestamp
                        Text(entry.timeString)
                            .font(Typography.terminalTimestamp)
                            .foregroundStyle(ColorSystem.textQuaternary)
                    }

                    // Subtitle (if present)
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textTertiary)
                            .lineLimit(1)
                    }
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? ColorSystem.terminalBgSelected : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CategoryIndicator: View {
    let category: DebugLogCategory
    let level: DebugLogLevel

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .fill(indicatorColor.opacity(0.15))
                .frame(width: 24, height: 24)

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(indicatorColor)
        }
    }

    private var indicatorColor: Color {
        if level == .error {
            return ColorSystem.error
        } else if level == .warning {
            return ColorSystem.warning
        }
        return category.color
    }

    private var iconName: String {
        switch (category, level) {
        case (_, .error): return "exclamationmark.triangle.fill"
        case (_, .warning): return "exclamationmark.circle.fill"
        case (.http, _): return "arrow.up.arrow.down"
        case (.websocket, _): return "bolt.fill"
        case (.app, _): return "app.fill"
        case (.all, _): return "list.bullet"
        }
    }
}

private struct StatusBadge: View {
    let status: Int

    var body: some View {
        Text("\(status)")
            .font(Typography.badge)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        if (200...299).contains(status) { return ColorSystem.success }
        if (400...499).contains(status) { return ColorSystem.warning }
        return ColorSystem.error
    }
}

// MARK: - Empty State

private struct EmptyLogsView: View {
    let category: DebugLogCategory
    let isSearching: Bool

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: isSearching ? "magnifyingglass" : "tray")
                .font(.system(size: 40))
                .foregroundStyle(ColorSystem.textQuaternary)

            VStack(spacing: Spacing.xxs) {
                Text(isSearching ? "No matches" : "No logs yet")
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textSecondary)

                Text(isSearching
                     ? "Try a different search term"
                     : "Logs will appear as events occur")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBg)
    }
}

// MARK: - Detail Placeholder (iPad)

private struct DetailPlaceholderView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(ColorSystem.textQuaternary)

            Text("Select a log to view details")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBg)
    }
}

// MARK: - Preview

#Preview {
    AdminToolsView()
}
