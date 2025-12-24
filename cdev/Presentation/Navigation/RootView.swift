import SwiftUI

/// Root view - handles connection state and navigation
/// Non-blocking design: Dashboard is shown during connecting/reconnecting so users can continue working
struct RootView: View {
    @StateObject var appState: AppState
    @ObservedObject private var managerStore = ManagerStore.shared
    @ObservedObject private var workspaceStore = WorkspaceStore.shared

    /// Track if user has selected a workspace from the manager
    @State private var hasSelectedWorkspace: Bool = false


    var body: some View {
        Group {
            // New architecture: Show WorkspaceManager first to let user choose
            // Only show Dashboard after user selects a workspace AND connected
            let showDashboard = hasSelectedWorkspace && workspaceStore.activeWorkspace != nil && appState.connectionState.isConnected
            let _ = AppLogger.log("[RootView] Check: hasSelectedWorkspace=\(hasSelectedWorkspace), activeWorkspace=\(workspaceStore.activeWorkspace?.name ?? "nil"), isConnected=\(appState.connectionState.isConnected), showDashboard=\(showDashboard)")

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
                            AppLogger.log("[RootView] Setting hasSelectedWorkspace = true")
                            hasSelectedWorkspace = true
                        }
                        return success
                    },
                    showDismissButton: false  // No dismiss button when used as root view
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasSelectedWorkspace)
        .animation(.easeInOut(duration: 0.3), value: appState.connectionState.isConnected)
        .onChange(of: appState.connectionState) { oldState, newState in
            // Handle connection failures - return to workspace manager
            // Note: No popup alert - the WorkspaceManagerView banner shows status
            if case .failed(let reason) = newState {
                AppLogger.log("[RootView] Connection failed: \(reason), returning to workspace manager")
                hasSelectedWorkspace = false
                // Clear active workspace on failure
                WorkspaceStore.shared.clearActive()
            }
            // Also handle disconnection while viewing dashboard
            if case .disconnected = newState, oldState.isConnected {
                AppLogger.log("[RootView] Disconnected, returning to workspace manager")
                hasSelectedWorkspace = false
            }
        }
        .onAppear {
            // Migration: Clear old saved workspaces from previous architecture
            // They were created via QR pairing and don't work with the new system
            migrateToNewArchitecture()
        }
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
