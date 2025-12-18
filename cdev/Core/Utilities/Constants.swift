import Foundation

/// Application constants
enum Constants {
    /// Network configuration
    enum Network {
        static let defaultHTTPPort = 8766
        static let defaultWSPort = 8765
        static let connectionTimeout: TimeInterval = 15
        static let requestTimeout: TimeInterval = 60  // Increased for dev tunnels
        static let pingInterval: TimeInterval = 30
        static let maxReconnectAttempts = 5
        static let reconnectDelay: TimeInterval = 2
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
        static let autoReconnect = "auto_reconnect"
        static let showTimestamps = "show_timestamps"
        static let syntaxHighlighting = "syntax_highlighting"
        static let hapticFeedback = "haptic_feedback"
        static let theme = "app_theme"
        static let showSessionId = "show_session_id"
        static let diffZoomScale = "diff_zoom_scale"
    }
}
