import Foundation

/// Use case for parsing QR codes from agent
protocol ParseQRCodeUseCase {
    func execute(qrData: String) throws -> ConnectionInfo
}

final class DefaultParseQRCodeUseCase: ParseQRCodeUseCase {
    func execute(qrData: String) throws -> ConnectionInfo {
        AppLogger.log("Parsing QR code data")

        guard let data = qrData.data(using: .utf8) else {
            throw AppError.invalidQRCode
        }

        do {
            let decoder = JSONDecoder()
            let connectionInfo = try decoder.decode(ConnectionInfo.self, from: data)

            // Validate URLs
            guard connectionInfo.webSocketURL.scheme == "ws" || connectionInfo.webSocketURL.scheme == "wss" else {
                throw AppError.invalidQRCode
            }

            guard connectionInfo.httpURL.scheme == "http" || connectionInfo.httpURL.scheme == "https" else {
                throw AppError.invalidQRCode
            }

            AppLogger.log("QR code parsed successfully", type: .success)
            return connectionInfo
        } catch let error as AppError {
            throw error
        } catch {
            AppLogger.error(error, context: "QR code parsing")
            throw AppError.invalidQRCode
        }
    }
}
