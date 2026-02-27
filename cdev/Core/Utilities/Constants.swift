import Foundation

/// Application constants
enum Constants {
    /// Brand identity - change here to update app name everywhere
    enum Brand {
        static let appName = "Cdev+"
        static let tagline = "Mobile companion for Claude Code & Codex"
        static let author = "Brian Ly"
        static let email = "brianly1003@gmail.com"
        static let githubRepo = "https://github.com/brianly1003/cdev-ios"
        static let githubIssues = "https://github.com/brianly1003/cdev-ios/issues"
    }

    /// Network configuration
    enum Network {
        static let defaultHTTPPort = 16180
        static let connectionTimeout: TimeInterval = 30       // Increased for dev tunnels
        static let requestTimeout: TimeInterval = 120         // 2 min for dev tunnels with slow ops
        static let requestTimeoutLocal: TimeInterval = 30     // Faster for localhost

        // WebSocket stability settings (mobile-optimized per WEBSOCKET-STABILITY.md)
        static let pingInterval: TimeInterval = 30           // WebSocket ping interval
        static let heartbeatInterval: TimeInterval = 30      // Server sends heartbeat every 30s
        static let heartbeatTimeout: TimeInterval = 45       // Reconnect if no heartbeat for 45s (1.5x interval)
        static let maxReconnectAttempts = 10                 // Increased for mobile (was 5)
        static let reconnectDelay: TimeInterval = 1          // Initial delay (was 2)
        static let maxReconnectDelay: TimeInterval = 30      // Cap exponential backoff at 30s

        // HTTP settings
        static let httpMaxRetries = 3
        static let httpRetryDelay: TimeInterval = 1.0
    }

    /// Cache configuration
    enum Cache {
        static let maxLogLines = 1000
        static let maxDiffSize = 100_000 // 100KB
        static let sessionCacheExpiry: TimeInterval = 3600 // 1 hour
    }

    /// UI configuration
    enum UI {
        static let animationDuration: Double = 0.3
        static let debounceInterval: TimeInterval = 0.3
        static let maxDisplayedLogs = 500
    }

    /// Diff viewer zoom configuration
    enum Zoom {
        static let minScale: CGFloat = 0.6
        static let maxScale: CGFloat = 2.0
        static let defaultScale: CGFloat = 1.0
        static let stepSize: CGFloat = 0.1
        static let presets: [CGFloat] = [0.6, 0.8, 1.0, 1.2, 1.5, 2.0]
    }

    /// Keychain keys
    enum Keychain {
        static let serviceName = "com.brianly.cdev"
        static let sessionTokenKey = "session_token"
        static let serverURLKey = "server_url"
    }

    /// UserDefaults keys
    enum UserDefaults {
        static let lastConnectedServer = "last_connected_server"
        static let showTimestamps = "show_timestamps"
        static let hapticFeedback = "haptic_feedback"
        static let theme = "app_theme"
        static let diffZoomScale = "diff_zoom_scale"
        static let selectedSessionId = "selected_session_id"
        static let selectedSessionRuntime = "selected_session_runtime"
        static let useElementsView = "use_elements_view"  // Feature flag for Elements API UI
    }
}
