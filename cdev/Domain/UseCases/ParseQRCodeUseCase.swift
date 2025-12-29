import Foundation

/// Use case for parsing QR codes from agent
protocol ParseQRCodeUseCase {
    func execute(qrData: String) throws -> ConnectionInfo
}

final class DefaultParseQRCodeUseCase: ParseQRCodeUseCase {
    func execute(qrData: String) throws -> ConnectionInfo {
        AppLogger.log("Parsing QR code data")

        // Check if data is empty
        guard !qrData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidQRCodeDetail(reason: "Empty QR code data")
        }

        guard let data = qrData.data(using: .utf8) else {
            throw AppError.invalidQRCodeDetail(reason: "Invalid character encoding")
        }

        // Check if it looks like JSON
        guard qrData.trimmingCharacters(in: .whitespaces).hasPrefix("{") else {
            throw AppError.invalidQRCodeDetail(reason: "Not a cdev QR code. Expected JSON format.")
        }

        do {
            let decoder = JSONDecoder()
            let connectionInfo = try decoder.decode(ConnectionInfo.self, from: data)

            // Validate WebSocket URL scheme
            guard connectionInfo.webSocketURL.scheme == "ws" || connectionInfo.webSocketURL.scheme == "wss" else {
                throw AppError.invalidQRCodeDetail(reason: "Invalid WebSocket URL scheme. Expected ws:// or wss://")
            }

            // Validate HTTP URL scheme
            guard connectionInfo.httpURL.scheme == "http" || connectionInfo.httpURL.scheme == "https" else {
                throw AppError.invalidQRCodeDetail(reason: "Invalid HTTP URL scheme. Expected http:// or https://")
            }

            // Validate required fields are not empty
            guard !connectionInfo.repoName.isEmpty else {
                throw AppError.invalidQRCodeDetail(reason: "Missing repository name")
            }

            AppLogger.log("QR code parsed successfully", type: .success)
            if connectionInfo.token != nil {
                AppLogger.log("QR code contains auth token", type: .info)
            }
            return connectionInfo
        } catch let error as AppError {
            throw error
        } catch let decodingError as DecodingError {
            // Provide more specific error messages for decoding failures
            let reason: String
            switch decodingError {
            case .keyNotFound(let key, _):
                reason = "Missing required field: \(key.stringValue)"
            case .valueNotFound(_, let context):
                reason = "Missing value for: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            case .typeMismatch(_, let context):
                reason = "Invalid type for: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            case .dataCorrupted(let context):
                reason = context.debugDescription
            @unknown default:
                reason = "Invalid QR code format"
            }
            AppLogger.error(decodingError, context: "QR code parsing")
            throw AppError.invalidQRCodeDetail(reason: reason)
        } catch {
            AppLogger.error(error, context: "QR code parsing")
            throw AppError.invalidQRCodeDetail(reason: "Failed to parse QR code data")
        }
    }
}
