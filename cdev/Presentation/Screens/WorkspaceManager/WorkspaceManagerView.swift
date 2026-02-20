import SwiftUI

// MARK: - Workspace Manager View

/// Main screen for managing remote workspaces
/// Shows list of workspaces with status and actions
struct WorkspaceManagerView: View {
    @StateObject private var viewModel = WorkspaceManagerViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    /// Callback when user wants to connect to a workspace
    /// Returns true if connection succeeded (dismisses view), false otherwise (stays on page)
    var onConnectToWorkspace: ((RemoteWorkspace, String) async -> Bool)?

    /// Callback when user wants to disconnect from server
    /// If provided, this will be called instead of direct WebSocket disconnect
    /// to allow parent views to handle the full disconnect flow
    var onDisconnect: (() async -> Void)?

    /// Whether to show the Done/dismiss button (false when used as root view)
    var showDismissButton: Bool = true

    /// Show debug logs sheet (for FloatingToolkit)
    @State private var showDebugLogs: Bool = false

    /// Show settings sheet (for FloatingToolkit)
    @State private var showSettings: Bool = false

    /// Scroll request (from floating toolkit force touch)
    @State private var scrollRequest: ScrollDirection?

    /// Git setup sheet state (uses sheet(item:) pattern)
    @State private var gitSetupWorkspace: RemoteWorkspace?

    /// No Git alert state (shown when tapping workspace without git)
    @State private var showNoGitAlert: Bool = false
    @State private var noGitAlertWorkspace: RemoteWorkspace?

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Toolkit items for FloatingToolkitButton (only shows Debug when root view)
    private var toolkitItems: [ToolkitItem] {
        ToolkitBuilder()
            .add(.settings { showSettings = true })
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
                                // Quick add section
                                Button {
                                    viewModel.showManualAddSheet = true
                                } label: {
                                    Label("Add by Path", systemImage: "folder.badge.plus")
                                }

                                Button {
                                    viewModel.showDiscoverySheet = true
                                } label: {
                                    Label("Discover Repos", systemImage: "magnifyingglass")
                                }

                                Divider()

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
                                Task {
                                    // If callback provided, use it for full disconnect flow
                                    // Otherwise fall back to direct disconnect
                                    if let onDisconnect = onDisconnect {
                                        await onDisconnect()
                                        viewModel.resetManagerState()
                                    } else {
                                        viewModel.resetManager()
                                    }
                                }
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
                ManagerSetupView { host, token, pairingCode in
                    Task {
                        await viewModel.connect(to: host, token: token, pairingCode: pairingCode)
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
            .sheet(isPresented: $viewModel.showManualAddSheet) {
                ManualWorkspaceAddView(
                    onAdd: { path in
                        try await viewModel.addWorkspaceManually(path: path)
                    },
                    onOpenWorkspace: { workspace in
                        // Connect to the workspace
                        Task {
                            if let host = viewModel.savedHost {
                                let success = await onConnectToWorkspace?(workspace, host) ?? false
                                if success {
                                    dismiss()
                                }
                            }
                        }
                    },
                    onSetupGit: { workspace in
                        // Trigger GitSetupWizard sheet
                        gitSetupWorkspace = workspace
                    },
                    onAddRemote: { workspace in
                        // Trigger GitSetupWizard for remote setup (starts at addRemote step)
                        gitSetupWorkspace = workspace
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.showCodexStartPromptSheet) {
                CodexStartPromptSheet(
                    workspaceName: viewModel.codexStartWorkspace?.name ?? "Workspace",
                    prompt: $viewModel.codexStartPrompt,
                    onCancel: {
                        viewModel.showCodexStartPromptSheet = false
                        viewModel.codexStartPrompt = ""
                        viewModel.codexStartWorkspace = nil
                    },
                    onStart: {
                        Task { await viewModel.startCodexWorkspaceWithPrompt() }
                    }
                )
                .presentationDetents([.medium])
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
                    // Already connected - ensure list is loaded
                    if viewModel.workspaces.isEmpty {
                        await viewModel.refreshWorkspaces()
                    }
                } else if viewModel.hasSavedManager {
                    // Not connected but have saved manager - try to reconnect with retry
                    await viewModel.connectToSavedManager()
                } else {
                    // No saved manager - show setup
                    viewModel.showSetupSheet = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }

                Task {
                    if viewModel.isConnected {
                        // Ensure list repopulates after long background/foreground cycles.
                        if viewModel.workspaces.isEmpty {
                            await viewModel.refreshWorkspaces()
                        }
                    } else if viewModel.hasSavedManager && !viewModel.isConnecting {
                        await viewModel.retryConnection()
                    }
                }
            }
            .sheet(isPresented: $showDebugLogs) {
                AdminToolsView()
                    .responsiveSheet()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .responsiveSheet()
            }
            .sheet(item: $gitSetupWorkspace, onDismiss: {
                // Refresh workspace list to update git state
                Task { await viewModel.refreshWorkspaces() }
            }) { workspace in
                GitSetupWizard(viewModel: GitSetupViewModel(
                    workspaceId: workspace.id,
                    gitState: workspace.workspaceGitState,
                    workspaceManager: .shared
                ))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(ColorSystem.terminalBg)
            }
            .sheet(isPresented: $showNoGitAlert, onDismiss: {
                noGitAlertWorkspace = nil
                // Note: If gitSetupWorkspace was set, the git setup sheet shows automatically
            }) {
                if let workspace = noGitAlertWorkspace {
                    NoGitAlertSheet(
                        workspace: workspace,
                        onSetupGit: {
                            // Store workspace for git setup, dismiss current sheet
                            gitSetupWorkspace = workspace
                            showNoGitAlert = false
                        },
                        onOpenAnyway: {
                            showNoGitAlert = false
                            // Delay connection until sheet is dismissed
                            Task {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                await connectToWorkspace(workspace)
                            }
                        },
                        onCancel: {
                            showNoGitAlert = false
                        }
                    )
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(20)
                    .presentationBackground(ColorSystem.terminalBgElevated)
                }
            }
            // Note: GitSetup sheet uses sheet(item:) so it presents automatically
            // when gitSetupWorkspace is set (no onChange handler needed)
            .sheet(isPresented: $viewModel.showRemovalSheet) {
                if let info = viewModel.removalInfo {
                    WorkspaceRemovalSheet(
                        info: info,
                        onStopSession: {
                            await viewModel.stopSessionThenRemove()
                        },
                        onLeaveOnly: {
                            await viewModel.leaveWorkspaceOnly()
                        },
                        onRemoveForEveryone: {
                            await viewModel.removeWorkspaceForEveryone()
                        },
                        onCancel: {
                            viewModel.cancelRemoval()
                        }
                    )
                    .presentationDetents([.height(info.hasOtherViewers ? 320 : 260)])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(20)
                }
            }
            .sheet(isPresented: $viewModel.showSessionStopSheet) {
                if let info = viewModel.sessionStopInfo {
                    SessionStopWarningSheet(
                        info: info,
                        onConfirmStop: {
                            await viewModel.confirmStopSession()
                        },
                        onCancel: {
                            viewModel.cancelStopSession()
                        }
                    )
                    .presentationDetents([.height(260)])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(20)
                }
            }
            } // End NavigationStack

            // Floating toolkit button with Debug Logs only
            FloatingToolkitButton(items: toolkitItems) { direction in
                requestScroll(direction: direction)
            }
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
        ScrollViewReader { proxy in
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
                            // Check if workspace needs git setup - show alert instead of direct connect
                            if workspace.workspaceGitState == .noGit {
                                noGitAlertWorkspace = workspace
                                showNoGitAlert = true
                                return
                            }

                            // Normal connection flow
                            Task {
                                await connectToWorkspace(workspace)
                            }
                        },
                        onStart: {
                            Task { await viewModel.startWorkspace(workspace) }
                        },
                        onStop: {
                            Task { await viewModel.stopWorkspace(workspace) }
                        },
                        onRemove: {
                            // Prepare removal with multi-device awareness
                            Task { await viewModel.prepareWorkspaceRemoval(workspace) }
                        },
                        onSetupGit: workspace.needsGitSetup ? {
                            gitSetupWorkspace = workspace
                        } : nil
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .id(workspace.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .refreshable {
                await refreshWorkspaceList()
            }
            .onChange(of: scrollRequest) { _, direction in
                guard let direction = direction else { return }
                handleScrollRequest(direction: direction, proxy: proxy)
            }
        }
    }

    private func refreshWorkspaceList() async {
        Haptics.light()
        await viewModel.refreshWorkspaces()
        Haptics.success()
    }

    private func refreshablePlaceholder<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { geometry in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshWorkspaceList()
            }
        }
    }

    // MARK: - Scroll Request Handler

    /// Request scroll to top or bottom (triggered by floating toolkit force touch)
    private func requestScroll(direction: ScrollDirection) {
        scrollRequest = direction
        // Auto-reset after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            scrollRequest = nil
        }
    }

    private func handleScrollRequest(direction: ScrollDirection, proxy: ScrollViewProxy) {
        guard !viewModel.filteredWorkspaces.isEmpty else { return }
        switch direction {
        case .top:
            if let firstId = viewModel.filteredWorkspaces.first?.id {
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(firstId, anchor: .top)
                }
            }
        case .bottom:
            if let lastId = viewModel.filteredWorkspaces.last?.id {
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Connection Helper

    /// Connect to workspace (extracted for reuse in alert "Open Anyway" action)
    private func connectToWorkspace(_ workspace: RemoteWorkspace) async {
        AppLogger.log("[WorkspaceManagerView] ========== WORKSPACE SWITCH START ==========")
        AppLogger.log("[WorkspaceManagerView] connectToWorkspace: workspace=\(workspace.name), id=\(workspace.id)")
        AppLogger.log("[WorkspaceManagerView] connectToWorkspace: hasActiveSession=\(workspace.hasActiveSession), sessions=\(workspace.sessions.count)")
        AppLogger.log("[WorkspaceManagerView] connectToWorkspace: savedHost=\(viewModel.savedHost ?? "nil"), isConnected=\(viewModel.isConnected)")
        AppLogger.log("[WorkspaceManagerView] connectToWorkspace: currentWorkspaceId=\(viewModel.currentWorkspaceId ?? "nil")")

        // For already-active workspaces, dismiss FIRST to avoid visual glitch
        // when WebSocket reconnects (shared WebSocket causes isConnected state change)
        if workspace.hasActiveSession {
            AppLogger.log("[WorkspaceManagerView] ACTIVE PATH: Dismissing first before connection")
            dismiss()

            // Wait for fullScreenCover dismiss animation to complete
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
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

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading workspaces...")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)
        }
        .frame(maxWidth: .infinity)
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

                Text("Add a workspace by path, or discover repositories on your machine.")
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                // Action buttons
                HStack(spacing: Spacing.sm) {
                    Button {
                        viewModel.showManualAddSheet = true
                    } label: {
                        Label("Add by Path", systemImage: "folder.badge.plus")
                            .font(Typography.buttonLabel)
                            .foregroundStyle(ColorSystem.primary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(ColorSystem.primary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.showDiscoverySheet = true
                    } label: {
                        Label("Discover Repos", systemImage: "magnifyingglass")
                            .font(Typography.buttonLabel)
                            .foregroundStyle(ColorSystem.textSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(ColorSystem.textSecondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
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
        .frame(maxWidth: .infinity)
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
                refreshablePlaceholder {
                    loadingView
                }
            } else if viewModel.filteredWorkspaces.isEmpty {
                refreshablePlaceholder {
                    emptyStateView
                }
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
/// Compact design with clear touch targets
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
            HStack(spacing: Spacing.xs) {
                // Status indicator with background pill
                statusPill

                Spacer()

                // Action buttons
                actionButtons
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, Spacing.xs)
            .background(bannerBackground)
        }
    }

    // MARK: - Status Pill (icon + text)

    @ViewBuilder
    private var statusPill: some View {
        HStack(spacing: Spacing.xs) {
            // Icon with small background
            ZStack {
                Circle()
                    .fill(statusIconBackground)
                    .frame(width: 28, height: 28)

                statusIcon
                    .font(.system(size: 13, weight: .semibold))
            }

            // Status text
            VStack(alignment: .leading, spacing: 0) {
                Text(status.statusText)
                    .font(Typography.caption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(status.statusColor)

                if let host = host {
                    Text(host)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                        .lineLimit(1)
                }
            }
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
                .tint(ColorSystem.warning)
        case .disconnected:
            Image(systemName: "wifi.slash")
                .foregroundStyle(ColorSystem.error)
        case .unreachable:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ColorSystem.error)
        }
    }

    private var statusIconBackground: Color {
        switch status {
        case .connected:
            return ColorSystem.success.opacity(0.15)
        case .connecting:
            return ColorSystem.warning.opacity(0.15)
        case .disconnected, .unreachable:
            return ColorSystem.error.opacity(0.15)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: Spacing.xs) {
            switch status {
            case .connecting:
                // Cancel button
                Button {
                    onCancel?()
                } label: {
                    Text("Cancel")
                        .font(Typography.caption1)
                        .fontWeight(.medium)
                        .foregroundStyle(ColorSystem.textSecondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(ColorSystem.terminalBgHighlight)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

            case .disconnected, .unreachable:
                // Retry button - prominent pill
                Button {
                    onRetry?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Retry")
                            .font(Typography.caption1)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(ColorSystem.primary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .background(ColorSystem.primary.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Change server button - square with border
                Button {
                    onChangeServer?()
                } label: {
                    Image(systemName: "server.rack")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ColorSystem.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(ColorSystem.terminalBgHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ColorSystem.textQuaternary.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

            case .connected:
                EmptyView()
            }
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

// MARK: - Codex Start Prompt Sheet

private struct CodexStartPromptSheet: View {
    let workspaceName: String
    @Binding var prompt: String
    let onCancel: () -> Void
    let onStart: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(spacing: layout.standardPadding) {
            VStack(spacing: Spacing.xxs) {
                Text("Start Codex Session")
                    .font(Typography.title3)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text(workspaceName)
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Text("Codex requires an initial prompt to start a new session.")
                .font(Typography.caption2)
                .foregroundStyle(ColorSystem.textTertiary)
                .multilineTextAlignment(.center)

            ZStack(alignment: .topLeading) {
                if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Describe what you want Codex to do…")
                        .font(Typography.body)
                        .foregroundStyle(ColorSystem.textQuaternary)
                        .padding(.horizontal, layout.smallPadding + 4)
                        .padding(.vertical, layout.smallPadding + 2)
                }

                TextEditor(text: $prompt)
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .padding(.horizontal, layout.smallPadding)
                    .padding(.vertical, layout.smallPadding / 2)
                    .frame(minHeight: 120)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }

            HStack(spacing: layout.contentSpacing) {
                Button("Cancel") {
                    onCancel()
                }
                .font(Typography.buttonLabel)
                .foregroundStyle(ColorSystem.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(Capsule())

                Button("Start") {
                    onStart()
                }
                .font(Typography.buttonLabel)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(ColorSystem.primary)
                .clipShape(Capsule())
            }
        }
        .padding(layout.standardPadding)
        .background(ColorSystem.terminalBg.ignoresSafeArea())
    }
}

// MARK: - Workspace Removal Sheet

/// Sheet for multi-device aware workspace removal
/// Shows different options based on session state and viewers
struct WorkspaceRemovalSheet: View {
    let info: WorkspaceRemovalInfo
    let onStopSession: () async -> Void
    let onLeaveOnly: () async -> Void
    let onRemoveForEveryone: () async -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(ColorSystem.textQuaternary)
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)

            // Header - compact
            VStack(spacing: Spacing.xxs) {
                Image(systemName: headerIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(headerColor)

                Text(headerTitle)
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text(info.workspace.name)
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .lineLimit(1)

                Text(info.stateDescription)
                    .font(Typography.caption2)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, Spacing.md)

            Divider()
                .background(ColorSystem.terminalBgHighlight)

            // Action buttons based on state
            // Only show "Session Running" warning if there are >= 2 viewers
            // If only current device is viewing, no need for warning popup
            VStack(spacing: 0) {
                if showSessionRunningWarning {
                    // Session running with other viewers - primary action is Stop Session
                    actionButton(
                        title: "Stop Session",
                        subtitle: "Stop the running Claude session first",
                        icon: "stop.circle.fill",
                        color: ColorSystem.warning,
                        action: { Task { await onStopSession() } }
                    )

                    Divider()
                        .background(ColorSystem.terminalBgHighlight)
                        .padding(.leading, 48)

                    actionButton(
                        title: "Cancel",
                        subtitle: nil,
                        icon: "xmark.circle",
                        color: ColorSystem.textSecondary,
                        action: onCancel
                    )

                } else if info.hasOtherViewers {
                    // Other viewers - show Leave Only / Remove Anyway options
                    actionButton(
                        title: "Leave Only",
                        subtitle: "Remove from this device only",
                        icon: "rectangle.portrait.and.arrow.right",
                        color: ColorSystem.primary,
                        action: { Task { await onLeaveOnly() } }
                    )

                    Divider()
                        .background(ColorSystem.terminalBgHighlight)
                        .padding(.leading, 48)

                    actionButton(
                        title: "Remove for Everyone",
                        subtitle: "Remove workspace from all devices",
                        icon: "trash.fill",
                        color: ColorSystem.error,
                        action: { Task { await onRemoveForEveryone() } }
                    )

                    Divider()
                        .background(ColorSystem.terminalBgHighlight)
                        .padding(.leading, 48)

                    actionButton(
                        title: "Cancel",
                        subtitle: nil,
                        icon: "xmark.circle",
                        color: ColorSystem.textSecondary,
                        action: onCancel
                    )

                } else {
                    // No conflicts - simple remove confirmation
                    actionButton(
                        title: "Remove Workspace",
                        subtitle: "Remove from manager (files not deleted)",
                        icon: "trash.fill",
                        color: ColorSystem.error,
                        action: { Task { await onRemoveForEveryone() } }
                    )

                    Divider()
                        .background(ColorSystem.terminalBgHighlight)
                        .padding(.leading, 48)

                    actionButton(
                        title: "Cancel",
                        subtitle: nil,
                        icon: "xmark.circle",
                        color: ColorSystem.textSecondary,
                        action: onCancel
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(ColorSystem.terminalBgElevated)
    }

    // MARK: - Header Properties

    // Only show "Session Running" warning if there are >= 2 viewers
    private var showSessionRunningWarning: Bool {
        info.hasActiveSession && info.viewerCount >= 2
    }

    private var headerIcon: String {
        if showSessionRunningWarning {
            return "exclamationmark.triangle.fill"
        } else if info.hasOtherViewers {
            return "person.2.fill"
        } else {
            return "trash.circle"
        }
    }

    private var headerColor: Color {
        if showSessionRunningWarning {
            return ColorSystem.warning
        } else if info.hasOtherViewers {
            return ColorSystem.primary
        } else {
            return ColorSystem.error
        }
    }

    private var headerTitle: String {
        if showSessionRunningWarning {
            return "Session Running"
        } else if info.hasOtherViewers {
            return "Other Devices Viewing"
        } else {
            return "Remove Workspace?"
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private func actionButton(
        title: String,
        subtitle: String?,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: layout.iconMedium))
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(color == ColorSystem.textSecondary ? ColorSystem.textPrimary : color)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Typography.caption2)
                            .foregroundStyle(ColorSystem.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Stop Warning Sheet

/// Warning sheet shown when stopping a session that has other viewers
/// Allows user to confirm or cancel the stop action
struct SessionStopWarningSheet: View {
    let info: SessionStopInfo
    let onConfirmStop: () async -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(ColorSystem.textQuaternary)
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)

            // Header
            VStack(spacing: Spacing.xxs) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(ColorSystem.warning)

                Text("Other Viewers Active")
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text(info.workspace.name)
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .lineLimit(1)

                Text(info.warningMessage)
                    .font(Typography.caption2)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .multilineTextAlignment(.center)

                Text(info.detailMessage)
                    .font(Typography.caption2)
                    .foregroundStyle(ColorSystem.textQuaternary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.bottom, Spacing.md)

            Divider()
                .background(ColorSystem.terminalBgHighlight)

            // Action buttons
            VStack(spacing: 0) {
                actionButton(
                    title: "Stop Anyway",
                    subtitle: "Other devices will be notified",
                    icon: "stop.circle.fill",
                    color: ColorSystem.error,
                    action: { Task { await onConfirmStop() } }
                )

                Divider()
                    .background(ColorSystem.terminalBgHighlight)
                    .padding(.leading, 48)

                actionButton(
                    title: "Cancel",
                    subtitle: nil,
                    icon: "xmark.circle",
                    color: ColorSystem.textSecondary,
                    action: onCancel
                )
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(ColorSystem.terminalBgElevated)
    }

    // MARK: - Action Button

    @ViewBuilder
    private func actionButton(
        title: String,
        subtitle: String?,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(color == ColorSystem.textSecondary ? ColorSystem.textPrimary : color)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Typography.caption2)
                            .foregroundStyle(ColorSystem.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - No Git Alert Sheet

/// Custom styled sheet for workspace without git repository
/// Matches Cdev Signature Design System - Eye-Friendly Edition
/// Uses ColorSystem terminal theme with desaturated accent colors
struct NoGitAlertSheet: View {
    let workspace: RemoteWorkspace
    let onSetupGit: () -> Void
    let onOpenAnyway: () -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator - using textQuaternary for subtle visibility
            RoundedRectangle(cornerRadius: 2.5)
                .fill(ColorSystem.textQuaternary)
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)

            // Header with icon and title
            VStack(spacing: Spacing.sm) {
                // Warning icon with glow effect - using warningGlow from ColorSystem
                ZStack {
                    // Outer glow - matches ColorSystem.warningGlow pattern
                    Circle()
                        .fill(ColorSystem.warningGlow)
                        .frame(width: 72, height: 72)

                    // Inner circle - subtle warning background
                    Circle()
                        .fill(ColorSystem.warning.opacity(0.2))
                        .frame(width: 56, height: 56)

                    // Icon - Golden Pulse warning color (#F6C85D in dark mode)
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(ColorSystem.warning)
                }

                // Title - using textPrimary (#E2E8F0 in dark mode)
                Text("No Git Repository")
                    .font(Typography.title3)
                    .foregroundColor(ColorSystem.textPrimary)

                // Workspace name badge - terminal themed
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                    Text(workspace.name)
                        .font(Typography.terminal)
                }
                .foregroundColor(ColorSystem.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(Capsule())

                // Description - using textTertiary for muted hint text
                Text("This workspace is not tracked by git.\nSetup git to track changes and sync.")
                    .font(Typography.caption1)
                    .foregroundColor(ColorSystem.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.bottom, Spacing.lg)

            // Action buttons - following Cdev button patterns
            VStack(spacing: Spacing.sm) {
                // Primary action - Setup Git
                // Uses Terminal Mint success color (#68D391 in dark mode)
                Button {
                    Haptics.medium()
                    onSetupGit()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: layout.iconMedium))
                        Text("Setup Git")
                            .font(Typography.buttonLabel)
                    }
                    .foregroundColor(ColorSystem.terminalBg) // Dark text on light button
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.buttonHeight + 8)
                    .background(ColorSystem.success)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .buttonStyle(.plain)

                // Secondary action - Open Anyway
                // Uses Cdev Teal primary color (#4FD1C5 in dark mode)
                Button {
                    Haptics.light()
                    onOpenAnyway()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: layout.iconMedium))
                        Text("Open Anyway")
                            .font(Typography.buttonLabel)
                    }
                    .foregroundColor(ColorSystem.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.buttonHeight + 4)
                    .background(ColorSystem.primaryGlow)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .stroke(ColorSystem.primary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Cancel button - text only, using textTertiary
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(Typography.buttonLabel)
                        .foregroundColor(ColorSystem.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: layout.buttonHeight)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, layout.largePadding)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(ColorSystem.terminalBgElevated) // #1E2128 in dark mode
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

#Preview("No Git Alert Sheet") {
    NoGitAlertSheet(
        workspace: RemoteWorkspace(
            id: "test-1",
            name: "test001",
            path: "/Users/brianly/Projects/test001"
        ),
        onSetupGit: {},
        onOpenAnyway: {},
        onCancel: {}
    )
    .frame(height: 320)
    .background(ColorSystem.terminalBg)
}
