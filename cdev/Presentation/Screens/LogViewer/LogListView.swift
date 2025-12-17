import SwiftUI

/// Compact log list - terminal-style view optimized for developer productivity
struct LogListView: View {
    let logs: [LogEntry]
    let onClear: () -> Void

    @AppStorage(Constants.UserDefaults.showTimestamps) private var showTimestamps = true

    var body: some View {
        Group {
            if logs.isEmpty {
                EmptyStateView(
                    icon: "terminal",
                    title: "No Output",
                    subtitle: "Claude's output will appear here"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(logs) { entry in
                                LogEntryRow(entry: entry, showTimestamp: showTimestamps)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                    }
                    .onChange(of: logs.count) { _, _ in
                        // Auto-scroll to bottom
                        if let lastLog = logs.last {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .background(Color.black)
            }
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry
    let showTimestamp: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // Compact timestamp (HH:mm:ss only)
            if showTimestamp {
                Text(compactTimestamp)
                    .font(Typography.terminalTimestamp)
                    .foregroundStyle(Color.gray.opacity(0.6))
                    .frame(width: 48, alignment: .leading)
            }

            // Content - compact terminal font
            Text(entry.content)
                .font(Typography.terminal)
                .foregroundStyle(entryColor)
                .textSelection(.enabled)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp)
    }

    private var entryColor: Color {
        switch entry.stream {
        case .stdout:
            return .white
        case .stderr:
            return .logStderr
        case .system:
            return .logInfo
        }
    }
}

// MARK: - Compact Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(Typography.footnote)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(Typography.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }
}
