import Foundation
import Combine

/// Main dashboard view model - central hub for all agent interactions
@MainActor
final class DashboardViewModel: ObservableObject {
    // MARK: - Published State

    // Connection
    @Published var connectionState: ConnectionState = .disconnected
    @Published var agentStatus: AgentStatus = AgentStatus()

    // Claude
    @Published var claudeState: ClaudeState = .idle
    @Published var pendingInteraction: PendingInteraction?

    // Logs & Diffs
    @Published var logs: [LogEntry] = []
    @Published var diffs: [DiffEntry] = []
    @Published var selectedTab: DashboardTab = .logs

    // UI State
    @Published var promptText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var showPromptSheet: Bool = false

    // MARK: - Dependencies

    private let webSocketService: WebSocketServiceProtocol
    private let agentRepository: AgentRepositoryProtocol
    private let sendPromptUseCase: SendPromptUseCase
    private let respondToClaudeUseCase: RespondToClaudeUseCase

    private let logCache: LogCache
    private let diffCache: DiffCache

    private var eventTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    // MARK: - Init

    init(
        webSocketService: WebSocketServiceProtocol,
        agentRepository: AgentRepositoryProtocol,
        sendPromptUseCase: SendPromptUseCase,
        respondToClaudeUseCase: RespondToClaudeUseCase,
        logCache: LogCache,
        diffCache: DiffCache
    ) {
        self.webSocketService = webSocketService
        self.agentRepository = agentRepository
        self.sendPromptUseCase = sendPromptUseCase
        self.respondToClaudeUseCase = respondToClaudeUseCase
        self.logCache = logCache
        self.diffCache = diffCache

        startListening()
    }

    deinit {
        eventTask?.cancel()
        stateTask?.cancel()
    }

    // MARK: - Public Actions

    /// Send prompt to Claude
    func sendPrompt() async {
        guard !promptText.isBlank else { return }

        isLoading = true
        Haptics.light()

        do {
            try await sendPromptUseCase.execute(prompt: promptText, mode: .continue, sessionId: nil)
            promptText = ""
            showPromptSheet = false
            Haptics.success()
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
            Haptics.error()
        }

        isLoading = false
    }

    /// Stop Claude
    func stopClaude() async {
        isLoading = true
        Haptics.medium()

        do {
            try await agentRepository.stopClaude()
            Haptics.success()
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
            Haptics.error()
        }

        isLoading = false
    }

    /// Approve permission
    func approvePermission() async {
        guard let interaction = pendingInteraction else { return }
        Haptics.success()

        do {
            try await respondToClaudeUseCase.handlePermission(
                approved: true,
                requestId: interaction.requestId
            )
            pendingInteraction = nil
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
        }
    }

    /// Deny permission
    func denyPermission() async {
        guard let interaction = pendingInteraction else { return }
        Haptics.warning()

        do {
            try await respondToClaudeUseCase.handlePermission(
                approved: false,
                requestId: interaction.requestId
            )
            pendingInteraction = nil
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
        }
    }

    /// Answer question
    func answerQuestion(_ response: String) async {
        guard let interaction = pendingInteraction else { return }
        Haptics.light()

        do {
            try await respondToClaudeUseCase.answerQuestion(
                response: response,
                requestId: interaction.requestId
            )
            pendingInteraction = nil
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
        }
    }

    /// Refresh status
    func refreshStatus() async {
        do {
            agentStatus = try await agentRepository.fetchStatus()
            claudeState = agentStatus.claudeState
        } catch {
            AppLogger.error(error, context: "Refresh status")
        }
    }

    /// Clear logs
    func clearLogs() async {
        await logCache.clear()
        logs = []
        Haptics.light()
    }

    /// Clear diffs
    func clearDiffs() async {
        await diffCache.clear()
        diffs = []
        Haptics.light()
    }

    // MARK: - Private

    private func startListening() {
        // Listen to connection state
        stateTask = Task {
            for await state in webSocketService.connectionStateStream {
                self.connectionState = state
            }
        }

        // Listen to events
        eventTask = Task {
            for await event in webSocketService.eventStream {
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: AgentEvent) async {
        switch event.type {
        case .claudeLog:
            if let entry = LogEntry.from(event: event) {
                await logCache.add(entry)
                logs = await logCache.getAll()
            }

        case .claudeStatus:
            if case .claudeStatus(let payload) = event.payload,
               let state = payload.state {
                claudeState = state
                if state != .waiting {
                    pendingInteraction = nil
                }
            }

        case .claudeWaiting:
            pendingInteraction = PendingInteraction.fromWaiting(event: event)
            Haptics.warning()

        case .claudePermission:
            pendingInteraction = PendingInteraction.fromPermission(event: event)
            Haptics.warning()

        case .gitDiff:
            if let entry = DiffEntry.from(event: event) {
                await diffCache.add(entry)
                diffs = await diffCache.getAll()
            }

        case .statusResponse:
            if case .statusResponse(let payload) = event.payload {
                agentStatus = AgentStatus.from(payload: payload)
                claudeState = agentStatus.claudeState
            }

        case .error:
            if case .error(let payload) = event.payload,
               let message = payload.message {
                error = .commandFailed(reason: message)
            }

        default:
            break
        }
    }
}

// MARK: - Tab

enum DashboardTab: String, CaseIterable {
    case logs = "Terminal"
    case diffs = "Changes"

    var icon: String {
        switch self {
        case .logs: return "terminal"
        case .diffs: return "doc.text.magnifyingglass"
        }
    }
}
