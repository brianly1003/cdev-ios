import SwiftUI

/// Compact log list - terminal-style view
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
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(logs) { entry in
                                LogEntryRow(entry: entry, showTimestamp: showTimestamps)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !logs.isEmpty {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                }
            }
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry
    let showTimestamp: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            // Timestamp
            if showTimestamp {
                Text(entry.formattedTimestamp)
                    .font(Typography.codeSmall)
                    .foregroundStyle(Color.gray)
                    .frame(width: 70, alignment: .leading)
            }

            // Content
            Text(entry.content)
                .font(Typography.code)
                .foregroundStyle(entryColor)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(Typography.title3)
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(Typography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}
