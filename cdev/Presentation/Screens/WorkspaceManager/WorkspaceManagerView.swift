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

    /// Track if connection has failed (prevents auto-reconnect loops)
    @State private var hasConnectionFailed: Bool = false

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
                ZStack {
                    // Background
                    ColorSystem.terminalBg
                        .ignoresSafeArea()

                    if viewModel.isConnected {
                        connectedContent
                    } else if !viewModel.hasCheckedConnection {
                        // Show connecting state while checking saved connection
                        connectingContent
                    } else {
                        disconnectedContent
                    }
                }
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

                if viewModel.isConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
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
                    // Reset failure flag when user manually tries to connect
                    hasConnectionFailed = false
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
            .alert("Error", isPresented: $viewModel.showError) {
                Button("Retry") {
                    viewModel.showError = false
                    // Reset failure flag and try again
                    hasConnectionFailed = false
                    Task {
                        await viewModel.connectToSavedManager()
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.showError = false
                }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "Unknown error")
            }
            .onChange(of: viewModel.showError) { _, newValue in
                // Mark connection as failed when error is shown
                if newValue {
                    hasConnectionFailed = true
                }
            }
            .onChange(of: viewModel.isConnected) { _, newValue in
                // Reset failure flag when successfully connected
                if newValue {
                    hasConnectionFailed = false
                }
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
                } else if viewModel.hasSavedManager && !hasConnectionFailed {
                    // Not connected but have saved manager - try to reconnect (once)
                    await viewModel.connectToSavedManager()
                } else if !viewModel.hasSavedManager {
                    // No saved manager - show setup
                    viewModel.showSetupSheet = true
                } else if hasConnectionFailed {
                    // Had a saved manager but connection failed - mark check as complete
                    // This shows "Not Connected" instead of endless "Connecting..."
                    viewModel.markConnectionChecked()
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

    // MARK: - Connected Content

    private var connectedContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, layout.standardPadding)
                .padding(.vertical, layout.smallPadding)

            // Status summary
            statusSummary
                .padding(.horizontal, layout.standardPadding)
                .padding(.bottom, layout.smallPadding)

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

    // MARK: - Connecting Content (initial check)

    private var connectingContent: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting...")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Disconnected Content

    private var disconnectedContent: some View {
        VStack(spacing: Spacing.lg) {
            if viewModel.isConnecting {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Connecting...")
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textSecondary)
            } else {
                Image(systemName: "network.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(ColorSystem.textTertiary)

                Text("Not Connected")
                    .font(Typography.title3)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("Connect to a workspace manager to view and manage your workspaces.")
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                Button {
                    viewModel.showSetupSheet = true
                } label: {
                    Label("Connect", systemImage: "wifi")
                        .font(Typography.buttonLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(ColorSystem.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}

// MARK: - Preview

#Preview {
    WorkspaceManagerView()
}
