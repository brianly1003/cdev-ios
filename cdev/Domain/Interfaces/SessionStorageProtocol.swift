import Foundation
import SwiftUI

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

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
