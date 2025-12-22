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

    // Streaming Indicator State
    @Published var isStreaming: Bool = false
    @Published var streamingStartTime: Date?

    // Session Watching State
    @Published var isWatchingSession: Bool = false
    @Published var watchingSessionId: String?

    // Force new session flag (set by /new command)
    private var forceNewSession: Bool = false

    // Terminal Search State
    let terminalSearchState = TerminalSearchState()
    private var searchDebounceTask: Task<Void, Never>?
    private var searchStateCancellable: AnyCancellable?

    // Scroll Request (for floating toolkit long-press gesture)
    @Published var scrollRequest: ScrollDirection?

    // Sessions (for /resume command)
    @Published var sessions: [SessionsResponse.SessionInfo] = []
    @Published var showSessionPicker: Bool = false
    @Published var sessionsHasMore: Bool = false
    @Published var isLoadingMoreSessions: Bool = false
    private var sessionsNextOffset: Int = 0
    private let sessionsPageSize: Int = 20

    // Session Messages Pagination
    @Published var messagesHasMore: Bool = false
    @Published var isLoadingMoreMessages: Bool = false
    @Published var messagesTotalCount: Int = 0
    private var messagesNextOffset: Int = 0
    private let messagesPageSize: Int = 20

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

    // Debouncing for chat elements updates (claude_message events)
    private var chatElementsUpdateScheduled = false
    private var pendingChatElements: [ChatElement] = []

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

    // Deduplication for real-time messages
    // O(1) lookup to prevent duplicate elements from multiple sources
    private var seenElementIds: Set<String> = []

    // Memory management: max elements to keep in memory
    // Older elements will be removed when this limit is exceeded
    private let maxChatElements = 500

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

        // Forward search state changes to trigger view re-renders
        // (Nested ObservableObjects don't propagate changes automatically)
        searchStateCancellable = terminalSearchState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        startListening()

        // If already connected, load history (with delay to let UI render first)
        if connectionState.isConnected {
            AppLogger.log("[DashboardViewModel] init - already connected, scheduling history load in 300ms")
            // Use utility priority to avoid blocking UI interactions
            Task(priority: .utility) {
                // Wait for UI to be fully interactive before loading data
                // This prevents hang when user tries to interact during initial load
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

                // Skip if already loaded (e.g., by reconnection handler)
                guard !hasCompletedInitialLoad else {
                    AppLogger.log("[DashboardViewModel] init Task - skipping, already loaded")
                    return
                }

                AppLogger.log("[DashboardViewModel] init Task - starting loadRecentSessionHistory")
                await loadRecentSessionHistory()
                // refreshGitStatus after loadRecentSessionHistory sets hasCompletedInitialLoad
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

    /// Queue chat elements for debounced UI update
    /// Elements are deduplicated and batched before updating the UI
    private func queueChatElements(_ elements: [ChatElement]) {
        // Filter duplicates before adding to pending queue
        for element in elements {
            guard !seenElementIds.contains(element.id) else { continue }
            seenElementIds.insert(element.id)
            pendingChatElements.append(element)
        }

        // Schedule debounced update if not already scheduled
        scheduleChatElementsUpdate()
    }

    /// Schedule a debounced chat elements UI update
    /// Batches rapid claude_message events to prevent UI lag
    private func scheduleChatElementsUpdate() {
        guard !chatElementsUpdateScheduled else { return }
        chatElementsUpdateScheduled = true

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            guard let self = self else { return }

            // Move pending elements to main array
            if !self.pendingChatElements.isEmpty {
                let count = self.pendingChatElements.count
                self.chatElements.append(contentsOf: self.pendingChatElements)
                self.pendingChatElements.removeAll()
                self.trimChatElementsIfNeeded()
                AppLogger.log("[Dashboard] Batched \(count) chat elements (debounced update)")
            }

            self.chatElementsUpdateScheduled = false
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
        // Use content-based ID with sessionId for deduplication with WebSocket events
        let userElement = ChatElement.userInput(userMessage, sessionId: userSelectedSessionId)
        addElementIfNew(userElement)  // Use deduplication method

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
                // 0. If forceNewSession flag is set (from /new command) → start new session
                // 1. If userSelectedSessionId exists → validate against server → if invalid, clear logs and start new
                // 2. If no session selected → fetch sessions list → use most recent if exists
                // 3. If sessions list is empty → start new session

                let mode: SessionMode
                let sessionIdToSend: String?

                if forceNewSession {
                    // User explicitly requested new session via /new command
                    mode = .new
                    sessionIdToSend = nil
                    forceNewSession = false  // Reset flag after use
                    AppLogger.log("[Dashboard] Sending prompt: mode=new (forceNewSession flag)")
                } else if let selectedId = userSelectedSessionId, !selectedId.isEmpty {
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

    /// Load more session messages (infinite scroll)
    func loadMoreMessages() async {
        guard messagesHasMore, !isLoadingMoreMessages else { return }
        guard let sessionId = userSelectedSessionId, !sessionId.isEmpty else { return }

        isLoadingMoreMessages = true
        do {
            let response = try await _agentRepository.getSessionMessages(
                sessionId: sessionId,
                limit: messagesPageSize,
                offset: messagesNextOffset,
                order: "desc"
            )

            // Update pagination state
            messagesHasMore = response.hasMore
            messagesNextOffset = response.nextOffset

            AppLogger.log("[Dashboard] Loaded more messages: +\(response.count), offset=\(messagesNextOffset), hasMore=\(messagesHasMore)")

            // Prepend older messages (API returns desc, so higher offset = older messages)
            // Reverse to get chronological order, then prepend to existing messages
            var newElements: [ChatElement] = []
            // Track new IDs locally (we prepend, so can't use addElementIfNew)
            var seenNewIds = Set<String>()
            // Track Edit tool IDs to filter their tool_results
            var editToolIds: Set<String> = []

            for message in response.messages.reversed() {
                if let entry = LogEntry.from(sessionMessage: message, sessionId: sessionId) {
                    await logCache.add(entry)
                }

                // Check for context compaction messages
                if message.isContextCompaction == true {
                    // Create context compaction element instead of regular element
                    // Only for user messages with the summary (not system messages)
                    if message.type == "user" {
                        let summary = message.textContent
                        let element = ChatElement.contextCompaction(summary: summary)
                        // Check both instance set and local set
                        if !seenElementIds.contains(element.id) && !seenNewIds.contains(element.id) {
                            seenNewIds.insert(element.id)
                            newElements.append(element)
                        }
                    }
                    // Skip system compaction messages (they just mark the boundary)
                    continue
                }

                // Use new factory that properly handles Edit tools as diff views
                let (elements, newEditToolIds) = ChatElement.from(sessionMessage: message)
                editToolIds.formUnion(newEditToolIds)

                // Filter out Edit tool_results and duplicates
                for element in elements {
                    // Skip Edit tool results (already shown as diff)
                    if case .toolResult(let content) = element.content {
                        if editToolIds.contains(content.toolCallId) {
                            continue
                        }
                    }

                    if !seenElementIds.contains(element.id) && !seenNewIds.contains(element.id) {
                        seenNewIds.insert(element.id)
                        newElements.append(element)
                    }
                }
            }
            // Add new IDs to instance set for future deduplication
            seenElementIds.formUnion(seenNewIds)
            chatElements.insert(contentsOf: newElements, at: 0)
            await forceLogUpdate()
        } catch {
            AppLogger.error(error, context: "Load more messages")
        }
        isLoadingMoreMessages = false
    }

    /// Resume a specific session (user explicitly selected)
    func resumeSession(_ sessionId: String) async {
        showSessionPicker = false
        isLoading = true
        Haptics.medium()

        // Stop watching previous session
        await stopWatchingSession()

        // Clear current logs and elements
        await logCache.clear()
        logs = []
        chatElements = []
        seenElementIds.removeAll()  // Clear deduplication set

        // Reset pagination state
        messagesNextOffset = 0
        messagesHasMore = false
        messagesTotalCount = 0

        // Update sessionId - this is a TRUSTED source (user explicit selection)
        setSelectedSession(sessionId)
        hasActiveConversation = false  // Reset - will be set true on first prompt
        AppLogger.log("[Dashboard] User resumed session: \(sessionId)")

        // Load first page of session messages
        do {
            let messagesResponse = try await _agentRepository.getSessionMessages(
                sessionId: sessionId,
                limit: messagesPageSize,
                offset: 0,
                order: "desc"
            )

            // Update pagination state
            messagesHasMore = messagesResponse.hasMore
            messagesNextOffset = messagesResponse.nextOffset
            messagesTotalCount = messagesResponse.total

            AppLogger.log("[Dashboard] Loaded \(messagesResponse.count) of \(messagesResponse.total) messages, hasMore=\(messagesResponse.hasMore)")

            // Track Edit tool IDs to filter their tool_results (shown as diff instead)
            var editToolIds: Set<String> = []

            // Reverse messages since API returns desc (newest first) but UI shows oldest at top
            // Use instance seenElementIds (already cleared above)
            for message in messagesResponse.messages.reversed() {
                if let entry = LogEntry.from(sessionMessage: message, sessionId: sessionId) {
                    await logCache.add(entry)
                }

                // Check for context compaction messages
                if message.isContextCompaction == true {
                    // Create context compaction element instead of regular element
                    // Only for user messages with the summary (not system messages)
                    if message.type == "user" {
                        let summary = message.textContent
                        let element = ChatElement.contextCompaction(summary: summary)
                        addElementIfNew(element)
                    }
                    // Skip system compaction messages (they just mark the boundary)
                    continue
                }

                // Use new factory that properly handles Edit tools as diff views
                let (elements, newEditToolIds) = ChatElement.from(sessionMessage: message)
                editToolIds.formUnion(newEditToolIds)

                // Filter out tool_results that correspond to Edit tools (already shown as diff)
                let filteredElements = elements.filter { element in
                    if case .toolResult(let content) = element.content {
                        // Filter out Edit tool results
                        return !editToolIds.contains(content.toolCallId)
                    }
                    return true
                }

                addElementsIfNew(filteredElements)
            }
            await forceLogUpdate()

            // Start watching this session for real-time updates
            await startWatchingCurrentSession()

            Haptics.success()
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
            Haptics.error()
        }

        isLoading = false
    }

    /// Start a new session (clear current context)
    func startNewSession() async {
        // Stop watching current session
        await stopWatchingSession()

        // Clear logs, elements, and session state
        await logCache.clear()
        logs = []
        chatElements = []
        seenElementIds.removeAll()
        setSelectedSession(nil)
        hasActiveConversation = false
        forceNewSession = true  // Ensure next prompt uses mode: "new"
        AppLogger.log("[Dashboard] Started new session - cleared session state, forceNewSession=true")

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
        // Stop watching current session
        await stopWatchingSession()

        await logCache.clear()
        logs = []
        chatElements = []
        seenElementIds.removeAll()
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
        // Refresh source control view (this fetches git status)
        await sourceControlViewModel.refresh()

        // Update legacy diff cache from sourceControlViewModel state (no extra API call)
        await diffCache.clear()
        let allFiles = sourceControlViewModel.state.stagedFiles + sourceControlViewModel.state.allUnstagedFiles
        for file in allFiles {
            let entry = DiffEntry(
                id: file.id,
                filePath: file.path,
                diff: file.diff,
                additions: file.additions,
                deletions: file.deletions,
                changeType: FileChangeType(rawValue: file.status.rawValue)
            )
            await diffCache.add(entry)
        }
        await forceDiffUpdate()
    }

    /// Clear logs and chat elements
    func clearLogs() async {
        await logCache.clear()
        logs = []
        chatElements = []
        seenElementIds.removeAll()
        // Reset pagination so next load starts from beginning
        messagesNextOffset = 0
        messagesHasMore = true  // Allow loading again
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
                seenElementIds.removeAll()  // Clear deduplication set
                // Reset pagination state
                messagesNextOffset = 0
                messagesHasMore = false
                messagesTotalCount = 0
                AppLogger.log("[Dashboard] Cleared data for new session")
            } else if !chatElements.isEmpty {
                // Same session and already have data - skip reloading to prevent duplicates
                AppLogger.log("[Dashboard] Same session with \(chatElements.count) elements - skipping reload")
                // Still start watching if not already
                await startWatchingCurrentSession()
                return
            } else {
                AppLogger.log("[Dashboard] Same session but empty - loading data")
            }

            // Store sessionId - this is a TRUSTED source (from sessions API)
            setSelectedSession(sessionId)
            hasActiveConversation = false  // Reset - will be set true on first prompt
            AppLogger.log("[Dashboard] Set userSelectedSessionId: \(sessionId)")

            // Yield to let UI thread breathe before network call
            await Task.yield()

            // Get first page of messages for the session
            AppLogger.log("[Dashboard] Fetching messages for session: \(sessionId)")
            let messagesResponse: SessionMessagesResponse
            do {
                messagesResponse = try await _agentRepository.getSessionMessages(
                    sessionId: sessionId,
                    limit: messagesPageSize,
                    offset: 0,
                    order: "desc"
                )

                // Update pagination state
                messagesHasMore = messagesResponse.hasMore
                messagesNextOffset = messagesResponse.nextOffset
                messagesTotalCount = messagesResponse.total

                AppLogger.log("[Dashboard] Got \(messagesResponse.count) of \(messagesResponse.total) messages, hasMore=\(messagesResponse.hasMore)")
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
            // Reverse messages since API returns desc (newest first) but UI shows oldest at top
            let chronologicalMessages = Array(messagesResponse.messages.reversed())
            var entriesAdded = 0
            // Track Edit tool IDs to filter their tool_results
            var editToolIds: Set<String> = []
            // Use instance seenElementIds (already cleared above for new session)
            for (index, message) in chronologicalMessages.enumerated() {
                if let entry = LogEntry.from(sessionMessage: message, sessionId: sessionId) {
                    await logCache.add(entry)
                    entriesAdded += 1
                }

                // Check for context compaction messages
                if message.isContextCompaction == true {
                    // Create context compaction element instead of regular element
                    // Only for user messages with the summary (not system messages)
                    if message.type == "user" {
                        let summary = message.textContent
                        let element = ChatElement.contextCompaction(summary: summary)
                        addElementIfNew(element)
                    }
                    // Skip system compaction messages (they just mark the boundary)
                    continue
                }

                // Use new factory that properly handles Edit tools as diff views
                let (elements, newEditToolIds) = ChatElement.from(sessionMessage: message)
                editToolIds.formUnion(newEditToolIds)

                // Log first few messages for debugging duplicate issue
                if index < 3 {
                    AppLogger.log("[Dashboard] History msg[\(index)] - uuid: \(message.uuid ?? "nil"), computed id: \(message.id)")
                    AppLogger.log("[Dashboard] History msg[\(index)] - element IDs: \(elements.map { $0.id })")
                }

                // Filter out Edit tool_results (already shown as diff) and add remaining
                let filteredElements = elements.filter { element in
                    if case .toolResult(let content) = element.content {
                        return !editToolIds.contains(content.toolCallId)
                    }
                    return true
                }
                addElementsIfNew(filteredElements)

                // Yield every 10 messages to prevent UI starvation
                if index > 0 && index % 10 == 0 {
                    await Task.yield()
                }
            }
            AppLogger.log("[Dashboard] Created \(entriesAdded) log entries and \(chatElements.count) elements from \(messagesResponse.count) messages (deduplicated)")

            // Update logs array
            await forceLogUpdate()

            // Start watching this session for real-time updates
            await startWatchingCurrentSession()

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

                // Handle reconnection - re-establish session watch and reload data
                if !wasConnected && state.isConnected {
                    AppLogger.log("[Dashboard] Reconnected - loading data in 300ms")
                    // Delay to let UI settle after connection state change
                    // This prevents hang when user tries to interact during load
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    AppLogger.log("[Dashboard] Reconnected - starting loadRecentSessionHistory")
                    await self.loadRecentSessionHistory()
                    // refreshStatus() calls refreshGitStatus() internally when hasCompletedInitialLoad is true
                    AppLogger.log("[Dashboard] Reconnected - starting refreshStatus (includes git status)")
                    await self.refreshStatus()

                    // Re-establish session watch for live mode
                    // Use userSelectedSessionId or agentStatus.sessionId
                    let sessionToWatch = self.userSelectedSessionId ?? self.agentStatus.sessionId
                    AppLogger.log("[Dashboard] Reconnected - checking session watch: userSelectedSessionId=\(self.userSelectedSessionId ?? "nil"), agentStatus.sessionId=\(self.agentStatus.sessionId ?? "nil")")
                    if let sessionId = sessionToWatch, !sessionId.isEmpty {
                        AppLogger.log("[Dashboard] Reconnected - re-establishing session watch for: \(sessionId)")
                        self.isWatchingSession = false  // Reset so watch can be re-established
                        self.watchingSessionId = nil
                        // Set userSelectedSessionId if not set
                        if self.userSelectedSessionId == nil {
                            self.userSelectedSessionId = sessionId
                        }
                        await self.startWatchingCurrentSession()
                    } else {
                        AppLogger.log("[Dashboard] Reconnected - no session to watch")
                    }

                    AppLogger.log("[Dashboard] Reconnected - load completed")
                }

                // Reset watching state on disconnect
                if wasConnected && !state.isConnected {
                    AppLogger.log("[Dashboard] Disconnected - resetting watch state")
                    self.isWatchingSession = false
                    self.watchingSessionId = nil
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
                AppLogger.log("[Dashboard] claude_message received - uuid: \(payload.uuid ?? "nil"), role: \(payload.effectiveRole ?? "nil")")

                // Skip user message echoes from real-time events (already shown optimistically)
                // User messages are only needed when loading session history, not from WebSocket
                if payload.effectiveRole == "user" {
                    AppLogger.log("[Dashboard] Skipping user message echo from WebSocket")
                    return
                }

                let elements = ChatElement.from(payload: payload)

                // Queue elements for debounced UI update (batches rapid events)
                if !elements.isEmpty {
                    queueChatElements(elements)
                }

                // Update streaming indicator state
                // isStreaming when: stopReason is empty/nil AND content contains thinking
                let hasThinking = payload.effectiveContent?.containsThinking == true
                let isStillStreaming = (payload.stopReason == nil || payload.stopReason?.isEmpty == true) && hasThinking

                if isStillStreaming && !isStreaming {
                    // Started streaming
                    isStreaming = true
                    streamingStartTime = Date()
                    AppLogger.log("[Dashboard] Streaming started (thinking)")
                } else if !isStillStreaming && isStreaming {
                    // Stopped streaming
                    isStreaming = false
                    if let startTime = streamingStartTime {
                        let duration = Date().timeIntervalSince(startTime)
                        AppLogger.log("[Dashboard] Streaming stopped after \(String(format: "%.1f", duration))s")
                    }
                    streamingStartTime = nil
                }
            }

        case .claudeLog:
            // claude_log is used ONLY for extracting session_id from system/init events
            // Content display uses claude_message events (structured format)
            if case .claudeLog(let payload) = event.payload {
                // Check for session initialization event (new session started)
                if let parsed = payload.parsed,
                   parsed.isSessionInit,
                   let newSessionId = parsed.sessionId,
                   !newSessionId.isEmpty {
                    AppLogger.log("[Dashboard] claude_log system/init - new session_id: \(newSessionId)")

                    // Update selected session and persist
                    setSelectedSession(newSessionId)
                    hasActiveConversation = true

                    // Start watching this new session for real-time updates
                    await startWatchingCurrentSession()
                }
                // Ignore all other claude_log content (claude_message handles UI)
            }

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
                // 3. Clear streaming indicator
                if previousState == .running && (state == .idle || state == .stopped) {
                    hasActiveConversation = false
                    isStreaming = false
                    streamingStartTime = nil
                    AppLogger.log("[Dashboard] Claude stopped - reset hasActiveConversation and streaming")
                    // Note: Don't refresh git status here - file_changed events will handle it
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
            // Log git status changed event (for debugging)
            // Note: Don't refresh here - file_changed events already trigger refresh
            if case .gitStatusChanged(let payload) = event.payload {
                AppLogger.log("[Dashboard] Git status changed - branch: \(payload.branch ?? "?"), staged: \(payload.stagedCount ?? 0), unstaged: \(payload.unstagedCount ?? 0)")
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

        case .sessionWatchStarted:
            // Server confirmed we're watching a session
            if case .sessionWatch(let payload) = event.payload,
               let sessionId = payload.sessionId {
                isWatchingSession = true
                watchingSessionId = sessionId
                AppLogger.log("[Dashboard] Session watch confirmed: \(sessionId)")
            }

        case .sessionWatchStopped:
            // Server says we're no longer watching
            if case .sessionWatch(let payload) = event.payload {
                let reason = payload.reason ?? "unknown"
                isWatchingSession = false
                watchingSessionId = nil
                AppLogger.log("[Dashboard] Session watch stopped: \(reason)")
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

    /// Convert ChatMessage to ChatElements for unified rendering
    /// Returns multiple elements for messages with tool_use/tool_result blocks
    private func convertChatMessageToElements(_ message: ChatMessage) -> [ChatElement] {
        var elements: [ChatElement] = []

        switch message.type {
        case .user:
            // User messages may have text or tool_result content
            for (index, block) in message.contentBlocks.enumerated() {
                switch block.type {
                case .text:
                    if !block.content.isEmpty {
                        // Use message ID + index for unique ID
                        let uniqueId = "\(message.id)-text-\(index)"
                        elements.append(ChatElement(
                            id: uniqueId,
                            type: .userInput,
                            timestamp: message.timestamp,
                            content: .userInput(UserInputContent(text: block.content))
                        ))
                    }
                case .toolResult:
                    // Tool result from user message (command output)
                    // Skip empty tool results
                    guard !block.content.isEmpty else { continue }
                    let lines = block.content.components(separatedBy: "\n")
                    let summary = lines.prefix(3).joined(separator: "\n")
                    // Use block.id + "_result" suffix to avoid collision with tool_use
                    let uniqueId = "\(block.id)-result"
                    elements.append(ChatElement(
                        id: uniqueId,
                        type: .toolResult,
                        timestamp: message.timestamp,
                        content: .toolResult(ToolResultContent(
                            toolCallId: block.id,
                            toolName: block.toolName ?? "",
                            isError: block.isError,
                            summary: summary,
                            fullContent: block.content
                        ))
                    ))
                default:
                    break
                }
            }

        case .assistant:
            // Assistant messages may have text, tool_use, or thinking blocks
            for (index, block) in message.contentBlocks.enumerated() {
                switch block.type {
                case .text:
                    if !block.content.isEmpty {
                        // Use message ID + index for unique ID
                        let uniqueId = "\(message.id)-text-\(index)"
                        elements.append(ChatElement(
                            id: uniqueId,
                            type: .assistantText,
                            timestamp: message.timestamp,
                            content: .assistantText(AssistantTextContent(text: block.content, model: message.model))
                        ))
                    }
                case .toolUse:
                    // Tool call from assistant - parse input params
                    let toolName = block.toolName ?? "tool"
                    var params: [String: String] = [:]
                    if let inputStr = block.toolInput {
                        // Parse "key: value\nkey2: value2" format
                        for line in inputStr.components(separatedBy: "\n") {
                            let parts = line.split(separator: ":", maxSplits: 1)
                            if parts.count == 2 {
                                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                                params[key] = value
                            }
                        }
                    }
                    let display = formatToolCallDisplay(tool: toolName, params: params)
                    // Use block.id directly for tool_use (it's unique)
                    elements.append(ChatElement(
                        id: block.id,
                        type: .toolCall,
                        timestamp: message.timestamp,
                        content: .toolCall(ToolCallContent(
                            tool: toolName,
                            toolId: block.id,
                            display: display,
                            params: params,
                            status: .completed
                        ))
                    ))
                case .thinking:
                    if !block.content.isEmpty {
                        // Use message ID + index for unique ID
                        let uniqueId = "\(message.id)-thinking-\(index)"
                        elements.append(ChatElement(
                            id: uniqueId,
                            type: .thinking,
                            timestamp: message.timestamp,
                            content: .thinking(ThinkingContent(text: block.content))
                        ))
                    }
                default:
                    break
                }
            }

        case .system:
            if !message.textContent.isEmpty {
                elements.append(ChatElement.assistantText(message.textContent))
            }
        }

        return elements
    }

    /// Format tool call display string from params dictionary
    private func formatToolCallDisplay(tool: String, params: [String: String]) -> String {
        // Priority: command > file_path > pattern > other params
        if tool == "Bash", let cmd = params["command"] {
            return cmd
        } else if ["Read", "Write", "Edit"].contains(tool), let path = params["file_path"] {
            return path
        } else if ["Glob", "Grep"].contains(tool), let pattern = params["pattern"] {
            return "pattern: \"\(pattern)\""
        }

        // Fallback: show first param value
        if let firstValue = params.values.first {
            return firstValue.count > 60 ? String(firstValue.prefix(60)) + "..." : firstValue
        }

        return ""
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

    // MARK: - Terminal Search

    /// Perform search with debounce
    func performSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            // Debounce: 150ms delay
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            let searchText = terminalSearchState.searchText
            let filters = terminalSearchState.activeFilters

            // Find matching elements
            let matchingIds = chatElements
                .filter { $0.matches(searchText: searchText, filters: filters) }
                .map { $0.id }

            terminalSearchState.matchingElementIds = matchingIds
            terminalSearchState.currentMatchIndex = 0

            AppLogger.log("[Search] Found \(matchingIds.count) matches for '\(searchText)' with \(filters.count) filters")
        }
    }

    /// Scroll to current search match
    func scrollToCurrentMatch() -> String? {
        return terminalSearchState.currentMatchId
    }

    /// Request scroll to top or bottom (triggered by floating toolkit long-press)
    func requestScroll(direction: ScrollDirection) {
        scrollRequest = direction
        // Auto-reset after a short delay (the view will observe and handle it)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            scrollRequest = nil
        }
    }

    // MARK: - Session Watching

    /// Start watching the currently selected session for real-time updates
    /// Called automatically when session is loaded or resumed
    func startWatchingCurrentSession() async {
        guard let sessionId = userSelectedSessionId, !sessionId.isEmpty else {
            AppLogger.log("[Dashboard] No session to watch")
            return
        }

        // Already watching this session?
        if isWatchingSession && watchingSessionId == sessionId {
            AppLogger.log("[Dashboard] Already watching session: \(sessionId)")
            return
        }

        // Must be connected
        guard connectionState.isConnected else {
            AppLogger.log("[Dashboard] Cannot watch session - not connected")
            return
        }

        do {
            try await webSocketService.watchSession(sessionId)
            // JSON-RPC response confirms watching - set state immediately
            isWatchingSession = true
            watchingSessionId = sessionId
            AppLogger.log("[Dashboard] Now watching session: \(sessionId)")
        } catch {
            AppLogger.error(error, context: "Watch session")
        }
    }

    /// Stop watching the current session
    func stopWatchingSession() async {
        guard isWatchingSession else { return }

        do {
            try await webSocketService.unwatchSession()
            isWatchingSession = false
            watchingSessionId = nil
            AppLogger.log("[Dashboard] Stopped watching session")
        } catch {
            // Still clear local state even if command fails
            isWatchingSession = false
            watchingSessionId = nil
            AppLogger.error(error, context: "Unwatch session")
        }
    }

    /// Trim chat elements to prevent memory bloat
    /// Removes oldest elements when exceeding maxChatElements
    private func trimChatElementsIfNeeded() {
        guard chatElements.count > maxChatElements else { return }

        let removeCount = chatElements.count - maxChatElements
        let removedElements = Array(chatElements.prefix(removeCount))

        // Remove from deduplication set
        for element in removedElements {
            seenElementIds.remove(element.id)
        }

        // Remove from array
        chatElements.removeFirst(removeCount)
        AppLogger.log("[Dashboard] Trimmed \(removeCount) old elements (memory management)")
    }

    /// Add element with deduplication check
    /// Returns true if element was added, false if duplicate
    @discardableResult
    private func addElementIfNew(_ element: ChatElement) -> Bool {
        guard !seenElementIds.contains(element.id) else {
            return false
        }

        seenElementIds.insert(element.id)
        chatElements.append(element)
        trimChatElementsIfNeeded()
        return true
    }

    /// Add multiple elements with deduplication
    /// Returns count of elements actually added
    @discardableResult
    private func addElementsIfNew(_ elements: [ChatElement]) -> Int {
        var addedCount = 0
        for element in elements {
            if addElementIfNew(element) {
                addedCount += 1
            }
        }
        return addedCount
    }

    // MARK: - Workspace Management

    /// Switch to a different workspace
    func switchWorkspace(_ workspace: Workspace) async {
        AppLogger.log("[Dashboard] Switching to workspace: \(workspace.name)")

        // Stop watching and disconnect
        await stopWatchingSession()
        webSocketService.disconnect()

        // Don't clear data immediately - let new session data replace it
        // This prevents flashing when switching workspaces
        // The loadRecentSessionHistory() will clear when new session loads

        // Clear session tracking so new session will trigger data reload
        userSelectedSessionId = nil
        hasActiveConversation = false
        seenElementIds.removeAll()

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

        // Stop watching and disconnect
        await stopWatchingSession()
        webSocketService.disconnect()

        // Clear workspace store active
        WorkspaceStore.shared.clearActive()

        // Clear state
        await clearLogsAndDiffs()
        seenElementIds.removeAll()
        connectionState = .disconnected
        claudeState = .idle
    }

    /// Retry connection to the last active workspace
    func retryConnection() async {
        AppLogger.log("[Dashboard] Retrying connection")

        // Get the active workspace and try to reconnect
        if let workspace = WorkspaceStore.shared.activeWorkspace {
            let connectionInfo = ConnectionInfo(
                webSocketURL: workspace.webSocketURL,
                httpURL: workspace.httpURL,
                sessionId: workspace.sessionId ?? "",
                repoName: workspace.name
            )
            do {
                try await webSocketService.connect(to: connectionInfo)
                AppLogger.log("[Dashboard] Retry connection successful")
            } catch {
                AppLogger.error(error, context: "Retry connection")
                self.error = .connectionFailed(underlying: error)
            }
        } else {
            AppLogger.log("[Dashboard] No active workspace to retry connection")
        }
    }

    /// Cancel ongoing connection attempt
    func cancelConnection() {
        AppLogger.log("[Dashboard] Cancelling connection")
        webSocketService.disconnect()
    }

    /// Clear all logs and diffs
    private func clearLogsAndDiffs() async {
        logs = []
        diffs = []
        chatMessages = []
        chatElements = []
        seenElementIds.removeAll()
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
