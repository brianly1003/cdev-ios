import Foundation

/// Dependency injection container - Service Locator pattern
/// Following CleanerApp architecture
final class DependencyContainer {
    static let shared = DependencyContainer()

    private init() {}

    // MARK: - Services (Lazy initialization)

    lazy var webSocketService: WebSocketServiceProtocol = WebSocketService()

    lazy var httpService: HTTPServiceProtocol = HTTPService()

    lazy var keychainService: KeychainService = KeychainService()

    // MARK: - Caches

    lazy var logCache: LogCache = LogCache()

    lazy var diffCache: DiffCache = DiffCache()

    // MARK: - Repositories

    lazy var sessionRepository: SessionRepository = SessionRepository(
        keychain: keychainService
    )

    lazy var agentRepository: AgentRepositoryProtocol = AgentRepository(
        webSocketService: webSocketService,
        httpService: httpService
    )

    // MARK: - Use Cases

    lazy var connectToAgentUseCase: ConnectToAgentUseCase = DefaultConnectToAgentUseCase(
        webSocketService: webSocketService,
        sessionStorage: sessionRepository
    )

    lazy var sendPromptUseCase: SendPromptUseCase = DefaultSendPromptUseCase(
        agentRepository: agentRepository
    )

    lazy var respondToClaudeUseCase: RespondToClaudeUseCase = DefaultRespondToClaudeUseCase(
        agentRepository: agentRepository
    )

    lazy var parseQRCodeUseCase: ParseQRCodeUseCase = DefaultParseQRCodeUseCase()

    // MARK: - ViewModel Factories

    @MainActor
    func makeAppState() -> AppState {
        AppState(
            webSocketService: webSocketService,
            httpService: httpService,
            sessionRepository: sessionRepository,
            connectToAgentUseCase: connectToAgentUseCase,
            parseQRCodeUseCase: parseQRCodeUseCase,
            sendPromptUseCase: sendPromptUseCase,
            respondToClaudeUseCase: respondToClaudeUseCase,
            agentRepository: agentRepository,
            logCache: logCache,
            diffCache: diffCache
        )
    }
}
