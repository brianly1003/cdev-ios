//
//  ExternalSessionsView.swift
//  Cdev
//
//  UI components for displaying external Claude sessions
//  Detected via hooks from VS Code, Cursor, terminal
//

import SwiftUI

// MARK: - External Sessions Badge

/// Compact badge showing external session count
/// Used in status bar to indicate external activity
struct ExternalSessionsBadge: View {
    @ObservedObject var manager: ExternalSessionManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        if manager.activeSessionCount > 0 {
            HStack(spacing: layout.ultraTightSpacing) {
                Image(systemName: manager.hasActivePermissions ? "exclamationmark.triangle.fill" : "externaldrive.connected.to.line.below")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(manager.hasActivePermissions ? ColorSystem.warning : ColorSystem.info)

                Text("\(manager.activeSessionCount)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(manager.hasActivePermissions ? ColorSystem.warning : ColorSystem.info)
            }
            .padding(.horizontal, layout.tightSpacing)
            .padding(.vertical, 2)
            .background(
                (manager.hasActivePermissions ? ColorSystem.warning : ColorSystem.info)
                    .opacity(0.15)
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
    }
}

// MARK: - External Sessions Section

/// Expandable section showing external sessions in dashboard
struct ExternalSessionsSection: View {
    @ObservedObject var manager: ExternalSessionManager
    @State private var isExpanded: Bool = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        if manager.activeSessionCount > 0 {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: layout.tightSpacing) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ColorSystem.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))

                        Text("External Sessions")
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textSecondary)

                        Text("(\(manager.activeSessionCount))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(ColorSystem.textTertiary)

                        Spacer()

                        if manager.hasActivePermissions {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(ColorSystem.warning)
                        }
                    }
                    .padding(.horizontal, layout.smallPadding)
                    .padding(.vertical, layout.tightSpacing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Sessions list
                if isExpanded {
                    VStack(spacing: 1) {
                        ForEach(manager.sessionsByActivity) { session in
                            ExternalSessionRow(session: session)
                        }
                    }
                    .padding(.horizontal, layout.smallPadding)
                    .padding(.bottom, layout.smallPadding)
                }
            }
            .background(ColorSystem.terminalBgElevated.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
    }
}

// MARK: - External Session Row

/// Compact row displaying an external session
struct ExternalSessionRow: View {
    let session: ExternalSession
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
            // Main row
            HStack(spacing: layout.tightSpacing) {
                // Status icon
                Image(systemName: session.status.icon)
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(statusColor)
                    .frame(width: 14)

                // Project name
                Text(session.projectName)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .lineLimit(1)

                // Branch (if available)
                if let branch = session.gitBranch {
                    Text(branch)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Status/tool indicator
                if let tool = session.currentTool {
                    Text(tool)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorSystem.info)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(ColorSystem.info.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                } else {
                    Text(session.status.displayName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(statusColor)
                }
            }

            // Permission banner (if pending)
            if session.hasPendingPermission, let permission = session.pendingPermission {
                ExternalPermissionBanner(permission: permission)
            }
        }
        .padding(.vertical, layout.tightSpacing)
        .padding(.horizontal, layout.tightSpacing)
        .background(ColorSystem.terminalBg)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    private var statusColor: Color {
        switch session.status {
        case .idle:
            return ColorSystem.success
        case .toolRunning:
            return ColorSystem.info
        case .permissionPending:
            return ColorSystem.warning
        }
    }
}

// MARK: - External Permission Banner

/// Non-interactive banner showing permission pending in external session
/// User must respond on desktop - this is informational only
struct ExternalPermissionBanner: View {
    let permission: PendingExternalPermission
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
            // Header
            HStack(spacing: layout.tightSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(ColorSystem.warning)

                Text(permission.tool)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.warning)

                Spacer()

                Text("Respond on desktop")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .italic()
            }

            // Permission details
            Text(permission.displaySummary)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textSecondary)
                .lineLimit(2)
        }
        .padding(layout.tightSpacing)
        .background(ColorSystem.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }
}

// MARK: - External Session Detail View

/// Detailed view of an external session with tool history
struct ExternalSessionDetailView: View {
    let session: ExternalSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorSystem.terminalBg
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: layout.contentSpacing) {
                        // Session info
                        sessionInfoSection

                        // Current status
                        currentStatusSection

                        // Tool history
                        toolHistorySection
                    }
                    .padding(layout.standardPadding)
                }
            }
            .navigationTitle(session.projectName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ColorSystem.terminalBgElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ColorSystem.primary)
                }
            }
        }
    }

    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: layout.tightSpacing) {
            Text("Session Info")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)

            VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                InfoRow(label: "Directory", value: session.workingDirectory)
                if let branch = session.gitBranch {
                    InfoRow(label: "Branch", value: branch)
                }
                InfoRow(label: "Started", value: session.startTime.formatted())
                InfoRow(label: "Session ID", value: String(session.id.prefix(8)) + "...")
            }
            .padding(layout.smallPadding)
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
    }

    private var currentStatusSection: some View {
        VStack(alignment: .leading, spacing: layout.tightSpacing) {
            Text("Current Status")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)

            HStack(spacing: layout.tightSpacing) {
                Image(systemName: session.status.icon)
                    .font(.system(size: layout.iconMedium))
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.status.displayName)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textPrimary)

                    if let tool = session.currentTool {
                        Text("Running: \(tool)")
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(layout.smallPadding)
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

            // Permission banner
            if session.hasPendingPermission, let permission = session.pendingPermission {
                ExternalPermissionBanner(permission: permission)
            }
        }
    }

    private var toolHistorySection: some View {
        VStack(alignment: .leading, spacing: layout.tightSpacing) {
            HStack {
                Text("Tool History")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)

                Spacer()

                Text("\(session.toolHistory.count) executions")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }

            if session.toolHistory.isEmpty {
                Text("No tool executions yet")
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(layout.standardPadding)
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(session.toolHistory) { tool in
                        ToolExecutionRow(tool: tool)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .idle: return ColorSystem.success
        case .toolRunning: return ColorSystem.info
        case .permissionPending: return ColorSystem.warning
        }
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let label: String
    let value: String
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        HStack {
            Text(label)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textPrimary)
                .lineLimit(1)

            Spacer()
        }
    }
}

// MARK: - Tool Execution Row

private struct ToolExecutionRow: View {
    let tool: ToolExecution
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        HStack(spacing: layout.tightSpacing) {
            // Tool icon
            Image(systemName: iconForTool(tool.toolName))
                .font(.system(size: layout.iconSmall))
                .foregroundStyle(tool.isRunning ? ColorSystem.info : ColorSystem.textTertiary)
                .frame(width: 14)

            // Tool name
            Text(tool.toolName)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textPrimary)

            // Input summary
            if let input = tool.inputSummary {
                Text(input)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Duration or spinner
            if tool.isRunning {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Text(tool.durationString)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(tool.isError ? ColorSystem.error : ColorSystem.textTertiary)
            }
        }
        .padding(.vertical, layout.tightSpacing)
        .padding(.horizontal, layout.smallPadding)
        .background(ColorSystem.terminalBgElevated)
    }

    private func iconForTool(_ name: String) -> String {
        switch name.lowercased() {
        case "bash": return "terminal"
        case "write": return "doc.badge.plus"
        case "edit": return "pencil"
        case "read": return "doc.text"
        case "glob": return "magnifyingglass"
        case "grep": return "text.magnifyingglass"
        case "task": return "person.fill"
        default: return "gearshape"
        }
    }
}

// MARK: - Previews

#Preview("Badge") {
    HStack {
        ExternalSessionsBadge(manager: {
            let manager = ExternalSessionManager()
            return manager
        }())
    }
    .padding()
    .background(ColorSystem.terminalBg)
}

#Preview("Session Row") {
    VStack {
        ExternalSessionRow(session: ExternalSession(
            id: "test-123",
            workingDirectory: "/Users/dev/my-project",
            gitBranch: "main",
            currentTool: "Bash"
        ))

        ExternalSessionRow(session: {
            var session = ExternalSession(
                id: "test-456",
                workingDirectory: "/Users/dev/another-project",
                gitBranch: "feature/hooks"
            )
            session.hasPendingPermission = true
            session.pendingPermission = PendingExternalPermission(
                from: HookPermissionPayload(
                    sessionId: "test-456",
                    tool: "Bash",
                    description: "Execute: npm install",
                    command: "npm install",
                    path: nil
                )
            )
            return session
        }())
    }
    .padding()
    .background(ColorSystem.terminalBg)
}
