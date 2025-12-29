import SwiftUI

// MARK: - Workspace Row View

/// Compact row displaying a remote workspace with status and actions
/// Single-port architecture: status is derived from sessions
/// Follows ResponsiveLayout for iPhone/iPad consistency
struct WorkspaceRowView: View {
    let workspace: RemoteWorkspace
    let isCurrentWorkspace: Bool
    let isLoading: Bool
    let isUnreachable: Bool
    let operation: WorkspaceOperation?
    let isServerConnected: Bool  // Whether we have connection to server
    let onConnect: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void
    var onSetupGit: (() -> Void)?  // Optional: called when user wants to setup git

    // Responsive layout
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Whether row interaction is enabled (only when server is connected)
    private var isInteractionEnabled: Bool {
        isServerConnected && !isLoading
    }

    // MARK: - Derived Status

    /// Derived status from active sessions
    private var derivedStatus: DerivedWorkspaceStatus {
        if workspace.hasActiveSession {
            return .hasActiveSessions(count: workspace.activeSessionCount)
        } else {
            return .noActiveSessions
        }
    }

    /// Whether workspace has active sessions (equivalent to old "running")
    private var isRunning: Bool {
        workspace.hasActiveSession
    }

    var body: some View {
        HStack(spacing: layout.contentSpacing) {
            // Status indicator
            statusIndicator

            // Workspace info
            VStack(alignment: .leading, spacing: 2) {
                // Name row with git status
                HStack(spacing: layout.tightSpacing) {
                    Text(workspace.name)
                        .font(Typography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(isCurrentWorkspace ? ColorSystem.primary : ColorSystem.textPrimary)
                        .lineLimit(1)

                    if isCurrentWorkspace {
                        Text("Current")
                            .font(Typography.badge)
                            .foregroundStyle(ColorSystem.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ColorSystem.primary.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    // Git status badge for non-git workspaces
                    if workspace.needsGitSetup {
                        gitSetupBadge
                    }
                }

                // Full path row (like Repository Discovery)
                Text(workspace.path)
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Session count (when has active sessions)
                if workspace.activeSessionCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.system(size: 9))
                        Text(workspace.activeSessionCount == 1 ? "1 session" : "\(workspace.activeSessionCount) sessions")
                            .font(Typography.caption2)
                    }
                    .foregroundStyle(ColorSystem.textQuaternary)
                }
            }

            Spacer(minLength: 0)

            // Status badge (shows operation when loading)
            statusBadge

            // Action button (shows spinner when loading)
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: layout.indicatorSize, height: layout.indicatorSize)
            } else {
                // Navigate/Start button
                Button {
                    guard isInteractionEnabled else {
                        Haptics.light()
                        return
                    }
                    AppLogger.log("[WorkspaceRow] Action button tapped for: \(workspace.name)")
                    Haptics.medium()
                    onConnect()
                } label: {
                    actionIcon
                }
                .buttonStyle(.borderless)
                .disabled(!isServerConnected)
            }
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, layout.smallPadding)
        .background(isCurrentWorkspace ? ColorSystem.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        // Dim the row when server is disconnected
        .opacity(isServerConnected ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.25), value: isServerConnected)
        // Only allow tap gesture when server is connected
        .simultaneousGesture(
            TapGesture().onEnded {
                guard isInteractionEnabled else {
                    // Brief haptic feedback to indicate disabled state
                    Haptics.light()
                    return
                }
                // Tapping anywhere on the row connects/starts the workspace
                // Using simultaneousGesture allows both this and swipe actions to work
                AppLogger.log("[WorkspaceRow] Row tapped for: \(workspace.name)")
                Haptics.medium()
                onConnect()
            }
        )
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: layout.dotSize, height: layout.dotSize)
            .overlay(
                // Pulse animation when loading (starting a session)
                Circle()
                    .stroke(statusColor.opacity(0.5), lineWidth: 2)
                    .scaleEffect(isLoading ? 1.5 : 1)
                    .opacity(isLoading ? 0 : 1)
                    .animation(
                        isLoading ?
                            .easeInOut(duration: 1).repeatForever(autoreverses: false) :
                            .default,
                        value: isLoading
                    )
            )
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        // Show operation text when loading, unreachable when can't connect, otherwise show status
        let displayText: String
        let badgeColor: Color

        if isLoading {
            displayText = operation?.displayText ?? "Starting..."
            badgeColor = ColorSystem.warning
        } else if isUnreachable && isRunning {
            displayText = "Unreachable"
            badgeColor = ColorSystem.error
        } else {
            displayText = derivedStatus.displayText
            badgeColor = statusColor
        }

        return Text(displayText)
            .font(Typography.badge)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12))
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: isLoading)
            .animation(.easeInOut(duration: 0.2), value: isUnreachable)
    }

    // MARK: - Action Icon

    @ViewBuilder
    private var actionIcon: some View {
        // Icon indicates what action will happen:
        // 1. No sessions/Unreachable → Green play (Start session)
        // 2. Has sessions → Blue arrow (Navigate to Dashboard)
        //
        // The entire row is now a button, so this is just an icon indicator

        if isRunning && !isUnreachable {
            // Has active sessions - show blue arrow to navigate to Dashboard
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: layout.iconLarge))
                .foregroundStyle(ColorSystem.primary)
                .frame(width: layout.indicatorSize, height: layout.indicatorSize)
        } else {
            // No sessions or unreachable - show green play (Start session)
            Image(systemName: "play.fill")
                .font(.system(size: layout.iconAction))
                .foregroundStyle(ColorSystem.success)
                .frame(width: layout.indicatorSize, height: layout.indicatorSize)
        }
    }

    // MARK: - Git Setup Badge

    @ViewBuilder
    private var gitSetupBadge: some View {
        let gitState = workspace.workspaceGitState
        // Use ColorSystem.warning (Golden Pulse #F6C85D) for noGit state per CDEV-COLOR-SYSTEM.md
        let badgeColor = gitState == .noGit ? ColorSystem.warning : ColorSystem.textTertiary

        // Display-only badge (no tap action) - shows git state info
        // Match "Current" badge style: Typography.badge, padding(.horizontal, 6), padding(.vertical, 2)
        HStack(spacing: 3) {
            Image(systemName: gitState.icon)
                .font(.system(size: 8))
            Text(gitState.shortText)
                .font(Typography.badge)
        }
        .foregroundColor(badgeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var statusColor: Color {
        // Show error color if unreachable
        if isUnreachable && isRunning {
            return ColorSystem.error
        }

        switch derivedStatus {
        case .hasActiveSessions:
            return ColorSystem.success
        case .noActiveSessions:
            return ColorSystem.textTertiary
        }
    }
}

// MARK: - Derived Workspace Status

/// Status derived from session state (since workspace itself doesn't have status)
private enum DerivedWorkspaceStatus {
    case hasActiveSessions(count: Int)
    case noActiveSessions

    var displayText: String {
        switch self {
        case .hasActiveSessions(let count):
            return count == 1 ? "Active" : "\(count) Active"
        case .noActiveSessions:
            return "Idle"
        }
    }
}

// MARK: - Swipeable Row Wrapper

/// Adds swipe actions to WorkspaceRowView
struct SwipeableWorkspaceRow: View {
    let workspace: RemoteWorkspace
    let isCurrentWorkspace: Bool
    let isLoading: Bool
    let isUnreachable: Bool
    let operation: WorkspaceOperation?
    let isServerConnected: Bool  // Whether we have connection to server
    let onConnect: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void
    var onSetupGit: (() -> Void)?

    init(
        workspace: RemoteWorkspace,
        isCurrentWorkspace: Bool,
        isLoading: Bool = false,
        isUnreachable: Bool = false,
        operation: WorkspaceOperation? = nil,
        isServerConnected: Bool = true,
        onConnect: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onSetupGit: (() -> Void)? = nil
    ) {
        self.workspace = workspace
        self.isCurrentWorkspace = isCurrentWorkspace
        self.isLoading = isLoading
        self.isUnreachable = isUnreachable
        self.operation = operation
        self.isServerConnected = isServerConnected
        self.onConnect = onConnect
        self.onStart = onStart
        self.onStop = onStop
        self.onRemove = onRemove
        self.onSetupGit = onSetupGit
    }

    var body: some View {
        WorkspaceRowView(
            workspace: workspace,
            isCurrentWorkspace: isCurrentWorkspace,
            isLoading: isLoading,
            isUnreachable: isUnreachable,
            operation: operation,
            isServerConnected: isServerConnected,
            onConnect: onConnect,
            onStart: onStart,
            onStop: onStop,
            onRemove: onRemove,
            onSetupGit: onSetupGit
        )
        // Only show swipe actions when server is connected
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isServerConnected {
                // Remove button (always shown)
                Button(role: .destructive) {
                    Haptics.warning()
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .tint(ColorSystem.error)

                // Stop button (only when workspace has active sessions)
                if workspace.hasActiveSession && !isUnreachable {
                    Button {
                        Haptics.warning()
                        onStop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .tint(ColorSystem.warning)
                }
            }
        }
        // Leading swipe (swipe right) for git setup
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if isServerConnected && workspace.needsGitSetup, let onSetupGit = onSetupGit {
                Button {
                    Haptics.medium()
                    onSetupGit()
                } label: {
                    Label("Setup Git", systemImage: "arrow.triangle.branch")
                }
                .tint(ColorSystem.primary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Running Workspace") {
    VStack(spacing: 0) {
        WorkspaceRowView(
            workspace: RemoteWorkspace(
                id: "ws-1",
                name: "Backend API",
                path: "/Users/dev/projects/backend",
                autoStart: true,
                sessions: [
                    Session(
                        id: "sess-1",
                        workspaceId: "ws-1",
                        status: .running,
                        startedAt: Date(),
                        lastActive: Date()
                    )
                ]
            ),
            isCurrentWorkspace: true,
            isLoading: false,
            isUnreachable: false,
            operation: nil,
            isServerConnected: true,
            onConnect: {},
            onStart: {},
            onStop: {},
            onRemove: {}
        )

        Divider()

        WorkspaceRowView(
            workspace: RemoteWorkspace(
                id: "ws-2",
                name: "Frontend App",
                path: "/Users/dev/projects/frontend",
                autoStart: false,
                sessions: [
                    Session(
                        id: "sess-2",
                        workspaceId: "ws-2",
                        status: .running,
                        startedAt: Date().addingTimeInterval(-3600),
                        lastActive: Date().addingTimeInterval(-3600)
                    )
                ]
            ),
            isCurrentWorkspace: false,
            isLoading: false,
            isUnreachable: true,  // Shows "Unreachable" status
            operation: nil,
            isServerConnected: true,
            onConnect: {},
            onStart: {},
            onStop: {},
            onRemove: {}
        )

        Divider()

        // Disconnected server state - row is dimmed
        WorkspaceRowView(
            workspace: RemoteWorkspace(
                id: "ws-3",
                name: "Documentation",
                path: "/Users/dev/projects/docs",
                autoStart: false,
                sessions: []  // No active sessions
            ),
            isCurrentWorkspace: false,
            isLoading: false,
            isUnreachable: false,
            operation: nil,
            isServerConnected: false,  // Server disconnected - row dimmed
            onConnect: {},
            onStart: {},
            onStop: {},
            onRemove: {}
        )

        Divider()

        WorkspaceRowView(
            workspace: RemoteWorkspace(
                id: "ws-4",
                name: "Multi-Session Project",
                path: "/Users/dev/projects/multi",
                autoStart: true,
                sessions: [
                    Session(id: "sess-4a", workspaceId: "ws-4", status: .running),
                    Session(id: "sess-4b", workspaceId: "ws-4", status: .running)
                ]
            ),
            isCurrentWorkspace: false,
            isLoading: false,
            isUnreachable: false,
            operation: nil,
            isServerConnected: true,
            onConnect: {},
            onStart: {},
            onStop: {},
            onRemove: {}
        )
    }
    .background(ColorSystem.terminalBg)
}
