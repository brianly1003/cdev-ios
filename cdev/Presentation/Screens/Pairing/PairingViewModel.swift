import Foundation
import AVFoundation

@MainActor
final class PairingViewModel: ObservableObject {
    // MARK: - Published State

    @Published var hasCameraPermission = false
    @Published var manualURL = ""
    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var error: AppError?
    @Published var showTokenExpiredAlert = false
    @Published var tokenExpiredMessage = ""

    // MARK: - Dependencies

    private let parseQRCodeUseCase: ParseQRCodeUseCase
    private let connectToAgentUseCase: ConnectToAgentUseCase
    private let httpService: HTTPServiceProtocol
    private weak var appState: AppState?

    // MARK: - Init

    init(
        parseQRCodeUseCase: ParseQRCodeUseCase,
        connectToAgentUseCase: ConnectToAgentUseCase,
        httpService: HTTPServiceProtocol,
        appState: AppState
    ) {
        self.parseQRCodeUseCase = parseQRCodeUseCase
        self.connectToAgentUseCase = connectToAgentUseCase
        self.httpService = httpService
        self.appState = appState

        TokenManager.shared.setHTTPService(httpService)
        checkCameraPermission()
    }

    // MARK: - Camera Permission

    func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        hasCameraPermission = status == .authorized
    }

    func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                self?.hasCameraPermission = granted
            }
        }
    }

    // MARK: - QR Code Handling

    func handleScannedCode(_ code: String) async {
        // Debounce: Skip if same code scanned recently (check AppState)
        guard appState?.shouldProcessScan(code: code) == true else {
            AppLogger.log("Ignoring duplicate QR scan (debounced)")
            return
        }

        // Also skip if already connecting
        guard !isConnecting else {
            AppLogger.log("Ignoring QR scan - already connecting")
            return
        }

        // Record this scan in AppState (persists across ViewModel instances)
        appState?.recordScan(code: code)

        isConnecting = true
        Haptics.success()

        AppLogger.log("[Pairing] QR code scanned, length: \(code.count)")
        AppLogger.log("[Pairing] QR data preview: \(String(code.prefix(100)))...")

        do {
            let connectionInfo = try parseQRCodeUseCase.execute(qrData: code)
            AppLogger.log("[Pairing] Parsed ConnectionInfo:")
            AppLogger.log("[Pairing]   ws: \(connectionInfo.webSocketURL)")
            AppLogger.log("[Pairing]   http: \(connectionInfo.httpURL)")
            AppLogger.log("[Pairing]   token: \(connectionInfo.token != nil ? "present" : "none")")
            await connect(to: connectionInfo)
        } catch {
            AppLogger.log("[Pairing] Parse error: \(error)", type: .error)
            self.error = error as? AppError ?? .invalidQRCode
            Haptics.error()
        }

        isConnecting = false
    }

    // MARK: - Manual Connection

    func connectManually() async {
        guard !manualURL.isBlank else { return }

        isConnecting = true

        // Parse manual URL
        guard let wsURL = URL(string: manualURL) else {
            error = .invalidQRCode
            isConnecting = false
            return
        }

        // Derive HTTP URL from WebSocket URL
        var httpURLComponents = URLComponents(url: wsURL, resolvingAgainstBaseURL: false)
        httpURLComponents?.scheme = wsURL.scheme == "wss" ? "https" : "http"
        httpURLComponents?.path = ""  // Remove /ws path for HTTP base URL

        // Only set port for local connections without explicit port
        // Dev tunnels and other proxies use standard ports (80/443)
        let isLocalConnection = wsURL.host == "localhost" || wsURL.host == "127.0.0.1" || wsURL.host?.hasPrefix("192.168.") == true
        if isLocalConnection && wsURL.port == nil {
            httpURLComponents?.port = Constants.Network.defaultHTTPPort
        }

        guard let httpURL = httpURLComponents?.url else {
            error = .invalidQRCode
            isConnecting = false
            return
        }

        // Create connection info (without session ID and repo name - will be fetched)
        let connectionInfo = ConnectionInfo(
            webSocketURL: wsURL,
            httpURL: httpURL,
            sessionId: "manual",
            repoName: "Unknown"
        )

        await connect(to: connectionInfo)
        isConnecting = false
    }

    // MARK: - Private

    private func connect(to connectionInfo: ConnectionInfo) async {
        do {
            // Set HTTP base URL and resolve access token if needed
            httpService.baseURL = connectionInfo.httpURL

            var updatedConnectionInfo = connectionInfo
            if let token = connectionInfo.token, TokenType.from(token: token) == .pairing {
                guard let host = connectionInfo.httpURL.host ?? connectionInfo.webSocketURL.host else {
                    throw AppError.invalidQRCodeDetail(reason: "Missing host in connection info")
                }
                AppLogger.log("[Pairing] Exchanging pairing token for access token")
                let tokenPair = try await TokenManager.shared.exchangePairingToken(token, host: host)
                httpService.authToken = tokenPair.accessToken
                updatedConnectionInfo = ConnectionInfo(
                    webSocketURL: connectionInfo.webSocketURL,
                    httpURL: connectionInfo.httpURL,
                    sessionId: connectionInfo.sessionId,
                    repoName: connectionInfo.repoName,
                    token: tokenPair.accessToken,
                    tokenExpiresAt: Self.formatISO8601(tokenPair.accessTokenExpiresAt)
                )
            } else {
                httpService.authToken = connectionInfo.token
                if connectionInfo.token != nil {
                    AppLogger.log("[Pairing] Auth token configured for HTTP requests")
                }
            }

            // Connect via WebSocket (auth header set in WebSocketService)
            try await connectToAgentUseCase.execute(connectionInfo: updatedConnectionInfo)

            // Save workspace for quick reconnection
            WorkspaceStore.shared.setActive(
                from: updatedConnectionInfo,
                repoName: updatedConnectionInfo.repoName
            )

            // Clear scan history on successful connection
            appState?.clearScanHistory()

            isConnected = true
            Haptics.success()
        } catch {
            let appError = error as? AppError ?? .connectionFailed(underlying: error)
            let isPairingFailure: Bool
            if case .pairingFailed = appError {
                isPairingFailure = true
            } else {
                isPairingFailure = false
            }

            // Handle authentication errors specially
            if appError.isAuthenticationError || isPairingFailure {
                handleAuthenticationError(appError)
            } else {
                self.error = appError
            }
            Haptics.error()
        }
    }

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // MARK: - Authentication Error Handling

    /// Handle authentication errors by showing a re-scan prompt
    private func handleAuthenticationError(_ error: AppError) {
        switch error {
        case .tokenExpired:
            tokenExpiredMessage = "The QR code has expired. QR codes are valid for 60 seconds.\n\nPlease refresh the QR code on your computer and scan again."
            showTokenExpiredAlert = true
        case .tokenInvalid:
            tokenExpiredMessage = "The authentication token is invalid.\n\nPlease refresh the QR code on your computer and scan again."
            showTokenExpiredAlert = true
        case .httpRequestFailed(let statusCode, _) where statusCode == 401 || statusCode == 403:
            tokenExpiredMessage = "Authentication failed (HTTP \(statusCode)).\n\nPlease refresh the QR code on your computer and scan again."
            showTokenExpiredAlert = true
        case .pairingFailed(let reason):
            tokenExpiredMessage = "\(reason)\n\nPlease refresh the QR code and try again."
            showTokenExpiredAlert = true
        default:
            self.error = error
        }

        // Clear the HTTP auth token on auth failure
        httpService.authToken = nil
    }

    /// Dismiss token expired alert and prepare for re-scan
    func dismissTokenExpiredAlert() {
        showTokenExpiredAlert = false
        tokenExpiredMessage = ""
        appState?.clearScanHistory()  // Allow immediate re-scan
    }
}
