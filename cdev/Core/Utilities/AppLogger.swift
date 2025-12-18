import Foundation
import os.log

/// Secure logging utility - logs are completely removed in release builds
/// CRITICAL: Never log sensitive data (tokens, passwords, user data)
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.brianly.cdev"

    private static let generalLog = Logger(subsystem: subsystem, category: "general")
    private static let networkLog = Logger(subsystem: subsystem, category: "network")
    private static let webSocketLog = Logger(subsystem: subsystem, category: "websocket")
    private static let uiLog = Logger(subsystem: subsystem, category: "ui")

    enum LogType {
        case info
        case success
        case warning
        case error
    }

    /// General application logging
    static func log(_ message: String, type: LogType = .info) {
        #if DEBUG
        switch type {
        case .info:
            generalLog.info("\(message)")
        case .success:
            generalLog.info("[SUCCESS] \(message)")
        case .warning:
            generalLog.warning("[WARNING] \(message)")
        case .error:
            generalLog.error("[ERROR] \(message)")
        }
        #endif
    }

    /// Network-related logging
    static func network(_ message: String, type: LogType = .info) {
        #if DEBUG
        switch type {
        case .info:
            networkLog.info("\(message)")
        case .success:
            networkLog.info("[SUCCESS] \(message)")
        case .warning:
            networkLog.warning("[WARNING] \(message)")
        case .error:
            networkLog.error("[ERROR] \(message)")
        }
        #endif
    }

    /// WebSocket-specific logging
    static func webSocket(_ message: String, type: LogType = .info) {
        #if DEBUG
        switch type {
        case .info:
            webSocketLog.info("[WS] \(message)")
        case .success:
            webSocketLog.info("[WS] ✓ \(message)")
        case .warning:
            webSocketLog.warning("[WS] ⚠ \(message)")
        case .error:
            webSocketLog.error("[WS] ✗ \(message)")
        }
        #endif
    }

    /// UI-related logging
    static func ui(_ message: String, type: LogType = .info) {
        #if DEBUG
        switch type {
        case .info:
            uiLog.info("\(message)")
        case .success:
            uiLog.info("[SUCCESS] \(message)")
        case .warning:
            uiLog.warning("[WARNING] \(message)")
        case .error:
            uiLog.error("[ERROR] \(message)")
        }
        #endif
    }

    /// Log errors with context
    static func error(_ error: Error, context: String? = nil) {
        #if DEBUG
        if let context = context {
            generalLog.error("[ERROR] \(context): \(error.localizedDescription)")
        } else {
            generalLog.error("[ERROR] \(error.localizedDescription)")
        }
        #endif
    }
}
