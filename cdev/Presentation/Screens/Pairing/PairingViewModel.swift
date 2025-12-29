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
            AppLogger.log("[Pairing]   token: \(connectionInfo.token != nil ? "YES (\(connectionInfo.token!.prefix(15))...)" : "NO")")
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
            // Set HTTP base URL and auth token
            httpService.baseURL = connectionInfo.httpURL
            httpService.authToken = connectionInfo.token
            if connectionInfo.token != nil {
                AppLogger.log("[Pairing] Auth token configured for HTTP requests")
            }

            // Connect via WebSocket (token is appended to URL in WebSocketService)
            try await connectToAgentUseCase.execute(connectionInfo: connectionInfo)

            // Save workspace for quick reconnection
            WorkspaceStore.shared.setActive(
                from: connectionInfo,
                repoName: connectionInfo.repoName
            )

            // Clear scan history on successful connection
            appState?.clearScanHistory()

            isConnected = true
            Haptics.success()
        } catch {
            let appError = error as? AppError ?? .connectionFailed(underlying: error)

            // Handle authentication errors specially
            if appError.isAuthenticationError {
                handleAuthenticationError(appError)
            } else {
                self.error = appError
            }
            Haptics.error()
        }
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
