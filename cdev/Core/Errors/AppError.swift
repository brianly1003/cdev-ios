import Foundation

/// Application-wide error types following CleanerApp patterns
enum AppError: LocalizedError {
    // Connection errors
    case connectionFailed(underlying: Error?)
    case connectionTimeout
    case connectionClosed(reason: String?)
    case serverUnreachable

    // WebSocket errors
    case webSocketDisconnected
    case webSocketMessageFailed(underlying: Error)
    case invalidMessageFormat

    // HTTP errors
    case httpRequestFailed(statusCode: Int, message: String?)
    case httpTimeout
    case invalidResponse

    // Agent errors
    case agentNotRunning
    case claudeAlreadyRunning
    case claudeNotRunning
    case commandFailed(reason: String)

    // Pairing errors
    case invalidQRCode
    case pairingFailed(reason: String)
    case sessionExpired

    // Data errors
    case decodingFailed(underlying: Error)
    case encodingFailed(underlying: Error)
    case fileNotFound(path: String)
    case fileTooLarge(path: String, size: Int64)

    // Security errors
    case authenticationRequired
    case biometricFailed
    case keychainError(underlying: Error?)

    // General errors
    case unknown(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let error):
            if let error = error {
                return "Connection failed: \(error.localizedDescription)"
            }
            return "Connection failed"
        case .connectionTimeout:
            return "Connection timed out"
        case .connectionClosed(let reason):
            if let reason = reason {
                return "Connection closed: \(reason)"
            }
            return "Connection closed"
        case .serverUnreachable:
            return "Server is unreachable"
        case .webSocketDisconnected:
            return "WebSocket disconnected"
        case .webSocketMessageFailed(let error):
            return "Failed to send message: \(error.localizedDescription)"
        case .invalidMessageFormat:
            return "Invalid message format"
        case .httpRequestFailed(let statusCode, let message):
            if let message = message {
                return "Request failed (\(statusCode)): \(message)"
            }
            return "Request failed with status \(statusCode)"
        case .httpTimeout:
            return "Request timed out"
        case .invalidResponse:
            return "Invalid response from server"
        case .agentNotRunning:
            return "Agent is not running"
        case .claudeAlreadyRunning:
            return "Claude is already running"
        case .claudeNotRunning:
            return "Claude is not running"
        case .commandFailed(let reason):
            return "Command failed: \(reason)"
        case .invalidQRCode:
            return "Invalid QR code"
        case .pairingFailed(let reason):
            return "Pairing failed: \(reason)"
        case .sessionExpired:
            return "Session has expired"
        case .decodingFailed(let error):
            return "Failed to decode data: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode data: \(error.localizedDescription)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileTooLarge(let path, _):
            return "File too large: \(path)"
        case .authenticationRequired:
            return "Authentication required"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .keychainError(let error):
            if let error = error {
                return "Keychain error: \(error.localizedDescription)"
            }
            return "Keychain error"
        case .unknown(let error):
            if let error = error {
                return "Unknown error: \(error.localizedDescription)"
            }
            return "An unknown error occurred"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .connectionFailed, .connectionTimeout, .serverUnreachable:
            return "Check that the agent is running and you're on the same network"
        case .webSocketDisconnected, .connectionClosed:
            return "Try reconnecting to the agent"
        case .invalidQRCode:
            return "Scan the QR code displayed by the agent"
        case .sessionExpired:
            return "Reconnect using a new QR code"
        case .authenticationRequired, .biometricFailed:
            return "Please authenticate to continue"
        default:
            return nil
        }
    }
}
