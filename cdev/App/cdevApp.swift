import SwiftUI

/// Main app entry point
@main
struct cdevApp: App {
    @StateObject private var appState = DependencyContainer.shared.makeAppState()

    var body: some Scene {
        WindowGroup {
            RootView(appState: appState)
                .preferredColorScheme(colorScheme)
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
}
