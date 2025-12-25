import SwiftUI

/// Session picker sheet for /resume command - Compact UI
/// Now with navigation to session history detail view
struct SessionPickerView: View {
    let sessions: [SessionsResponse.SessionInfo]
    let currentSessionId: String?
    let workspaceId: String?
    let hasMore: Bool
    let isLoadingMore: Bool
    let agentRepository: AgentRepositoryProtocol
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onDeleteAll: () -> Void
    let onLoadMore: () -> Void
    let onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var showDeleteAllAlert = false
    @State private var selectedSession: SessionsResponse.SessionInfo?

    var filteredSessions: [SessionsResponse.SessionInfo] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter { session in
            session.summary.localizedCaseInsensitiveContains(searchText) ||
            session.sessionId.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
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
                    // Session list with navigation to history
                    List {
                        ForEach(filteredSessions) { session in
                            NavigationLink {
                                SessionHistoryView(
                                    session: session,
                                    agentRepository: agentRepository,
                                    workspaceId: workspaceId,
                                    onResume: {
                                        onSelect(session.sessionId)
                                    }
                                )
                            } label: {
                                SessionRowView(
                                    session: session,
                                    isCurrentSession: session.sessionId == currentSessionId
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8))
                            .listRowBackground(
                                session.sessionId == currentSessionId
                                    ? ColorSystem.success.opacity(0.08)
                                    : ColorSystem.terminalBg
                            )
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(session.sessionId)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(ColorSystem.error)
                            }
                            // Quick resume on swipe left
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    Haptics.selection()
                                    onSelect(session.sessionId)
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .tint(ColorSystem.primary)
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
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8))
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
        .responsiveSheet()
        .preferredColorScheme(.dark)
    }
}

/// Simple session row view (no custom swipe - uses native swipeActions)
/// Shows running vs historical status with visual indicators
struct SessionRowView: View {
    let session: SessionsResponse.SessionInfo
    let isCurrentSession: Bool

    /// Status color based on session state
    private var statusColor: Color {
        if isCurrentSession {
            return ColorSystem.success
        }
        return session.isRunning ? ColorSystem.success : ColorSystem.textQuaternary
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Status indicator - pulsing for running sessions
            ZStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                // Pulse animation for running sessions
                if session.isRunning {
                    Circle()
                        .stroke(statusColor, lineWidth: 1)
                        .frame(width: 10, height: 10)
                        .opacity(0.5)
                }
            }
            .frame(width: 12, height: 12)

            // Summary and Session ID
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(session.summary)
                        .font(Typography.terminal)
                        .foregroundStyle(isCurrentSession ? ColorSystem.success : ColorSystem.textPrimary)
                        .lineLimit(1)

                    // Running badge for active sessions
                    if session.isRunning {
                        Text("RUNNING")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(ColorSystem.success)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(ColorSystem.success.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                // Session ID (small, truncated)
                Text(session.sessionId)
                    .font(Typography.terminalTimestamp)
                    .foregroundStyle(ColorSystem.textQuaternary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            // Compact meta - close to chevron
            VStack(alignment: .trailing, spacing: 2) {
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

                // Viewer count if others are viewing
                if session.viewerCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "eye")
                            .font(.system(size: 7))
                        Text("\(session.viewerCount)")
                    }
                    .font(Typography.terminalTimestamp)
                    .foregroundStyle(ColorSystem.primary)
                }
            }
        }
        .padding(.leading, Spacing.sm)
        .padding(.trailing, Spacing.xs)  // Minimal trailing - content close to chevron
        .padding(.vertical, Spacing.xs)
        .frame(height: 48)
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
    /// Parse ISO8601 date with or without fractional seconds
    private func parseDate(_ dateString: String) -> Date? {
        // Try with fractional seconds first
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: dateString) {
            return date
        }

        // Try without fractional seconds (e.g., "2025-12-21T23:15:08+07:00")
        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]
        return formatterWithoutFractional.date(from: dateString)
    }

    /// Relative time string (e.g., "4 min ago")
    var relativeTime: String {
        guard let date = parseDate(lastUpdated) else {
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
        guard let date = parseDate(lastUpdated) else {
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
