import SwiftUI

/// Pulse Terminal Log Viewer - optimized for developer productivity
struct LogListView: View {
    let logs: [LogEntry]
    let onClear: () -> Void

    @AppStorage(Constants.UserDefaults.showTimestamps) private var showTimestamps = true

    var body: some View {
        Group {
            if logs.isEmpty {
                EmptyStateView(
                    icon: Icons.terminal,
                    title: "No Output",
                    subtitle: "Claude's output will appear here"
                )
            } else {
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
                        }
                        .padding(.horizontal, Spacing.xs)
                        .padding(.top, Spacing.xxs)
                        .padding(.bottom, Spacing.sm)
                    }
                    .onChange(of: logs.count) { oldCount, newCount in
                        // Auto-scroll to bottom when logs change
                        guard let lastLog = logs.last else { return }

                        if oldCount > 0 && newCount > oldCount {
                            // Incremental update - scroll with animation
                            withAnimation(Animations.logAppear) {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        } else if newCount > 0 {
                            // Initial load or bulk update - wait for LazyVStack to render
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBg)
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

            // Content with stream-based colors
            Text(entry.content)
                .font(Typography.terminal)
                .foregroundStyle(streamColor)
                .textSelection(.enabled)
                .lineSpacing(1)
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
