import SwiftUI

// MARK: - Debug Log Types (Shared between AppLogger and DebugLogStore)

/// Categories of debug logs
enum DebugLogCategory: String, CaseIterable, Identifiable, Codable {
    case all = "All"
    case http = "HTTP"
    case websocket = "WS"
    case app = "App"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .http: return "arrow.up.arrow.down"
        case .websocket: return "bolt.fill"
        case .app: return "app.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: return ColorSystem.textSecondary
        case .http: return ColorSystem.primary
        case .websocket: return ColorSystem.warning
        case .app: return ColorSystem.info
        }
    }
}

/// Log severity level
enum DebugLogLevel: String, Codable {
    case info
    case success
    case warning
    case error

    var icon: String {
        switch self {
        case .info: return ""
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return ColorSystem.textSecondary
        case .success: return ColorSystem.success
        case .warning: return ColorSystem.warning
        case .error: return ColorSystem.error
        }
    }
}
