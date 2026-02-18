import Foundation
import Combine

/// Global app state - manages connection and creates view models
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected
    @Published private(set) var hasWorkspaces: Bool = false

    // MARK: - App Lifecycle State

    /// Tracks if disconnection is expected (app going to background)
    /// When true, we don't navigate away from Dashboard on disconnect
    @Published private(set) var isExpectedDisconnection: Bool = false

    /// Tracks if user explicitly disconnected (vs background/network issues)
    @Published private(set) var wasExplicitDisconnect: Bool = false

    // MARK: - Cached ViewModels (prevents recreation on state changes)

    private var _dashboardViewModel: DashboardViewModel?
    private var _pairingViewModel: PairingViewModel?

    // MARK: - QR Scan Debouncing (persists across PairingViewModel instances)

    var lastScannedCode: String?
    var lastScanTime: Date?
    let scanDebounceInterval: TimeInterval = 3.0

    func shouldProcessScan(code: String) -> Bool {
        if let lastCode = lastScannedCode,
           let lastTime = lastScanTime,
           lastCode == code,
           Date().timeIntervalSince(lastTime) < scanDebounceInterval {
            return false
        }
        return true
    }

    func recordScan(code: String) {
        lastScannedCode = code
        lastScanTime = Date()
    }

    func clearScanHistory() {
        lastScannedCode = nil
        lastScanTime = nil
    }

    // MARK: - Dependencies

    private let webSocketService: WebSocketServiceProtocol
    private let httpService: HTTPServiceProtocol
    private let sessionRepository: SessionRepository
    private let connectToAgentUseCase: ConnectToAgentUseCase
    private let parseQRCodeUseCase: ParseQRCodeUseCase
    private let sendPromptUseCase: SendPromptUseCase
    private let respondToClaudeUseCase: RespondToClaudeUseCase
    private let agentRepository: AgentRepositoryProtocol
    private let fileRepository: FileRepositoryProtocol
    private let logCache: LogCache
    private let diffCache: DiffCache

    private var stateTask: Task<Void, Never>?
    private var workspaceCancellable: AnyCancellable?

    // MARK: - Init

    init(
        webSocketService: WebSocketServiceProtocol,
        httpService: HTTPServiceProtocol,
        sessionRepository: SessionRepository,
        connectToAgentUseCase: ConnectToAgentUseCase,
        parseQRCodeUseCase: ParseQRCodeUseCase,
        sendPromptUseCase: SendPromptUseCase,
        respondToClaudeUseCase: RespondToClaudeUseCase,
        agentRepository: AgentRepositoryProtocol,
        fileRepository: FileRepositoryProtocol,
        logCache: LogCache,
        diffCache: DiffCache
    ) {
        self.webSocketService = webSocketService
        self.httpService = httpService
        self.sessionRepository = sessionRepository
        self.connectToAgentUseCase = connectToAgentUseCase
        self.parseQRCodeUseCase = parseQRCodeUseCase
        self.sendPromptUseCase = sendPromptUseCase
        self.respondToClaudeUseCase = respondToClaudeUseCase
        self.agentRepository = agentRepository
        self.fileRepository = fileRepository
        self.logCache = logCache
        self.diffCache = diffCache

        // Initialize hasWorkspaces from UserDefaults (sync initial state)
        if let data = UserDefaults.standard.data(forKey: "cdev.saved_workspaces"),
           let workspaces = try? JSONDecoder().decode([Workspace].self, from: data) {
            self.hasWorkspaces = !workspaces.isEmpty
        }

        // Observe WorkspaceStore changes to update hasWorkspaces
        workspaceCancellable = WorkspaceStore.shared.$workspaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] workspaces in
                self?.hasWorkspaces = !workspaces.isEmpty
            }

        startListening()
        attemptAutoReconnect()
    }

    deinit {
        stateTask?.cancel()
        workspaceCancellable?.cancel()
    }

    // MARK: - ViewModel Factories

    func makePairingViewModel() -> PairingViewModel {
        if let existing = _pairingViewModel {
            return existing
        }
        let vm = PairingViewModel(
            parseQRCodeUseCase: parseQRCodeUseCase,
            connectToAgentUseCase: connectToAgentUseCase,
            httpService: httpService,
            appState: self
        )
        _pairingViewModel = vm
        return vm
    }

    func makeDashboardViewModel() -> DashboardViewModel {
        if let existing = _dashboardViewModel {
            return existing
        }
        let vm = DashboardViewModel(
            webSocketService: webSocketService,
            agentRepository: agentRepository,
            sendPromptUseCase: sendPromptUseCase,
            respondToClaudeUseCase: respondToClaudeUseCase,
            sessionRepository: sessionRepository,
            fileRepository: fileRepository,
            logCache: logCache,
            diffCache: diffCache,
            appState: self
        )
        _dashboardViewModel = vm
        return vm
    }

    // MARK: - Public Actions

    /// Cancel ongoing connection attempt
    func cancelConnection() {
        AppLogger.log("Cancelling connection")
        webSocketService.disconnect()
    }

    /// Clear HTTP service base URL (stops any pending/cached requests)
    func clearHTTPState() {
        httpService.baseURL = nil
        AppLogger.log("[AppState] Cleared HTTP base URL")
    }

    // MARK: - App Lifecycle

    /// Mark that we expect a disconnection (app going to background)
    /// This prevents navigation away from Dashboard on disconnect
    func markExpectedDisconnection() {
        isExpectedDisconnection = true
        wasExplicitDisconnect = false
        AppLogger.log("[AppState] Marked expected disconnection (background)")
    }

    /// Clear the expected disconnection flag (connection restored)
    func clearExpectedDisconnection() {
        isExpectedDisconnection = false
        AppLogger.log("[AppState] Cleared expected disconnection flag")
    }

    /// Mark that user explicitly disconnected (navigated away)
    func markExplicitDisconnect() {
        wasExplicitDisconnect = true
        isExpectedDisconnection = false
        AppLogger.log("[AppState] Marked explicit disconnect")
    }

    /// Reconnect to the active workspace after app returns from background
    func reconnectToActiveWorkspace() async {
        guard let workspace = WorkspaceStore.shared.activeWorkspace else {
            AppLogger.log("[AppState] No active workspace to reconnect to")
            return
        }

        AppLogger.log("[AppState] Attempting to reconnect to: \(workspace.name)")

        // Check if already connected
        if webSocketService.isConnected {
            AppLogger.log("[AppState] Already connected, skipping reconnection")
            clearExpectedDisconnection()
            return
        }

        // Set connection state to reconnecting
        connectionState = .reconnecting(attempt: 1)

        // Retrieve stored token for this host (if available)
        var accessToken: String?
        if let host = workspace.webSocketURL.host,
           let storedHost = TokenManager.shared.getStoredHost(),
           storedHost == host {
            accessToken = await TokenManager.shared.getValidAccessToken()
            if accessToken != nil {
                AppLogger.log("[AppState] Retrieved stored token for reconnection")
            } else {
                AppLogger.log("[AppState] No valid token available for reconnection", type: .warning)
            }
        }

        // Create connection info from saved workspace
        let connectionInfo = ConnectionInfo(
            webSocketURL: workspace.webSocketURL,
            httpURL: workspace.httpURL,
            sessionId: workspace.sessionId ?? "",
            repoName: workspace.name,
            token: accessToken
        )

        // Restore HTTP base URL
        httpService.baseURL = workspace.httpURL

        do {
            try await connectToAgentUseCase.execute(connectionInfo: connectionInfo)
            AppLogger.log("[AppState] Reconnection successful")

            // Re-subscribe to workspace events if we have a remote workspace ID
            if let remoteId = workspace.remoteWorkspaceId {
                try await WorkspaceManagerService.shared.subscribe(workspaceId: remoteId)
                AppLogger.log("[AppState] Re-subscribed to workspace events")
            }

            // Restore session context in DashboardViewModel
            if let sessionId = workspace.sessionId ?? sessionRepository.selectedSessionId {
                _dashboardViewModel?.setWorkspaceContext(
                    name: workspace.name,
                    sessionId: sessionId
                )
            }

            clearExpectedDisconnection()
            Haptics.success()
        } catch {
            AppLogger.error(error, context: "Reconnect to workspace")
            connectionState = .failed(reason: error.localizedDescription)
            // Don't clear expected disconnection - let RootView retry
        }
    }

    // MARK: - Private

    private func startListening() {
        stateTask = Task {
            for await state in webSocketService.connectionStateStream {
                self.connectionState = state
            }
        }
    }

    private func attemptAutoReconnect() {
        guard sessionRepository.autoReconnect else {
            AppLogger.log("[AppState] Auto-reconnect disabled")
            return
        }

        Task {
            // New architecture: Use WorkspaceManagerService for auto-reconnect
            // Only auto-connect to the WebSocket server, don't select a specific workspace
            // Let user choose from workspace manager

            // Check if we have a saved manager host
            guard let managerHost = ManagerStore.shared.lastHost else {
                AppLogger.log("[AppState] No saved manager host, not attempting auto-reconnect")
                return
            }

            AppLogger.log("[AppState] Auto-connecting to manager at: \(managerHost)")

            // Determine URL scheme based on host type
            let isLocal = isLocalHost(managerHost)
            let wsScheme = isLocal ? "ws" : "wss"
            let httpScheme = isLocal ? "http" : "https"

            let wsURL: URL
            let httpURL: URL

            if isLocal {
                wsURL = URL(string: "\(wsScheme)://\(managerHost):\(ServerConnection.serverPort)/ws")!
                httpURL = URL(string: "\(httpScheme)://\(managerHost):\(ServerConnection.serverPort)")!
            } else {
                wsURL = URL(string: "\(wsScheme)://\(managerHost)/ws")!
                httpURL = URL(string: "\(httpScheme)://\(managerHost)")!
            }

            // Retrieve stored token for this host (if available)
            var accessToken: String?
            if let storedHost = TokenManager.shared.getStoredHost(),
               storedHost == managerHost {
                accessToken = await TokenManager.shared.getValidAccessToken()
                if accessToken != nil {
                    AppLogger.log("[AppState] Retrieved stored token for auto-reconnect")
                }
            }

            let connectionInfo = ConnectionInfo(
                webSocketURL: wsURL,
                httpURL: httpURL,
                sessionId: "",
                repoName: "Workspaces",
                token: accessToken
            )

            httpService.baseURL = httpURL

            do {
                try await connectToAgentUseCase.execute(connectionInfo: connectionInfo)
                AppLogger.log("[AppState] Auto-connect to manager successful, workspace list available")
                // Don't auto-select a workspace - let user choose from workspace manager
            } catch {
                AppLogger.error(error, context: "Auto-reconnect to manager")
                webSocketService.disconnect()
                httpService.baseURL = nil
                AppLogger.log("[AppState] Auto-reconnect failed")
            }
        }
    }

    /// Check if there are saved workspaces available
    /// Deprecated: Use `hasWorkspaces` property for reactive updates
    var hasSavedWorkspaces: Bool {
        hasWorkspaces
    }

    // MARK: - Agent Connection

    /// Connect directly to a cdev-agent at the given host
    /// cdev-agent uses: WebSocket on port 8765, HTTP on port 8766
    func connectToAgent(host: String) async {
        AppLogger.log("[AppState] Connecting to cdev-agent at \(host)")

        // Determine URL scheme based on host type
        let isLocal = isLocalHost(host)
        let wsScheme = isLocal ? "ws" : "wss"
        let httpScheme = isLocal ? "http" : "https"

        // cdev-agent ports (for local connections)
        // For dev tunnels, port is embedded in the hostname
        let wsURL: URL
        let httpURL: URL

        if isLocal {
            // Local network: explicit ports
            wsURL = URL(string: "\(wsScheme)://\(host):8765/ws")!
            httpURL = URL(string: "\(httpScheme)://\(host):8766")!
        } else {
            // Dev tunnels: port is in subdomain, no explicit port needed
            // e.g., abc123x4-8765.asse.devtunnels.ms for WebSocket
            // Need to handle HTTP separately (port 8766 tunnel)
            wsURL = URL(string: "\(wsScheme)://\(host)/ws")!
            // For HTTP, user needs to provide the 8766 tunnel URL separately
            // For now, assume same host (might need adjustment)
            let httpHost = host.replacingOccurrences(of: "-8765.", with: "-8766.")
            httpURL = URL(string: "\(httpScheme)://\(httpHost)")!
        }

        // Create workspace entry
        let workspace = Workspace(
            name: extractWorkspaceName(from: host),
            webSocketURL: wsURL,
            httpURL: httpURL,
            sessionId: nil,
            branch: nil
        )

        // Save to workspace store
        WorkspaceStore.shared.saveWorkspace(workspace)
        WorkspaceStore.shared.setActive(workspace)

        // Retrieve stored token for this host (if available)
        var accessToken: String?
        if let storedHost = TokenManager.shared.getStoredHost(),
           storedHost == host {
            accessToken = await TokenManager.shared.getValidAccessToken()
            if accessToken != nil {
                AppLogger.log("[AppState] Retrieved stored token for agent connection")
            }
        }

        // Create connection info
        let connectionInfo = ConnectionInfo(
            webSocketURL: wsURL,
            httpURL: httpURL,
            sessionId: "",
            repoName: workspace.name,
            token: accessToken
        )

        // Set HTTP base URL
        httpService.baseURL = httpURL

        // Connect
        do {
            try await connectToAgentUseCase.execute(connectionInfo: connectionInfo)
            AppLogger.log("[AppState] Connected to cdev-agent at \(host)")
            Haptics.success()
        } catch {
            AppLogger.error(error, context: "Connect to cdev-agent")
            Haptics.error()
        }
    }

    /// Check if host is a local network address
    private func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" {
            return true
        }
        // IP address pattern
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        if let regex = try? NSRegularExpression(pattern: ipPattern),
           regex.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil {
            return true
        }
        // .local domains (Bonjour)
        if host.hasSuffix(".local") {
            return true
        }
        return false
    }

    /// Extract a readable workspace name from host
    private func extractWorkspaceName(from host: String) -> String {
        // For IP addresses, use "Agent @ IP"
        if host.contains(".") && !host.contains("-") {
            return "Agent @ \(host)"
        }
        // For dev tunnels, extract the tunnel ID
        if let dashIndex = host.firstIndex(of: "-") {
            return String(host[..<dashIndex])
        }
        return host
    }

    /// Replace port in dev tunnel subdomain
    /// e.g., "abc123x4-8765.asse.devtunnels.ms" with port 8766 → "abc123x4-8766.asse.devtunnels.ms"
    private func replacePortInDevTunnel(host: String, newPort: Int) -> String {
        // Pattern: {id}-{port}.{rest}
        // Find the pattern: dash followed by 4-5 digit port, then dot
        let portPattern = #"-(\d{4,5})\."#

        guard let regex = try? NSRegularExpression(pattern: portPattern),
              let match = regex.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)),
              let portRange = Range(match.range(at: 0), in: host) else {
            // If pattern not found, return host as-is (might not be a dev tunnel)
            return host
        }

        // Replace the port in the subdomain
        let newPortString = "-\(newPort)."
        return host.replacingCharacters(in: portRange, with: newPortString)
    }

    // MARK: - Remote Workspace Connection

    /// Connect to a remote workspace from the Workspace Manager
    /// Single-port architecture: uses the same server connection (port 8766)
    /// Starts a session for the workspace if none exists
    /// Returns true if connection succeeded, false otherwise
    @discardableResult
    func connectToRemoteWorkspace(_ remoteWorkspace: RemoteWorkspace, host: String) async -> Bool {
        AppLogger.log("[AppState] ========== CONNECT TO REMOTE WORKSPACE ==========")
        AppLogger.log("[AppState] connectToRemoteWorkspace: workspace=\(remoteWorkspace.name), id=\(remoteWorkspace.id)")
        AppLogger.log("[AppState] connectToRemoteWorkspace: host=\(host), hasActiveSession=\(remoteWorkspace.hasActiveSession)")
        AppLogger.log("[AppState] connectToRemoteWorkspace: activeSession=\(remoteWorkspace.activeSession?.id ?? "nil")")

        // Single-port architecture: all workspaces share the same server port
        let isLocal = isLocalHost(host)
        let wsScheme = isLocal ? "ws" : "wss"
        let httpScheme = isLocal ? "http" : "https"

        // Create URLs using single port (8766)
        let wsURL: URL
        let httpURL: URL

        if isLocal {
            // Local network: use single server port
            wsURL = URL(string: "\(wsScheme)://\(host):\(ServerConnection.serverPort)/ws")!
            httpURL = URL(string: "\(httpScheme)://\(host):\(ServerConnection.serverPort)")!
        } else {
            // Dev tunnels: host already includes port in subdomain
            wsURL = URL(string: "\(wsScheme)://\(host)/ws")!
            httpURL = URL(string: "\(httpScheme)://\(host)")!
        }

        // Create local workspace entry
        let workspace = Workspace(
            name: remoteWorkspace.name,
            webSocketURL: wsURL,
            httpURL: httpURL,
            sessionId: remoteWorkspace.activeSession?.id,  // Use active session if exists
            branch: nil,
            remoteWorkspaceId: remoteWorkspace.id  // Server-side workspace ID for workspace-aware APIs
        )

        // Save to workspace store and use the returned workspace (which has the correct ID)
        let savedWorkspace = WorkspaceStore.shared.saveWorkspace(workspace)
        WorkspaceStore.shared.setActive(savedWorkspace)
        AppLogger.log("[AppState] Saved workspace: \(savedWorkspace.name), id: \(savedWorkspace.id)")

        // Retrieve stored token for this host (if available)
        var accessToken: String?
        if let storedHost = TokenManager.shared.getStoredHost(),
           storedHost == host {
            accessToken = await TokenManager.shared.getValidAccessToken()
            if accessToken != nil {
                AppLogger.log("[AppState] Retrieved stored token for remote workspace connection")
            }
        }

        // Create connection info
        let connectionInfo = ConnectionInfo(
            webSocketURL: wsURL,
            httpURL: httpURL,
            sessionId: remoteWorkspace.activeSession?.id ?? "",
            repoName: remoteWorkspace.name,
            token: accessToken
        )

        // Set HTTP base URL
        httpService.baseURL = httpURL

        // Connect (if not already connected to this server)
        do {
            // Only connect if not already connected
            AppLogger.log("[AppState] connectToRemoteWorkspace: isConnected=\(webSocketService.isConnected)")
            if !webSocketService.isConnected {
                AppLogger.log("[AppState] connectToRemoteWorkspace: Connecting to WebSocket...")
                try await connectToAgentUseCase.execute(connectionInfo: connectionInfo)
                AppLogger.log("[AppState] connectToRemoteWorkspace: WebSocket connected")
            } else {
                AppLogger.log("[AppState] connectToRemoteWorkspace: Already connected, skipping connect")
            }

            // Subscribe to workspace events
            AppLogger.log("[AppState] connectToRemoteWorkspace: Subscribing to workspace events...")
            try await WorkspaceManagerService.shared.subscribe(workspaceId: remoteWorkspace.id)
            AppLogger.log("[AppState] connectToRemoteWorkspace: Subscribed")

            // Get or create session for this workspace
            var activeSessionId: String?

            if remoteWorkspace.hasActiveSession, let session = remoteWorkspace.activeSession {
                // Use existing active session
                activeSessionId = session.id
                AppLogger.log("[AppState] connectToRemoteWorkspace: Using existing session: \(session.id)")
            } else {
                // Start a new session
                let preferredRuntime = sessionRepository.selectedSessionRuntime
                let runtime: AgentRuntime
                if RuntimeCapabilityRegistryStore.shared.isSupported(preferredRuntime) {
                    runtime = preferredRuntime
                } else {
                    runtime = RuntimeCapabilityRegistryStore.shared.defaultRuntime()
                    sessionRepository.selectedSessionRuntime = runtime
                    AppLogger.log(
                        "[AppState] connectToRemoteWorkspace: runtime fallback \(preferredRuntime.rawValue) -> \(runtime.rawValue)",
                        type: .warning
                    )
                }
                AppLogger.log("[AppState] connectToRemoteWorkspace: Starting new session for workspace...")
                let session = try await WorkspaceManagerService.shared.startSession(
                    workspaceId: remoteWorkspace.id,
                    runtime: runtime
                )
                activeSessionId = session.id
                AppLogger.log("[AppState] connectToRemoteWorkspace: Started session: \(session.id), runtime: \(runtime.rawValue)")
            }

            // Set the session ID for DashboardViewModel to use
            if let sessionId = activeSessionId {
                sessionRepository.selectedSessionId = sessionId
                AppLogger.log("[AppState] connectToRemoteWorkspace: Set selectedSessionId: \(sessionId)")
            }

            // Update DashboardViewModel workspace context (if cached)
            // This ensures correct workspace name is displayed immediately
            AppLogger.log("[AppState] connectToRemoteWorkspace: Updating DashboardViewModel context...")
            _dashboardViewModel?.setWorkspaceContext(
                name: remoteWorkspace.name,
                sessionId: activeSessionId
            )

            AppLogger.log("[AppState] connectToRemoteWorkspace: SUCCESS - Connected to \(remoteWorkspace.name)")
            AppLogger.log("[AppState] ========== CONNECT TO REMOTE WORKSPACE END (SUCCESS) ==========")
            // Clear unreachable status on successful connection
            WorkspaceManagerService.shared.clearUnreachableStatus(remoteWorkspace.id)
            Haptics.success()
            return true
        } catch {
            AppLogger.log("[AppState] connectToRemoteWorkspace: FAILED - \(error.localizedDescription)", type: .error)
            AppLogger.log("[AppState] ========== CONNECT TO REMOTE WORKSPACE END (FAILED) ==========")
            AppLogger.error(error, context: "Connect to remote workspace")
            Haptics.error()
            // Mark workspace as unreachable so UI shows correct status
            WorkspaceManagerService.shared.markWorkspaceUnreachable(remoteWorkspace.id)
            // Refresh workspace list from manager
            Task {
                AppLogger.log("[AppState] Connection failed, refreshing workspace status from manager")
                _ = try? await WorkspaceManagerService.shared.listWorkspaces()
            }
            return false
        }
    }
}
