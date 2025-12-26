import SwiftUI

/// Root view - handles connection state and navigation
/// Non-blocking design: Dashboard is shown during connecting/reconnecting so users can continue working
/// PERSISTENCE: User's dashboard intent is persisted across app lifecycle (background/foreground)
struct RootView: View {
    @StateObject var appState: AppState
    @ObservedObject private var managerStore = ManagerStore.shared
    @ObservedObject private var workspaceStore = WorkspaceStore.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Persist user's intent to be on Dashboard (survives background/foreground cycles)
    @AppStorage("cdev.userOnDashboard") private var userOnDashboard: Bool = false

    /// Track if we're in the process of reconnecting after foreground
    @State private var isRestoringConnection: Bool = false

    var body: some View {
        Group {
            // Show Dashboard if:
            // 1. User has selected a workspace (persisted intent)
            // 2. Active workspace exists in store
            // Note: Don't require connection state - Dashboard handles its own connection UI
            // This allows Dashboard to remain visible during reconnection after background
            let showDashboard = userOnDashboard && workspaceStore.activeWorkspace != nil
            let _ = AppLogger.log("[RootView] Check: userOnDashboard=\(userOnDashboard), activeWorkspace=\(workspaceStore.activeWorkspace?.name ?? "nil"), isConnected=\(appState.connectionState.isConnected), showDashboard=\(showDashboard)")

            if showDashboard {
                DashboardView(viewModel: appState.makeDashboardViewModel())
            } else {
                // Show Workspace Manager for multi-workspace management
                // User must select a workspace before seeing Dashboard
                WorkspaceManagerView(
                    onConnectToWorkspace: { workspace, host in
                        // When user connects to a remote workspace:
                        // - Creates local workspace and connects to it
                        // Returns true on success, false on failure
                        AppLogger.log("[RootView] onConnectToWorkspace called for: \(workspace.name) on \(host)")
                        let success = await appState.connectToRemoteWorkspace(workspace, host: host)
                        AppLogger.log("[RootView] connectToRemoteWorkspace returned: \(success)")
                        if success {
                            AppLogger.log("[RootView] Setting userOnDashboard = true")
                            userOnDashboard = true
                        }
                        return success
                    },
                    showDismissButton: false  // No dismiss button when used as root view
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: userOnDashboard)
        .animation(.easeInOut(duration: 0.3), value: appState.connectionState.isConnected)
        // Handle app lifecycle (background/foreground)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .onChange(of: appState.connectionState) { oldState, newState in
            handleConnectionStateChange(from: oldState, to: newState)
        }
        .onAppear {
            // Migration: Clear old saved workspaces from previous architecture
            migrateToNewArchitecture()

            // Restore connection if user was on Dashboard
            if userOnDashboard && workspaceStore.activeWorkspace != nil {
                AppLogger.log("[RootView] onAppear: Restoring connection for active workspace")
                Task {
                    await restoreConnectionIfNeeded()
                }
            }
        }
    }

    // MARK: - Scene Phase Handling

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App came to foreground
            AppLogger.log("[RootView] Scene became active")
            if userOnDashboard && workspaceStore.activeWorkspace != nil {
                Task {
                    await restoreConnectionIfNeeded()
                }
            }

        case .background:
            // App going to background - WebSocket will disconnect
            // Don't clear userOnDashboard - we want to restore when coming back
            AppLogger.log("[RootView] Scene entering background - preserving dashboard state")
            appState.markExpectedDisconnection()

        case .inactive:
            // Transitional state - ignore
            break

        @unknown default:
            break
        }
    }

    // MARK: - Connection State Handling

    private func handleConnectionStateChange(from oldState: ConnectionState, to newState: ConnectionState) {
        switch newState {
        case .failed(let reason):
            // Only navigate away if it's a FINAL failure AND not restoring from background
            // Check if we should abandon dashboard
            if !isRestoringConnection && !appState.isExpectedDisconnection {
                AppLogger.log("[RootView] Connection failed (final): \(reason), returning to workspace manager")
                userOnDashboard = false
                WorkspaceStore.shared.clearActive()
            } else {
                AppLogger.log("[RootView] Connection failed but in restoration mode - keeping dashboard")
                // Try to restore connection
                Task {
                    await restoreConnectionIfNeeded()
                }
            }

        case .disconnected:
            // Don't navigate away on disconnection - wait for reconnection attempt
            // Only navigate away if user explicitly disconnected (not from background)
            if oldState.isConnected && !appState.isExpectedDisconnection && !isRestoringConnection {
                // Check if this was an explicit user disconnect (not background)
                if appState.wasExplicitDisconnect {
                    AppLogger.log("[RootView] Explicit disconnect, returning to workspace manager")
                    userOnDashboard = false
                } else {
                    AppLogger.log("[RootView] Unexpected disconnect - attempting reconnection")
                    Task {
                        await restoreConnectionIfNeeded()
                    }
                }
            }

        case .connected:
            // Connection restored
            isRestoringConnection = false
            appState.clearExpectedDisconnection()
            AppLogger.log("[RootView] Connection restored")

        case .connecting, .reconnecting:
            // In progress - keep dashboard visible
            break
        }
    }

    // MARK: - Connection Restoration

    private func restoreConnectionIfNeeded() async {
        guard !appState.connectionState.isConnected else {
            AppLogger.log("[RootView] Already connected, skipping restoration")
            return
        }

        guard let workspace = workspaceStore.activeWorkspace else {
            AppLogger.log("[RootView] No active workspace for restoration")
            return
        }

        isRestoringConnection = true
        AppLogger.log("[RootView] Restoring connection for workspace: \(workspace.name)")

        // Attempt reconnection through AppState
        await appState.reconnectToActiveWorkspace()
    }

    /// One-time migration to clear old workspace data
    private func migrateToNewArchitecture() {
        let migrationKey = "cdev.migrated_to_single_port_v1"

        if !UserDefaults.standard.bool(forKey: migrationKey) {
            AppLogger.log("[RootView] Migrating to single-port architecture, clearing old workspaces")
            // Clear old WorkspaceStore data
            WorkspaceStore.shared.clearAll()
            // Mark migration complete
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }
}

// MARK: - Connecting View

struct ConnectingView: View {
    let state: ConnectionState
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Spacer()

                ProgressView()
                    .scaleEffect(1.5)

                Text(state.statusText)
                    .font(Typography.bodyBold)

                if case .reconnecting(let attempt) = state {
                    Text("Attempt \(attempt) of \(Constants.Network.maxReconnectAttempts)")
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}
