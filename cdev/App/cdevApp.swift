import SwiftUI
import UserNotifications

/// Main app entry point
@main
struct cdevApp: App {
    @StateObject private var appState = DependencyContainer.shared.makeAppState()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    /// Tracks if user is on Dashboard (persisted for app lifecycle)
    @AppStorage("cdev.userOnDashboard") private var userOnDashboard: Bool = false

    init() {
        // Configure WorkspaceManagerService with WebSocket connection
        // This must happen early so the service can make JSON-RPC calls
        WorkspaceManagerService.shared.configure(
            webSocketService: DependencyContainer.shared.webSocketService
        )

        // Request notification permissions for permission alerts
        Task {
            await NotificationService.shared.requestAuthorization()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView(appState: appState)
                    .preferredColorScheme(colorScheme)
                    .onChange(of: scenePhase) { _, newPhase in
                        handleScenePhaseChange(newPhase)
                    }

                // Splash screen overlay
                if showSplash {
                    SplashScreen()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // Delay before dismissing splash
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showSplash = false
                    }
                }
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
            // Preserve watch if user is on Dashboard (will reconnect on foreground)
            webSocketService.handleAppWillResignActive(preserveWatch: userOnDashboard)
        @unknown default:
            break
        }
    }
}

// MARK: - Splash Screen

/// Branded splash screen with app logo
struct SplashScreen: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var glowPulse: Bool = false

    var body: some View {
        ZStack {
            // Background - matches launch screen
            Color(red: 0.082, green: 0.086, blue: 0.106)
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
                // App Logo with glow aura
                ZStack {
                    // Outer glow pulse
                    Circle()
                        .fill(ColorSystem.brand.opacity(0.15))
                        .frame(width: 96, height: 96)
                        .blur(radius: 12)
                        .scaleEffect(glowPulse ? 1.15 : 1.0)
                        .opacity(glowPulse ? 0.3 : 0.5)

                    // Inner glow
                    Circle()
                        .fill(ColorSystem.brand.opacity(0.25))
                        .frame(width: 86, height: 86)
                        .blur(radius: 6)

                    // App Logo
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .shadow(color: ColorSystem.brand.opacity(0.35), radius: 8)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // App name
                Text("Cdev")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(logoOpacity)
            }
        }
        .onAppear {
            // Animate logo appearance
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            // Start glow pulse animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }
}
