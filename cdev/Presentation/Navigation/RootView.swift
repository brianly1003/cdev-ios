import SwiftUI

/// Root view - handles connection state and navigation
struct RootView: View {
    @StateObject var appState: AppState

    var body: some View {
        Group {
            switch appState.connectionState {
            case .disconnected, .failed:
                // Show pairing view when disconnected
                PairingView(viewModel: appState.makePairingViewModel())

            case .connecting, .reconnecting:
                // Show connecting state with cancel option
                ConnectingView(
                    state: appState.connectionState,
                    onCancel: { appState.cancelConnection() }
                )

            case .connected:
                // Show main dashboard
                DashboardView(viewModel: appState.makeDashboardViewModel())
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
