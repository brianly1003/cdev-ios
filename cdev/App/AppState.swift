import Foundation
import Combine

/// Global app state - manages connection and creates view models
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected
    @Published private(set) var hasWorkspaces: Bool = false

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
            // First try WorkspaceStore (new system) - check UserDefaults directly
            if let data = UserDefaults.standard.data(forKey: "cdev.saved_workspaces"),
               let workspaces = try? JSONDecoder().decode([Workspace].self, from: data),
               let lastWorkspace = workspaces.sorted(by: { $0.lastConnected > $1.lastConnected }).first {

                AppLogger.log("[AppState] Auto-reconnecting to workspace: \(lastWorkspace.name) at \(lastWorkspace.webSocketURL)")
                let connectionInfo = ConnectionInfo(
                    webSocketURL: lastWorkspace.webSocketURL,
                    httpURL: lastWorkspace.httpURL,
                    sessionId: lastWorkspace.sessionId ?? "",
                    repoName: lastWorkspace.name
                )
                httpService.baseURL = connectionInfo.httpURL
                do {
                    try await connectToAgentUseCase.execute(connectionInfo: connectionInfo)
                    WorkspaceStore.shared.setActive(lastWorkspace)
                    AppLogger.log("[AppState] Auto-reconnect successful")
                } catch {
                    AppLogger.error(error, context: "Auto-reconnect to workspace")
                }
                return
            }

            AppLogger.log("[AppState] No saved workspaces found, trying old session storage")

            // Fallback to old session storage
            do {
                if let lastConnection = try await sessionRepository.loadLastConnection() {
                    AppLogger.log("Auto-reconnecting to \(lastConnection.host)")
                    httpService.baseURL = lastConnection.httpURL
                    try await connectToAgentUseCase.execute(connectionInfo: lastConnection)
                }
            } catch {
                AppLogger.error(error, context: "Auto-reconnect")
            }
        }
    }

    /// Check if there are saved workspaces available
    /// Deprecated: Use `hasWorkspaces` property for reactive updates
    var hasSavedWorkspaces: Bool {
        hasWorkspaces
    }
}
