import Foundation
import Combine

/// Global app state - manages connection and creates view models
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected

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
    private let logCache: LogCache
    private let diffCache: DiffCache

    private var stateTask: Task<Void, Never>?

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
        self.logCache = logCache
        self.diffCache = diffCache

        startListening()
        attemptAutoReconnect()
    }

    deinit {
        stateTask?.cancel()
    }

    // MARK: - ViewModel Factories

    func makePairingViewModel() -> PairingViewModel {
        PairingViewModel(
            parseQRCodeUseCase: parseQRCodeUseCase,
            connectToAgentUseCase: connectToAgentUseCase,
            httpService: httpService,
            appState: self
        )
    }

    func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel(
            webSocketService: webSocketService,
            agentRepository: agentRepository,
            sendPromptUseCase: sendPromptUseCase,
            respondToClaudeUseCase: respondToClaudeUseCase,
            sessionRepository: sessionRepository,
            logCache: logCache,
            diffCache: diffCache
        )
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
        guard sessionRepository.autoReconnect else { return }

        Task {
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
}
