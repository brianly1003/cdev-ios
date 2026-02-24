import SwiftUI
import Combine

// MARK: - Server Connection Status

/// Status of connection to the workspace manager server
enum ServerConnectionStatus: Equatable {
    case connected
    case connecting(attempt: Int, maxAttempts: Int)
    case disconnected
    case unreachable(lastError: String?)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .connected:
            return "Connected"
        case .connecting(let attempt, let max):
            return "Connecting... (\(attempt)/\(max))"
        case .disconnected:
            return "Disconnected"
        case .unreachable:
            return "Server Unreachable"
        }
    }

    var statusColor: Color {
        switch self {
        case .connected: return ColorSystem.success
        case .connecting: return ColorSystem.warning
        case .disconnected, .unreachable: return ColorSystem.error
        }
    }
}

// MARK: - Workspace Operation Type

/// Type of operation being performed on a workspace
enum WorkspaceOperation: Equatable {
    case starting
    case stopping
    case connecting
    case removing

    var displayText: String {
        switch self {
        case .starting: return "Starting..."
        case .stopping: return "Stopping..."
        case .connecting: return "Connecting..."
        case .removing: return "Removing..."
        }
    }
}

// MARK: - Workspace Removal

/// Result of workspace removal operation
enum WorkspaceRemovalResult {
    case removed           // Workspace removed for everyone
    case leftOnly          // Only left workspace (still exists for others)
    case cancelled         // User cancelled
    case needsSessionStop  // Session must be stopped first
}

// MARK: - Workspace Manager ViewModel

/// ViewModel for managing remote workspaces
/// Single-port architecture: handles session lifecycle operations
@MainActor
final class WorkspaceManagerViewModel: ObservableObject {
    // MARK: - Published State

    /// All workspaces from manager
    @Published private(set) var workspaces: [RemoteWorkspace] = []

    /// Filtered workspaces based on search
    @Published var searchText: String = ""

    /// Loading states
    @Published private(set) var isLoading: Bool = false

    /// Per-workspace loading state (tracks which workspace is being operated on)
    @Published private(set) var loadingWorkspaceId: String?
    @Published private(set) var currentOperation: WorkspaceOperation?

    /// Track workspaces that failed to connect (observed from service)
    @Published private(set) var unreachableWorkspaceIds: Set<String> = []

    /// Error state (now used for inline display, not popup)
    @Published var error: WorkspaceManagerError?
    @Published var showError: Bool = false

    /// Server connection status (non-blocking)
    @Published private(set) var serverStatus: ServerConnectionStatus = .disconnected

    /// Retry configuration
    let maxRetryAttempts = 10
    private let retryCooldownAfterCycle: TimeInterval = 5
    private var currentRetryAttempt = 0
    private var connectionCancelled = false

    /// Currently active workspace (connected to agent)
    @Published var currentWorkspaceId: String?

    /// Show setup sheet
    @Published var showSetupSheet: Bool = false

    /// Show discovery sheet
    @Published var showDiscoverySheet: Bool = false

    /// Show manual add sheet
    @Published var showManualAddSheet: Bool = false

    /// Show removal confirmation sheet
    @Published var showRemovalSheet: Bool = false

    /// Workspace pending removal with its state
    @Published var removalInfo: WorkspaceRemovalInfo?

    /// Show session stop warning sheet (when other devices are viewing)
    @Published var showSessionStopSheet: Bool = false

    /// Session pending stop with viewer info
    @Published var sessionStopInfo: SessionStopInfo?

    /// Token expiry warning state
    @Published var showTokenExpiryWarning: Bool = false
    @Published var tokenTimeRemaining: TimeInterval = 0

    /// Codex start prompt sheet state
    @Published var showCodexStartPromptSheet: Bool = false
    @Published var codexStartPrompt: String = ""
    @Published var codexStartWorkspace: RemoteWorkspace?

    // MARK: - Dependencies

    private let managerService: WorkspaceManagerService
    private let managerStore: ManagerStore
    private let webSocketService: WebSocketServiceProtocol
    private let httpService: HTTPServiceProtocol
    private let sessionRepository: SessionRepository
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// Filtered workspaces based on search text
    var filteredWorkspaces: [RemoteWorkspace] {
        guard !searchText.isEmpty else { return workspaces }
        let query = searchText.lowercased()
        return workspaces.filter { workspace in
            workspace.name.lowercased().contains(query) ||
            workspace.path.lowercased().contains(query)
        }
    }

    /// Running workspaces count (workspaces with active sessions)
    var runningCount: Int {
        workspaces.filter { $0.hasActiveSession }.count
    }

    /// Has saved manager connection
    var hasSavedManager: Bool {
        managerStore.hasManager
    }

    /// Saved manager host
    var savedHost: String? {
        managerStore.lastHost
    }

    /// Check if connected to server (WebSocket is active)
    var isConnected: Bool {
        serverStatus.isConnected
    }

    /// Loading state for connecting
    @Published private(set) var isConnecting: Bool = false

    /// Whether initial connection check is complete
    /// Used to prevent "Not Connected" flash on appear
    @Published private(set) var hasCheckedConnection: Bool = false

    /// Ensures we auto-load workspaces once per connected lifecycle
    private var hasAutoLoadedForCurrentConnection = false

    // MARK: - Initialization

    init(
        managerService: WorkspaceManagerService? = nil,
        managerStore: ManagerStore? = nil,
        webSocketService: WebSocketServiceProtocol? = nil,
        httpService: HTTPServiceProtocol? = nil,
        sessionRepository: SessionRepository? = nil
    ) {
        self.managerService = managerService ?? .shared
        self.managerStore = managerStore ?? .shared
        self.webSocketService = webSocketService ?? DependencyContainer.shared.webSocketService
        self.httpService = httpService ?? DependencyContainer.shared.httpService
        self.sessionRepository = sessionRepository ?? DependencyContainer.shared.sessionRepository

        // Initialize currentWorkspaceId from the active workspace's remoteWorkspaceId
        // This ensures "Current" badge shows correctly when reopening the view
        self.currentWorkspaceId = WorkspaceStore.shared.activeWorkspace?.remoteWorkspaceId

        // Initialize serverStatus based on current WebSocket state
        if self.webSocketService.isConnected {
            self.serverStatus = .connected
            self.hasCheckedConnection = true
        } else if !self.managerStore.hasManager {
            self.serverStatus = .disconnected
            self.hasCheckedConnection = true
        } else {
            // Has saved manager but not connected - will try to connect
            self.serverStatus = .disconnected
            self.hasCheckedConnection = false
        }

        // Set up TokenManager with HTTPService for token refresh
        TokenManager.shared.setHTTPService(self.httpService)
        setupTokenManagerCallbacks()

        setupBindings()
        setupTokenExpiryWarning()
    }

    private func setupTokenManagerCallbacks() {
        // Handle token refresh success - update HTTP service auth token
        TokenManager.shared.onTokensRefreshed = { [weak self] tokenPair in
            Task { @MainActor in
                self?.httpService.authToken = tokenPair.accessToken
                AppLogger.log("[WorkspaceManager] Token refreshed, updated HTTP auth token")
            }
        }

        // Handle token refresh failure
        TokenManager.shared.onRefreshFailed = { [weak self] error in
            Task { @MainActor in
                AppLogger.log("[WorkspaceManager] Token refresh failed: \(error)", type: .error)
                if let appError = error as? AppError {
                    switch appError {
                    case .refreshTokenExpired, .tokenInvalid:
                        self?.handleRefreshTokenExpired()
                        return
                    case .httpRequestFailed(let statusCode, _):
                        if statusCode == 401 || statusCode == 403 {
                            self?.handleRefreshTokenExpired()
                            return
                        }
                    default:
                        break
                    }
                }
                AppLogger.log("[WorkspaceManager] Refresh failed but tokens may still be valid - will retry later", type: .warning)
            }
        }

        // Handle token expiring soon warning
        TokenManager.shared.onTokenExpiringSoon = { [weak self] timeRemaining in
            Task { @MainActor in
                self?.handleTokenExpiryWarning(timeRemaining: timeRemaining)
            }
        }

        TokenManager.shared.onPairingApprovalPending = { [weak self] requestID, _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isConnecting else { return }

                let currentAttempt = max(self.currentRetryAttempt, 1)
                self.serverStatus = .connecting(attempt: currentAttempt, maxAttempts: self.maxRetryAttempts)

                if let requestID, !requestID.isEmpty {
                    AppLogger.log("[WorkspaceManager] Pairing approval pending (request_id: \(requestID))")
                } else {
                    AppLogger.log("[WorkspaceManager] Pairing approval pending")
                }
            }
        }
    }

    private func handleRefreshTokenExpired() {
        // Refresh token expired - disconnect and prompt for re-pairing
        serverStatus = .disconnected
        webSocketService.disconnect()
        TokenManager.shared.clearTokens()

        // Show error to user
        self.error = .rpcError(code: 401, message: "Session expired. Please scan a new QR code.")
        self.showError = true

        // Show setup sheet for re-pairing
        showSetupSheet = true
    }

    /// Exchange pairing token for access/refresh token pair
    private func exchangePairingToken(_ pairingToken: String, host: String) async throws -> TokenPair {
        // Set up HTTP service with the correct base URL before exchange
        let normalizedHost = normalizeHostInput(host)
        let parts = splitHostPort(normalizedHost)
        let hostOnly = parts.host
        let port = parts.port
        let hostWithPort = port != nil ? "\(hostOnly):\(port!)" : hostOnly
        let isLocal = isLocalHost(hostOnly)
        let httpScheme = isLocal ? "http" : "https"
        let baseURL: URL
        if isLocal {
            let resolvedPort = port ?? ServerConnection.serverPort
            baseURL = URL(string: "\(httpScheme)://\(hostOnly):\(resolvedPort)")!
        } else {
            baseURL = URL(string: "\(httpScheme)://\(hostWithPort)")!
        }
        httpService.baseURL = baseURL

        // Exchange the pairing token
        let tokenPair = try await TokenManager.shared.exchangePairingToken(pairingToken, host: hostWithPort)

        // Update HTTP service with new access token
        httpService.authToken = tokenPair.accessToken

        return tokenPair
    }

    private struct PairingCodeRequest: Encodable {
        let code: String
    }

    private struct PairingCodeResponse: Decodable {
        let pairingToken: String

        enum CodingKeys: String, CodingKey {
            case pairingToken = "pairing_token"
        }
    }

    private func exchangePairingCode(_ code: String, host: String) async throws -> String {
        let normalizedHost = normalizeHostInput(host)
        let parts = splitHostPort(normalizedHost)
        let hostOnly = parts.host
        let port = parts.port
        let hostWithPort = port != nil ? "\(hostOnly):\(port!)" : hostOnly
        let isLocal = isLocalHost(hostOnly)
        let httpScheme = isLocal ? "http" : "https"
        let baseURL: URL
        if isLocal {
            let resolvedPort = port ?? ServerConnection.serverPort
            baseURL = URL(string: "\(httpScheme)://\(hostOnly):\(resolvedPort)")!
        } else {
            baseURL = URL(string: "\(httpScheme)://\(hostWithPort)")!
        }

        httpService.baseURL = baseURL
        let response: PairingCodeResponse = try await httpService.post(
            path: "api/pair/code",
            body: PairingCodeRequest(code: code)
        )
        return response.pairingToken
    }

    private func setupTokenExpiryWarning() {
        // Set up callback for token expiry warning
        // Note: Need to use concrete type since callback is set on WebSocketService
        if let wsService = webSocketService as? WebSocketService {
            wsService.onTokenExpiryWarning = { [weak self] timeRemaining in
                Task { @MainActor in
                    self?.handleTokenExpiryWarning(timeRemaining: timeRemaining)
                }
            }
        }
    }

    private func handleTokenExpiryWarning(timeRemaining: TimeInterval) {
        AppLogger.log("[WorkspaceManager] Token expiry warning - \(Int(timeRemaining))s remaining")
        self.tokenTimeRemaining = timeRemaining
        self.showTokenExpiryWarning = true
    }

    /// Dismiss token expiry warning (user acknowledged)
    func dismissTokenExpiryWarning() {
        showTokenExpiryWarning = false
    }

    private func setupBindings() {
        // Observe workspaces from service
        managerService.$workspaces
            .receive(on: DispatchQueue.main)
            .assign(to: &$workspaces)

        // Observe loading state
        managerService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        // Observe unreachable workspace IDs from service
        managerService.$unreachableWorkspaceIds
            .receive(on: DispatchQueue.main)
            .assign(to: &$unreachableWorkspaceIds)

        // Observe errors
        managerService.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.error = error
                    self?.showError = true
                }
            }
            .store(in: &cancellables)

        // Observe WebSocket connection state to sync serverStatus
        // This handles cases where AppState connects directly bypassing the ViewModel
        Task { [weak self] in
            guard let self = self else { return }
            for await state in self.webSocketService.connectionStateStream {
                await MainActor.run {
                    switch state {
                    case .connected:
                        // Only update if we're not already connected (avoid flickering)
                        if self.serverStatus != .connected {
                            self.serverStatus = .connected
                            self.isConnecting = false
                            self.hasCheckedConnection = true
                            AppLogger.log("[WorkspaceManager] Connection state synced: connected")
                        }

                        // Connection became ready - load workspace list once
                        if !self.hasAutoLoadedForCurrentConnection {
                            self.hasAutoLoadedForCurrentConnection = true
                            Task { [weak self] in
                                await self?.refreshWorkspacesAfterConnection()
                            }
                        }
                    case .disconnected:
                        self.hasAutoLoadedForCurrentConnection = false
                        // Only update if we were connected and not in a retry loop
                        if self.serverStatus == .connected {
                            self.serverStatus = .disconnected
                            AppLogger.log("[WorkspaceManager] Connection state synced: disconnected")
                        }
                    case .connecting:
                        // Don't override detailed connecting status from our own retry loop
                        break
                    case .reconnecting(let attempt):
                        // Update UI to show reconnection progress (WebSocket auto-reconnect)
                        // Only if ViewModel is not running its own retry loop
                        if !self.isConnecting {
                            self.serverStatus = .connecting(attempt: attempt, maxAttempts: Constants.Network.maxReconnectAttempts)
                            AppLogger.log("[WorkspaceManager] Connection state synced: reconnecting (\(attempt))")
                        }
                    case .failed(let reason):
                        self.hasAutoLoadedForCurrentConnection = false
                        // Only update to failed state if ViewModel is not running its own retry loop
                        // ViewModel's connectWithRetry handles its own state transitions
                        if !self.isConnecting {
                            self.serverStatus = .unreachable(lastError: reason)
                            AppLogger.log("[WorkspaceManager] Connection state synced: failed - \(reason)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Connection

    /// Connect to saved manager host
    /// In single-port architecture, this just saves the host and refreshes workspaces
    func connectToSavedManager() async {
        guard let host = managerStore.lastHost else {
            isConnecting = false
            hasCheckedConnection = true
            serverStatus = .disconnected
            showSetupSheet = true
            return
        }

        // Use saved token if available
        await connectWithRetry(to: host, token: managerStore.lastToken)
    }

    /// Connect to server with automatic retry
    /// Shows progress in serverStatus
    func connectWithRetry(to host: String, token: String? = nil) async {
        let normalizedHost = normalizeHostInput(host)
        guard !normalizedHost.isEmpty else {
            self.error = .rpcError(code: -1, message: "Please enter a valid IP address or hostname")
            self.showError = true
            return
        }

        // Prevent duplicate retry loops.
        if isConnecting {
            AppLogger.log("[WorkspaceManager] Skipping connect - retry loop already active")
            return
        }

        // Skip if already connected (prevents duplicate connections from AppState + WorkspaceManagerView race)
        if webSocketService.isConnected {
            AppLogger.log("[WorkspaceManager] Skipping connect - already connected")
            serverStatus = .connected
            isConnecting = false
            hasCheckedConnection = true
            await refreshWorkspaces()
            return
        }

        // Reset cancellation flag
        connectionCancelled = false
        currentRetryAttempt = 0

        isConnecting = true
        hasCheckedConnection = true  // Mark as checked immediately so UI doesn't show initial loading
        serverStatus = .connecting(attempt: 1, maxAttempts: maxRetryAttempts)

        // Tell WebSocket we're managing our own retry loop (prevents .failed state flickering)
        webSocketService.isExternalRetryInProgress = true
        defer {
            webSocketService.isExternalRetryInProgress = false
            if connectionCancelled {
                currentRetryAttempt = 0
            }
            isConnecting = false
        }

        // Save host early so UI can show it (do not persist pairing token)
        managerStore.saveHost(normalizedHost, token: nil)
        managerService.setCurrentHost(normalizedHost)

        // Resolve access token (pairing -> exchange, or stored)
        var fallbackAccessToken: String? = nil
        if let providedToken = token {
            if TokenType.from(token: providedToken) == .pairing {
                AppLogger.log("[WorkspaceManager] Detected pairing token, exchanging for access/refresh pair")
                do {
                    let tokenPair = try await exchangePairingToken(providedToken, host: normalizedHost)
                    fallbackAccessToken = tokenPair.accessToken
                    AppLogger.log("[WorkspaceManager] Token exchange successful, access token expires: \(tokenPair.accessTokenExpiresAt)")
                } catch {
                    AppLogger.log("[WorkspaceManager] Token exchange failed: \(error)", type: .error)
                    let (code, message) = Self.rpcErrorInfo(from: error)
                    self.error = .rpcError(code: code, message: message)
                    self.showError = true
                    self.serverStatus = .unreachable(lastError: message)
                    return
                }
            } else {
                fallbackAccessToken = providedToken
            }
        }

        // Retry loop persists until success or explicit cancellation.
        while !connectionCancelled && !Task.isCancelled {
            currentRetryAttempt += 1
            if currentRetryAttempt > maxRetryAttempts {
                AppLogger.log(
                    "[WorkspaceManager] Retry cycle exhausted (\(maxRetryAttempts) attempts), continuing after \(Int(retryCooldownAfterCycle))s cooldown",
                    type: .warning
                )
                currentRetryAttempt = 1
                await waitForRetry(seconds: retryCooldownAfterCycle)
                if connectionCancelled || Task.isCancelled { break }
            }

            serverStatus = .connecting(attempt: currentRetryAttempt, maxAttempts: maxRetryAttempts)
            AppLogger.log("[WorkspaceManager] Connection attempt \(currentRetryAttempt)/\(maxRetryAttempts) to \(normalizedHost)")

            let accessToken = await resolveAccessTokenForReconnect(host: normalizedHost, fallbackToken: fallbackAccessToken)
            if accessToken != fallbackAccessToken {
                fallbackAccessToken = accessToken
            }
            if let accessToken {
                managerStore.saveHost(normalizedHost, token: accessToken)
            }

            let connectionInfo = buildConnectionInfo(for: normalizedHost, token: accessToken)
            httpService.baseURL = connectionInfo.httpURL
            httpService.authToken = accessToken

            do {
                try await webSocketService.connect(to: connectionInfo)
                // Success!
                serverStatus = .connected
                currentRetryAttempt = 0
                if !hasAutoLoadedForCurrentConnection {
                    hasAutoLoadedForCurrentConnection = true
                    await refreshWorkspacesAfterConnection()
                }
                Haptics.success()
                AppLogger.log("[WorkspaceManager] Connected successfully to \(normalizedHost)")
                return
            } catch {
                AppLogger.log("[WorkspaceManager] Connection attempt \(currentRetryAttempt) failed: \(error.localizedDescription)")

                // Check if cancelled
                if connectionCancelled {
                    AppLogger.log("[WorkspaceManager] Connection cancelled by user")
                    return
                }

                if Self.shouldStopRetryLoop(for: error) {
                    let (code, message) = Self.rpcErrorInfo(from: error)
                    self.error = .rpcError(code: code, message: message)
                    self.showError = true
                    self.serverStatus = .unreachable(lastError: message)
                    connectionCancelled = true
                    return
                }

                // If not last attempt, wait before retry
                if currentRetryAttempt < maxRetryAttempts {
                    await waitForRetry(seconds: 2)
                }
            }
        }
    }

    /// Single connection attempt (for manual retry)
    func connect(to host: String, token: String? = nil, pairingCode: String? = nil) async {
        let normalizedHost = normalizeHostInput(host)
        guard !normalizedHost.isEmpty else {
            self.error = .rpcError(code: -1, message: "Please enter a valid IP address or hostname")
            self.showError = true
            return
        }

        if isConnecting {
            AppLogger.log("[WorkspaceManager] Cancelling active retry loop for new connection request")
            connectionCancelled = true
            currentRetryAttempt = 0
            await webSocketService.disconnect()

            let waitDeadline = Date().addingTimeInterval(3)
            while isConnecting && Date() < waitDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            if isConnecting {
                AppLogger.log("[WorkspaceManager] Retry loop did not stop before new connection request", type: .warning)
                self.error = .rpcError(code: -1, message: "Previous connection is still shutting down. Please try again.")
                self.showError = true
                return
            }
        }

        var resolvedToken = token
        let trimmedCode = pairingCode?.trimmingCharacters(in: .whitespacesAndNewlines)

        if resolvedToken == nil {
            do {
                let pairingInfo = try await fetchPairingInfo(for: normalizedHost)
                let authRequired = pairingInfo.authRequired ?? false

                if authRequired {
                    guard let code = trimmedCode, !code.isEmpty else {
                        self.error = .rpcError(code: 401, message: "Pairing code required. Open /pair on your computer and enter the code.")
                        self.showError = true
                        self.serverStatus = .unreachable(lastError: "Pairing code required")
                        return
                    }

                    let pairingToken = try await exchangePairingCode(code, host: normalizedHost)
                    let tokenPair = try await exchangePairingToken(pairingToken, host: normalizedHost)
                    resolvedToken = tokenPair.accessToken
                } else if let tokenFromInfo = pairingInfo.token {
                    if let expiresAt = pairingInfo.tokenExpiresAt, Date() > expiresAt {
                        self.error = .rpcError(code: 401, message: "Pairing token expired. Please refresh the QR code on your computer.")
                        self.showError = true
                        self.serverStatus = .unreachable(lastError: "Pairing token expired")
                        return
                    }
                    let tokenPair = try await exchangePairingToken(tokenFromInfo, host: normalizedHost)
                    resolvedToken = tokenPair.accessToken
                }
            } catch {
                let (code, message) = Self.rpcErrorInfo(from: error)
                self.error = .rpcError(code: code, message: message)
                self.showError = true
                self.serverStatus = .unreachable(lastError: message)
                return
            }
        }

        await connectWithRetry(to: normalizedHost, token: resolvedToken)
    }

    /// Retry connection to current saved host
    func retryConnection() async {
        guard let host = managerStore.lastHost else {
            showSetupSheet = true
            return
        }
        // Use saved token if available
        await connectWithRetry(to: host, token: managerStore.lastToken)
    }

    /// Cancel ongoing connection attempts
    func cancelConnection() {
        connectionCancelled = true
        currentRetryAttempt = 0
        isConnecting = false
        if !webSocketService.isConnected {
            serverStatus = .disconnected
        }
        AppLogger.log("[WorkspaceManager] Connection cancelled by user")
    }

    /// Build connection info for a host
    private func buildConnectionInfo(for host: String, token: String? = nil) -> ConnectionInfo {
        let parts = splitHostPort(host)
        let hostOnly = parts.host
        let port = parts.port
        let hostWithPort = port != nil ? "\(hostOnly):\(port!)" : hostOnly
        let isLocal = isLocalHost(hostOnly)
        let wsScheme = isLocal ? "ws" : "wss"
        let httpScheme = isLocal ? "http" : "https"

        let wsURL: URL
        let httpURL: URL

        if isLocal {
            let resolvedPort = port ?? ServerConnection.serverPort
            wsURL = URL(string: "\(wsScheme)://\(hostOnly):\(resolvedPort)/ws")!
            httpURL = URL(string: "\(httpScheme)://\(hostOnly):\(resolvedPort)")!
        } else {
            wsURL = URL(string: "\(wsScheme)://\(hostWithPort)/ws")!
            httpURL = URL(string: "\(httpScheme)://\(hostWithPort)")!
        }

        AppLogger.log("[WorkspaceManager] Building ConnectionInfo with token: \(token != nil ? "present" : "none")")

        return ConnectionInfo(
            webSocketURL: wsURL,
            httpURL: httpURL,
            sessionId: "",
            repoName: "Workspaces",
            token: token  // Include access token for auth
        )
    }

    private static func rpcErrorInfo(from error: Error) -> (Int, String) {
        if let appError = error as? AppError {
            switch appError {
            case .pairingApprovalPending(let requestID, _):
                if let requestID, !requestID.isEmpty {
                    return (202, "Waiting for host approval (\(requestID))")
                }
                return (202, "Waiting for host approval")
            case .pairingFailed(let reason):
                return (403, reason)
            case .httpRequestFailed(let statusCode, let message):
                return (statusCode, message ?? appError.localizedDescription)
            case .tokenInvalid, .tokenExpired, .refreshTokenExpired:
                return (401, appError.localizedDescription)
            case .authorizationFailed(let statusCode):
                return (statusCode, appError.localizedDescription)
            default:
                return (-1, appError.localizedDescription)
            }
        }
        return (-1, error.localizedDescription)
    }

    private func resolveAccessTokenForReconnect(host: String, fallbackToken: String?) async -> String? {
        if let storedHost = TokenManager.shared.getStoredHost(),
           storedHost == host,
           let refreshedToken = await TokenManager.shared.getValidAccessToken() {
            if refreshedToken != fallbackToken {
                AppLogger.log("[WorkspaceManager] Using refreshed access token for host: \(host)")
            }
            return refreshedToken
        }
        return fallbackToken
    }

    private func waitForRetry(seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let intervalNs: UInt64 = 100_000_000 // 100ms
        let iterations = Int((seconds * 1_000_000_000) / Double(intervalNs))
        for _ in 0..<max(iterations, 1) {
            if connectionCancelled || Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: intervalNs)
        }
    }

    private static func shouldStopRetryLoop(for error: Error) -> Bool {
        if let appError = error as? AppError {
            switch appError {
            case .tokenInvalid, .tokenExpired, .refreshTokenExpired:
                return true
            case .authorizationFailed(let statusCode):
                return statusCode == 401 || statusCode == 403
            case .httpRequestFailed(let statusCode, _):
                return statusCode == 401 || statusCode == 403
            default:
                break
            }
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("authentication failed")
            || message.contains("unauthorized")
            || message.contains("forbidden")
    }

    private struct HostParts {
        let host: String
        let port: Int?
    }

    private func normalizeHostInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var host = trimmed
        let schemes = ["https://", "http://", "wss://", "ws://", "cdev-manager://"]
        for scheme in schemes where host.hasPrefix(scheme) {
            host = String(host.dropFirst(scheme.count))
            break
        }

        if let slashIndex = host.firstIndex(of: "/") {
            host = String(host[..<slashIndex])
        }

        return host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitHostPort(_ host: String) -> HostParts {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colonIndex = trimmed.lastIndex(of: ":") else {
            return HostParts(host: trimmed, port: nil)
        }

        let portPart = trimmed[trimmed.index(after: colonIndex)...]
        if let port = Int(portPart), port > 0 && port <= 65535 {
            let hostOnly = String(trimmed[..<colonIndex])
            if !hostOnly.isEmpty {
                return HostParts(host: hostOnly, port: port)
            }
        }

        return HostParts(host: trimmed, port: nil)
    }

    private func fetchPairingInfo(for host: String) async throws -> ConnectionInfo {
        let parts = splitHostPort(host)
        let hostOnly = parts.host
        let port = parts.port
        let hostWithPort = port != nil ? "\(hostOnly):\(port!)" : hostOnly
        let isLocal = isLocalHost(hostOnly)
        let httpScheme = isLocal ? "http" : "https"

        let baseURL: URL
        if isLocal {
            let resolvedPort = port ?? ServerConnection.serverPort
            baseURL = URL(string: "\(httpScheme)://\(hostOnly):\(resolvedPort)")!
        } else {
            baseURL = URL(string: "\(httpScheme)://\(hostWithPort)")!
        }

        AppLogger.log("[WorkspaceManager] Fetching pairing info from \(baseURL.absoluteString)")
        httpService.baseURL = baseURL
        let info: ConnectionInfo = try await httpService.get(path: "api/pair/info", queryItems: nil)
        return info
    }

    /// Check if host is a local network address
    private func isLocalHost(_ host: String) -> Bool {
        let hostOnly = splitHostPort(host).host
        if hostOnly == "localhost" || hostOnly == "127.0.0.1" {
            return true
        }
        // IP address pattern
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        if let regex = try? NSRegularExpression(pattern: ipPattern),
           regex.firstMatch(in: hostOnly, range: NSRange(hostOnly.startIndex..., in: hostOnly)) != nil {
            return true
        }
        // .local domains (Bonjour)
        if hostOnly.hasSuffix(".local") {
            return true
        }
        return false
    }

    // MARK: - Workspace Operations

    /// Refresh workspace list
    func refreshWorkspaces() async {
        do {
            _ = try await managerService.listWorkspaces()
        } catch let error as WorkspaceManagerError {
            self.error = error
            self.showError = true
        } catch {
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
        }
    }

    /// Refresh workspace list with short retries after a new connection is established.
    /// This handles startup races where the socket is up but RPC requests are briefly unavailable.
    private func refreshWorkspacesAfterConnection() async {
        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            guard webSocketService.isConnected else { return }

            do {
                _ = try await managerService.listWorkspaces()
                return
            } catch {
                let isLastAttempt = attempt == maxAttempts
                if isLastAttempt {
                    if let managerError = error as? WorkspaceManagerError {
                        self.error = managerError
                    } else {
                        self.error = .rpcError(code: -1, message: error.localizedDescription)
                    }
                    self.showError = true
                    AppLogger.log("[WorkspaceManager] Workspace refresh failed after connect: \(error.localizedDescription)", type: .error)
                    return
                }

                AppLogger.log("[WorkspaceManager] Workspace refresh retry \(attempt + 1)/\(maxAttempts) after connect", type: .warning)
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    /// Start a session for a workspace
    func startWorkspace(_ workspace: RemoteWorkspace) async {
        // Debounce: Prevent multiple rapid taps
        guard loadingWorkspaceId == nil else {
            AppLogger.log("[WorkspaceManager] Ignoring start - already loading workspace: \(loadingWorkspaceId ?? "unknown")")
            return
        }

        let runtime = resolveRuntime(for: workspace)
        if runtime == .codex {
            codexStartWorkspace = workspace
            codexStartPrompt = ""
            showCodexStartPromptSheet = true
            return
        }

        loadingWorkspaceId = workspace.id
        currentOperation = .starting
        defer {
            loadingWorkspaceId = nil
            currentOperation = nil
        }

        do {
            // Start a new session for this workspace
            _ = try await managerService.startSession(workspaceId: workspace.id, runtime: runtime)
            Haptics.success()
        } catch let error as WorkspaceManagerError {
            self.error = error
            self.showError = true
            Haptics.error()
        } catch {
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
            Haptics.error()
        }
    }

    func startCodexWorkspaceWithPrompt() async {
        guard let workspace = codexStartWorkspace else { return }
        let prompt = codexStartPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            self.error = .rpcError(code: -1, message: "Enter a prompt to start a Codex session.")
            self.showError = true
            return
        }

        loadingWorkspaceId = workspace.id
        currentOperation = .starting
        defer {
            loadingWorkspaceId = nil
            currentOperation = nil
        }

        do {
            try await managerService.sendPrompt(
                sessionId: nil,
                workspaceId: workspace.id,
                prompt: prompt,
                mode: "new",
                runtime: .codex
            )
            showCodexStartPromptSheet = false
            codexStartPrompt = ""
            codexStartWorkspace = nil
            Haptics.success()
            await refreshWorkspaces()
        } catch let error as WorkspaceManagerError {
            self.error = error
            self.showError = true
            Haptics.error()
        } catch {
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
            Haptics.error()
        }
    }

    /// Prepare to stop sessions for a workspace - checks for other viewers first
    /// Shows warning if other devices are viewing the session
    func prepareStopWorkspace(_ workspace: RemoteWorkspace) async {
        // Debounce: Prevent multiple rapid taps
        guard loadingWorkspaceId == nil else {
            AppLogger.log("[WorkspaceManager] Ignoring stop prep - already loading workspace: \(loadingWorkspaceId ?? "unknown")")
            return
        }

        loadingWorkspaceId = workspace.id
        currentOperation = .stopping

        // Check for other viewers across all running sessions
        let myClientId = webSocketService.clientId
        var hasOtherViewers = false
        var totalOtherViewerCount = 0
        var otherViewerIds: [String] = []

        for session in workspace.sessions where session.status == .running {
            if let viewers = session.viewers {
                for viewerId in viewers where viewerId != myClientId {
                    hasOtherViewers = true
                    totalOtherViewerCount += 1
                    if !otherViewerIds.contains(viewerId) {
                        otherViewerIds.append(viewerId)
                    }
                }
            }
        }

        loadingWorkspaceId = nil
        currentOperation = nil

        if hasOtherViewers {
            // Show warning dialog
            sessionStopInfo = SessionStopInfo(
                workspace: workspace,
                otherViewerCount: totalOtherViewerCount,
                otherViewerIds: otherViewerIds
            )
            showSessionStopSheet = true
            AppLogger.log("[WorkspaceManager] Stop requested for workspace with \(totalOtherViewerCount) other viewer(s)")
        } else {
            // No other viewers - stop directly
            await stopWorkspaceConfirmed(workspace)
        }
    }

    /// Stop all sessions for a workspace (confirmed action)
    /// Called directly when no other viewers, or after user confirms warning
    func stopWorkspaceConfirmed(_ workspace: RemoteWorkspace) async {
        // Debounce: Prevent multiple rapid taps
        guard loadingWorkspaceId == nil else {
            AppLogger.log("[WorkspaceManager] Ignoring stop - already loading workspace: \(loadingWorkspaceId ?? "unknown")")
            return
        }

        loadingWorkspaceId = workspace.id
        currentOperation = .stopping
        defer {
            loadingWorkspaceId = nil
            currentOperation = nil
        }

        do {
            // Stop all active sessions for this workspace
            for session in workspace.sessions where session.status == .running {
                try await managerService.stopSession(sessionId: session.id, runtime: session.runtime)
            }
            // Also clear unreachable status when stopped
            managerService.clearUnreachableStatus(workspace.id)
            Haptics.light()
        } catch let error as WorkspaceManagerError {
            self.error = error
            self.showError = true
            Haptics.error()
        } catch {
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
            Haptics.error()
        }
    }

    /// Legacy stop method - now checks for viewers first
    func stopWorkspace(_ workspace: RemoteWorkspace) async {
        await prepareStopWorkspace(workspace)
    }

    /// Confirm stop after warning (user acknowledged other viewers)
    func confirmStopSession() async {
        guard let info = sessionStopInfo else { return }
        showSessionStopSheet = false
        sessionStopInfo = nil
        await stopWorkspaceConfirmed(info.workspace)
    }

    /// Cancel stop session flow
    func cancelStopSession() {
        showSessionStopSheet = false
        sessionStopInfo = nil
    }

    /// Connect to a workspace (start session if needed, then switch to it)
    func connectToWorkspace(_ workspace: RemoteWorkspace) async -> RemoteWorkspace? {
        AppLogger.log("[WorkspaceManagerVM] connectToWorkspace called for: \(workspace.name), hasActiveSession: \(workspace.hasActiveSession)")

        // Debounce: Prevent multiple rapid taps from creating multiple sessions
        guard loadingWorkspaceId == nil else {
            AppLogger.log("[WorkspaceManagerVM] Ignoring connect - already loading workspace: \(loadingWorkspaceId ?? "unknown")")
            return nil
        }

        loadingWorkspaceId = workspace.id
        currentOperation = .connecting
        defer {
            AppLogger.log("[WorkspaceManagerVM] connectToWorkspace defer - clearing loadingWorkspaceId")
            loadingWorkspaceId = nil
            currentOperation = nil
        }

        do {
            // If already has active session, just return directly - no need to refresh
            if workspace.hasActiveSession {
                AppLogger.log("[WorkspaceManagerVM] Workspace already has active session - returning directly")
                currentWorkspaceId = workspace.id
                Haptics.success()
                return workspace
            }

            // Start new session
            AppLogger.log("[WorkspaceManagerVM] Starting new session for workspace")
            currentOperation = .starting
            let runtime = resolveRuntime(for: workspace)
            _ = try await managerService.startSession(workspaceId: workspace.id, runtime: runtime)
            AppLogger.log("[WorkspaceManagerVM] Session started")

            // Refresh to get updated workspace with sessions (only after starting)
            AppLogger.log("[WorkspaceManagerVM] Refreshing workspace list")
            _ = try await managerService.listWorkspaces()

            // Find the updated workspace
            guard let updatedWorkspace = workspaces.first(where: { $0.id == workspace.id }) else {
                AppLogger.log("[WorkspaceManagerVM] ERROR: Workspace not found after refresh")
                self.error = .workspaceFailed(workspace.id)
                self.showError = true
                Haptics.error()
                return nil
            }

            AppLogger.log("[WorkspaceManagerVM] SUCCESS: Returning workspace \(updatedWorkspace.name)")
            currentOperation = .connecting
            currentWorkspaceId = updatedWorkspace.id
            Haptics.success()
            return updatedWorkspace
        } catch let error as WorkspaceManagerError {
            AppLogger.log("[WorkspaceManagerVM] ERROR (WorkspaceManagerError): \(error)")
            self.error = error
            self.showError = true
            Haptics.error()
            // Refresh to get actual status from manager
            await refreshWorkspaces()
            return nil
        } catch {
            AppLogger.log("[WorkspaceManagerVM] ERROR (generic): \(error)")
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
            Haptics.error()
            // Refresh to get actual status from manager
            await refreshWorkspaces()
            return nil
        }
    }

    private func resolveRuntime(for workspace: RemoteWorkspace) -> AgentRuntime {
        let storedRuntime = sessionRepository.selectedSessionRuntime
        let workspaceRuntime = workspace.activeRuntime
        let preferredRuntime = workspaceRuntime ?? storedRuntime

        let runtime: AgentRuntime
        if RuntimeCapabilityRegistryStore.shared.isSupported(preferredRuntime) {
            runtime = preferredRuntime
        } else {
            runtime = RuntimeCapabilityRegistryStore.shared.defaultRuntime()
            AppLogger.log(
                "[WorkspaceManagerVM] Runtime fallback for workspace \(workspace.id): \(preferredRuntime.rawValue) -> \(runtime.rawValue)",
                type: .warning
            )
        }

        if sessionRepository.selectedSessionRuntime != runtime {
            sessionRepository.selectedSessionRuntime = runtime
        }
        return runtime
    }

    /// Called when connection to a workspace agent fails
    /// Marks workspace as unreachable and refreshes status from manager
    func handleConnectionFailure(workspaceId: String) async {
        if currentWorkspaceId == workspaceId {
            currentWorkspaceId = nil
        }
        // Mark as unreachable via service - shows "Unreachable" instead of "Active"
        managerService.markWorkspaceUnreachable(workspaceId)
        // Refresh workspace list to get actual status
        await refreshWorkspaces()
    }

    /// Check if a workspace is marked as unreachable
    func isWorkspaceUnreachable(_ workspace: RemoteWorkspace) -> Bool {
        managerService.isWorkspaceUnreachable(workspace.id)
    }

    /// Clear unreachable status for a workspace (called when successfully connected or restarted)
    func clearUnreachableStatus(_ workspaceId: String) {
        managerService.clearUnreachableStatus(workspaceId)
    }

    /// Check if a workspace is currently loading
    func isWorkspaceLoading(_ workspace: RemoteWorkspace) -> Bool {
        loadingWorkspaceId == workspace.id
    }

    /// Get the operation type for a loading workspace
    func operationFor(_ workspace: RemoteWorkspace) -> WorkspaceOperation? {
        guard loadingWorkspaceId == workspace.id else { return nil }
        return currentOperation
    }

    /// Start and connect to workspace (convenience)
    func startAndConnect(_ workspace: RemoteWorkspace) async -> RemoteWorkspace? {
        return await connectToWorkspace(workspace)
    }

    // MARK: - Manual Workspace Add

    /// Add a workspace manually by path
    /// Used as an alternative to Discovery Repos when user knows exact path
    /// - Parameters:
    ///   - path: Absolute path to the folder/repository
    ///   - createIfMissing: If true, creates the directory if it doesn't exist
    /// - Returns: The created workspace with git state for further setup
    @discardableResult
    func addWorkspaceManually(path: String, createIfMissing: Bool = true) async throws -> RemoteWorkspace {
        let workspace = try await managerService.addWorkspace(path: path, createIfMissing: createIfMissing)
        AppLogger.log("[WorkspaceManager] Manually added workspace: \(workspace.name), isGitRepo: \(workspace.isGitRepo ?? false), gitState: \(workspace.gitState ?? "unknown")")
        return workspace
    }

    // MARK: - Remove Workspace (Multi-Device Aware)

    /// Prepare workspace removal - checks state and shows appropriate UI
    /// Called when user initiates removal (swipe action or menu)
    func prepareWorkspaceRemoval(_ workspace: RemoteWorkspace) async {
        // Debounce: Prevent multiple rapid taps
        guard loadingWorkspaceId == nil else {
            AppLogger.log("[WorkspaceManager] Ignoring removal prep - already loading workspace: \(loadingWorkspaceId ?? "unknown")")
            return
        }

        loadingWorkspaceId = workspace.id
        currentOperation = .removing

        do {
            // Get removal info with viewer data
            let info = try await managerService.getWorkspaceRemovalInfo(
                workspace: workspace,
                myClientId: webSocketService.clientId
            )

            loadingWorkspaceId = nil
            currentOperation = nil

            // Decision tree based on state
            if info.hasActiveSession {
                // Session running - must stop first
                removalInfo = info
                showRemovalSheet = true
            } else if info.hasOtherViewers {
                // Other viewers - show options (Leave Only / Remove Anyway / Cancel)
                removalInfo = info
                showRemovalSheet = true
            } else {
                // No conflicts - remove directly with simple confirmation
                removalInfo = info
                showRemovalSheet = true
            }

        } catch {
            loadingWorkspaceId = nil
            currentOperation = nil

            // If we can't get status, fall back to simple removal flow
            AppLogger.log("[WorkspaceManager] Failed to get removal info, using fallback: \(error.localizedDescription)", type: .warning)
            removalInfo = WorkspaceRemovalInfo(
                workspace: workspace,
                hasActiveSession: workspace.hasActiveSession,
                activeSessionId: workspace.activeSession?.id,
                hasOtherViewers: false,
                viewerCount: 0,
                otherViewerIds: []
            )
            showRemovalSheet = true
        }
    }

    /// Stop running session, then auto-proceed with workspace removal
    func stopSessionThenRemove() async {
        guard let info = removalInfo, let sessionId = info.activeSessionId else {
            AppLogger.log("[WorkspaceManager] No session to stop", type: .warning)
            return
        }

        showRemovalSheet = false
        loadingWorkspaceId = info.workspace.id
        currentOperation = .stopping

        do {
            // Step 1: Stop the session
            let runtime = runtimeForSession(sessionId: sessionId, in: info.workspace)
            try await managerService.stopSession(sessionId: sessionId, runtime: runtime)
            AppLogger.log("[WorkspaceManager] Session stopped, proceeding with removal")

            // Wait briefly for session to fully stop
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

            // Step 2: Auto-proceed with workspace removal
            currentOperation = .removing
            try await managerService.removeWorkspace(info.workspace.id)

            // Clear from current if it was selected
            if currentWorkspaceId == info.workspace.id {
                currentWorkspaceId = nil
            }

            // Clear unreachable status
            managerService.clearUnreachableStatus(info.workspace.id)

            loadingWorkspaceId = nil
            currentOperation = nil
            removalInfo = nil

            AppLogger.log("[WorkspaceManager] Workspace removed after stopping session: \(info.workspace.name)")
            Haptics.success()

        } catch {
            loadingWorkspaceId = nil
            currentOperation = nil
            self.error = .rpcError(code: -1, message: "Failed to stop session and remove: \(error.localizedDescription)")
            self.showError = true
            Haptics.error()
        }
    }

    /// Leave workspace without removing it (for multi-device scenarios)
    /// Unsubscribes from events and removes from local UI only
    func leaveWorkspaceOnly() async {
        guard let info = removalInfo else { return }

        showRemovalSheet = false
        loadingWorkspaceId = info.workspace.id
        currentOperation = .removing

        do {
            try await managerService.leaveWorkspace(info.workspace.id)

            // Clear from current if it was selected
            if currentWorkspaceId == info.workspace.id {
                currentWorkspaceId = nil
            }

            loadingWorkspaceId = nil
            currentOperation = nil
            removalInfo = nil

            AppLogger.log("[WorkspaceManager] Left workspace (local only): \(info.workspace.name)")
            Haptics.success()

        } catch {
            loadingWorkspaceId = nil
            currentOperation = nil
            self.error = .rpcError(code: -1, message: "Failed to leave workspace: \(error.localizedDescription)")
            self.showError = true
            Haptics.error()
        }
    }

    /// Remove workspace for everyone (force remove)
    func removeWorkspaceForEveryone() async {
        guard let info = removalInfo else { return }

        showRemovalSheet = false
        loadingWorkspaceId = info.workspace.id
        currentOperation = .removing

        do {
            // Stop all sessions first if any are running
            if info.hasActiveSession, let sessionId = info.activeSessionId {
                let runtime = runtimeForSession(sessionId: sessionId, in: info.workspace)
                try await managerService.stopSession(sessionId: sessionId, runtime: runtime)
            }

            // Remove workspace from manager (server broadcasts to all clients)
            try await managerService.removeWorkspace(info.workspace.id)

            // Clear from current if it was selected
            if currentWorkspaceId == info.workspace.id {
                currentWorkspaceId = nil
            }

            // Clear unreachable status
            managerService.clearUnreachableStatus(info.workspace.id)

            loadingWorkspaceId = nil
            currentOperation = nil
            removalInfo = nil

            AppLogger.log("[WorkspaceManager] Removed workspace for everyone: \(info.workspace.name)")
            Haptics.success()

        } catch {
            loadingWorkspaceId = nil
            currentOperation = nil
            self.error = .rpcError(code: -1, message: "Failed to remove workspace: \(error.localizedDescription)")
            self.showError = true
            Haptics.error()
        }
    }

    /// Cancel removal flow
    func cancelRemoval() {
        showRemovalSheet = false
        removalInfo = nil
        loadingWorkspaceId = nil
        currentOperation = nil
    }

    private func runtimeForSession(sessionId: String, in workspace: RemoteWorkspace) -> AgentRuntime {
        workspace.sessions.first(where: { $0.id == sessionId })?.runtime
        ?? workspace.activeRuntime
        ?? sessionRepository.selectedSessionRuntime
    }

    /// Legacy removal method - now redirects to new multi-device aware flow
    func removeWorkspace(_ workspace: RemoteWorkspace) async {
        await prepareWorkspaceRemoval(workspace)
    }

    // MARK: - Setup

    /// Clear saved manager, disconnect, and show setup
    /// Use this when no onDisconnect callback is available (e.g., root view)
    func resetManager() {
        AppLogger.log("[WorkspaceManager] Resetting manager - disconnecting WebSocket")

        Task {
            await TokenManager.shared.revokeStoredRefreshToken()
        }

        // Disconnect WebSocket first
        webSocketService.disconnect()

        // Reset local state
        resetManagerState()
    }

    /// Reset local manager state without disconnecting WebSocket
    /// Use this after calling onDisconnect callback to clean up manager state
    func resetManagerState() {
        AppLogger.log("[WorkspaceManager] Resetting manager state")

        // Clear workspace store
        WorkspaceStore.shared.clearActive()

        // Reset manager state
        managerStore.clear()
        managerService.reset()

        // Update status
        serverStatus = .disconnected
        hasAutoLoadedForCurrentConnection = false
        currentWorkspaceId = nil

        // Show setup sheet
        showSetupSheet = true
    }

    /// Mark connection check as complete (used when connection failed previously)
    func markConnectionChecked() {
        hasCheckedConnection = true
    }
}

// MARK: - Preview Helpers

extension WorkspaceManagerViewModel {
    /// Create a preview instance with mock data
    static var preview: WorkspaceManagerViewModel {
        let vm = WorkspaceManagerViewModel()
        // Note: Can't easily mock the service, but previews can use real service
        return vm
    }
}
