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

    // Sessions (for /resume command)
    @Published var sessions: [SessionsResponse.SessionInfo] = []
    @Published var showSessionPicker: Bool = false

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

        // Initialize with current connection state
        self.connectionState = webSocketService.connectionState

        startListening()

        // If already connected, load history immediately
        if connectionState.isConnected {
            Task {
                await loadRecentSessionHistory()
                await refreshGitStatus()
            }
        }
        // Otherwise, history will be loaded when connection is established (in startListening)
    }

    deinit {
        eventTask?.cancel()
        stateTask?.cancel()
    }

    // MARK: - Public Actions

    /// Send prompt to Claude (or handle built-in commands)
    func sendPrompt() async {
        guard !promptText.isBlank else { return }

        let userMessage = promptText
        promptText = "" // Clear immediately for fast UX

        // Check for built-in commands (start with /)
        if userMessage.hasPrefix("/") {
            await handleCommand(userMessage)
            return
        }

        isLoading = true
        Haptics.light()

        // Add user's message to logs immediately (optimistic UI)
        let userEntry = LogEntry(
            content: "> \(userMessage)",
            stream: .user
        )
        await logCache.add(userEntry)
        logs = await logCache.getAll()

        do {
            // If Claude is waiting for a response, use respondToClaude
            // Otherwise use runClaude with continue mode (Claude CLI handles session)
            if claudeState == .waiting, let interaction = pendingInteraction {
                try await respondToClaudeUseCase.answerQuestion(
                    response: userMessage,
                    requestId: interaction.requestId
                )
                pendingInteraction = nil
            } else {
                // Determine mode based on sessionId availability
                // - First message (no sessionId): use "new" mode
                // - Follow-up messages (has sessionId): use "continue" mode with sessionId
                let currentSessionId = agentStatus.sessionId
                let mode: SessionMode = (currentSessionId != nil && !currentSessionId!.isEmpty) ? .continue : .new

                try await sendPromptUseCase.execute(
                    prompt: userMessage,
                    mode: mode,
                    sessionId: currentSessionId
                )
            }
            showPromptSheet = false
            Haptics.success()
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
            Haptics.error()
        }

        isLoading = false
    }

    // MARK: - Built-in Commands

    /// Handle built-in commands (start with /)
    private func handleCommand(_ input: String) async {
        let command = input.lowercased().trimmingCharacters(in: .whitespaces)
        Haptics.light()

        switch command {
        case "/resume":
            await loadSessions()
            showSessionPicker = true

        case "/new":
            await startNewSession()

        case "/clear":
            await clearAndStartNew()

        case "/sessions":
            await loadSessions()
            showSessionPicker = true

        case "/help":
            await showHelp()

        default:
            // Unknown command - show help
            let helpEntry = LogEntry(
                content: "Unknown command: \(input)\nType /help for available commands.",
                stream: .system
            )
            await logCache.add(helpEntry)
            logs = await logCache.getAll()
        }
    }

    /// Load available sessions for picker
    func loadSessions() async {
        do {
            let response = try await agentRepository.getSessions()
            sessions = response.sessions
        } catch {
            AppLogger.error(error, context: "Load sessions")
        }
    }

    /// Resume a specific session
    func resumeSession(_ sessionId: String) async {
        showSessionPicker = false
        isLoading = true
        Haptics.medium()

        // Clear current logs
        await logCache.clear()
        logs = []

        // Update sessionId
        updateSessionId(sessionId)

        // Load session messages
        do {
            let messagesResponse = try await agentRepository.getSessionMessages(sessionId: sessionId)
            for message in messagesResponse.messages {
                if let entry = LogEntry.from(sessionMessage: message, sessionId: sessionId) {
                    await logCache.add(entry)
                }
            }
            logs = await logCache.getAll()

            // Add system message
            let resumeEntry = LogEntry(
                content: "📍 Resumed session",
                stream: .system
            )
            await logCache.add(resumeEntry)
            logs = await logCache.getAll()

            Haptics.success()
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
            Haptics.error()
        }

        isLoading = false
    }

    /// Start a new session (clear current context)
    func startNewSession() async {
        // Clear logs and sessionId
        await logCache.clear()
        logs = []
        updateSessionId("")

        // Add system message
        let newEntry = LogEntry(
            content: "🆕 Started new session",
            stream: .system
        )
        await logCache.add(newEntry)
        logs = await logCache.getAll()
        Haptics.success()
    }

    /// Clear logs and start a new session
    private func clearAndStartNew() async {
        await logCache.clear()
        logs = []
        updateSessionId("")

        let clearEntry = LogEntry(
            content: "🧹 Cleared & started new session",
            stream: .system
        )
        await logCache.add(clearEntry)
        logs = await logCache.getAll()
        Haptics.success()
    }

    /// Delete a specific session
    func deleteSession(_ sessionId: String) async {
        do {
            _ = try await agentRepository.deleteSession(sessionId: sessionId)
            // Remove from local list
            sessions.removeAll { $0.sessionId == sessionId }
            Haptics.success()
        } catch {
            AppLogger.error(error, context: "Delete session")
            self.error = error as? AppError ?? .unknown(underlying: error)
            Haptics.error()
        }
    }

    /// Delete all sessions
    func deleteAllSessions() async {
        do {
            let response = try await agentRepository.deleteAllSessions()
            sessions = []
            AppLogger.log("Deleted \(response.deleted) sessions")

            // Also clear current logs and session
            await logCache.clear()
            logs = []
            updateSessionId("")

            let entry = LogEntry(
                content: "🗑️ Deleted all sessions",
                stream: .system
            )
            await logCache.add(entry)
            logs = await logCache.getAll()
            Haptics.success()
        } catch {
            AppLogger.error(error, context: "Delete all sessions")
            self.error = error as? AppError ?? .unknown(underlying: error)
            Haptics.error()
        }
    }

    /// Show help for available commands
    private func showHelp() async {
        let helpText = """
        Available commands:
        /resume  - Pick a session to continue
        /new     - Start fresh conversation
        /clear   - Clear output & start new
        /help    - Show this help
        """
        let helpEntry = LogEntry(
            content: helpText,
            stream: .system
        )
        await logCache.add(helpEntry)
        logs = await logCache.getAll()
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
        // Also refresh git status
        await refreshGitStatus()
    }

    /// Refresh git status from API
    func refreshGitStatus() async {
        do {
            let gitStatus = try await agentRepository.getGitStatus()
            // Clear existing entries and add fresh ones from API
            await diffCache.clear()
            for file in gitStatus.files {
                let entry = DiffEntry.from(gitFile: file)
                await diffCache.add(entry)
            }
            diffs = await diffCache.getAll()
        } catch {
            AppLogger.error(error, context: "Refresh git status")
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

    /// Load history from most recent session
    private func loadRecentSessionHistory() async {
        do {
            // First get list of sessions to find the most recent one
            let sessionsResponse = try await agentRepository.getSessions()

            // Use current session ID if available and not empty, otherwise use most recent
            var sessionId: String?
            if let current = sessionsResponse.current, !current.isEmpty {
                sessionId = current
            } else {
                sessionId = sessionsResponse.sessions.first?.sessionId
            }

            guard let sessionId = sessionId, !sessionId.isEmpty else {
                AppLogger.log("No session history available")
                return
            }

            AppLogger.log("Loading history for session: \(sessionId)")

            // Clear existing logs before loading new session
            await logCache.clear()

            // Store sessionId in agentStatus
            updateSessionId(sessionId)

            // Get messages for the session
            AppLogger.log("Fetching messages for session: \(sessionId)")
            let messagesResponse = try await agentRepository.getSessionMessages(sessionId: sessionId)
            AppLogger.log("Got \(messagesResponse.count) messages")

            // Only add messages if there are any
            guard messagesResponse.count > 0 else {
                AppLogger.log("Session has no messages")
                logs = []
                return
            }

            // Convert to log entries and add to cache (skip tool messages with no text)
            for message in messagesResponse.messages {
                if let entry = LogEntry.from(sessionMessage: message, sessionId: sessionId) {
                    await logCache.add(entry)
                }
            }

            // Update logs array
            logs = await logCache.getAll()
            AppLogger.log("Loaded \(messagesResponse.count) messages from session history, total logs: \(logs.count)")
        } catch {
            // Log the actual error for debugging
            AppLogger.error(error, context: "Load session history")

            // If session not found (404), clear the stale sessionId
            if case .httpRequestFailed(let statusCode, _) = error as? AppError, statusCode == 404 {
                AppLogger.log("Session not found, clearing stale sessionId")
                updateSessionId("")
            }
        }
    }

    private func startListening() {
        // Listen to connection state
        stateTask = Task {
            for await state in webSocketService.connectionStateStream {
                let wasConnected = self.connectionState.isConnected
                self.connectionState = state

                // Load history when connection is first established
                if !wasConnected && state.isConnected {
                    await self.loadRecentSessionHistory()
                    await self.refreshGitStatus()
                }
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
            // Capture sessionId from log events
            if case .claudeLog(let payload) = event.payload,
               let sessionId = payload.sessionId {
                updateSessionId(sessionId)
            }

        case .claudeStatus:
            if case .claudeStatus(let payload) = event.payload,
               let state = payload.state {
                let previousState = claudeState
                claudeState = state
                if state != .waiting {
                    pendingInteraction = nil
                }
                // Capture sessionId from status events
                if let sessionId = payload.sessionId {
                    updateSessionId(sessionId)
                }
                // Refresh git status when Claude finishes (running -> idle/stopped)
                // This handles commits, resets, and other git operations
                if previousState == .running && (state == .idle || state == .stopped) {
                    await refreshGitStatus()
                }
            }

        case .claudeSessionInfo:
            // Capture sessionId from session info events
            if case .claudeSessionInfo(let payload) = event.payload,
               let sessionId = payload.sessionId {
                updateSessionId(sessionId)
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

        case .fileChanged:
            // Handle file changes (even without git diff)
            if case .fileChanged(let payload) = event.payload,
               let path = payload.path {
                // If file was deleted, remove from cache
                if payload.change == .deleted {
                    await diffCache.remove(path: path)
                    diffs = await diffCache.getAll()
                } else if let entry = DiffEntry.fromFileChanged(event: event) {
                    await diffCache.add(entry)
                    diffs = await diffCache.getAll()
                }
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

    /// Update sessionId in agentStatus to maintain context
    private func updateSessionId(_ sessionId: String) {
        guard agentStatus.sessionId != sessionId else { return }
        agentStatus = AgentStatus(
            claudeState: agentStatus.claudeState,
            sessionId: sessionId,
            repoName: agentStatus.repoName,
            repoPath: agentStatus.repoPath,
            connectedClients: agentStatus.connectedClients,
            uptime: agentStatus.uptime
        )
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
