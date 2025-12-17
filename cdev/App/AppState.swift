import Foundation
import Combine

/// Global app state - manages connection and creates view models
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected

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
            httpService: httpService
        )
    }

    func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel(
            webSocketService: webSocketService,
            agentRepository: agentRepository,
            sendPromptUseCase: sendPromptUseCase,
            respondToClaudeUseCase: respondToClaudeUseCase,
            logCache: logCache,
            diffCache: diffCache
        )
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
