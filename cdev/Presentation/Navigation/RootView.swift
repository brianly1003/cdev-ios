import SwiftUI

/// Root view - handles connection state and navigation
/// Non-blocking design: Dashboard is shown during connecting/reconnecting so users can continue working
struct RootView: View {
    @StateObject var appState: AppState

    var body: some View {
        Group {
            // If has saved workspaces, always show Dashboard (connection status shown inline)
            // This allows users to continue viewing Terminal, Changes, Explorer while reconnecting
            if appState.hasSavedWorkspaces {
                DashboardView(viewModel: appState.makeDashboardViewModel())
            } else {
                // No workspaces - show Pairing for first-time setup
                PairingView(viewModel: appState.makePairingViewModel())
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.connectionState.isConnected)
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
