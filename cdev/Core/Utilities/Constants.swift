import Foundation

/// Application constants
enum Constants {
    /// Network configuration
    enum Network {
        static let defaultHTTPPort = 8766
        static let defaultWSPort = 8765
        static let connectionTimeout: TimeInterval = 10
        static let requestTimeout: TimeInterval = 30
        static let pingInterval: TimeInterval = 30
        static let maxReconnectAttempts = 5
        static let reconnectDelay: TimeInterval = 2
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
    }
}
