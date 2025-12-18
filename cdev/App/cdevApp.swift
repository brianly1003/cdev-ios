import SwiftUI

/// Main app entry point
@main
struct cdevApp: App {
    @StateObject private var appState = DependencyContainer.shared.makeAppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(appState: appState)
                .preferredColorScheme(colorScheme)
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
    }

    private var colorScheme: ColorScheme? {
        let theme = DependencyContainer.shared.sessionRepository.theme
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Handle app lifecycle transitions for WebSocket connection stability
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        let webSocketService = DependencyContainer.shared.webSocketService

        switch phase {
        case .active:
            // App is in foreground - check and reconnect if needed
            webSocketService.handleAppDidBecomeActive()
        case .inactive:
            // App is transitioning (e.g., incoming call, control center)
            // No action needed
            break
        case .background:
            // App is backgrounding - prepare for potential disconnection
            webSocketService.handleAppWillResignActive()
        @unknown default:
            break
        }
    }
}
