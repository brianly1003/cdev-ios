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

    // Chat Messages (unified view with tool calls)
    @Published var chatMessages: [ChatMessage] = []
    @Published var isLoadingChatMessages: Bool = false

    // Chat Elements (Elements API style - sophisticated UI)
    @Published var chatElements: [ChatElement] = []

    // Source Control (Mini Repo Management)
    @Published var sourceControlViewModel: SourceControlViewModel!

    // File Explorer
    @Published var explorerViewModel: ExplorerViewModel!

    /// Log count excluding system messages (for badge display)
    /// System messages like "Started new session" are still shown but not counted
    var logsCountForBadge: Int {
        chatElements.count > 0 ? chatElements.count : logs.filter { $0.stream != .system }.count
    }

    // UI State
    @Published var promptText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var showPromptSheet: Bool = false

    // Sessions (for /resume command)
    @Published var sessions: [SessionsResponse.SessionInfo] = []
    @Published var showSessionPicker: Bool = false
    @Published var sessionsHasMore: Bool = false
    @Published var isLoadingMoreSessions: Bool = false
    private var sessionsNextOffset: Int = 0
    private let sessionsPageSize: Int = 20

    // MARK: - Dependencies

    private let webSocketService: WebSocketServiceProtocol
    private let _agentRepository: AgentRepositoryProtocol
    private let sendPromptUseCase: SendPromptUseCase
    private let respondToClaudeUseCase: RespondToClaudeUseCase
    private let sessionRepository: SessionRepository

    /// Public accessor for agentRepository (needed for SessionHistoryView)
    var agentRepository: AgentRepositoryProtocol { _agentRepository }

    private let logCache: LogCache
    private let diffCache: DiffCache
    private weak var appState: AppState?

    private var eventTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    // Debouncing for log updates to prevent UI lag
    private var logUpdateScheduled = false
    private var diffUpdateScheduled = false

    // Prevent duplicate initial loads
    private var isInitialLoadInProgress = false
    private var hasCompletedInitialLoad = false

    // Session management
    // - userSelectedSessionId: Session from history, user selection, or claude_session_info event
    // - hasActiveConversation: Whether we've sent a message and Claude processed it
    // Mode logic (cdev-agent API):
    //   - new: Start fresh conversation (no session_id)
    //   - continue: Continue specific session (session_id REQUIRED)
    // Flow:
    //   - Have session → validate against server → continue if valid, new if invalid
    //   - No session → fetch recent from server → continue if exists, new if empty
    private var userSelectedSessionId: String?
    private var hasActiveConversation: Bool = false

    // MARK: - Init

    init(
        webSocketService: WebSocketServiceProtocol,
        agentRepository: AgentRepositoryProtocol,
        sendPromptUseCase: SendPromptUseCase,
        respondToClaudeUseCase: RespondToClaudeUseCase,
        sessionRepository: SessionRepository,
        fileRepository: FileRepositoryProtocol,
        logCache: LogCache,
        diffCache: DiffCache,
        appState: AppState? = nil
    ) {
        self.webSocketService = webSocketService
        self._agentRepository = agentRepository
        self.sendPromptUseCase = sendPromptUseCase
        self.respondToClaudeUseCase = respondToClaudeUseCase
        self.sessionRepository = sessionRepository
        self.logCache = logCache
        self.diffCache = diffCache
        self.appState = appState

        // Initialize Source Control ViewModel
        self.sourceControlViewModel = SourceControlViewModel(agentRepository: agentRepository)

        // Initialize File Explorer ViewModel
        self.explorerViewModel = ExplorerViewModel(
            fileRepository: fileRepository,
            gitStatusProvider: { [weak self] in
                self?.sourceControlViewModel.state.allFiles ?? []
            }
        )

        // Load persisted session ID from storage and initialize agentStatus
        self.userSelectedSessionId = sessionRepository.selectedSessionId
        if let storedId = userSelectedSessionId {
            AppLogger.log("[Dashboard] Loaded stored sessionId: \(storedId)")
            // Initialize agentStatus with stored sessionId so refreshStatus preserves it
            self.agentStatus = AgentStatus(sessionId: storedId)
        }

        // Initialize with current connection state
        self.connectionState = webSocketService.connectionState
        AppLogger.log("[DashboardViewModel] init - connectionState: \(connectionState), starting listeners")

        startListening()

        // If already connected, load history (with delay to let UI render first)
        if connectionState.isConnected {
            AppLogger.log("[DashboardViewModel] init - already connected, scheduling history load in 300ms")
            // Use utility priority to avoid blocking UI interactions
            Task(priority: .utility) {
                // Wait for UI to be fully interactive before loading data
                // This prevents hang when user tries to interact during initial load
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                AppLogger.log("[DashboardViewModel] init Task - starting loadRecentSessionHistory")
                await loadRecentSessionHistory()
                AppLogger.log("[DashboardViewModel] init Task - starting refreshGitStatus")
                await refreshGitStatus()
                AppLogger.log("[DashboardViewModel] init Task - completed")
            }
        }
        // Otherwise, history will be loaded when connection is established (in startListening)
        AppLogger.log("[DashboardViewModel] init completed")
    }

    deinit {
        eventTask?.cancel()
        stateTask?.cancel()
    }

    // MARK: - Debounced Updates

    /// Schedule a debounced log UI update to prevent main thread blocking
    /// Uses flag-based coalescing - only one update runs per 100ms window
    private func scheduleLogUpdate() {
        guard !logUpdateScheduled else { return }
        logUpdateScheduled = true

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            guard let self = self else { return }
            self.logUpdateScheduled = false
            self.logs = await self.logCache.getAll()
        }
    }

    /// Schedule a debounced diff UI update
    private func scheduleDiffUpdate() {
        guard !diffUpdateScheduled else { return }
        diffUpdateScheduled = true

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            guard let self = self else { return }
            self.diffUpdateScheduled = false
            self.diffs = await self.diffCache.getAll()
        }
    }

    /// Force immediate log update (for user actions)
    private func forceLogUpdate() async {
        logUpdateScheduled = false
        logs = await logCache.getAll()
    }

    /// Force immediate diff update
    private func forceDiffUpdate() async {
        diffUpdateScheduled = false
        diffs = await diffCache.getAll()
    }

    // MARK: - Public Actions

    /// Send prompt to Claude (or handle built-in commands)
    func sendPrompt() async {
        guard !promptText.isBlank else { return }

        // Prevent sending while Claude is running
        guard claudeState != .running else {
            AppLogger.log("[Dashboard] Blocked send - Claude is already running")
            Haptics.warning()
            return
        }

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
        await forceLogUpdate() // Immediate for user action

        // Also add as ChatElement for sophisticated UI
        let userElement = ChatElement.userInput(userMessage)
        chatElements.append(userElement)

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
                // Session mode logic based on API documentation (cdev-agent):
                // - new: Start fresh conversation (NO session_id)
                // - continue: Continue a SPECIFIC session by ID (session_id REQUIRED)
                //
                // Flow:
                // 1. If userSelectedSessionId exists → validate against server → if invalid, clear logs and start new
                // 2. If no session selected → fetch sessions list → use most recent if exists
                // 3. If sessions list is empty → start new session

                let mode: SessionMode
                let sessionIdToSend: String?

                if let selectedId = userSelectedSessionId, !selectedId.isEmpty {
                    // Validate stored sessionId against server
                    let isValid = await validateSessionExists(selectedId)

                    if isValid {
                        // Session still exists - continue it
                        mode = .continue
                        sessionIdToSend = selectedId
                        AppLogger.log("[Dashboard] Sending prompt: mode=continue, sessionId=\(selectedId)")
                    } else {
                        // Session was removed from server - clear state and start new
                        AppLogger.log("[Dashboard] Session \(selectedId) removed from server, clearing and starting new")
                        setSelectedSession(nil)
                        await logCache.clear()
                        await forceLogUpdate()

                        mode = .new
                        sessionIdToSend = nil
                    }
                } else {
                    // No session selected - try to get the most recent from server
                    if let recentId = await getMostRecentSessionId() {
                        // Found a recent session - continue it
                        mode = .continue
                        sessionIdToSend = recentId
                        setSelectedSession(recentId)
                        AppLogger.log("[Dashboard] Using recent session: mode=continue, sessionId=\(recentId)")
                    } else {
                        // No sessions exist on server - start fresh
                        mode = .new
                        sessionIdToSend = nil
                        AppLogger.log("[Dashboard] No sessions exist, starting new")
                    }
                }

                try await sendPromptUseCase.execute(
                    prompt: userMessage,
                    mode: mode,
                    sessionId: sessionIdToSend
                )
            }
            showPromptSheet = false
            Haptics.success()
        } catch let appError as AppError {
            // Handle specific errors gracefully (don't show error popup)
            if case .httpRequestFailed(let statusCode, _) = appError, statusCode == 409 {
                AppLogger.log("[Dashboard] Claude is already running (409)")
                Haptics.warning()
            } else if case .httpRequestFailed(let statusCode, _) = appError, statusCode == 504 {
                // 504 Gateway Timeout - request likely succeeded but response timed out
                // We get status updates via WebSocket, so Claude probably started
                AppLogger.log("[Dashboard] Gateway timeout on /run - Claude likely started (check WebSocket events)")
                Haptics.light()
                // Don't show error - WebSocket will confirm if Claude started
            } else if case .claudeAlreadyRunning = appError {
                AppLogger.log("[Dashboard] Claude is already running")
                Haptics.warning()
            } else {
                self.error = appError
                Haptics.error()
            }
        } catch {
            self.error = .unknown(underlying: error)
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
            await forceLogUpdate()
        }
    }

    /// Load available sessions for picker (first page)
    func loadSessions() async {
        do {
            // Reset pagination state
            sessionsNextOffset = 0
            let response = try await _agentRepository.getSessions(limit: sessionsPageSize, offset: 0)
            sessions = response.sessions
            sessionsHasMore = response.hasMore
            sessionsNextOffset = response.nextOffset
            AppLogger.log("[Dashboard] Loaded \(response.sessions.count) sessions, total=\(response.total ?? 0), hasMore=\(sessionsHasMore)")
        } catch {
            AppLogger.error(error, context: "Load sessions")
        }
    }

    /// Load more sessions (pagination)
    func loadMoreSessions() async {
        guard sessionsHasMore, !isLoadingMoreSessions else { return }

        isLoadingMoreSessions = true
        do {
            let response = try await _agentRepository.getSessions(limit: sessionsPageSize, offset: sessionsNextOffset)
            sessions.append(contentsOf: response.sessions)
            sessionsHasMore = response.hasMore
            sessionsNextOffset = response.nextOffset
            AppLogger.log("[Dashboard] Loaded more sessions: +\(response.sessions.count), total now=\(sessions.count), hasMore=\(sessionsHasMore)")
        } catch {
            AppLogger.error(error, context: "Load more sessions")
        }
        isLoadingMoreSessions = false
    }

    /// Resume a specific session (user explicitly selected)
    func resumeSession(_ sessionId: String) async {
        showSessionPicker = false
        isLoading = true
        Haptics.medium()

        // Clear current logs and elements
        await logCache.clear()
        logs = []
        chatElements = []

        // Update sessionId - this is a TRUSTED source (user explicit selection)
        setSelectedSession(sessionId)
        hasActiveConversation = false  // Reset - will be set true on first prompt
        AppLogger.log("[Dashboard] User resumed session: \(sessionId)")

        // Load session messages
        do {
            let messagesResponse = try await _agentRepository.getSessionMessages(sessionId: sessionId)
            for message in messagesResponse.messages {
                if let entry = LogEntry.from(sessionMessage: message, sessionId: sessionId) {
                    await logCache.add(entry)
                }
                // Also create ChatElement from session message
                let chatMessage = ChatMessage.from(sessionMessage: message)
                if let element = convertChatMessageToElement(chatMessage) {
                    chatElements.append(element)
                }
            }
            await forceLogUpdate()
            Haptics.success()
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
            Haptics.error()
        }

        isLoading = false
    }

    /// Start a new session (clear current context)
    func startNewSession() async {
        // Clear logs, elements, and session state
        await logCache.clear()
        logs = []
        chatElements = []
        setSelectedSession(nil)
        hasActiveConversation = false
        AppLogger.log("[Dashboard] Started new session - cleared session state")

        // Add system message
        let newEntry = LogEntry(
            content: "🆕 Started new session",
            stream: .system
        )
        await logCache.add(newEntry)
        await forceLogUpdate()
        Haptics.success()
    }

    /// Clear logs and start a new session
    private func clearAndStartNew() async {
        await logCache.clear()
        logs = []
        chatElements = []
        setSelectedSession(nil)
        hasActiveConversation = false
        AppLogger.log("[Dashboard] Cleared & started new - cleared session state")

        let clearEntry = LogEntry(
            content: "🧹 Cleared & started new session",
            stream: .system
        )
        await logCache.add(clearEntry)
        await forceLogUpdate()
        Haptics.success()
    }

    /// Delete a specific session
    func deleteSession(_ sessionId: String) async {
        do {
            _ = try await _agentRepository.deleteSession(sessionId: sessionId)
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
            let response = try await _agentRepository.deleteAllSessions()
            sessions = []
            AppLogger.log("[Dashboard] Deleted \(response.deleted) sessions")

            // Also clear current logs, elements, and session state
            await logCache.clear()
            logs = []
            chatElements = []
            setSelectedSession(nil)
            hasActiveConversation = false

            let entry = LogEntry(
                content: "🗑️ Deleted all sessions",
                stream: .system
            )
            await logCache.add(entry)
            await forceLogUpdate()
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
        await forceLogUpdate()
    }

    /// Stop Claude
    func stopClaude() async {
        isLoading = true
        Haptics.medium()

        do {
            try await _agentRepository.stopClaude()
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
            let newStatus = try await _agentRepository.fetchStatus()

            // IMPORTANT: Re-read sessionId AFTER await to avoid race condition
            // During the await, loadRecentSessionHistory may have set the sessionId
            // We must use the current value, not a pre-await captured value
            let currentSessionId = agentStatus.sessionId
            AppLogger.log("[Dashboard] refreshStatus: using sessionId=\(currentSessionId ?? "nil")")

            // Update status but preserve sessionId (never use sessionId from /api/status)
            agentStatus = AgentStatus(
                claudeState: newStatus.claudeState,
                sessionId: currentSessionId,  // Keep current sessionId
                repoName: newStatus.repoName,
                repoPath: newStatus.repoPath,
                connectedClients: newStatus.connectedClients,
                uptime: newStatus.uptime
            )
            claudeState = agentStatus.claudeState
            AppLogger.log("[Dashboard] refreshStatus: completed, claudeState=\(claudeState.rawValue)")
        } catch {
            AppLogger.error(error, context: "Refresh status")
        }
        // Only refresh git status if initial load is done (to avoid race condition)
        if hasCompletedInitialLoad {
            await refreshGitStatus()
        }
    }

    /// Refresh git status from API
    func refreshGitStatus() async {
        // Refresh source control view
        await sourceControlViewModel.refresh()

        // Also update legacy diff cache for backward compatibility
        do {
            let gitStatus = try await _agentRepository.getGitStatus()
            // Clear existing entries and add fresh ones from API
            await diffCache.clear()
            for file in gitStatus.files {
                let entry = DiffEntry.from(gitFile: file)
                await diffCache.add(entry)
            }
            await forceDiffUpdate()
        } catch {
            AppLogger.error(error, context: "Refresh git status")
        }
    }

    /// Clear logs and chat elements
    func clearLogs() async {
        await logCache.clear()
        logs = []
        chatElements = []
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
        // Prevent duplicate loads
        guard !isInitialLoadInProgress else {
            AppLogger.log("[Dashboard] loadRecentSessionHistory skipped - already in progress")
            return
        }
        isInitialLoadInProgress = true
        AppLogger.log("[Dashboard] Starting loadRecentSessionHistory")

        defer {
            isInitialLoadInProgress = false
            hasCompletedInitialLoad = true
        }

        do {
            // First get list of sessions to find the most recent one (just need 1)
            AppLogger.log("[Dashboard] Calling getSessions API...")
            let sessionsResponse = try await _agentRepository.getSessions(limit: 1, offset: 0)
            AppLogger.log("[Dashboard] Sessions response: current=\(sessionsResponse.current ?? "nil"), total=\(sessionsResponse.total ?? 0)")

            // Use current session ID if available and not empty, otherwise use most recent
            var sessionId: String?
            if let current = sessionsResponse.current, !current.isEmpty {
                sessionId = current
                AppLogger.log("[Dashboard] Using current session: \(current)")
            } else {
                sessionId = sessionsResponse.sessions.first?.sessionId
                AppLogger.log("[Dashboard] Using first session: \(sessionId ?? "none")")
            }

            guard let sessionId = sessionId, !sessionId.isEmpty else {
                AppLogger.log("[Dashboard] No session history available")
                return
            }

            AppLogger.log("[Dashboard] Loading history for session: \(sessionId)")

            // Only clear if loading a different session (prevents flashing on reconnect)
            let isNewSession = userSelectedSessionId != sessionId
            if isNewSession {
                await logCache.clear()
                chatElements = []
                AppLogger.log("[Dashboard] Cleared data for new session")
            } else {
                AppLogger.log("[Dashboard] Same session - keeping existing data")
            }

            // Store sessionId - this is a TRUSTED source (from sessions API)
            setSelectedSession(sessionId)
            hasActiveConversation = false  // Reset - will be set true on first prompt
            AppLogger.log("[Dashboard] Set userSelectedSessionId: \(sessionId)")

            // Yield to let UI thread breathe before network call
            await Task.yield()

            // Get messages for the session
            AppLogger.log("[Dashboard] Fetching messages for session: \(sessionId)")
            let messagesResponse: SessionMessagesResponse
            do {
                messagesResponse = try await _agentRepository.getSessionMessages(sessionId: sessionId)
                AppLogger.log("[Dashboard] Got \(messagesResponse.count) messages")
            } catch {
                AppLogger.error(error, context: "Fetch session messages")
                throw error
            }

            // Yield after network call to prevent UI starvation
            await Task.yield()

            // Only add messages if there are any
            guard messagesResponse.count > 0 else {
                AppLogger.log("[Dashboard] Session has no messages")
                logs = []
                return
            }

            // Convert to log entries and ChatElements (skip tool messages with no text)
            var entriesAdded = 0
            for (index, message) in messagesResponse.messages.enumerated() {
                if let entry = LogEntry.from(sessionMessage: message, sessionId: sessionId) {
                    await logCache.add(entry)
                    entriesAdded += 1
                }
                // Also create ChatElement from session message
                let chatMessage = ChatMessage.from(sessionMessage: message)
                let element = convertChatMessageToElement(chatMessage)
                if let element = element {
                    chatElements.append(element)
                }

                // Yield every 10 messages to prevent UI starvation
                if index > 0 && index % 10 == 0 {
                    await Task.yield()
                }
            }
            AppLogger.log("[Dashboard] Created \(entriesAdded) log entries and \(chatElements.count) elements from \(messagesResponse.count) messages")

            // Update logs array
            await forceLogUpdate()
            AppLogger.log("[Dashboard] Loaded session history, total logs in view: \(logs.count)")
        } catch {
            // Log the actual error for debugging
            AppLogger.error(error, context: "Load session history failed")

            // If session not found (404), clear the stale session state
            if case .httpRequestFailed(let statusCode, _) = error as? AppError, statusCode == 404 {
                AppLogger.log("[Dashboard] Session not found (404), clearing session state")
                setSelectedSession(nil)
                hasActiveConversation = false
            }
        }
        AppLogger.log("[Dashboard] loadRecentSessionHistory completed")
    }

    private func startListening() {
        AppLogger.log("[DashboardViewModel] startListening - setting up connection state listener")
        // Listen to connection state
        stateTask = Task {
            for await state in webSocketService.connectionStateStream {
                let wasConnected = self.connectionState.isConnected
                self.connectionState = state
                AppLogger.log("[Dashboard] Connection state changed: wasConnected=\(wasConnected), isNowConnected=\(state.isConnected)")

                // Load history when connection is first established
                if !wasConnected && state.isConnected {
                    AppLogger.log("[Dashboard] First connection - loading history and git status in 300ms")
                    // Delay to let UI settle after connection state change
                    // This prevents hang when user tries to interact during load
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    AppLogger.log("[Dashboard] First connection - starting loadRecentSessionHistory")
                    await self.loadRecentSessionHistory()
                    AppLogger.log("[Dashboard] First connection - starting refreshGitStatus")
                    await self.refreshGitStatus()
                    AppLogger.log("[Dashboard] First connection - load completed")
                }
            }
        }

        AppLogger.log("[DashboardViewModel] startListening - setting up event listener")
        // Listen to events
        eventTask = Task {
            for await event in webSocketService.eventStream {
                await self.handleEvent(event)
            }
        }
        AppLogger.log("[DashboardViewModel] startListening - completed")
    }

    private func handleEvent(_ event: AgentEvent) async {
        switch event.type {
        case .claudeMessage:
            // NEW: Structured message with content blocks
            // Convert to ChatElements for sophisticated UI
            if case .claudeMessage(let payload) = event.payload {
                let elements = ChatElement.from(payload: payload)
                for element in elements {
                    chatElements.append(element)
                }
                AppLogger.log("[Dashboard] Added \(elements.count) chat elements from claude_message")
            }

        case .claudeLog:
            if let entry = LogEntry.from(event: event) {
                await logCache.add(entry)
                scheduleLogUpdate() // Debounced - prevents UI lag with rapid logs

                // NOTE: Don't convert claude_log to ChatElements
                // claude_log is plain text output - not structured messages
                // ChatElements should only come from claude_message events (structured)
                // The legacy LogListView handles claude_log display properly
            }
            // NOTE: Do NOT update sessionId from log events!
            // Session ID should only come from trusted sources:
            // 1. /api/claude/sessions (loadRecentSessionHistory)
            // 2. User explicit selection via /resume command

        case .claudeStatus:
            if case .claudeStatus(let payload) = event.payload,
               let state = payload.state {
                let previousState = claudeState
                claudeState = state
                if state != .waiting {
                    pendingInteraction = nil
                }

                // NOTE: Do NOT update sessionId from status events!
                // Session ID should only come from trusted sources.

                // When Claude finishes (running -> idle/stopped):
                // 1. Reset hasActiveConversation so next prompt will use resume mode
                // 2. Refresh git status
                if previousState == .running && (state == .idle || state == .stopped) {
                    hasActiveConversation = false
                    AppLogger.log("[Dashboard] Claude stopped - reset hasActiveConversation")
                    await refreshGitStatus()
                }
            }

        case .claudeSessionInfo:
            // Capture session ID from claude_session_info event
            // This is broadcast after Claude starts and gives us the actual session ID
            // We should update userSelectedSessionId so subsequent messages continue this session
            if case .claudeSessionInfo(let payload) = event.payload,
               let sessionId = payload.sessionId, !sessionId.isEmpty {
                AppLogger.log("[Dashboard] Received claude_session_info: \(sessionId)")
                // Update both display and user's selected session (persisted)
                // This ensures subsequent messages use mode=continue with this session_id
                setSelectedSession(sessionId)
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
                scheduleDiffUpdate() // Debounced
            }

        case .fileChanged:
            // Handle file changes per API-REFERENCE.md
            // Change types: created, modified, deleted, renamed
            if case .fileChanged(let payload) = event.payload,
               let path = payload.path,
               let changeType = payload.change {
                AppLogger.log("[Dashboard] File changed: \(path) (\(changeType.rawValue))" +
                              (payload.oldPath != nil ? " from \(payload.oldPath!)" : ""))

                // Update diff cache based on change type
                switch changeType {
                case .deleted:
                    await diffCache.remove(path: path)
                    scheduleDiffUpdate()

                case .renamed:
                    // Remove old path, add new path
                    if let oldPath = payload.oldPath {
                        await diffCache.remove(path: oldPath)
                    }
                    if let entry = DiffEntry.fromFileChanged(event: event) {
                        await diffCache.add(entry)
                    }
                    scheduleDiffUpdate()

                case .created, .modified:
                    if let entry = DiffEntry.fromFileChanged(event: event) {
                        await diffCache.add(entry)
                        scheduleDiffUpdate()
                    }
                }

                // Refresh source control to show the new/changed file in Changes tab
                Task { await sourceControlViewModel.refresh() }

                // Notify Explorer to refresh affected directories
                let directory = (path as NSString).deletingLastPathComponent
                let explorerPath = explorerViewModel.currentPath

                // Check if current Explorer directory is affected
                let isCurrentDirAffected = directory == explorerPath ||
                                           (directory.isEmpty && explorerPath.isEmpty)

                // For renames, also check if old path directory is affected
                let isOldDirAffected: Bool = {
                    guard let oldPath = payload.oldPath else { return false }
                    let oldDir = (oldPath as NSString).deletingLastPathComponent
                    return oldDir == explorerPath || (oldDir.isEmpty && explorerPath.isEmpty)
                }()

                if isCurrentDirAffected || isOldDirAffected {
                    AppLogger.log("[Dashboard] File changed in current Explorer path, refreshing")
                    Task { await explorerViewModel.refresh() }
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

        case .gitStatusChanged:
            // Refresh source control when git status changes
            if case .gitStatusChanged(let payload) = event.payload {
                AppLogger.log("[Dashboard] Git status changed - branch: \(payload.branch ?? "?"), staged: \(payload.stagedCount ?? 0), unstaged: \(payload.unstagedCount ?? 0)")
                // Trigger source control refresh
                Task { await sourceControlViewModel.refresh() }
            }

        case .gitOperationCompleted:
            // Refresh source control after git operations complete
            if case .gitOperationCompleted(let payload) = event.payload {
                let op = payload.operation ?? "unknown"
                let success = payload.success ?? false
                AppLogger.log("[Dashboard] Git operation completed - \(op): \(success ? "success" : "failed")")
                if !success, let error = payload.error {
                    self.error = .commandFailed(reason: "Git \(op) failed: \(error)")
                }
                // Trigger source control refresh
                Task { await sourceControlViewModel.refresh() }
            }

        default:
            break
        }
    }

    /// Update sessionId in agentStatus to maintain context
    private func updateSessionId(_ sessionId: String) {
        guard agentStatus.sessionId != sessionId else { return }
        AppLogger.log("[Dashboard] Setting sessionId: \(sessionId.isEmpty ? "(empty)" : sessionId)")
        agentStatus = AgentStatus(
            claudeState: agentStatus.claudeState,
            sessionId: sessionId,
            repoName: agentStatus.repoName,
            repoPath: agentStatus.repoPath,
            connectedClients: agentStatus.connectedClients,
            uptime: agentStatus.uptime
        )
    }

    /// Set userSelectedSessionId and persist to storage
    /// Also updates the display sessionId in agentStatus
    private func setSelectedSession(_ sessionId: String?) {
        userSelectedSessionId = sessionId
        sessionRepository.selectedSessionId = sessionId

        if let id = sessionId, !id.isEmpty {
            AppLogger.log("[Dashboard] Persisted selectedSessionId: \(id)")
            updateSessionId(id)
        } else {
            AppLogger.log("[Dashboard] Cleared selectedSessionId")
            updateSessionId("")
        }
    }

    // MARK: - Session Validation Helpers

    /// Validate that a sessionId still exists on the server
    /// Returns true if session exists, false if not found or error
    /// Note: Checks up to 100 sessions (should cover recently used sessions)
    private func validateSessionExists(_ sessionId: String) async -> Bool {
        do {
            // Load a larger batch for validation since we need to search
            let sessionsResponse = try await _agentRepository.getSessions(limit: 100, offset: 0)
            let exists = sessionsResponse.sessions.contains { $0.sessionId == sessionId }
            if !exists {
                AppLogger.log("[Dashboard] Session \(sessionId) not found in first 100 sessions (deleted or old)")
            }
            return exists
        } catch {
            AppLogger.error(error, context: "Validate session exists")
            // On error, assume session is invalid to be safe
            return false
        }
    }

    /// Convert ChatMessage to ChatElement for unified rendering
    private func convertChatMessageToElement(_ message: ChatMessage) -> ChatElement? {
        switch message.type {
        case .user:
            return ChatElement.userInput(message.textContent)

        case .assistant:
            // For assistant messages, we need to create multiple elements for different blocks
            // For simplicity, just create one element with the text content
            if !message.textContent.isEmpty {
                return ChatElement.assistantText(message.textContent, model: message.model)
            }
            return nil

        case .system:
            return ChatElement.assistantText(message.textContent)
        }
    }

    /// Get the most recent session ID from the server
    /// Returns the current session if available, otherwise the first session in the list
    private func getMostRecentSessionId() async -> String? {
        do {
            // Just need the first session, so limit to 1
            let sessionsResponse = try await _agentRepository.getSessions(limit: 1, offset: 0)
            AppLogger.log("[Dashboard] getMostRecentSessionId: current=\(sessionsResponse.current ?? "nil"), total=\(sessionsResponse.total ?? 0)")

            // Prefer current session if available
            if let current = sessionsResponse.current, !current.isEmpty {
                return current
            }

            // Otherwise use the most recent from the list
            return sessionsResponse.sessions.first?.sessionId
        } catch {
            AppLogger.error(error, context: "Get most recent session ID")
            return nil
        }
    }

    // MARK: - Workspace Management

    /// Switch to a different workspace
    func switchWorkspace(_ workspace: Workspace) async {
        AppLogger.log("[Dashboard] Switching to workspace: \(workspace.name)")

        // Disconnect current connection
        webSocketService.disconnect()

        // Don't clear data immediately - let new session data replace it
        // This prevents flashing when switching workspaces
        // The loadRecentSessionHistory() will clear when new session loads

        // Clear session tracking so new session will trigger data reload
        userSelectedSessionId = nil
        hasActiveConversation = false

        // Update workspace store
        WorkspaceStore.shared.setActive(workspace)

        // Create connection info from workspace
        let connectionInfo = ConnectionInfo(
            webSocketURL: workspace.webSocketURL,
            httpURL: workspace.httpURL,
            sessionId: workspace.sessionId ?? "",
            repoName: workspace.name
        )

        // Connect to new workspace
        do {
            try await webSocketService.connect(to: connectionInfo)
            await refreshStatus()
        } catch {
            self.error = .connectionFailed(underlying: error)
        }
    }

    /// Disconnect from current workspace
    func disconnect() async {
        AppLogger.log("[Dashboard] Disconnecting from workspace")

        // Disconnect WebSocket
        webSocketService.disconnect()

        // Clear workspace store active
        WorkspaceStore.shared.clearActive()

        // Clear state
        await clearLogsAndDiffs()
        connectionState = .disconnected
        claudeState = .idle
    }

    /// Clear all logs and diffs
    private func clearLogsAndDiffs() async {
        logs = []
        diffs = []
        chatMessages = []
        chatElements = []
        await logCache.clear()
        await diffCache.clear()
    }

    /// Create a PairingViewModel for the pairing sheet
    func makePairingViewModel() -> PairingViewModel? {
        appState?.makePairingViewModel()
    }
}

// MARK: - Tab

enum DashboardTab: String, CaseIterable {
    case logs = "Terminal"
    case diffs = "Changes"
    case explorer = "Explorer"

    var icon: String {
        switch self {
        case .logs: return "terminal"
        case .diffs: return "arrow.triangle.branch"
        case .explorer: return "folder"
        }
    }
}
