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

        do {
            let connectionInfo = try parseQRCodeUseCase.execute(qrData: code)
            await connect(to: connectionInfo)
        } catch {
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
        httpURLComponents?.port = Constants.Network.defaultHTTPPort

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
            // Set HTTP base URL
            httpService.baseURL = connectionInfo.httpURL

            // Connect via WebSocket
            try await connectToAgentUseCase.execute(connectionInfo: connectionInfo)

            // Clear scan history on successful connection
            appState?.clearScanHistory()

            isConnected = true
            Haptics.success()
        } catch {
            self.error = error as? AppError ?? .connectionFailed(underlying: error)
            Haptics.error()
        }
    }
}
