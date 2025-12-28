import Foundation
import Combine

/// Main dashboard view model - central hub for all agent interactions
@MainActor
final class DashboardViewModel: ObservableObject {
    // MARK: - Published State

    // Connection
    @Published var connectionState: ConnectionState = .disconnected {
        didSet {
            #if DEBUG
            if oldValue != connectionState {
                AppLogger.log("[DashboardVM] connectionState: \(oldValue) → \(connectionState)")
            }
            #endif
        }
    }
    @Published var agentStatus: AgentStatus = AgentStatus()

    // Claude
    @Published var claudeState: ClaudeState = .idle {
        didSet {
            #if DEBUG
            if oldValue != claudeState {
                AppLogger.log("[DashboardVM] claudeState: \(oldValue) → \(claudeState)")
            }
            #endif
        }
    }
    @Published var pendingInteraction: PendingInteraction?

    // Logs & Diffs
    @Published var logs: [LogEntry] = []
    @Published var diffs: [DiffEntry] = []
    @Published var selectedTab: DashboardTab = .logs {
        didSet {
            #if DEBUG
            if oldValue != selectedTab {
                AppLogger.log("[DashboardVM] selectedTab: \(oldValue) → \(selectedTab)")
            }
            #endif
        }
    }

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
    @Published var isBashMode: Bool = false  // Persistent bash mode toggle
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var showPromptSheet: Bool = false

    // Streaming Indicator State
    @Published var isStreaming: Bool = false
    @Published var streamingStartTime: Date?
    @Published var spinnerMessage: String?  // Message from pty_spinner events (e.g., "Vibing…")

    // Session Watching State
    @Published var isWatchingSession: Bool = false
    @Published var watchingSessionId: String?

    // Interactive PTY Mode (always true since we use permission_mode: "interactive")
    // When in interactive mode, skip claude_log processing and use pty_* events instead
    @Published var isInteractiveMode: Bool = true

    // Trust folder pending state - when true, session APIs (watch/messages) should be skipped
    // because the session doesn't exist in .claude/projects/ until user approves trust
    @Published var isPendingTrustFolder: Bool = false

    // Pending temp session state - when true, we have a temporary session ID from session/start
    // but haven't received session_id_resolved yet. Don't show temp ID in UI until resolved.
    @Published var isPendingTempSession: Bool = false

    // Navigation signal - when true, the view should show the workspace list
    // Set when session_id_failed is received to allow user to pick a different workspace
    @Published var shouldShowWorkspaceList: Bool = false

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

    // Workspace-aware APIs
    private let workspaceManager = WorkspaceManagerService.shared
    private let workspaceStore = WorkspaceStore.shared

    /// Get the current workspace ID if available
    var currentWorkspaceId: String? {
        workspaceStore.activeWorkspace?.remoteWorkspaceId
    }

    private var eventTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    // Debouncing for log updates to prevent UI lag
    private var logUpdateScheduled = false
    private var diffUpdateScheduled = false

    // Debouncing for chat elements updates (claude_message events)
    private var chatElementsUpdateScheduled = false
    private var pendingChatElements: [ChatElement] = []

    // Task tracking for agent tasks (Plan, Explore, etc.)
    private var activeTasks: [String: TaskContent] = [:]  // taskId -> TaskContent
    private var taskGroups: [String: [String]] = [:]  // agentType -> [taskIds]

    // Prevent duplicate initial loads
    private var isInitialLoadInProgress = false
    private var hasCompletedInitialLoad = false

    // Prevent duplicate reconnection loads
    private var isReconnectionInProgress = false

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

    // Track prompts sent by THIS client to deduplicate only our own echoes
    // Hashes are kept for a few seconds to handle duplicate server echoes
    // After timeout, they're cleaned up to allow repeated commands
    private var sentPromptHashes: [String: Date] = [:]
    private let sentPromptTimeout: TimeInterval = 5  // Keep for 5 seconds to handle server duplicates

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

        // Load persisted bash mode state
        self.isBashMode = UserDefaults.standard.bool(forKey: "dashboardBashMode")

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

                // Sync workspace IDs first - this enables workspace-aware APIs
                AppLogger.log("[DashboardViewModel] init Task - syncing workspace IDs")
                _ = try? await WorkspaceManagerService.shared.listWorkspaces()

                // Check for pending trust_folder permission that arrived before Dashboard was ready
                if let pendingEvent = webSocketService.consumePendingTrustFolderPermission() {
                    AppLogger.log("[DashboardViewModel] init Task - found pending trust_folder permission")
                    await handleEvent(pendingEvent)
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
        searchDebounceTask?.cancel()
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
    /// Tasks are tracked and grouped by agent type
    private func queueChatElements(_ elements: [ChatElement]) {
        // Filter duplicates and process tasks
        for element in elements {
            guard !seenElementIds.contains(element.id) else { continue }
            seenElementIds.insert(element.id)

            // Handle task tracking
            if case .task(let taskContent) = element.content {
                // Track this task
                activeTasks[taskContent.id] = taskContent

                // Add to agent type group
                if taskGroups[taskContent.agentType] == nil {
                    taskGroups[taskContent.agentType] = []
                }
                taskGroups[taskContent.agentType]?.append(taskContent.id)

                AppLogger.log("[Task] Tracking task: \(taskContent.id) (\(taskContent.agentType))")
            }
            // Handle tool_result that might update a task
            else if case .toolResult(let toolResult) = element.content {
                // Check if this is a result for a Task
                if let task = activeTasks[toolResult.toolCallId] {
                    // Extract metadata from result
                    let (agentId, toolUses) = extractTaskMetadata(from: toolResult.fullContent)

                    // Update task
                    var updatedTask = task
                    updatedTask.status = toolResult.isError ? .failed : .completed
                    updatedTask.agentId = agentId
                    updatedTask.toolUses = toolUses

                    activeTasks[updatedTask.id] = updatedTask

                    AppLogger.log("[Task] Updated task \(updatedTask.id): status=\(updatedTask.status), toolUses=\(toolUses ?? 0)")

                    // Don't queue the tool_result - it's absorbed into the task
                    continue
                }
            }

            pendingChatElements.append(element)
        }

        // Schedule debounced update if not already scheduled
        scheduleChatElementsUpdate()
    }

    /// Schedule a debounced chat elements UI update
    /// Batches rapid claude_message events to prevent UI lag
    /// Groups consecutive tasks by agent type
    private func scheduleChatElementsUpdate() {
        guard !chatElementsUpdateScheduled else { return }
        chatElementsUpdateScheduled = true

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            guard let self = self else { return }

            // Group tasks before adding to main array
            if !self.pendingChatElements.isEmpty {
                let grouped = self.groupConsecutiveTasks(self.pendingChatElements)
                let count = grouped.count
                self.chatElements.append(contentsOf: grouped)
                self.pendingChatElements.removeAll()
                self.trimChatElementsIfNeeded()
                AppLogger.log("[Dashboard] Batched \(count) chat elements (debounced update)")
            }

            self.chatElementsUpdateScheduled = false
        }
    }

    /// Group consecutive task elements by agent type
    /// Creates TaskGroupContent for consecutive tasks of the same type
    private func groupConsecutiveTasks(_ elements: [ChatElement]) -> [ChatElement] {
        var result: [ChatElement] = []
        var currentTaskGroup: [TaskContent] = []
        var currentAgentType: String?

        for element in elements {
            if case .task(let taskContent) = element.content {
                // Get latest task state from tracking
                let latestTask = activeTasks[taskContent.id] ?? taskContent

                // Check if this belongs to current group
                if let agentType = currentAgentType, agentType == latestTask.agentType {
                    // Same type - add to group
                    currentTaskGroup.append(latestTask)
                } else {
                    // Different type - flush current group
                    if !currentTaskGroup.isEmpty, let agentType = currentAgentType {
                        result.append(createTaskGroupElement(agentType: agentType, tasks: currentTaskGroup))
                    }
                    // Start new group
                    currentTaskGroup = [latestTask]
                    currentAgentType = latestTask.agentType
                }
            } else {
                // Non-task element - flush current group
                if !currentTaskGroup.isEmpty, let agentType = currentAgentType {
                    result.append(createTaskGroupElement(agentType: agentType, tasks: currentTaskGroup))
                    currentTaskGroup = []
                    currentAgentType = nil
                }
                // Add non-task element
                result.append(element)
            }
        }

        // Flush remaining group
        if !currentTaskGroup.isEmpty, let agentType = currentAgentType {
            result.append(createTaskGroupElement(agentType: agentType, tasks: currentTaskGroup))
        }

        return result
    }

    /// Create a task group element
    private func createTaskGroupElement(agentType: String, tasks: [TaskContent]) -> ChatElement {
        // If only one task, return it as standalone
        if tasks.count == 1 {
            return ChatElement(
                id: tasks[0].id,
                type: .task,
                content: .task(tasks[0])
            )
        }

        // Multiple tasks - create group
        let groupId = "taskgroup-\(agentType)-\(tasks.map { $0.id }.joined())"
        return ChatElement(
            id: groupId,
            type: .taskGroup,
            content: .taskGroup(TaskGroupContent(
                agentType: agentType,
                tasks: tasks,
                isExpanded: false
            ))
        )
    }

    /// Extract task metadata from tool_result content
    /// Returns (agentId, toolUses)
    private func extractTaskMetadata(from content: String) -> (String?, Int?) {
        var agentId: String?
        var toolUses: Int?

        // Extract agentId using regex: "agentId: xxxxx"
        if let agentIdMatch = content.range(of: #"agentId:\s*([a-f0-9]+)"#, options: .regularExpression) {
            let matchedText = String(content[agentIdMatch])
            agentId = matchedText.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
        }

        // Extract tool uses by counting "tool_use" occurrences or finding explicit count
        // Look for patterns like "10 tool uses" or "17 tool uses"
        if let toolUsesMatch = content.range(of: #"(\d+)\s+tool\s+use"#, options: .regularExpression) {
            let matchedText = String(content[toolUsesMatch])
            if let number = Int(matchedText.components(separatedBy: " ").first ?? "") {
                toolUses = number
            }
        }

        return (agentId, toolUses)
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

        var userMessage = promptText
        promptText = "" // Clear immediately for fast UX

        // Check for built-in commands FIRST (before bash mode prefix)
        // Slash commands like /resume, /clear, /new should work regardless of bash mode
        if userMessage.hasPrefix("/") {
            await handleCommand(userMessage)
            return
        }

        // Bash mode handling: Auto-detect or apply mode
        // 1. If user types ! in normal mode → auto-enable bash mode
        // 2. If in bash mode → add ! prefix (unless already present)
        if userMessage.hasPrefix("!") && !isBashMode {
            // Auto-enable bash mode when user types ! in normal mode
            isBashMode = true
            UserDefaults.standard.set(true, forKey: "dashboardBashMode")
            Haptics.light()
            // Remove ! prefix since we'll track it's a bash command
            userMessage = String(userMessage.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Apply bash mode prefix if enabled
        if isBashMode && !userMessage.hasPrefix("!") {
            userMessage = "!" + userMessage
        }

        // Track this prompt to deduplicate our own echo later
        let promptHash = hashPrompt(userMessage)
        sentPromptHashes[promptHash] = Date()
        cleanupExpiredPromptHashes()
        AppLogger.log("[Dashboard] Tracking sent prompt - hash: \(promptHash), text: '\(userMessage)'")

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

    /// Toggle bash mode on/off with haptic feedback and persistence
    func toggleBashMode() {
        isBashMode.toggle()
        UserDefaults.standard.set(isBashMode, forKey: "dashboardBashMode")
        Haptics.selection()
        AppLogger.log("[Dashboard] Bash mode toggled: \(isBashMode ? "ON" : "OFF")")
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
    /// Uses workspace-aware session/history API when available
    func loadSessions() async {
        do {
            // Reset pagination state
            sessionsNextOffset = 0

            // Workspace ID is required for session APIs
            guard let workspaceId = currentWorkspaceId else {
                AppLogger.log("[Dashboard] Cannot load sessions - no workspace ID", type: .warning)
                sessions = []
                sessionsHasMore = false
                return
            }

            AppLogger.log("[Dashboard] Using workspace/session/history: \(workspaceId)")
            let historyResponse = try await workspaceManager.getSessionHistory(workspaceId: workspaceId, limit: sessionsPageSize)

            // Convert HistorySessionInfo to SessionsResponse.SessionInfo
            sessions = (historyResponse.sessions ?? []).map { historySession in
                SessionsResponse.SessionInfo(
                    sessionId: historySession.sessionId,
                    summary: historySession.summary ?? "No summary",
                    messageCount: historySession.messageCount ?? 0,
                    lastUpdated: historySession.lastUpdated ?? "",
                    branch: historySession.branch
                )
            }
            // workspace/session/history doesn't support pagination yet
            sessionsHasMore = false
            sessionsNextOffset = sessions.count
            AppLogger.log("[Dashboard] Loaded \(sessions.count) sessions from workspace history, total=\(historyResponse.total ?? 0)")
        } catch is CancellationError {
            AppLogger.log("[Dashboard] Session loading cancelled")
        } catch {
            AppLogger.error(error, context: "Load sessions")
        }
    }

    /// Load more sessions (pagination)
    func loadMoreSessions() async {
        guard sessionsHasMore, !isLoadingMoreSessions else { return }

        // Workspace ID is required for session APIs
        guard let workspaceId = currentWorkspaceId else {
            AppLogger.log("[Dashboard] Cannot load more sessions - no workspace ID", type: .warning)
            return
        }

        isLoadingMoreSessions = true
        do {
            let response = try await _agentRepository.getSessions(workspaceId: workspaceId, limit: sessionsPageSize, offset: sessionsNextOffset)
            sessions.append(contentsOf: response.sessions)
            sessionsHasMore = response.hasMore
            sessionsNextOffset = response.nextOffset
            AppLogger.log("[Dashboard] Loaded more sessions: +\(response.sessions.count), total now=\(sessions.count), hasMore=\(sessionsHasMore)")
        } catch is CancellationError {
            AppLogger.log("[Dashboard] Load more sessions cancelled")
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
                workspaceId: currentWorkspaceId,
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

        // Notify server of active session selection (for multi-device sync)
        if let workspaceId = currentWorkspaceId {
            do {
                _ = try await _agentRepository.activateSession(workspaceId: workspaceId, sessionId: sessionId)
            } catch {
                AppLogger.log("[Dashboard] Failed to activate session: \(error)", type: .warning)
                // Non-fatal - continue with resume flow
            }
        }

        // IMPORTANT: Start watching the new session BEFORE fetching messages
        // The workspace/session/messages API requires the session to be watched first
        await startWatchingCurrentSession()

        // Load first page of session messages
        do {
            let messagesResponse = try await _agentRepository.getSessionMessages(
                sessionId: sessionId,
                workspaceId: currentWorkspaceId,
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

            // Note: Watch was already started before fetching messages
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
            // Update state immediately after successful stop
            // (don't wait for WebSocket event which may be delayed or missing)
            claudeState = .idle
            isStreaming = false
            streamingStartTime = nil
            hasActiveConversation = false
            AppLogger.log("[Dashboard] Claude stopped via stopClaude()")
            Haptics.success()
        } catch {
            // Check if this is a "session not found" error
            // If so, the session is already gone - reset state instead of showing error
            let errorMessage = String(describing: error).lowercased()
            if errorMessage.contains("session not found") || errorMessage.contains("session_not_found") {
                AppLogger.log("[Dashboard] Session not found during stop - resetting state")
                claudeState = .idle
                isStreaming = false
                streamingStartTime = nil
                hasActiveConversation = false
                Haptics.light()
            } else {
                self.error = error as? AppError ?? .unknown(underlying: error)
                Haptics.error()
            }
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

    /// Dismiss the pending interaction by sending escape key
    /// Used when user closes the permission panel via X button
    func dismissPendingInteraction() {
        Task {
            await dismissPTYPermission()
        }
    }

    /// Send escape key to dismiss PTY permission and clear local state
    private func dismissPTYPermission() async {
        guard pendingInteraction?.isPTYMode == true else {
            pendingInteraction = nil
            return
        }

        // Get current session ID
        let sessionId = userSelectedSessionId ?? agentStatus.sessionId
        guard let sessionId = sessionId, !sessionId.isEmpty else {
            AppLogger.log("[Dashboard] No session ID for PTY dismiss", type: .error)
            pendingInteraction = nil
            return
        }

        do {
            // Send escape key to server to cancel the permission prompt
            try await _agentRepository.sendInput(sessionId: sessionId, input: "escape")
            pendingInteraction = nil
            AppLogger.log("[Dashboard] PTY permission dismissed with escape key")
            Haptics.light()
        } catch {
            // Still clear local state even if server request fails
            pendingInteraction = nil
            AppLogger.log("[Dashboard] PTY dismiss failed: \(error)", type: .error)
        }
    }

    // MARK: - PTY Mode Helpers

    /// Validate that a PTY option key is a valid keyboard shortcut
    /// Valid keys: numbers (1-9), letters (n, y, etc.), special keys (esc, enter, tab)
    private func isValidPTYOptionKey(_ key: String) -> Bool {
        let validKeys = Set(["1", "2", "3", "4", "5", "6", "7", "8", "9",
                             "n", "y", "esc", "escape", "enter", "return", "tab"])
        return validKeys.contains(key.lowercased()) || key.count == 1
    }

    // MARK: - PTY Mode Permission Responses

    /// Respond to PTY permission by navigating to the selected option and pressing enter.
    /// The PTY terminal uses arrow key navigation:
    /// - Find the currently selected option (selected == true)
    /// - Navigate "down" to reach the target option
    /// - Send "enter" to confirm
    func respondToPTYPermission(key: String) async {
        guard let interaction = pendingInteraction, interaction.isPTYMode else { return }
        Haptics.light()

        // Get session ID: prefer interaction's sessionId (for PTY after session_id_failed),
        // then userSelectedSessionId, then agentStatus
        let sessionId = interaction.sessionId ?? userSelectedSessionId ?? agentStatus.sessionId
        guard let sessionId = sessionId, !sessionId.isEmpty else {
            AppLogger.log("[Dashboard] No session ID for PTY response", type: .error)
            return
        }

        // Get options from the interaction
        guard let options = interaction.ptyOptions, !options.isEmpty else {
            AppLogger.log("[Dashboard] No PTY options available", type: .error)
            return
        }

        // Find the currently selected option index (default to 0 if none marked)
        let currentIndex = options.firstIndex { $0.selected == true } ?? 0

        // Find the target option index by key
        guard let targetIndex = options.firstIndex(where: { $0.key == key }) else {
            AppLogger.log("[Dashboard] PTY option with key '\(key)' not found", type: .error)
            return
        }

        // Calculate navigation direction and count
        let distance = targetIndex - currentIndex
        let direction: String
        let keyPresses: Int

        if distance > 0 {
            // Target is below current - need to go down
            direction = "down"
            keyPresses = distance
        } else if distance < 0 {
            // Target is above current - need to go up
            direction = "up"
            keyPresses = -distance  // Make positive
        } else {
            // Already at target - just press enter
            direction = ""
            keyPresses = 0
        }

        AppLogger.log("[Dashboard] PTY navigation: current=\(currentIndex), target=\(targetIndex), direction=\(direction.isEmpty ? "none" : direction), presses=\(keyPresses)")

        do {
            // Send navigation keys to reach target option
            for i in 0..<keyPresses {
                try await _agentRepository.sendInput(sessionId: sessionId, input: direction)
                AppLogger.log("[Dashboard] PTY sent '\(direction)' (\(i + 1)/\(keyPresses))")
                // Small delay between key presses to ensure they're processed in order
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }

            // Send "enter" to confirm selection
            try await _agentRepository.sendInput(sessionId: sessionId, input: "enter")
            pendingInteraction = nil
            AppLogger.log("[Dashboard] PTY permission responded: navigated to option '\(key)' and pressed enter")
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
            AppLogger.log("[Dashboard] PTY response failed: \(error)", type: .error)
        }
    }

    /// Approve PTY permission (sends "1" for Yes)
    func approvePTYPermission() async {
        await respondToPTYPermission(key: "1")
        Haptics.success()
    }

    /// Approve all PTY permissions (sends "2" for Yes All)
    func approveAllPTYPermissions() async {
        await respondToPTYPermission(key: "2")
        Haptics.success()
    }

    /// Deny PTY permission (sends "n" for No)
    func denyPTYPermission() async {
        await respondToPTYPermission(key: "n")
        Haptics.warning()
    }

    /// Refresh status using workspace/status API
    func refreshStatus() async {
        // Workspace ID is required for status APIs
        guard let workspaceId = currentWorkspaceId else {
            AppLogger.log("[Dashboard] refreshStatus: no workspace ID, skipping", type: .warning)
            return
        }

        do {
            AppLogger.log("[Dashboard] refreshStatus: using workspace/status for \(workspaceId)")
            let wsStatus = try await _agentRepository.getWorkspaceStatus(workspaceId: workspaceId)

            // IMPORTANT: Preserve sessionId from multiple sources (priority order):
            // 1. watchedSessionId from API (if actively watching and not empty)
            // 2. Current agentStatus.sessionId (set by setWorkspaceContext)
            // 3. userSelectedSessionId (user's explicit selection)
            // Note: API may return empty string "" instead of null, so check for both
            let currentSessionId = agentStatus.sessionId
            let watchedId = wsStatus.watchedSessionId
            let resolvedSessionId: String?
            if let watched = watchedId, !watched.isEmpty {
                resolvedSessionId = watched
            } else if let current = currentSessionId, !current.isEmpty {
                resolvedSessionId = current
            } else if let userSelected = userSelectedSessionId, !userSelected.isEmpty {
                resolvedSessionId = userSelected
            } else {
                resolvedSessionId = nil
            }
            AppLogger.log("[Dashboard] refreshStatus: resolving sessionId - watchedSessionId=\(watchedId ?? "nil"), currentSessionId=\(currentSessionId ?? "nil"), userSelectedSessionId=\(userSelectedSessionId ?? "nil") -> \(resolvedSessionId ?? "nil")")

            // Update agentStatus from workspace status
            agentStatus = AgentStatus(
                claudeState: claudeState,  // Keep current claudeState (updated via events)
                sessionId: resolvedSessionId,
                repoName: wsStatus.gitRepoName ?? wsStatus.workspaceName,
                repoPath: wsStatus.path,
                connectedClients: agentStatus.connectedClients,  // Not in workspace/status
                uptime: agentStatus.uptime  // Not in workspace/status
            )

            // Log git tracker state
            let trackerState = wsStatus.trackerState
            if !trackerState.isAvailable {
                AppLogger.log("[Dashboard] Git tracker state: \(wsStatus.gitTrackerState ?? "unknown"), error: \(wsStatus.gitLastError ?? "none")")
            }

            AppLogger.log("[Dashboard] refreshStatus (workspace): repoName=\(agentStatus.repoName ?? "nil"), sessionId=\(agentStatus.sessionId ?? "nil"), gitTrackerState=\(wsStatus.gitTrackerState ?? "nil"), hasActiveSession=\(wsStatus.hasActiveSession ?? false)")
        } catch {
            AppLogger.error(error, context: "Refresh status")
        }
        // Only refresh git status if initial load is done (to avoid race condition)
        AppLogger.log("[Dashboard] refreshStatus: hasCompletedInitialLoad=\(hasCompletedInitialLoad), will call refreshGitStatus: \(hasCompletedInitialLoad)")
        if hasCompletedInitialLoad {
            await refreshGitStatus()
        }
    }

    /// Refresh git status from API
    func refreshGitStatus() async {
        AppLogger.log("[Dashboard] refreshGitStatus: calling sourceControlViewModel.refresh()")
        // Refresh source control view (this fetches git status)
        await sourceControlViewModel.refresh()
        AppLogger.log("[Dashboard] refreshGitStatus: sourceControlViewModel.refresh() completed")

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
    /// - Parameter isReconnection: If true, forces reload even if data exists (to catch up on new messages)
    private func loadRecentSessionHistory(isReconnection: Bool = false) async {
        // Skip if pending trust_folder approval - session doesn't exist yet
        guard !isPendingTrustFolder else {
            AppLogger.log("[Dashboard] loadRecentSessionHistory skipped - pending trust_folder approval")
            return
        }

        // Prevent duplicate loads
        guard !isInitialLoadInProgress else {
            AppLogger.log("[Dashboard] loadRecentSessionHistory skipped - already in progress")
            return
        }

        // Prevent duplicate reconnection loads
        if isReconnection {
            guard !isReconnectionInProgress else {
                AppLogger.log("[Dashboard] Reconnection load skipped - already in progress")
                return
            }
            isReconnectionInProgress = true
        }

        isInitialLoadInProgress = true
        AppLogger.log("[Dashboard] Starting loadRecentSessionHistory (reconnection: \(isReconnection))")

        defer {
            isInitialLoadInProgress = false
            hasCompletedInitialLoad = true
            if isReconnection {
                isReconnectionInProgress = false
            }
        }

        do {
            // Determine which session to load:
            // 1. If userSelectedSessionId is already set (e.g., from setWorkspaceContext after starting a new session), use that
            // 2. Otherwise, query the sessions API to find the most recent session
            var sessionId: String?

            if let existingSessionId = userSelectedSessionId, !existingSessionId.isEmpty {
                // Use the session ID that was already set (e.g., when connecting to a new workspace)
                sessionId = existingSessionId
                AppLogger.log("[Dashboard] Using existing userSelectedSessionId: \(existingSessionId)")
            } else {
                // No session set yet - query the API to find one
                AppLogger.log("[Dashboard] Calling getSessions API...")
                let sessionsResponse = try await _agentRepository.getSessions(workspaceId: currentWorkspaceId, limit: 1, offset: 0)
                AppLogger.log("[Dashboard] Sessions response: current=\(sessionsResponse.current ?? "nil"), total=\(sessionsResponse.total ?? 0)")

                // Use current session ID if available and not empty, otherwise use most recent
                if let current = sessionsResponse.current, !current.isEmpty {
                    sessionId = current
                    AppLogger.log("[Dashboard] Using current session: \(current)")
                } else {
                    sessionId = sessionsResponse.sessions.first?.sessionId
                    AppLogger.log("[Dashboard] Using first session: \(sessionId ?? "none")")
                }
            }

            guard let sessionId = sessionId, !sessionId.isEmpty else {
                AppLogger.log("[Dashboard] No session history available")
                return
            }

            AppLogger.log("[Dashboard] Loading history for session: \(sessionId)")

            // Only clear if loading a different session (prevents flashing on reconnect)
            let isNewSession = userSelectedSessionId != sessionId
            let beforeCount = chatElements.count

            if isNewSession {
                await logCache.clear()
                chatElements = []
                seenElementIds.removeAll()  // Clear deduplication set
                // Reset pagination state
                messagesNextOffset = 0
                messagesHasMore = false
                messagesTotalCount = 0
                AppLogger.log("[Dashboard] Cleared data for new session")
            } else if !chatElements.isEmpty && !isReconnection {
                // Same session + have data + NOT reconnecting → skip to prevent duplicates
                AppLogger.log("[Dashboard] Same session with \(beforeCount) elements - skipping reload")
                // Still start watching if not already
                await startWatchingCurrentSession()
                return
            } else if !chatElements.isEmpty && isReconnection {
                // Same session + have data + IS reconnecting → fetch latest to catch up on new messages
                AppLogger.log("[Dashboard] Reconnection - fetching latest messages (current: \(beforeCount) elements)")
                // Don't clear - deduplication will filter existing, add new
            } else {
                AppLogger.log("[Dashboard] Same session but empty - loading data")
            }

            // Store sessionId - this is a TRUSTED source (from sessions API)
            setSelectedSession(sessionId)
            hasActiveConversation = false  // Reset - will be set true on first prompt
            AppLogger.log("[Dashboard] Set userSelectedSessionId: \(sessionId)")

            // IMPORTANT: Start watching the session BEFORE fetching messages
            // The workspace/session/messages API requires the session to be watched first
            await startWatchingCurrentSession()

            // Yield to let UI thread breathe before network call
            await Task.yield()

            // Get first page of messages for the session
            AppLogger.log("[Dashboard] Fetching messages for session: \(sessionId)")
            let messagesResponse: SessionMessagesResponse
            do {
                messagesResponse = try await _agentRepository.getSessionMessages(
                    sessionId: sessionId,
                    workspaceId: currentWorkspaceId,
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
            let afterCount = chatElements.count
            let newMessagesCount = afterCount - beforeCount

            AppLogger.log("[Dashboard] Created \(entriesAdded) log entries and \(afterCount) elements from \(messagesResponse.count) messages (deduplicated)")

            if isReconnection && newMessagesCount > 0 {
                AppLogger.log("[Dashboard] Reconnection synced \(newMessagesCount) new messages (before: \(beforeCount), after: \(afterCount))")
            }

            // Update logs array
            await forceLogUpdate()

            // Note: Watch was already started before fetching messages
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

                    // Sync workspace IDs first - this enables workspace-aware APIs
                    AppLogger.log("[Dashboard] Reconnected - syncing workspace IDs")
                    _ = try? await WorkspaceManagerService.shared.listWorkspaces()

                    AppLogger.log("[Dashboard] Reconnected - starting loadRecentSessionHistory")
                    await self.loadRecentSessionHistory(isReconnection: true)
                    // refreshStatus() calls refreshGitStatus() internally when hasCompletedInitialLoad is true
                    AppLogger.log("[Dashboard] Reconnected - starting refreshStatus (includes git status)")
                    await self.refreshStatus()

                    // Re-establish session watch for live mode (force=true to bypass "already watching" check)
                    // Use userSelectedSessionId or agentStatus.sessionId
                    let sessionToWatch = self.userSelectedSessionId ?? self.agentStatus.sessionId
                    AppLogger.log("[Dashboard] Reconnected - checking session watch: userSelectedSessionId=\(self.userSelectedSessionId ?? "nil"), agentStatus.sessionId=\(self.agentStatus.sessionId ?? "nil")")
                    if let sessionId = sessionToWatch, !sessionId.isEmpty {
                        AppLogger.log("[Dashboard] Reconnected - re-establishing session watch for: \(sessionId)")
                        // Reset watch state to ensure re-establishment
                        self.isWatchingSession = false
                        self.watchingSessionId = nil
                        // Set userSelectedSessionId if not set
                        if self.userSelectedSessionId == nil {
                            self.userSelectedSessionId = sessionId
                        }
                        // Use force=true to ensure watch is re-established even if state seems correct
                        await self.startWatchingCurrentSession(force: true)
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
                // IMPORTANT: Validate session ID to prevent messages from other sessions
                // Skip this event if it belongs to a different session than the one we're viewing
                if let eventSessionId = payload.sessionId,
                   !eventSessionId.isEmpty,
                   let selectedSessionId = userSelectedSessionId,
                   !selectedSessionId.isEmpty,
                   eventSessionId != selectedSessionId {
                    AppLogger.log("[Dashboard] claude_message skipped - session mismatch (event: \(eventSessionId), selected: \(selectedSessionId))")
                    return
                }

                AppLogger.log("[Dashboard] claude_message received - uuid: \(payload.uuid ?? "nil"), role: \(payload.effectiveRole ?? "nil"), sessionId: \(payload.sessionId ?? "nil")")

                // Skip user message echoes from real-time events (already shown optimistically)
                // BUT ONLY skip messages sent by THIS CLIENT, not from other clients (e.g., Claude Code CLI)
                // ALWAYS show bash mode OUTPUT (stdout/stderr) which is server-generated
                if payload.effectiveRole == "user" {
                    let textContent = payload.effectiveContent?.textContent ?? ""

                    // Check for bash tags
                    let hasBashInput = textContent.contains("<bash-input>")  // Bash command
                    let hasBashOutput = textContent.contains("<bash-stdout>") ||
                                       textContent.contains("<bash-stderr>")  // Bash output

                    // Handle bash INPUT: Extract command and check if it's ours
                    if hasBashInput {
                        // Extract command from <bash-input>command</bash-input>
                        let extractedCommand = extractBashCommand(from: textContent)
                        let hash = hashPrompt(extractedCommand)
                        let isOurs = sentPromptHashes[hash] != nil

                        AppLogger.log("[Dashboard] Bash command echo - extracted: '\(extractedCommand)', hash: \(hash), isOurs: \(isOurs), tracked hashes: \(sentPromptHashes.keys)")

                        // Skip only if this was OUR OWN bash command
                        // Keep hash for 5 seconds to handle duplicate server echoes
                        if isOurs {
                            AppLogger.log("[Dashboard] ✅ Skipping our own bash command echo (hash: \(hash), kept for dedup)")
                            return
                        } else {
                            // Show bash commands from other clients (e.g., laptop CLI)
                            AppLogger.log("[Dashboard] 📱 Showing bash command from another client")
                        }
                    }
                    // Show bash OUTPUT always (server-generated stdout/stderr)
                    else if hasBashOutput {
                        AppLogger.log("[Dashboard] Showing bash mode output with tags")
                    }
                    // Regular text prompts - skip only if from this client
                    // Keep hash for 5 seconds to handle duplicate server echoes
                    else if isOurOwnPrompt(textContent) {
                        let hash = hashPrompt(textContent)
                        AppLogger.log("[Dashboard] Skipping our own prompt echo (hash: \(hash), text: '\(textContent)')")
                        return
                    }
                    // Show messages from other clients (e.g., Claude Code CLI on laptop)
                    else {
                        let hash = hashPrompt(textContent)
                        AppLogger.log("[Dashboard] Showing user message from another client - hash: \(hash), text: '\(textContent)'")
                    }
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
                    spinnerMessage = nil
                    if let startTime = streamingStartTime {
                        let duration = Date().timeIntervalSince(startTime)
                        AppLogger.log("[Dashboard] Streaming stopped after \(String(format: "%.1f", duration))s")
                    }
                    streamingStartTime = nil
                }

                // In interactive mode, update isLoading based on claude_message
                // Note: claudeState is managed by pty_state events in interactive mode
                if isInteractiveMode {
                    // Reset isLoading when we receive any assistant message (Claude is responding)
                    if payload.effectiveRole == "assistant" && isLoading {
                        isLoading = false
                        AppLogger.log("[Dashboard] Interactive mode: Reset isLoading (received assistant message)")
                    }

                    // Only use stop_reason as a fallback if pty_state isn't working
                    if let stopReason = payload.stopReason, !stopReason.isEmpty {
                        // Claude finished - set to idle
                        if claudeState == .running {
                            claudeState = .idle
                            AppLogger.log("[Dashboard] Interactive mode: Claude finished (stop_reason: \(stopReason))")
                        }
                    }
                    // Don't set claudeState = .running here - pty_state handles state transitions
                }
            }

        case .claudeLog:
            // In interactive PTY mode, skip claude_log processing entirely
            // PTY mode uses pty_output/pty_permission events instead
            // claude_message events are still used for UI display
            guard !isInteractiveMode else {
                AppLogger.log("[Dashboard] Skipping claude_log in interactive mode")
                return
            }

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
                // 3. Clear streaming indicator and spinner message
                if previousState == .running && (state == .idle || state == .stopped) {
                    hasActiveConversation = false
                    isStreaming = false
                    streamingStartTime = nil
                    spinnerMessage = nil
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

        case .ptyPermission:
            // PTY mode permission prompt with options
            // Validate that options have proper keys before updating UI
            // This prevents flickering from intermediate/malformed events
            if case .ptyPermission(let payload) = event.payload,
               let options = payload.options,
               !options.isEmpty,
               options.allSatisfy({ isValidPTYOptionKey($0.key) }) {
                pendingInteraction = PendingInteraction.fromPTYPermission(event: event)
                claudeState = .waiting  // Update state to show waiting indicator
                Haptics.warning()

                // Check if this is a trust_folder permission - session APIs won't work until approved
                // Also mark as pending temp session since session_id_resolved will provide real ID
                if payload.type == .trustFolder {
                    isPendingTrustFolder = true
                    isPendingTempSession = true
                    AppLogger.log("[Dashboard] PTY trust_folder permission - session APIs delayed, waiting for real session ID")
                }

                // Send local notification if app is in background
                // This alerts the user that Claude needs permission approval
                Task {
                    await NotificationService.shared.sendPermissionNotification(
                        toolName: payload.toolName,
                        description: payload.displayDescription,
                        workspaceName: agentStatus.repoName
                    )
                }

                AppLogger.log("[Dashboard] PTY permission received with \(options.count) valid options, type=\(payload.type?.rawValue ?? "unknown")")
            } else {
                AppLogger.log("[Dashboard] PTY permission skipped - invalid or missing options")
            }

        case .ptyPermissionResolved:
            // Permission was resolved by another device - dismiss our permission UI
            if case .ptyPermissionResolved(let payload) = event.payload {
                let resolvedBy = payload.resolvedBy ?? "unknown"
                let input = payload.input ?? "unknown"
                AppLogger.log("[Dashboard] PTY permission resolved by another device: resolvedBy=\(resolvedBy), input=\(input)")

                // Clear the pending permission UI if we have one
                if pendingInteraction?.isPTYMode == true {
                    pendingInteraction = nil
                    Haptics.light()
                    AppLogger.log("[Dashboard] Dismissed local permission popup - resolved by another device")

                    // Clear the badge since permission was handled
                    // NotificationService.shared.clearPermissionNotification()
                }

                // Update claude state based on the resolution
                if payload.wasApproved {
                    claudeState = .running
                } else if payload.wasDenied {
                    // Permission was denied, Claude may still be waiting or idle
                    claudeState = .idle
                }
            }

        case .ptyOutput:
            // PTY mode terminal output - logged for debugging
            // Note: Display content uses claude_message events for now
            if case .ptyOutput(let payload) = event.payload,
               let cleanText = payload.cleanText, !cleanText.isEmpty {
                AppLogger.log("[Dashboard] PTY output: \(cleanText.prefix(100))")
            }

        case .ptyState:
            // PTY state change (idle, thinking, permission, question, error)
            if case .ptyState(let payload) = event.payload {
                if let state = payload.state {
                    let previousClaudeState = claudeState
                    let wasPendingTrust = isPendingTrustFolder

                    // Map PTY state to Claude state
                    switch state {
                    case .idle:
                        claudeState = .idle
                        isLoading = false  // Also reset loading when idle
                        spinnerMessage = nil  // Clear spinner message when idle
                    case .thinking:
                        claudeState = .running
                    case .permission, .question:
                        claudeState = .waiting
                    case .error:
                        claudeState = .error
                    }
                    AppLogger.log("[Dashboard] PTY state: \(state) → claudeState: \(previousClaudeState) → \(claudeState)")

                    // Check if trust_folder was just approved
                    // When state changes from permission to idle/thinking, trust was granted
                    if wasPendingTrust && (state == .idle || state == .thinking) {
                        isPendingTrustFolder = false
                        AppLogger.log("[Dashboard] Trust folder approved - initializing session APIs")

                        // Now that trust is granted, the session exists in .claude/projects/
                        // Initialize session watching and load history
                        Task {
                            await loadRecentSessionHistory(isReconnection: false)
                            await startWatchingCurrentSession(force: true)
                            AppLogger.log("[Dashboard] Post-trust session initialization complete")
                        }
                    }
                } else {
                    AppLogger.log("[Dashboard] PTY state event received but state was nil")
                }
            } else {
                AppLogger.log("[Dashboard] PTY state event payload decode failed")
            }

        case .ptySpinner:
            // PTY spinner event - update spinner message and claude state
            if case .ptySpinner(let payload) = event.payload {
                // Use the full text with symbol (e.g., "· Percolating…")
                // Replace "esc to interrupt" with mobile-friendly text (no escape key on mobile)
                var message = payload.text ?? payload.message
                message = message?.replacingOccurrences(of: "esc to interrupt", with: "press ⏹ to stop")
                spinnerMessage = message

                // pty_spinner indicates Claude is actively working - set to running
                if claudeState != .running {
                    claudeState = .running
                }

                // If not already streaming, start streaming when we receive spinner events
                if !isStreaming {
                    isStreaming = true
                    streamingStartTime = Date()
                }
                AppLogger.log("[Dashboard] PTY spinner: \(payload.message ?? "nil")")
            }

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
            // Real-time git status update from server's git watcher
            // Triggers when files are staged/unstaged, commits made, branches switched, etc.
            AppLogger.log("[Dashboard] Received gitStatusChanged event, payload=\(event.payload)")
            if case .gitStatusChanged(let payload) = event.payload {
                AppLogger.log("[Dashboard] Git status changed - branch: \(payload.branch ?? "?"), staged: \(payload.stagedCount ?? 0), unstaged: \(payload.unstagedCount ?? 0)")
                // Refresh source control UI to show latest git state
                AppLogger.log("[Dashboard] Triggering sourceControlViewModel.refresh()")
                Task { await sourceControlViewModel.refresh() }
            } else {
                AppLogger.log("[Dashboard] gitStatusChanged payload extraction failed - actual payload type: \(type(of: event.payload))", type: .warning)
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

        case .sessionJoined:
            // Another device joined the session we're viewing
            if case .sessionJoined(let payload) = event.payload {
                SessionAwarenessManager.shared.handleSessionJoined(payload)
            }

        case .sessionLeft:
            // Another device left the session we're viewing
            if case .sessionLeft(let payload) = event.payload {
                SessionAwarenessManager.shared.handleSessionLeft(payload)

                // WORKAROUND: Re-watch the session to ensure we keep receiving events
                // This compensates for potential server-side bug where unwatch from one client
                // might affect event delivery to other clients watching the same session
                // Note: session_left events may not include session_id, so re-watch if we have an active session
                if let currentSessionId = userSelectedSessionId, !currentSessionId.isEmpty {
                    // Re-watch if event has no session_id OR if it matches our session
                    let eventSessionId = event.sessionId
                    if eventSessionId == nil || eventSessionId == currentSessionId {
                        AppLogger.log("[Dashboard] Another device left (eventSessionId=\(eventSessionId ?? "nil")), re-establishing watch for session \(currentSessionId)")
                        Task {
                            // Use force: true to bypass "already watching" check - server may have
                            // incorrectly dropped our subscription when the other client unwatched
                            await startWatchingCurrentSession(force: true)
                        }
                    }
                }
            }

        case .sessionIdResolved:
            // Temporary session ID resolved to real Claude session ID
            // This happens after user accepts trust_folder for a new workspace
            if case .sessionIdResolved(let payload) = event.payload,
               let tempId = payload.temporaryId,
               let realId = payload.realId {
                AppLogger.log("[Dashboard] Session ID resolved: temp=\(tempId) → real=\(realId)")

                // Check if this resolution is for our current session
                if userSelectedSessionId == tempId {
                    AppLogger.log("[Dashboard] Updating session tracking from temp to real ID")

                    // Clear pending temp session flag - we now have real ID
                    isPendingTempSession = false

                    // Update session tracking to use real ID
                    setSelectedSession(realId)

                    // Re-watch the session with the real ID to receive claude_message events
                    // from the actual session file
                    Task {
                        AppLogger.log("[Dashboard] Re-watching session with real ID: \(realId)")
                        await stopWatchingSession()
                        await startWatchingCurrentSession(force: true)
                        AppLogger.log("[Dashboard] Session re-watch complete with real ID")
                    }
                } else {
                    AppLogger.log("[Dashboard] Session ID resolution for different session (current=\(userSelectedSessionId ?? "nil"), temp=\(tempId))")
                }
            }

        case .sessionIdFailed:
            // Session ID resolution failed (e.g., user declined trust_folder)
            AppLogger.log("[Dashboard] Received session_id_failed event - payload type: \(type(of: event.payload))")

            // Extract payload details if available
            var tempId = "unknown"
            var reason = "unknown"
            var message = "Session failed to start"

            if case .sessionIdFailed(let payload) = event.payload {
                tempId = payload.temporaryId ?? "unknown"
                reason = payload.reason ?? "unknown"
                message = payload.message ?? "Session failed to start"
            }

            AppLogger.log("[Dashboard] Session ID failed: temp=\(tempId), reason=\(reason), message=\(message)")

            // Clear pending states since session failed
            isPendingTempSession = false
            isPendingTrustFolder = false  // Reset so user can start a new session

            // Clear the permission dialog
            pendingInteraction = nil

            // Clear the failed session to prevent further session API calls
            setSelectedSession(nil)

            // Clear any displayed session ID
            updateSessionId("")

            // Force new session on next prompt - this ensures session/start is called
            // (instead of trying to continue an existing session)
            forceNewSession = true
            AppLogger.log("[Dashboard] Cleared failed session - forceNewSession=true for next prompt")

            // Reset claude state to idle (ready for new input)
            claudeState = .idle

            // Stay on Dashboard - user can send a new message to start a fresh session
            AppLogger.log("[Dashboard] Session failed - staying on Dashboard, ready for new session")

        case .streamReadComplete:
            // JSONL reader caught up to end of file - signal that Claude is done
            AppLogger.log("[Dashboard] Received stream_read_complete event, payload type: \(type(of: event.payload))")
            if case .streamReadComplete(let payload) = event.payload {
                let messagesEmitted = payload.messagesEmitted ?? 0
                let fileOffset = payload.fileOffset ?? 0
                let fileSize = payload.fileSize ?? 0
                AppLogger.log("[Dashboard] Stream read complete - messages: \(messagesEmitted), offset: \(fileOffset), size: \(fileSize), claudeState: \(claudeState)")

                // When file_offset == file_size, we've read the entire file - Claude is done
                if fileOffset == fileSize && fileSize > 0 {
                    AppLogger.log("[Dashboard] Setting claudeState to .idle (was: \(claudeState))")
                    claudeState = .idle
                    isStreaming = false
                    streamingStartTime = nil
                    spinnerMessage = nil
                    AppLogger.log("[Dashboard] Claude finished - stream read complete (offset == size), claudeState: \(claudeState)")
                } else {
                    AppLogger.log("[Dashboard] NOT setting idle: offset=\(fileOffset), size=\(fileSize)")
                }
            } else {
                AppLogger.log("[Dashboard] stream_read_complete payload extraction FAILED - actual: \(event.payload)")
            }

        case .sessionStopped:
            // Session was stopped by another device - sync UI state
            if case .sessionStopped(let payload) = event.payload {
                let stoppedSessionId = payload.sessionId ?? ""
                let stoppedWorkspaceId = payload.workspaceId ?? ""
                let stoppedBy = payload.stoppedBy ?? "unknown"
                AppLogger.log("[Dashboard] Session stopped broadcast: sessionId=\(stoppedSessionId), workspaceId=\(stoppedWorkspaceId), stoppedBy=\(stoppedBy)")

                // Update the workspace list to reflect session stopped
                WorkspaceManagerService.shared.removeSessionFromWorkspace(sessionId: stoppedSessionId)

                // Check if it's our current session
                let currentSessionId = agentStatus.sessionId
                if !stoppedSessionId.isEmpty && stoppedSessionId == currentSessionId {
                    AppLogger.log("[Dashboard] Current session was stopped by another device")

                    // Reset session state
                    claudeState = .idle
                    isStreaming = false
                    streamingStartTime = nil
                    spinnerMessage = nil
                    pendingInteraction = nil
                    forceNewSession = true

                    // Check if it was stopped by a different client
                    let myClientId = webSocketService.clientId
                    if stoppedBy != myClientId && !stoppedBy.isEmpty && stoppedBy != "unknown" {
                        // Another device stopped our session - show info message
                        error = .commandFailed(reason: "Session was stopped by another device")
                    }
                }
            }

        case .workspaceRemoved:
            // Workspace was removed from server - check if it's our current workspace
            if case .workspaceRemoved(let payload) = event.payload {
                let removedId = payload.id ?? ""
                let removedName = payload.name ?? "Unknown"
                AppLogger.log("[Dashboard] Workspace removed: id=\(removedId), name=\(removedName), currentWorkspaceId=\(currentWorkspaceId ?? "nil")")

                // Always update the workspace list
                WorkspaceManagerService.shared.handleWorkspaceRemoved(workspaceId: removedId)

                // Check if the removed workspace is the one we're currently viewing
                if let currentId = currentWorkspaceId, currentId == removedId {
                    AppLogger.log("[Dashboard] Current workspace was removed - navigating to workspace list")

                    // Clear session and workspace state
                    setSelectedSession(nil)
                    claudeState = .idle
                    isStreaming = false
                    streamingStartTime = nil
                    spinnerMessage = nil
                    pendingInteraction = nil
                    hasActiveConversation = false

                    // Clear the active workspace in WorkspaceStore
                    WorkspaceStore.shared.clearActive()

                    // Show info message (not really an error, more of a notification)
                    error = .commandFailed(reason: "Workspace '\(removedName)' was removed from server")

                    // Trigger navigation to workspace list
                    shouldShowWorkspaceList = true
                }
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
            let sessionsResponse = try await _agentRepository.getSessions(workspaceId: currentWorkspaceId, limit: 100, offset: 0)
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
            let sessionsResponse = try await _agentRepository.getSessions(workspaceId: currentWorkspaceId, limit: 1, offset: 0)
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
    /// - Parameter force: If true, ignores "already watching" check (used after reconnection)
    func startWatchingCurrentSession(force: Bool = false) async {
        AppLogger.log("[Dashboard] startWatchingCurrentSession(force=\(force)) - userSelectedSessionId=\(userSelectedSessionId ?? "nil"), isWatchingSession=\(isWatchingSession), watchingSessionId=\(watchingSessionId ?? "nil"), isConnected=\(connectionState.isConnected)")

        // Skip if pending trust_folder approval - session doesn't exist yet
        guard !isPendingTrustFolder else {
            AppLogger.log("[Dashboard] startWatchingCurrentSession skipped - pending trust_folder approval")
            return
        }

        guard let sessionId = userSelectedSessionId, !sessionId.isEmpty else {
            AppLogger.log("[Dashboard] No session to watch - userSelectedSessionId is nil or empty")
            return
        }

        // Already watching this session? (skip if force=true, e.g., after reconnection)
        if !force && isWatchingSession && watchingSessionId == sessionId {
            AppLogger.log("[Dashboard] Already watching session: \(sessionId)")
            return
        }

        // Must be connected
        guard connectionState.isConnected else {
            AppLogger.log("[Dashboard] Cannot watch session - not connected")
            return
        }

        do {
            AppLogger.log("[Dashboard] Calling watchSession API for: \(sessionId)")
            // Use workspace-aware API if available
            try await webSocketService.watchSession(sessionId, workspaceId: currentWorkspaceId)
            // JSON-RPC response confirms watching - set state immediately
            isWatchingSession = true
            watchingSessionId = sessionId
            AppLogger.log("[Dashboard] Now watching session: \(sessionId)\(currentWorkspaceId != nil ? " (workspace: \(currentWorkspaceId!))" : "")")

            // Notify server about session focus for multi-device awareness
            if let workspaceId = currentWorkspaceId {
                await SessionAwarenessManager.shared.setFocus(workspaceId: workspaceId, sessionId: sessionId)
            }
        } catch {
            AppLogger.error(error, context: "Watch session")
            // Reset state on failure so next attempt will try again
            isWatchingSession = false
            watchingSessionId = nil
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

            // Clear session focus for multi-device awareness
            SessionAwarenessManager.shared.clearFocus()
        } catch {
            // Still clear local state even if command fails
            isWatchingSession = false
            watchingSessionId = nil
            SessionAwarenessManager.shared.clearFocus()
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

        // Stop watching session first (while workspace subscription is still valid)
        await stopWatchingSession()

        // Then unsubscribe from previous workspace events
        if let previousWorkspaceId = WorkspaceStore.shared.activeWorkspace?.remoteWorkspaceId {
            AppLogger.log("[Dashboard] Unsubscribing from previous workspace: \(previousWorkspaceId)")
            do {
                try await workspaceManager.unsubscribe(workspaceId: previousWorkspaceId)
            } catch {
                AppLogger.log("[Dashboard] Failed to unsubscribe from previous workspace: \(error.localizedDescription)", type: .warning)
            }
        }

        // Disconnect WebSocket
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

    /// Disconnect from current workspace and reset all state to default
    func disconnect() async {
        AppLogger.log("[Dashboard] Disconnecting from workspace")

        // Mark as explicit disconnect BEFORE WebSocket disconnect
        // This tells RootView to navigate away instead of trying to reconnect
        appState?.markExplicitDisconnect()

        // Stop watching session first (while workspace subscription is still valid)
        await stopWatchingSession()

        // Then unsubscribe from workspace events
        if let workspaceId = WorkspaceStore.shared.activeWorkspace?.remoteWorkspaceId {
            AppLogger.log("[Dashboard] Unsubscribing from workspace: \(workspaceId)")
            do {
                try await workspaceManager.unsubscribe(workspaceId: workspaceId)
            } catch {
                AppLogger.log("[Dashboard] Failed to unsubscribe: \(error.localizedDescription)", type: .warning)
            }
        }

        // Disconnect WebSocket
        AppLogger.log("[Dashboard] Calling webSocketService.disconnect()")
        webSocketService.disconnect()
        AppLogger.log("[Dashboard] webSocketService.disconnect() completed")

        // Clear workspace store active
        AppLogger.log("[Dashboard] Clearing workspace store")
        WorkspaceStore.shared.clearActive()
        AppLogger.log("[Dashboard] Workspace store cleared")

        // Clear manager store to prevent auto-reconnection
        AppLogger.log("[Dashboard] Clearing manager store")
        ManagerStore.shared.clear()
        WorkspaceManagerService.shared.reset()
        AppLogger.log("[Dashboard] Manager store cleared")

        // Clear HTTP base URL to stop any pending/cached requests
        AppLogger.log("[Dashboard] Clearing HTTP state")
        appState?.clearHTTPState()
        AppLogger.log("[Dashboard] HTTP state cleared")

        // Clear all state to default - do this synchronously to avoid blocking
        AppLogger.log("[Dashboard] Clearing logs and diffs")
        logs = []
        diffs = []
        chatMessages = []
        chatElements = []
        seenElementIds.removeAll()
        AppLogger.log("[Dashboard] Logs and diffs cleared")

        // Clear caches in background (don't await)
        Task.detached { [logCache, diffCache] in
            await logCache.clear()
            await diffCache.clear()
        }

        userSelectedSessionId = nil
        hasActiveConversation = false
        connectionState = .disconnected
        claudeState = .idle
        agentStatus = AgentStatus()
        pendingInteraction = nil
        promptText = ""
        isLoading = false
        error = nil
        isStreaming = false
        streamingStartTime = nil
        isPendingTrustFolder = false
        isPendingTempSession = false

        // Also clear from session repository
        sessionRepository.selectedSessionId = nil

        AppLogger.log("[Dashboard] State reset to default")
    }

    /// Update workspace context when switching to a new workspace
    /// Called by AppState after successfully connecting to ensure correct workspace name is displayed
    func setWorkspaceContext(name: String, sessionId: String?) {
        AppLogger.log("[Dashboard] setWorkspaceContext: name=\(name), sessionId=\(sessionId ?? "nil"), current userSelectedSessionId=\(userSelectedSessionId ?? "nil")")

        // Clear previous state for new workspace
        chatElements.removeAll()
        logs.removeAll()
        diffs.removeAll()
        seenElementIds.removeAll()
        pendingInteraction = nil
        isPendingTrustFolder = false  // Reset trust state for new workspace
        isPendingTempSession = false  // Reset temp session state for new workspace

        // IMPORTANT: When connecting to a workspace, always use the passed sessionId
        // The passed sessionId is the ACTIVE session for the workspace we're connecting to
        // The stored userSelectedSessionId might be from a different workspace or an old session
        // that no longer exists (e.g., from a previous app run)
        let effectiveSessionId: String?
        if let passedSessionId = sessionId, !passedSessionId.isEmpty {
            // Use the session ID from the workspace (this is the active session)
            effectiveSessionId = passedSessionId
            AppLogger.log("[Dashboard] setWorkspaceContext: using passed session \(passedSessionId)")
        } else if let currentSession = userSelectedSessionId, !currentSession.isEmpty {
            // Fallback to stored session only if no session was passed
            effectiveSessionId = currentSession
            AppLogger.log("[Dashboard] setWorkspaceContext: no session passed, keeping stored session \(currentSession)")
        } else {
            effectiveSessionId = nil
            AppLogger.log("[Dashboard] setWorkspaceContext: no session available")
        }

        // Update agentStatus with new workspace info
        agentStatus = AgentStatus(
            claudeState: claudeState,
            sessionId: effectiveSessionId,
            repoName: name,
            repoPath: agentStatus.repoPath,
            connectedClients: agentStatus.connectedClients,
            uptime: agentStatus.uptime
        )

        // Always update session tracking with the effective session ID
        userSelectedSessionId = effectiveSessionId
        if let sid = effectiveSessionId {
            sessionRepository.selectedSessionId = sid
        }

        // Reset conversation state
        hasActiveConversation = false
        hasCompletedInitialLoad = false

        // Reset Explorer for new workspace (async - fire and forget)
        Task {
            await explorerViewModel.resetForNewWorkspace()
        }

        // Check for pending trust_folder permission that arrived before Dashboard was ready
        // This handles the case where pty_permission arrives after session/start but before navigation
        if let pendingEvent = webSocketService.consumePendingTrustFolderPermission() {
            AppLogger.log("[Dashboard] Found pending trust_folder permission - applying")
            // CRITICAL: Set flags synchronously BEFORE async task to prevent session APIs from running
            isPendingTrustFolder = true
            isPendingTempSession = true  // Also pending temp session since we don't have real ID yet
            Task {
                await handleEvent(pendingEvent)
            }
        }

        AppLogger.log("[Dashboard] Workspace context updated: repoName=\(agentStatus.repoName ?? "nil"), sessionId=\(effectiveSessionId ?? "nil")")
    }

    /// Connect to a remote workspace from workspace manager
    /// Single-port architecture: starts a session for the workspace
    /// Returns true if connection succeeded, false otherwise
    @discardableResult
    func connectToRemoteWorkspace(_ workspace: RemoteWorkspace, host: String) async -> Bool {
        AppLogger.log("[DashboardVM] ========== CONNECT TO REMOTE WORKSPACE ==========")
        AppLogger.log("[DashboardVM] connectToRemoteWorkspace: workspace=\(workspace.name), id=\(workspace.id)")
        AppLogger.log("[DashboardVM] connectToRemoteWorkspace: host=\(host), hasActiveSession=\(workspace.hasActiveSession)")
        AppLogger.log("[DashboardVM] connectToRemoteWorkspace: sessions=\(workspace.sessions.map { $0.id })")

        // Stop watching current session first (while workspace subscription is still valid)
        AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Stopping current session watch...")
        await stopWatchingSession()
        AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Session watch stopped, isConnected=\(webSocketService.isConnected)")

        // Then unsubscribe from previous workspace events
        if let previousWorkspaceId = WorkspaceStore.shared.activeWorkspace?.remoteWorkspaceId,
           previousWorkspaceId != workspace.id {
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Unsubscribing from previous workspace: \(previousWorkspaceId)")
            do {
                try await workspaceManager.unsubscribe(workspaceId: previousWorkspaceId)
            } catch {
                AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Failed to unsubscribe: \(error.localizedDescription)", type: .warning)
            }
        }

        // Clear session tracking for new workspace
        userSelectedSessionId = nil
        hasActiveConversation = false
        seenElementIds.removeAll()
        AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Cleared session tracking")

        // Connect via appState (handles URL construction and subscription)
        AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Calling appState.connectToRemoteWorkspace...")
        let result = await appState?.connectToRemoteWorkspace(workspace, host: host) ?? false
        AppLogger.log("[DashboardVM] connectToRemoteWorkspace: appState returned \(result)")

        // If connection succeeded, reload all data for the new workspace
        if result {
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Reloading data for new workspace...")

            // Clear existing data for clean slate
            logs = []
            chatElements = []
            seenElementIds.removeAll()

            // Load session history and messages
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Loading session history...")
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: userSelectedSessionId=\(userSelectedSessionId ?? "nil"), workspaceId=\(currentWorkspaceId ?? "nil")")
            await loadRecentSessionHistory(isReconnection: true)
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: After loadRecentSessionHistory, hasCompletedInitialLoad=\(hasCompletedInitialLoad)")

            // Refresh status (includes git status)
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Refreshing status...")
            await refreshStatus()

            // Re-establish session watch
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Starting session watch...")
            await startWatchingCurrentSession()

            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Data reload complete")
        }

        AppLogger.log("[DashboardVM] ========== CONNECT TO REMOTE WORKSPACE END ==========")
        return result
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

    // MARK: - Prompt Deduplication Helpers

    /// Normalize prompt text for comparison
    /// Strips bash prefix (!), trims whitespace, lowercases
    private func normalizePromptForComparison(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading ! for bash commands (user types "!ls", server echoes "ls" or "!ls")
        if normalized.hasPrefix("!") {
            normalized = String(normalized.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        return normalized.lowercased()
    }

    /// Hash a prompt for deduplication tracking
    private func hashPrompt(_ prompt: String) -> String {
        let normalized = normalizePromptForComparison(prompt)
        return String(normalized.hashValue)
    }

    /// Check if a user message was sent by THIS client
    /// Returns true if this message matches a recently sent prompt
    /// Handles bash commands (with/without ! prefix)
    /// Note: Hash is kept for 5 seconds to handle duplicate server echoes
    private func isOurOwnPrompt(_ text: String) -> Bool {
        let hash = hashPrompt(text)
        return sentPromptHashes[hash] != nil
    }

    /// Remove expired prompt hashes (older than 5 seconds)
    /// Handles duplicate server echoes while allowing repeated commands after timeout
    private func cleanupExpiredPromptHashes() {
        let now = Date()
        sentPromptHashes = sentPromptHashes.filter { _, timestamp in
            now.timeIntervalSince(timestamp) < sentPromptTimeout
        }
    }

    /// Extract bash command from <bash-input>command</bash-input> tags
    /// Returns the command without tags, or original text if no tags found
    private func extractBashCommand(from text: String) -> String {
        // Pattern: <bash-input>COMMAND</bash-input>
        let pattern = #"<bash-input>(.*?)</bash-input>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let commandRange = Range(match.range(at: 1), in: text) else {
            return text  // No tags found, return original
        }

        // Trim whitespace to match optimistic display format
        // Optimistic: "! ls" -> "ls" (trimmed)
        // Server: "<bash-input> ls</bash-input>" -> "ls" (trimmed)
        return String(text[commandRange]).trimmingCharacters(in: .whitespaces)
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
