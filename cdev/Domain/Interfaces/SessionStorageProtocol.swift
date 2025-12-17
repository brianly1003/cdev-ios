import Foundation

/// Protocol for session/connection storage
protocol SessionStorageProtocol {
    /// Save connection info
    func saveConnection(_ info: ConnectionInfo) async throws

    /// Load last connection info
    func loadLastConnection() async throws -> ConnectionInfo?

    /// Clear saved connection
    func clearConnection() async throws

    /// Save session token
    func saveSessionToken(_ token: String) async throws

    /// Load session token
    func loadSessionToken() async throws -> String?

    /// Clear session token
    func clearSessionToken() async throws
}

/// Protocol for app settings storage
protocol SettingsStorageProtocol {
    /// Auto-reconnect enabled
    var autoReconnect: Bool { get set }

    /// Show timestamps in logs
    var showTimestamps: Bool { get set }

    /// Syntax highlighting enabled
    var syntaxHighlighting: Bool { get set }

    /// Haptic feedback enabled
    var hapticFeedback: Bool { get set }

    /// App theme
    var theme: AppTheme { get set }
}

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark
}
