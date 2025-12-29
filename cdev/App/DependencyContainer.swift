import Foundation

/// Dependency injection container - Service Locator pattern
/// Following CleanerApp architecture
/// @MainActor ensures safe access to MainActor-isolated singletons
@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()

    private init() {}

    // MARK: - Services (Lazy initialization)

    lazy var webSocketService: WebSocketServiceProtocol = WebSocketService()

    lazy var httpService: HTTPServiceProtocol = HTTPService()

    lazy var keychainService: KeychainService = KeychainService()

    // MARK: - Workspace Manager

    lazy var workspaceManagerService: WorkspaceManagerService = {
        let service = WorkspaceManagerService.shared
        service.configure(webSocketService: webSocketService)
        return service
    }()

    lazy var managerStore: ManagerStore = ManagerStore.shared

    // MARK: - Session Awareness

    lazy var sessionAwarenessManager: SessionAwarenessManager = {
        let manager = SessionAwarenessManager.shared
        // Note: agentRepository will be configured after it's initialized
        return manager
    }()

    // MARK: - Caches

    lazy var logCache: LogCache = LogCache()

    lazy var diffCache: DiffCache = DiffCache()

    lazy var fileCache: FileCache = FileCache()

    // MARK: - Repositories

    lazy var sessionRepository: SessionRepository = SessionRepository(
        keychain: keychainService
    )

    lazy var agentRepository: AgentRepositoryProtocol = AgentRepository(
        webSocketService: webSocketService
    )

    lazy var fileRepository: FileRepositoryProtocol = FileRepository(
        webSocketService: webSocketService,
        httpService: httpService,
        cache: fileCache,
        useMockData: false  // Use real cdev-agent API via JSON-RPC
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

    func makeAppState() -> AppState {
        // Configure session awareness manager with agent repository
        sessionAwarenessManager.configure(agentRepository: agentRepository)

        return AppState(
            webSocketService: webSocketService,
            httpService: httpService,
            sessionRepository: sessionRepository,
            connectToAgentUseCase: connectToAgentUseCase,
            parseQRCodeUseCase: parseQRCodeUseCase,
            sendPromptUseCase: sendPromptUseCase,
            respondToClaudeUseCase: respondToClaudeUseCase,
            agentRepository: agentRepository,
            fileRepository: fileRepository,
            logCache: logCache,
            diffCache: diffCache
        )
    }
}
