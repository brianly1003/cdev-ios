import SwiftUI

// MARK: - Workspace Manager View

/// Main screen for managing remote workspaces
/// Shows list of workspaces with status and actions
struct WorkspaceManagerView: View {
    @StateObject private var viewModel = WorkspaceManagerViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Callback when user wants to connect to a workspace
    /// Returns true if connection succeeded (dismisses view), false otherwise (stays on page)
    var onConnectToWorkspace: ((RemoteWorkspace, String) async -> Bool)?

    /// Whether to show the Done/dismiss button (false when used as root view)
    var showDismissButton: Bool = true

    /// Show debug logs sheet (for FloatingToolkit)
    @State private var showDebugLogs: Bool = false

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Toolkit items for FloatingToolkitButton (only shows Debug when root view)
    private var toolkitItems: [ToolkitItem] {
        ToolkitBuilder()
            .add(.debugLogs { showDebugLogs = true })
            .build()
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    // Server connection status banner (non-blocking)
                    ServerConnectionBanner(
                        status: viewModel.serverStatus,
                        host: viewModel.savedHost,
                        onRetry: {
                            Task { await viewModel.retryConnection() }
                        },
                        onCancel: {
                            viewModel.cancelConnection()
                        },
                        onChangeServer: {
                            viewModel.showSetupSheet = true
                        }
                    )

                    // Main content - always show workspace list structure
                    if viewModel.hasSavedManager {
                        workspaceListContent
                    } else {
                        noServerConfiguredContent
                    }
                }
                .background(ColorSystem.terminalBg.ignoresSafeArea())
                .navigationTitle("Workspaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showDismissButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundStyle(ColorSystem.primary)
                    }
                }

                // Always show menu when we have a saved manager
                if viewModel.hasSavedManager {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if viewModel.isConnected {
                                Button {
                                    viewModel.showDiscoverySheet = true
                                } label: {
                                    Label("Discover Repos", systemImage: "magnifyingglass")
                                }

                                Button {
                                    Task { await viewModel.refreshWorkspaces() }
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }

                                Divider()
                            }

                            Button {
                                viewModel.showSetupSheet = true
                            } label: {
                                Label("Change Server", systemImage: "server.rack")
                            }

                            Button(role: .destructive) {
                                viewModel.resetManager()
                            } label: {
                                Label("Disconnect", systemImage: "wifi.slash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: layout.iconLarge))
                                .foregroundStyle(ColorSystem.textSecondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSetupSheet) {
                ManagerSetupView { host in
                    Task {
                        await viewModel.connect(to: host)
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.showDiscoverySheet) {
                RepositoryDiscoveryView(
                    onConnectToWorkspace: { workspace, host in
                        // Await connection result - only dismiss on success
                        let success = await onConnectToWorkspace?(workspace, host) ?? false
                        if success {
                            dismiss()
                        }
                        return success
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .task {
                // Auto-connect or refresh on appear
                // Skip if already connecting (prevents loops on view re-appearance)
                guard !viewModel.isConnecting else {
                    AppLogger.log("[WorkspaceManager] Skipping task - already connecting")
                    return
                }

                if viewModel.isConnected {
                    // Already connected - just refresh workspace list
                    await viewModel.refreshWorkspaces()
                } else if viewModel.hasSavedManager {
                    // Not connected but have saved manager - try to reconnect with retry
                    await viewModel.connectToSavedManager()
                } else {
                    // No saved manager - show setup
                    viewModel.showSetupSheet = true
                }
            }
            .sheet(isPresented: $showDebugLogs) {
                AdminToolsView()
                    .responsiveSheet()
            }
            } // End NavigationStack

            // Floating toolkit button with Debug Logs only
            FloatingToolkitButton(items: toolkitItems) { _ in }
        } // End outer ZStack
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.textTertiary)

            TextField("Search workspaces...", text: $viewModel.searchText)
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)
                .autocorrectionDisabled()

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Status Summary

    private var statusSummary: some View {
        HStack(spacing: Spacing.md) {
            // Connected host
            HStack(spacing: Spacing.xxs) {
                Circle()
                    .fill(ColorSystem.success)
                    .frame(width: 6, height: 6)

                Text(viewModel.savedHost ?? "Manager")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Spacer()

            // Running count
            Text("\(viewModel.runningCount) running")
                .font(Typography.badge)
                .foregroundStyle(ColorSystem.success)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ColorSystem.success.opacity(0.12))
                .clipShape(Capsule())

            // Total count
            Text("\(viewModel.workspaces.count) total")
                .font(Typography.caption1)
                .foregroundStyle(ColorSystem.textTertiary)
        }
    }

    // MARK: - Workspace List

    private var workspaceList: some View {
        List {
            ForEach(viewModel.filteredWorkspaces) { workspace in
                SwipeableWorkspaceRow(
                    workspace: workspace,
                    isCurrentWorkspace: workspace.id == viewModel.currentWorkspaceId,
                    isLoading: viewModel.isWorkspaceLoading(workspace),
                    isUnreachable: viewModel.isWorkspaceUnreachable(workspace),
                    operation: viewModel.operationFor(workspace),
                    isServerConnected: viewModel.isConnected,
                    onConnect: {
                        Task {
                            AppLogger.log("[WorkspaceManagerView] ========== WORKSPACE SWITCH START ==========")
                            AppLogger.log("[WorkspaceManagerView] onConnect: workspace=\(workspace.name), id=\(workspace.id)")
                            AppLogger.log("[WorkspaceManagerView] onConnect: hasActiveSession=\(workspace.hasActiveSession), sessions=\(workspace.sessions.count)")
                            AppLogger.log("[WorkspaceManagerView] onConnect: savedHost=\(viewModel.savedHost ?? "nil"), isConnected=\(viewModel.isConnected)")
                            AppLogger.log("[WorkspaceManagerView] onConnect: currentWorkspaceId=\(viewModel.currentWorkspaceId ?? "nil")")

                            // For already-active workspaces, dismiss FIRST to avoid visual glitch
                            // when WebSocket reconnects (shared WebSocket causes isConnected state change)
                            if workspace.hasActiveSession {
                                AppLogger.log("[WorkspaceManagerView] ACTIVE PATH: Dismissing first before connection")
                                dismiss()

                                // Small delay to let dismiss animation start
                                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
                                AppLogger.log("[WorkspaceManagerView] ACTIVE PATH: After dismiss delay, calling connectToWorkspace")

                                let running = await viewModel.connectToWorkspace(workspace)
                                AppLogger.log("[WorkspaceManagerView] ACTIVE PATH: connectToWorkspace returned: \(running?.name ?? "nil")")

                                if let running = running, let host = viewModel.savedHost {
                                    AppLogger.log("[WorkspaceManagerView] ACTIVE PATH: Calling onConnectToWorkspace callback")
                                    let success = await onConnectToWorkspace?(running, host) ?? false
                                    AppLogger.log("[WorkspaceManagerView] ACTIVE PATH: onConnectToWorkspace returned: \(success)")
                                } else {
                                    AppLogger.log("[WorkspaceManagerView] ACTIVE PATH: Failed - running=\(running != nil), host=\(viewModel.savedHost ?? "nil")")
                                }
                            } else {
                                AppLogger.log("[WorkspaceManagerView] INACTIVE PATH: Starting new session flow")
                                // For inactive workspaces, wait for connection result before dismissing
                                let running = await viewModel.connectToWorkspace(workspace)
                                AppLogger.log("[WorkspaceManagerView] INACTIVE PATH: connectToWorkspace returned: \(running?.name ?? "nil")")

                                if let running = running, let host = viewModel.savedHost {
                                    AppLogger.log("[WorkspaceManagerView] INACTIVE PATH: Calling onConnectToWorkspace callback")
                                    let success = await onConnectToWorkspace?(running, host) ?? false
                                    AppLogger.log("[WorkspaceManagerView] INACTIVE PATH: onConnectToWorkspace returned: \(success)")
                                    if success {
                                        AppLogger.log("[WorkspaceManagerView] INACTIVE PATH: Dismissing view")
                                        dismiss()
                                    } else {
                                        AppLogger.log("[WorkspaceManagerView] INACTIVE PATH: Connection failed, NOT dismissing")
                                    }
                                } else {
                                    AppLogger.log("[WorkspaceManagerView] INACTIVE PATH: Failed - running=\(running != nil), host=\(viewModel.savedHost ?? "nil")")
                                }
                            }
                            AppLogger.log("[WorkspaceManagerView] ========== WORKSPACE SWITCH END ==========")
                        }
                    },
                    onStart: {
                        Task { await viewModel.startWorkspace(workspace) }
                    },
                    onStop: {
                        Task { await viewModel.stopWorkspace(workspace) }
                    }
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.refreshWorkspaces()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading workspaces...")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(ColorSystem.textTertiary)

            if viewModel.searchText.isEmpty {
                Text("No Workspaces")
                    .font(Typography.title3)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("Add workspaces on your laptop using the CLI, or discover repositories.")
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                Button {
                    viewModel.showDiscoverySheet = true
                } label: {
                    Label("Discover Repos", systemImage: "magnifyingglass")
                        .font(Typography.buttonLabel)
                        .foregroundStyle(ColorSystem.primary)
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.sm)
            } else {
                Text("No Results")
                    .font(Typography.title3)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("No workspaces match \"\(viewModel.searchText)\"")
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textSecondary)

                Button {
                    viewModel.searchText = ""
                } label: {
                    Text("Clear Search")
                        .font(Typography.buttonLabel)
                        .foregroundStyle(ColorSystem.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Workspace List Content

    /// Content showing the workspace list (works in both connected and disconnected states)
    private var workspaceListContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, layout.standardPadding)
                .padding(.vertical, layout.smallPadding)

            // Status summary (only when connected)
            if viewModel.isConnected {
                statusSummary
                    .padding(.horizontal, layout.standardPadding)
                    .padding(.bottom, layout.smallPadding)
            }

            Divider()
                .background(ColorSystem.terminalBgHighlight)

            // Workspace list
            if viewModel.isLoading && viewModel.workspaces.isEmpty {
                loadingView
            } else if viewModel.filteredWorkspaces.isEmpty {
                emptyStateView
            } else {
                workspaceList
            }
        }
        .dismissKeyboardOnTap()
    }

    // MARK: - No Server Configured Content

    /// Content shown when no server has been configured yet
    private var noServerConfiguredContent: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(ColorSystem.textTertiary)

            Text("No Server Configured")
                .font(Typography.title3)
                .foregroundStyle(ColorSystem.textPrimary)

            Text("Connect to a workspace manager to view and manage your remote workspaces.")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Button {
                viewModel.showSetupSheet = true
            } label: {
                Label("Connect to Server", systemImage: "wifi")
                    .font(Typography.buttonLabel)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(ColorSystem.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Server Connection Banner

/// Non-blocking banner showing server connection status with actions
struct ServerConnectionBanner: View {
    let status: ServerConnectionStatus
    let host: String?
    var onRetry: (() -> Void)?
    var onCancel: (() -> Void)?
    var onChangeServer: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        // Only show banner when not connected
        if !status.isConnected {
            HStack(spacing: Spacing.sm) {
                // Status indicator
                HStack(spacing: Spacing.xxs) {
                    statusIcon
                        .font(.system(size: layout.iconSmall))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(status.statusText)
                            .font(Typography.caption1)
                            .fontWeight(.medium)
                            .foregroundStyle(status.statusColor)

                        if let host = host {
                            Text(host)
                                .font(Typography.terminalSmall)
                                .foregroundStyle(ColorSystem.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: Spacing.xs) {
                    switch status {
                    case .connecting:
                        // Cancel button during connection attempts
                        Button {
                            onCancel?()
                        } label: {
                            Text("Cancel")
                                .font(Typography.caption1)
                                .fontWeight(.medium)
                                .foregroundStyle(ColorSystem.textSecondary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xxs)
                                .background(ColorSystem.terminalBgElevated)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                    case .disconnected, .unreachable:
                        // Retry button
                        Button {
                            onRetry?()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(Typography.caption1)
                                .fontWeight(.medium)
                                .foregroundStyle(ColorSystem.primary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xxs)
                                .background(ColorSystem.primary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        // Change server button
                        Button {
                            onChangeServer?()
                        } label: {
                            Image(systemName: "server.rack")
                                .font(.system(size: layout.iconSmall))
                                .foregroundStyle(ColorSystem.textSecondary)
                                .padding(Spacing.xxs)
                                .background(ColorSystem.terminalBgElevated)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                    case .connected:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, Spacing.xs)
            .background(bannerBackground)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ColorSystem.success)
        case .connecting:
            ProgressView()
                .scaleEffect(0.7)
        case .disconnected:
            Image(systemName: "wifi.slash")
                .foregroundStyle(ColorSystem.textTertiary)
        case .unreachable:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ColorSystem.error)
        }
    }

    private var bannerBackground: some View {
        switch status {
        case .connected:
            return ColorSystem.success.opacity(0.08)
        case .connecting:
            return ColorSystem.warning.opacity(0.08)
        case .disconnected:
            return ColorSystem.terminalBgElevated
        case .unreachable:
            return ColorSystem.error.opacity(0.08)
        }
    }
}

// MARK: - Preview

#Preview {
    WorkspaceManagerView()
}

#Preview("Connection Banner - Connecting") {
    VStack(spacing: 16) {
        ServerConnectionBanner(
            status: .connecting(attempt: 3, maxAttempts: 10),
            host: "192.168.1.100"
        )

        ServerConnectionBanner(
            status: .disconnected,
            host: "192.168.1.100"
        )

        ServerConnectionBanner(
            status: .unreachable(lastError: "Connection refused"),
            host: "192.168.1.100"
        )
    }
    .background(ColorSystem.terminalBg)
}
