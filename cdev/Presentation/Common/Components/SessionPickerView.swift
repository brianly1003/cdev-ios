import SwiftUI

/// Session picker sheet for /resume command - Compact UI
struct SessionPickerView: View {
    let sessions: [SessionsResponse.SessionInfo]
    let currentSessionId: String?
    let hasMore: Bool
    let isLoadingMore: Bool
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onDeleteAll: () -> Void
    let onLoadMore: () -> Void
    let onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var showDeleteAllAlert = false

    var filteredSessions: [SessionsResponse.SessionInfo] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter { session in
            session.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Compact search bar
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(ColorSystem.textTertiary)
                    TextField("Search...", text: $searchText)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textPrimary)
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 6)
                .background(ColorSystem.terminalBgElevated)
                .cornerRadius(6)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)

                Divider().background(ColorSystem.terminalBgHighlight)

                if filteredSessions.isEmpty {
                    // Empty state
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundStyle(ColorSystem.textQuaternary)
                        Text("No sessions")
                            .font(Typography.terminal)
                            .foregroundStyle(ColorSystem.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ColorSystem.terminalBg)
                } else {
                    // Session list with native swipe actions
                    List {
                        ForEach(filteredSessions) { session in
                            SessionRowView(
                                session: session,
                                isCurrentSession: session.sessionId == currentSessionId
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(
                                session.sessionId == currentSessionId
                                    ? ColorSystem.success.opacity(0.08)
                                    : ColorSystem.terminalBg
                            )
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.selection()
                                onSelect(session.sessionId)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(session.sessionId)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(ColorSystem.error)
                            }
                        }

                        // Load More button (only show when not searching and has more)
                        if hasMore && searchText.isEmpty {
                            Button {
                                onLoadMore()
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoadingMore {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(ColorSystem.primary)
                                    } else {
                                        Text("Load More")
                                            .font(Typography.terminal)
                                            .foregroundStyle(ColorSystem.primary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, Spacing.sm)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(ColorSystem.terminalBg)
                            .listRowSeparator(.hidden)
                            .disabled(isLoadingMore)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(ColorSystem.terminalBg)
                }
            }
            .background(ColorSystem.terminalBg)
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .font(Typography.terminal)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if !sessions.isEmpty {
                        Button {
                            showDeleteAllAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                        }
                        .tint(ColorSystem.error)
                    }
                }
            }
            .alert("Delete All Sessions?", isPresented: $showDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    onDeleteAll()
                    onDismiss()
                }
            } message: {
                Text("This will permanently delete all \(sessions.count) sessions.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

/// Simple session row view (no custom swipe - uses native swipeActions)
struct SessionRowView: View {
    let session: SessionsResponse.SessionInfo
    let isCurrentSession: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Status indicator
            Circle()
                .fill(isCurrentSession ? ColorSystem.success : ColorSystem.textQuaternary)
                .frame(width: 6, height: 6)

            // Summary
            Text(session.summary)
                .font(Typography.terminal)
                .foregroundStyle(isCurrentSession ? ColorSystem.success : ColorSystem.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Spacing.xs)

            // Compact meta
            HStack(spacing: 4) {
                Text(session.compactTime)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textQuaternary)

                Text("·")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textQuaternary)

                HStack(spacing: 2) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 8))
                    Text("\(session.messageCount)")
                }
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textQuaternary)
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ColorSystem.textQuaternary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .frame(minHeight: 44)
        .overlay(
            Rectangle()
                .fill(ColorSystem.terminalBgHighlight)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

// MARK: - SessionInfo Extension

extension SessionsResponse.SessionInfo {
    /// Relative time string (e.g., "4 min ago")
    var relativeTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: lastUpdated) else {
            return lastUpdated
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    /// Compact time string (e.g., "5m", "2h", "3d")
    var compactTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: lastUpdated) else {
            return "--"
        }

        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
        }
    }
}
