import Foundation
import Combine
import UIKit

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
    @Published var agentState: ClaudeState = .idle {
        didSet {
            #if DEBUG
            if oldValue != agentState {
                AppLogger.log("[DashboardVM] agentState: \(oldValue) → \(agentState)")
            }
            #endif
        }
    }
    @Published var pendingInteraction: PendingInteraction?

    // External Sessions (Claude running in VS Code, Cursor, terminal via hooks)
    @Published var externalSessionManager = ExternalSessionManager()

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
    @Published private(set) var terminalWindows: [TerminalWindow] = []
    @Published private(set) var activeTerminalWindowId: UUID?

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
    @Published var availableRuntimes: [AgentRuntime] = AgentRuntime.availableRuntimes()
    @Published var showSessionPicker: Bool = false
    @Published var selectedSessionRuntime: AgentRuntime = .claude {
        didSet {
            guard oldValue != selectedSessionRuntime else { return }

            sessionRepository.selectedSessionRuntime = selectedSessionRuntime
            // Clear runtime-agnostic stored session immediately to avoid cross-runtime leakage
            // if the user sends before async runtime-switch orchestration finishes.
            setSelectedSession(nil)
            isSessionPinnedByUser = false

            runtimeSwitchTask?.cancel()
            let previousRuntime = oldValue
            let nextRuntime = selectedSessionRuntime

            runtimeSwitchTask = Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.runtimeCoordinator.handleRuntimeSwitch(
                    from: previousRuntime,
                    to: nextRuntime,
                    selectedRuntime: { self.selectedSessionRuntime },
                    isCancelled: { Task.isCancelled },
                    watchOwnerIdProvider: { self.currentSessionWatchOwnerId() },
                    stopWatching: { await self.stopWatchingSession() },
                    clearRuntimeState: { await self.resetStateForRuntimeSwitch() },
                    loadSessions: { await self.loadSessions() },
                    loadRecentHistory: { await self.loadRecentSessionHistory(isReconnection: false) },
                    refreshStatus: { await self.refreshStatus() }
                )
            }
        }
    }
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

    // Image Attachments (for sending images to Claude)
    @Published var attachedImages: [AttachedImageState] = []
    @Published var showAttachmentMenu: Bool = false

    /// Whether new images can be attached (max 4)
    var canAttachMoreImages: Bool { attachedImages.count < AttachedImageState.Constants.maxImages }

    /// Whether any images are attached
    var hasAttachedImages: Bool { !attachedImages.isEmpty }

    /// Whether any images are currently uploading
    var isUploadingImages: Bool {
        attachedImages.contains { $0.isUploading }
    }

    /// Whether all attached images have been uploaded successfully
    var allImagesUploaded: Bool {
        attachedImages.allSatisfy { $0.isUploaded }
    }

    /// Whether any uploads have failed
    var hasFailedUploads: Bool {
        attachedImages.contains { $0.canRetry }
    }

    /// Keep bottom thinking bar aligned with run-state UI (top running + stop button).
    /// If runtime is still running, show the bar even when stream flags momentarily lag.
    var effectiveIsStreaming: Bool {
        isStreaming || agentState == .running
    }

    /// Message shown in the bottom thinking bar.
    /// Falls back to mobile-friendly interrupt hint while runtime is running.
    var effectiveSpinnerMessage: String? {
        if let spinnerMessage, !spinnerMessage.isEmpty {
            return spinnerMessage
        }
        guard effectiveIsStreaming else { return nil }
        return "Thinking... (\(Self.mobileStopText))"
    }

    // MARK: - Dependencies

    private let webSocketService: WebSocketServiceProtocol
    private let _agentRepository: AgentRepositoryProtocol
    private let sendPromptUseCase: SendPromptUseCase
    private let respondToClaudeUseCase: RespondToClaudeUseCase
    private let sessionRepository: SessionRepository
    private let runtimeCoordinator: DashboardRuntimeCoordinator
    private let fallbackSessionWatchOwnerId: String

    /// Public accessor for agentRepository (needed for SessionHistoryView)
    var agentRepository: AgentRepositoryProtocol { _agentRepository }

    private let logCache: LogCache
    private let diffCache: DiffCache
    private weak var appState: AppState?
    private var appStateWindowCancellables: Set<AnyCancellable> = []
    private var bufferedEventsBySessionId: [String: [AgentEvent]] = [:]
    private let maxBufferedEventsPerSession = 200
    private var pendingTempSessionWindowIds: Set<UUID> = []
    private var pendingTempSessionIdByWindowId: [UUID: String] = [:]
    private var windowOperationTokenByWindowId: [UUID: UUID] = [:]
    private var windowStateByWindowId: [UUID: TerminalWindowSessionState] = [:]

    // Mobile-friendly text replacements (no esc/ctrl+c on mobile)
    private static let mobileStopText = "press ⏹ to interrupt"

    // Workspace-aware APIs
    private let workspaceManager = WorkspaceManagerService.shared
    private let workspaceStore = WorkspaceStore.shared

    /// Get the current workspace ID if available
    var currentWorkspaceId: String? {
        workspaceStore.activeWorkspace?.remoteWorkspaceId
    }

    var windowsForCurrentWorkspace: [TerminalWindow] {
        guard let workspaceId = currentWorkspaceId else {
            return terminalWindows.filter { $0.isOpen }
        }
        return terminalWindows.filter { $0.isOpen && $0.workspaceId == workspaceId }
    }

    var activeWindow: TerminalWindow? {
        guard let activeTerminalWindowId else { return nil }
        return terminalWindows.first { $0.id == activeTerminalWindowId && $0.isOpen }
    }

    func ensureWindowForCurrentWorkspace() {
        guard let appState else { return }
        guard let workspaceId = currentWorkspaceId else { return }

        if appState.terminalWindows(for: workspaceId).isEmpty {
            _ = appState.openTerminalWindow(
                workspaceId: workspaceId,
                sessionId: userSelectedSessionId,
                runtime: selectedSessionRuntime
            )
        } else if appState.activeTerminalWindowId == nil,
                  let first = appState.terminalWindows(for: workspaceId).first {
            appState.activateTerminalWindow(first.id)
        }
    }

    func createTerminalWindow() async {
        guard let appState else { return }
        guard let workspaceId = currentWorkspaceId else { return }

        let nextIndex = appState.terminalWindows(for: workspaceId).count + 1
        let window = appState.openTerminalWindow(
            workspaceId: workspaceId,
            sessionId: nil,
            runtime: selectedSessionRuntime,
            title: "Window \(nextIndex)"
        )
        windowStateByWindowId[window.id] = TerminalWindowSessionState()
        await activateTerminalWindow(window.id)
    }

    func activateTerminalWindow(_ windowId: UUID) async {
        guard let appState else { return }
        guard let window = appState.terminalWindow(id: windowId) else { return }
        let activationToken = beginWindowOperation(windowId: windowId)
        let previousWindowId = activeTerminalWindowId
        if previousWindowId != windowId {
            persistWindowSnapshot(for: previousWindowId)
        }

        appState.activateTerminalWindow(windowId)
        activeTerminalWindowId = windowId
        syncPendingTempSessionForActiveWindow()

        guard isWindowOperationCurrent(windowId: windowId, token: activationToken) else { return }

        let windowSessionId = normalizedSessionId(window.sessionId)
        if let windowSessionId {
            if restoreWindowSnapshot(for: windowId) {
                AppLogger.log("[Dashboard] Restored in-memory state for window \(window.id)")
                // IMPORTANT:
                // Select session only AFTER restoring the target window snapshot.
                // If we select first, setSelectedSession() persists the currently visible
                // (previous tab) state into the newly active window, causing cross-tab bleed.
                setSelectedSession(windowSessionId)
                guard isWindowOperationCurrent(windowId: windowId, token: activationToken) else { return }
                await startWatchingCurrentSession(force: true)
                guard isWindowOperationCurrent(windowId: windowId, token: activationToken) else { return }
                await replayBufferedEvents(for: windowSessionId)
                guard isWindowOperationCurrent(windowId: windowId, token: activationToken) else { return }
                if agentState == .running || isStreaming {
                    await syncCurrentSessionRuntimeState(context: "tab-activate-restored")
                    guard isWindowOperationCurrent(windowId: windowId, token: activationToken) else { return }
                }
                persistWindowSnapshot(for: windowId)

                // If the restored snapshot is empty, force a server fetch for this session.
                // This handles race conditions where an empty snapshot was persisted during
                // a rapid tab switch while session data was still loading/streaming.
                if chatElements.isEmpty && logs.isEmpty {
                    AppLogger.log("[Dashboard] Restored snapshot is empty for session \(windowSessionId) - forcing resumeSession fetch")
                    await resumeSession(windowSessionId, windowId: windowId, operationToken: activationToken)
                }
                return
            }

            await resumeSession(windowSessionId, windowId: windowId, operationToken: activationToken)
            guard isWindowOperationCurrent(windowId: windowId, token: activationToken) else { return }
            await replayBufferedEvents(for: windowSessionId)
            guard isWindowOperationCurrent(windowId: windowId, token: activationToken) else { return }
            if agentState == .running || isStreaming {
                await syncCurrentSessionRuntimeState(context: "tab-activate-resume")
                guard isWindowOperationCurrent(windowId: windowId, token: activationToken) else { return }
            }
            persistWindowSnapshot(for: windowId)
        } else {
            guard isWindowOperationCurrent(windowId: windowId, token: activationToken) else { return }
            await clearWindowDisplayState()
            forceNewSession = true
            isWatchingSession = false
            watchingSessionId = nil
            SessionAwarenessManager.shared.clearFocus()
            setSelectedSession(nil)
            syncActiveTerminalWindowContext(sessionId: nil)
            windowStateByWindowId[window.id] = makeWindowStateSnapshot(
                sessionId: nil,
                runtime: window.runtime
            )
        }
    }

    func closeTerminalWindow(_ windowId: UUID) async {
        guard let appState else { return }
        guard let window = appState.terminalWindow(id: windowId) else { return }

        let wasActive = appState.activeTerminalWindowId == windowId
        let windowSessionId = normalizedSessionId(window.sessionId)
        let ownerId = watchOwnerId(for: window.id)

        if let windowSessionId {
            do {
                try await webSocketService.unwatchSession(
                    sessionId: windowSessionId,
                    ownerId: ownerId
                )
                AppLogger.log("[Dashboard] Closed window unwatch succeeded: window=\(window.id), session=\(windowSessionId)")
            } catch {
                AppLogger.log("[Dashboard] Closed window unwatch failed: \(error.localizedDescription)", type: .warning)
            }
            bufferedEventsBySessionId.removeValue(forKey: windowSessionId)
        }
        windowStateByWindowId.removeValue(forKey: windowId)
        pendingTempSessionWindowIds.remove(windowId)
        pendingTempSessionIdByWindowId.removeValue(forKey: windowId)
        windowOperationTokenByWindowId.removeValue(forKey: windowId)

        appState.closeTerminalWindow(windowId)

        if wasActive {
            if let nextActiveId = appState.activeTerminalWindowId {
                await activateTerminalWindow(nextActiveId)
            } else {
                await clearWindowDisplayState()
                setSelectedSession(nil)
                isWatchingSession = false
                watchingSessionId = nil
                syncActiveTerminalWindowContext(sessionId: nil)
            }
        }
        syncPendingTempSessionForActiveWindow()
    }

    private func ensureActiveTerminalWindow() -> TerminalWindow? {
        guard let appState else { return nil }
        let workspaceId = currentWorkspaceId

        if let activeWindowId = appState.activeTerminalWindowId,
           let activeWindow = appState.terminalWindow(id: activeWindowId),
           activeWindow.isOpen {
            if let workspaceId {
                if activeWindow.workspaceId == workspaceId {
                    return activeWindow
                }
            } else {
                return activeWindow
            }
        }

        guard let workspaceId else { return nil }

        if let existing = appState.terminalWindows(for: workspaceId).first {
            appState.activateTerminalWindow(existing.id)
            return appState.terminalWindow(id: existing.id)
        }

        return appState.openTerminalWindow(
            workspaceId: workspaceId,
            sessionId: userSelectedSessionId,
            runtime: selectedSessionRuntime
        )
    }

    private func watchOwnerId(for windowId: UUID) -> String {
        "dashboard-window-\(windowId.uuidString)"
    }

    private func currentSessionWatchOwnerId() -> String {
        if let window = ensureActiveTerminalWindow() {
            return watchOwnerId(for: window.id)
        }
        return fallbackSessionWatchOwnerId
    }

    private func syncActiveTerminalWindowContext(sessionId: String?) {
        guard let appState else { return }
        guard let window = ensureActiveTerminalWindow() else { return }
        appState.setTerminalWindowRuntime(window.id, runtime: selectedSessionRuntime)
        appState.setTerminalWindowSession(window.id, sessionId: sessionId)
    }

    private func beginWindowOperation(windowId: UUID?) -> UUID? {
        guard let windowId else { return nil }
        let token = UUID()
        windowOperationTokenByWindowId[windowId] = token
        return token
    }

    private func isWindowOperationCurrent(windowId: UUID?, token: UUID?) -> Bool {
        guard let windowId, let token else { return true }
        return activeTerminalWindowId == windowId && windowOperationTokenByWindowId[windowId] == token
    }

    private func syncPendingTempSessionForActiveWindow() {
        guard let activeWindowId = activeTerminalWindowId else {
            isPendingTempSession = false
            return
        }
        isPendingTempSession = pendingTempSessionWindowIds.contains(activeWindowId)
    }

    private func pendingWindowIdForIncomingTempSession(_ tempSessionId: String?) -> UUID? {
        if let normalizedTemp = normalizedSessionId(tempSessionId),
           let exactWindow = pendingTempSessionIdByWindowId.first(where: { $0.value == normalizedTemp })?.key {
            return exactWindow
        }

        let unresolvedWindowIds = pendingTempSessionWindowIds.filter { pendingTempSessionIdByWindowId[$0] == nil }
        if unresolvedWindowIds.count == 1 {
            return unresolvedWindowIds.first
        }
        return nil
    }

    private func isPendingTempSessionForActiveWindow() -> Bool {
        guard let activeWindowId = activeTerminalWindowId else { return false }
        return pendingTempSessionWindowIds.contains(activeWindowId)
    }

    private func setPendingTempSessionForActiveWindow(tempSessionId: String? = nil) {
        guard let activeWindowId = activeTerminalWindowId else {
            isPendingTempSession = true
            AppLogger.log("[Dashboard] New session pending - waiting for session_id_resolved (window=nil)")
            return
        }

        pendingTempSessionWindowIds.insert(activeWindowId)
        if let normalizedTemp = normalizedSessionId(tempSessionId) {
            pendingTempSessionIdByWindowId[activeWindowId] = normalizedTemp
        } else {
            pendingTempSessionIdByWindowId.removeValue(forKey: activeWindowId)
        }
        syncPendingTempSessionForActiveWindow()
        AppLogger.log("[Dashboard] New session pending - waiting for session_id_resolved (window=\(activeWindowId.uuidString), temp=\(pendingTempSessionIdByWindowId[activeWindowId] ?? "nil"), pendingWindows=\(pendingTempSessionWindowIds.count))")
    }

    private func clearPendingTempSession(reason: String, windowId: UUID? = nil, clearAll: Bool = false) {
        if clearAll {
            if !pendingTempSessionWindowIds.isEmpty {
                AppLogger.log("[Dashboard] Clearing all pending session resolutions (\(reason)) - windows=\(pendingTempSessionWindowIds.count)")
            }
            pendingTempSessionWindowIds.removeAll()
            pendingTempSessionIdByWindowId.removeAll()
            syncPendingTempSessionForActiveWindow()
            return
        }

        guard let targetWindowId = windowId ?? activeTerminalWindowId else {
            if !pendingTempSessionWindowIds.isEmpty {
                AppLogger.log("[Dashboard] Clearing pending session resolutions (\(reason)) with no target window - clearing all")
            }
            pendingTempSessionWindowIds.removeAll()
            pendingTempSessionIdByWindowId.removeAll()
            syncPendingTempSessionForActiveWindow()
            return
        }

        if pendingTempSessionWindowIds.contains(targetWindowId) || pendingTempSessionIdByWindowId[targetWindowId] != nil {
            AppLogger.log("[Dashboard] Clearing pending session resolution (\(reason)) - window=\(targetWindowId.uuidString), temp=\(pendingTempSessionIdByWindowId[targetWindowId] ?? "nil")")
        }
        pendingTempSessionWindowIds.remove(targetWindowId)
        pendingTempSessionIdByWindowId.removeValue(forKey: targetWindowId)
        syncPendingTempSessionForActiveWindow()
    }

    private func bindPendingWindow(_ windowId: UUID, toSessionId sessionId: String) {
        if pendingTempSessionIdByWindowId[windowId] == nil {
            pendingTempSessionIdByWindowId[windowId] = sessionId
        }

        if let appState,
           normalizedSessionId(appState.terminalWindow(id: windowId)?.sessionId) == nil {
            appState.setTerminalWindowSession(windowId, sessionId: sessionId)
        }

        syncPendingTempSessionForActiveWindow()
        AppLogger.log("[Dashboard] Bound pending window \(windowId) to temp session \(sessionId)")
    }

    private func routingDebugContext() -> String {
        let activeWindowValue = activeTerminalWindowId?.uuidString ?? "nil"
        let activeSessionValue = activeWindowSessionIdForRouting() ?? "nil"
        let selectedSessionValue = userSelectedSessionId ?? "nil"
        let watchingSessionValue = watchingSessionId ?? "nil"
        let pendingWindowsValue = pendingTempSessionWindowIds
            .map { $0.uuidString }
            .sorted()
            .joined(separator: ",")
        return "activeWindow=\(activeWindowValue), activeSession=\(activeSessionValue), selectedSession=\(selectedSessionValue), watchingSession=\(watchingSessionValue), pendingWindows=[\(pendingWindowsValue)]"
    }

    private func normalizedSessionId(_ sessionId: String?) -> String? {
        guard let raw = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private func clearWindowDisplayState() async {
        await logCache.clear()
        logs = []
        chatElements = []
        seenElementIds.removeAll()
        seenContentHashes.removeAll()
        messagesHasMore = false
        isLoadingMoreMessages = false
        messagesTotalCount = 0
        messagesNextOffset = 0
        isStreaming = false
        spinnerMessage = nil
        streamingStartTime = nil
        pendingInteraction = nil
        isLoading = false
        agentState = .idle
        hasActiveConversation = false
    }

    private func activeWindowSessionIdForRouting() -> String? {
        if let activeWindow = activeWindow {
            return normalizedSessionId(activeWindow.sessionId)
        }
        return normalizedSessionId(userSelectedSessionId)
    }

    private func isSessionTrackedByAnyOpenWindow(_ sessionId: String) -> Bool {
        terminalWindows.contains { window in
            window.isOpen && normalizedSessionId(window.sessionId) == sessionId
        }
    }

    private func shouldRouteEventBySession(_ event: AgentEvent) -> Bool {
        switch event.type {
        case .claudeMessage, .claudeLog, .claudeSessionInfo, .claudeWaiting, .claudePermission,
             .ptyOutput, .ptyState, .ptySpinner, .ptyPermission, .ptyPermissionResolved:
            return true
        default:
            return false
        }
    }

    private func shouldBufferEventForInactiveWindow(_ event: AgentEvent) -> String? {
        guard shouldRouteEventBySession(event) else { return nil }
        guard let eventSessionId = normalizedSessionId(event.sessionId) else { return nil }

        if let activeSessionId = activeWindowSessionIdForRouting(),
           !activeSessionId.isEmpty {
            guard eventSessionId != activeSessionId else { return nil }
            if isSessionTrackedByAnyOpenWindow(eventSessionId) {
                return eventSessionId
            }
            if let pendingWindowId = pendingWindowIdForIncomingTempSession(eventSessionId) {
                if let activeWindowId = activeTerminalWindowId, pendingWindowId == activeWindowId {
                    return nil
                }
                bindPendingWindow(pendingWindowId, toSessionId: eventSessionId)
                return eventSessionId
            }
            // Unknown/mismatched session: quarantine to prevent foreground tab contamination.
            AppLogger.log("[Dashboard] Quarantining event due to unknown session mismatch - eventType=\(event.type.rawValue), eventSession=\(eventSessionId), \(routingDebugContext())")
            return eventSessionId
        }

        if isSessionTrackedByAnyOpenWindow(eventSessionId) {
            return eventSessionId
        }

        if let pendingWindowId = pendingWindowIdForIncomingTempSession(eventSessionId) {
            if let activeWindowId = activeTerminalWindowId, pendingWindowId == activeWindowId {
                return nil
            }
            bindPendingWindow(pendingWindowId, toSessionId: eventSessionId)
            return eventSessionId
        }

        // No active session context and no pending match: quarantine unknown session events.
        AppLogger.log("[Dashboard] Quarantining event due to missing active context - eventType=\(event.type.rawValue), eventSession=\(eventSessionId), \(routingDebugContext())")
        return eventSessionId
    }

    private func bufferEvent(_ event: AgentEvent, for sessionId: String) {
        var events = bufferedEventsBySessionId[sessionId] ?? []
        events.append(event)
        if events.count > maxBufferedEventsPerSession {
            events.removeFirst(events.count - maxBufferedEventsPerSession)
        }
        bufferedEventsBySessionId[sessionId] = events
    }

    private func replayBufferedEvents(for sessionId: String) async {
        guard let events = bufferedEventsBySessionId.removeValue(forKey: sessionId),
              !events.isEmpty else { return }
        AppLogger.log("[Dashboard] Replaying \(events.count) buffered event(s) for session \(sessionId)")
        for event in events {
            await handleEvent(event)
        }
    }

    private struct TerminalWindowSessionState {
        var logs: [LogEntry] = []
        var chatElements: [ChatElement] = []
        var seenElementIds: Set<String> = []
        var seenContentHashes: Set<String> = []
        var messagesHasMore: Bool = false
        var isLoadingMoreMessages: Bool = false
        var messagesTotalCount: Int = 0
        var messagesNextOffset: Int = 0
        var isWatchingSession: Bool = false
        var watchingSessionId: String? = nil
        var hasActiveConversation: Bool = false
        var hasReceivedClaudeMessageForSession: Bool = false
        var lastPtyOutputLine: String? = nil
        var agentState: ClaudeState = .idle
        var isStreaming: Bool = false
        var streamingStartTime: Date? = nil
        var spinnerMessage: String? = nil
        var pendingInteraction: PendingInteraction? = nil
        var isLoading: Bool = false
        var snapshotSessionId: String? = nil
        var snapshotRuntime: AgentRuntime = .defaultRuntime
    }

    private func makeWindowStateSnapshot(
        sessionId: String? = nil,
        runtime: AgentRuntime? = nil
    ) -> TerminalWindowSessionState {
        TerminalWindowSessionState(
            logs: logs,
            chatElements: chatElements,
            seenElementIds: seenElementIds,
            seenContentHashes: seenContentHashes,
            messagesHasMore: messagesHasMore,
            isLoadingMoreMessages: isLoadingMoreMessages,
            messagesTotalCount: messagesTotalCount,
            messagesNextOffset: messagesNextOffset,
            isWatchingSession: isWatchingSession,
            watchingSessionId: watchingSessionId,
            hasActiveConversation: hasActiveConversation,
            hasReceivedClaudeMessageForSession: hasReceivedClaudeMessageForSession,
            lastPtyOutputLine: lastPtyOutputLine,
            agentState: agentState,
            isStreaming: isStreaming,
            streamingStartTime: streamingStartTime,
            spinnerMessage: spinnerMessage,
            pendingInteraction: pendingInteraction,
            isLoading: isLoading,
            snapshotSessionId: normalizedSessionId(sessionId ?? userSelectedSessionId),
            snapshotRuntime: runtime ?? selectedSessionRuntime
        )
    }

    private func persistWindowSnapshot(for windowId: UUID?) {
        guard let windowId else { return }
        guard let window = terminalWindows.first(where: { $0.id == windowId && $0.isOpen }) else { return }
        windowStateByWindowId[windowId] = makeWindowStateSnapshot(
            sessionId: normalizedSessionId(window.sessionId),
            runtime: window.runtime
        )
    }

    @discardableResult
    private func restoreWindowSnapshot(for windowId: UUID) -> Bool {
        guard let snapshot = windowStateByWindowId[windowId] else { return false }
        guard let window = terminalWindows.first(where: { $0.id == windowId && $0.isOpen }) else { return false }
        let expectedSessionId = normalizedSessionId(window.sessionId)
        if snapshot.snapshotSessionId != expectedSessionId || snapshot.snapshotRuntime != window.runtime {
            AppLogger.log(
                "[Dashboard] Skipping snapshot restore due to identity mismatch: window=\(windowId), snapshotSession=\(snapshot.snapshotSessionId ?? "nil"), expectedSession=\(expectedSessionId ?? "nil"), snapshotRuntime=\(snapshot.snapshotRuntime.rawValue), expectedRuntime=\(window.runtime.rawValue)"
            )
            return false
        }
        logs = snapshot.logs
        chatElements = snapshot.chatElements
        seenElementIds = snapshot.seenElementIds
        seenContentHashes = snapshot.seenContentHashes
        messagesHasMore = snapshot.messagesHasMore
        isLoadingMoreMessages = snapshot.isLoadingMoreMessages
        messagesTotalCount = snapshot.messagesTotalCount
        messagesNextOffset = snapshot.messagesNextOffset
        isWatchingSession = snapshot.isWatchingSession
        watchingSessionId = snapshot.watchingSessionId
        hasActiveConversation = snapshot.hasActiveConversation
        hasReceivedClaudeMessageForSession = snapshot.hasReceivedClaudeMessageForSession
        lastPtyOutputLine = snapshot.lastPtyOutputLine
        agentState = snapshot.agentState
        isStreaming = snapshot.isStreaming
        streamingStartTime = snapshot.streamingStartTime
        spinnerMessage = snapshot.spinnerMessage
        pendingInteraction = snapshot.pendingInteraction
        isLoading = snapshot.isLoading
        return true
    }

    private var eventTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var runtimeSwitchTask: Task<Void, Never>?

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
    private var sessionHistoryLoadToken = UUID()

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
    // True only when the user explicitly picked a session from history.
    // When false, we allow auto-switching to the latest session from history.
    private var isSessionPinnedByUser: Bool = false
    // Foreground reconciliation + stream watchdog
    private var lastStreamEventAt: Date?
    private var lastWatchdogStatusCheckAt: Date?
    private var streamWatchdogTask: Task<Void, Never>?
    private var isAppActive: Bool = true
    private let streamWatchdogInterval: TimeInterval = 5
    private let streamStaleThreshold: TimeInterval = 20
    private let watchdogMinStatusCheckInterval: TimeInterval = 10
    // Fallback when claude_message isn't emitted for PTY sessions
    private var hasReceivedClaudeMessageForSession: Bool = false
    private var lastPtyOutputLine: String?

    // Deduplication for real-time messages
    // O(1) lookup to prevent duplicate elements from multiple sources
    private var seenElementIds: Set<String> = []

    // Content-based deduplication (catches WebSocket vs History API duplicates)
    // Key: hash of (type + timestamp + first 200 chars of content)
    private var seenContentHashes: Set<String> = []

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
        self.fallbackSessionWatchOwnerId = UUID().uuidString
        self.runtimeCoordinator = DashboardRuntimeCoordinator(
            webSocketService: webSocketService,
            agentRepository: agentRepository,
            workspaceManager: workspaceManager
        )
        self.logCache = logCache
        self.diffCache = diffCache
        self.appState = appState
        if let appState {
            terminalWindows = appState.terminalWindows
            activeTerminalWindowId = appState.activeTerminalWindowId

            appState.$terminalWindows
                .receive(on: RunLoop.main)
                .sink { [weak self] windows in
                    self?.terminalWindows = windows
                }
                .store(in: &appStateWindowCancellables)

            appState.$activeTerminalWindowId
                .receive(on: RunLoop.main)
                .sink { [weak self] activeId in
                    self?.activeTerminalWindowId = activeId
                }
                .store(in: &appStateWindowCancellables)
        }

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
        self.selectedSessionRuntime = sessionRepository.selectedSessionRuntime
        reconcileAvailableRuntimes(context: "init")
        if let storedId = userSelectedSessionId {
            AppLogger.log("[Dashboard] Loaded stored sessionId: \(storedId)")
            // Initialize agentStatus with stored sessionId so refreshStatus preserves it
            self.agentStatus = AgentStatus(sessionId: storedId)
        }

        // Bash mode starts as false (normal mode) on each app launch
        // No persistence - resets when app is closed

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
                reconcileAvailableRuntimes(context: "init-connected")

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
        runtimeSwitchTask?.cancel()
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
        // Filter duplicates and process tasks.
        // For real-time streaming updates (same element ID, evolving content),
        // upsert existing entries so ChatView reflects incremental output.
        for element in elements {
            if shouldHideElementFromChatList(element) {
                continue
            }

            let contentHash = generateContentHash(for: element)

            if seenElementIds.contains(element.id) {
                // Exact duplicate (same ID + same content) - skip.
                if seenContentHashes.contains(contentHash) {
                    continue
                }

                // Update pending element in the same debounce window.
                if let pendingIndex = pendingChatElements.lastIndex(where: { $0.id == element.id }) {
                    pendingChatElements[pendingIndex] = element
                    seenContentHashes.insert(contentHash)
                    continue
                }

                // Update element already rendered to keep streaming text live.
                if let existingIndex = chatElements.lastIndex(where: { $0.id == element.id }) {
                    chatElements[existingIndex] = element
                    seenContentHashes.insert(contentHash)
                    AppLogger.log("[Dashboard] Updated streamed element: \(element.id)")
                    continue
                }

                // ID seen but no element found (e.g., trimmed). Treat as stale duplicate.
                continue
            }

            // Primary: ID-based deduplication
            // Secondary: Content-based deduplication (catches WebSocket vs History duplicates)
            guard !seenContentHashes.contains(contentHash) else {
                AppLogger.log("[Dashboard] Skipping duplicate content: \(element.type) at \(element.timestamp)")
                continue
            }

            seenElementIds.insert(element.id)
            seenContentHashes.insert(contentHash)

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

    /// Generate a content hash for deduplication
    /// Uses type + timestamp (to second) + first 200 chars of content
    private func generateContentHash(for element: ChatElement) -> String {
        let typeString = element.type.rawValue
        let timestampSeconds = Int(element.timestamp.timeIntervalSince1970)

        // Extract content text based on element type
        let contentSnippet: String
        switch element.content {
        case .userInput(let content):
            contentSnippet = String(content.text.prefix(200))
        case .assistantText(let content):
            contentSnippet = String(content.text.prefix(200))
        case .toolCall(let content):
            contentSnippet = "\(content.tool):\(content.display.prefix(150))"
        case .toolResult(let content):
            contentSnippet = "\(content.toolName):\(content.summary.prefix(150))"
        case .diff(let content):
            contentSnippet = content.filePath
        case .editDiff(let content):
            contentSnippet = content.filePath
        case .thinking(let content):
            contentSnippet = String(content.text.prefix(200))
        case .interrupted(let content):
            contentSnippet = String(content.message.prefix(200))
        case .contextCompaction(let content):
            contentSnippet = content.summary
        case .task(let content):
            contentSnippet = "\(content.agentType):\(content.id)"
        case .taskGroup(let content):
            contentSnippet = "\(content.agentType):\(content.tasks.map { $0.id }.joined(separator: ",").prefix(150))"
        }

        return "\(typeString)|\(timestampSeconds)|\(contentSnippet)"
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
        guard agentState != .running else {
            AppLogger.log("[Dashboard] Blocked send - Claude is already running")
            Haptics.warning()
            return
        }

        var userMessage = promptText
        promptText = "" // Clear immediately for fast UX

        // Check for built-in app commands FIRST (before bash mode prefix).
        // IMPORTANT: Only intercept known app commands so runtime slash commands
        // (e.g. /model, /bash, /... from Codex/Claude) still reach the agent.
        if let appCommand = appCommandIfSupported(userMessage) {
            await handleCommand(appCommand)
            return
        }

        // Bash mode handling: Auto-detect or apply mode
        // 1. If user types ! in normal mode → auto-enable bash mode
        // 2. If in bash mode → add ! prefix (unless already present)
        if userMessage.hasPrefix("!") && !isBashMode {
            // Auto-enable bash mode when user types ! in normal mode
            isBashMode = true
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
        // Uses UUID for unique ID - server echoes are skipped by isOurOwnPrompt()
        let userElement = ChatElement.userInput(userMessage, sessionId: userSelectedSessionId)
        addElementIfNew(userElement)

        do {
            // If Claude is waiting for a response, use respondToClaude
            // Otherwise use runClaude with continue mode (Claude CLI handles session)
            if agentState == .waiting, let interaction = pendingInteraction {
                try await respondToClaudeUseCase.answerQuestion(
                    response: userMessage,
                    requestId: interaction.requestId,
                    runtime: selectedSessionRuntime
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
                    isSessionPinnedByUser = false
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
                        isSessionPinnedByUser = false
                    }
                } else {
                    // No session selected in current tab.
                    // IMPORTANT: if this tab has no bound session yet, start a NEW session
                    // instead of auto-attaching to "most recent" (which may belong to another tab).
                    if let activeWindowSessionId = normalizedSessionId(activeWindow?.sessionId) {
                        mode = .continue
                        sessionIdToSend = activeWindowSessionId
                        setSelectedSession(activeWindowSessionId)
                        isSessionPinnedByUser = false
                        AppLogger.log("[Dashboard] Using active tab session: mode=continue, sessionId=\(activeWindowSessionId)")
                    } else if normalizedSessionId(activeWindow?.sessionId) == nil {
                        mode = .new
                        sessionIdToSend = nil
                        isSessionPinnedByUser = false
                        AppLogger.log("[Dashboard] Active tab has no session, starting new")
                    } else if let recentId = await getMostRecentSessionId() {
                        // Found a recent session - continue it
                        mode = .continue
                        sessionIdToSend = recentId
                        setSelectedSession(recentId)
                        isSessionPinnedByUser = false
                        AppLogger.log("[Dashboard] Using recent session: mode=continue, sessionId=\(recentId)")
                    } else {
                        // No sessions exist on server - start fresh
                        mode = .new
                        sessionIdToSend = nil
                        isSessionPinnedByUser = false
                        AppLogger.log("[Dashboard] No sessions exist, starting new")
                    }
                }

                // Append image paths to prompt if any images are uploaded
                var finalPrompt = userMessage
                let uploadedPaths = getUploadedImagePaths()
                if !uploadedPaths.isEmpty {
                    // Append image paths in a format Claude understands
                    let pathsText = uploadedPaths.joined(separator: ", ")
                    finalPrompt += "\n\n[Attached images: \(pathsText)]"
                    AppLogger.log("[Dashboard] Sending prompt with \(uploadedPaths.count) images: \(pathsText)")
                }

                if mode == .new {
                    setSelectedSession(nil)
                    if selectedSessionRuntime.requiresSessionResolutionOnNewSession {
                        setPendingTempSessionForActiveWindow()
                    } else {
                        clearPendingTempSession(reason: "new session without id resolution")
                        AppLogger.log("[Dashboard] New \(selectedSessionRuntime.rawValue) session requested")
                    }
                } else if isPendingTempSession {
                    clearPendingTempSession(reason: "continue mode prompt")
                }

                try await sendPromptUseCase.execute(
                    prompt: finalPrompt,
                    mode: mode,
                    sessionId: sessionIdToSend,
                    runtime: selectedSessionRuntime
                )

                // Clear attached images after successful send
                if !uploadedPaths.isEmpty {
                    clearAttachedImages()
                }

                // Refresh session history shortly after send to catch session ID switches
                scheduleSessionHistoryRefresh(reason: "post-send")
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

    /// Toggle bash mode on/off with haptic feedback (resets on app restart)
    func toggleBashMode() {
        isBashMode.toggle()
        Haptics.selection()
        AppLogger.log("[Dashboard] Bash mode toggled: \(isBashMode ? "ON" : "OFF")")
    }

    // MARK: - Built-in Commands

    /// Return the normalized built-in app command if supported.
    /// Unknown slash commands should pass through to the selected runtime.
    private func appCommandIfSupported(_ input: String) -> String? {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let supported: Set<String> = ["/resume", "/new", "/clear", "/sessions", "/help"]
        return supported.contains(normalized) ? normalized : nil
    }

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
            let response = try await fetchSessionsPage(
                runtime: selectedSessionRuntime,
                limit: sessionsPageSize,
                offset: sessionsNextOffset
            )
            sessions = response.sessions
            sessionsHasMore = response.hasMore
            sessionsNextOffset = response.nextOffset
            AppLogger.log("[Dashboard] Loaded \(sessions.count) \(selectedSessionRuntime.rawValue) sessions, hasMore=\(sessionsHasMore)")
        } catch is CancellationError {
            AppLogger.log("[Dashboard] Session loading cancelled")
        } catch {
            AppLogger.error(error, context: "Load sessions")
        }
    }

    /// Load more sessions (pagination)
    func loadMoreSessions() async {
        guard sessionsHasMore, !isLoadingMoreSessions else { return }

        isLoadingMoreSessions = true
        do {
            let response = try await fetchSessionsPage(
                runtime: selectedSessionRuntime,
                limit: sessionsPageSize,
                offset: sessionsNextOffset
            )
            sessions.append(contentsOf: response.sessions)
            sessionsHasMore = response.hasMore
            sessionsNextOffset = response.nextOffset
            AppLogger.log("[Dashboard] Loaded more \(selectedSessionRuntime.rawValue) sessions: +\(response.sessions.count), total now=\(sessions.count), hasMore=\(sessionsHasMore)")
        } catch is CancellationError {
            AppLogger.log("[Dashboard] Load more sessions cancelled")
        } catch {
            AppLogger.error(error, context: "Load more sessions")
        }
        isLoadingMoreSessions = false
    }

    /// Load more session messages (infinite scroll)
    func loadMoreMessages() async {
        if (chatElements.isEmpty && logs.isEmpty) || userSelectedSessionId == nil || userSelectedSessionId?.isEmpty == true {
            AppLogger.log("[Dashboard] loadMoreMessages fallback - refreshing session history")
            await loadRecentSessionHistory(isReconnection: false)
            return
        }
        guard !isLoadingMoreMessages else { return }
        guard !isPendingTempSessionForActiveWindow() else {
            AppLogger.log("[Dashboard] loadMoreMessages skipped - pending session_id_resolved")
            return
        }
        if !messagesHasMore {
            AppLogger.log("[Dashboard] loadMoreMessages no more pages - refreshing latest")
            await loadRecentSessionHistory(isReconnection: true)
            return
        }
        guard let sessionId = userSelectedSessionId, !sessionId.isEmpty else { return }

        isLoadingMoreMessages = true
        do {
            let response = try await fetchSessionMessagesPage(
                runtime: selectedSessionRuntime,
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
                    if shouldHideElementFromChatList(element) {
                        continue
                    }

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
            if isSessionNotFoundError(error) {
                AppLogger.log("[Dashboard] Session not found during loadMoreMessages - refreshing history")
                await handleSessionNotFound(context: "loadMoreMessages", refreshHistory: true)
            } else {
                AppLogger.error(error, context: "Load more messages")
            }
        }
        isLoadingMoreMessages = false
    }

    /// Resume a specific session (user explicitly selected)
    func resumeSession(_ sessionId: String, windowId: UUID? = nil, operationToken: UUID? = nil) async {
        let targetWindowId = windowId ?? activeTerminalWindowId
        let effectiveOperationToken = operationToken ?? beginWindowOperation(windowId: targetWindowId)
        func isCurrentWindowOperation(_ stage: String) -> Bool {
            let isCurrent = isWindowOperationCurrent(windowId: targetWindowId, token: effectiveOperationToken)
            if !isCurrent {
                AppLogger.log("[Dashboard] resumeSession aborted at \(stage) - stale window operation")
            }
            return isCurrent
        }
        guard isCurrentWindowOperation("start") else { return }

        showSessionPicker = false
        isLoading = true
        if isPendingTempSessionForActiveWindow() || targetWindowId == nil {
            clearPendingTempSession(reason: "resumeSession", windowId: targetWindowId)
        }
        isSessionPinnedByUser = true
        Haptics.medium()

        // Stop watching previous session
        await stopWatchingSession()
        guard isCurrentWindowOperation("after stopWatchingSession") else {
            isLoading = false
            return
        }

        // Clear current logs and elements
        await logCache.clear()
        guard isCurrentWindowOperation("after clear logs") else {
            isLoading = false
            return
        }
        logs = []
        chatElements = []
        seenElementIds.removeAll()  // Clear deduplication sets
        seenContentHashes.removeAll()

        // Reset pagination state
        messagesNextOffset = 0
        messagesHasMore = false
        messagesTotalCount = 0

        // Update sessionId - this is a TRUSTED source (user explicit selection)
        setSelectedSession(sessionId)
        hasActiveConversation = false  // Reset - will be set true on first prompt
        AppLogger.log("[Dashboard] User resumed session: \(sessionId)")

        // Notify server of active session selection when runtime requires workspace activation
        if selectedSessionRuntime.requiresWorkspaceActivationOnResume, let workspaceId = currentWorkspaceId {
            do {
                _ = try await _agentRepository.activateSession(workspaceId: workspaceId, sessionId: sessionId)
            } catch {
                AppLogger.log("[Dashboard] Failed to activate session: \(error)", type: .warning)
                // Non-fatal - continue with resume flow
            }
        }

        // Start watching the new session before fetching messages.
        await startWatchingCurrentSession()
        guard isCurrentWindowOperation("after startWatchingCurrentSession") else {
            isLoading = false
            return
        }

        // Load first page of session messages
        do {
            let messagesResponse = try await fetchSessionMessagesPage(
                runtime: selectedSessionRuntime,
                sessionId: sessionId,
                limit: messagesPageSize,
                offset: 0,
                order: "desc"
            )
            guard isCurrentWindowOperation("after fetchSessionMessagesPage") else {
                isLoading = false
                return
            }

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
            if !isCurrentWindowOperation("catch") {
                isLoading = false
                return
            }
            if isSessionNotFoundError(error) {
                AppLogger.log("[Dashboard] Session not found during resume - refreshing history")
                await handleSessionNotFound(context: "resumeSession messages", refreshHistory: true)
                isLoading = false
                return
            }
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
        seenContentHashes.removeAll()
        setSelectedSession(nil)
        hasActiveConversation = false
        isSessionPinnedByUser = false
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
        seenContentHashes.removeAll()
        setSelectedSession(nil)
        hasActiveConversation = false
        isSessionPinnedByUser = false
        AppLogger.log("[Dashboard] Cleared & started new - cleared session state")

        let clearEntry = LogEntry(
            content: "🧹 Cleared & started new session",
            stream: .system
        )
        await logCache.add(clearEntry)
        await forceLogUpdate()
        Haptics.success()
    }

    /// Delete a specific session using workspace/session/delete
    /// - Parameters:
    ///   - sessionId: Session ID to delete
    ///   - workspaceId: Workspace ID containing the session (uses currentWorkspaceId if nil)
    func deleteSession(_ sessionId: String, workspaceId: String? = nil) async {
        // Optimistic removal: update the List data source before the async network call
        // to prevent UICollectionView race condition (concurrent loadSessions refresh
        // during await can leave the collection view in an inconsistent state).
        let snapshot = sessions
        sessions.removeAll { $0.sessionId == sessionId }
        do {
            try await deleteSessionForRuntime(
                runtime: selectedSessionRuntime,
                sessionId: sessionId,
                workspaceId: workspaceId ?? currentWorkspaceId
            )
            AppLogger.log("[Dashboard] Deleted \(selectedSessionRuntime.rawValue) session: \(sessionId)")
            Haptics.success()
        } catch {
            sessions = snapshot
            AppLogger.error(error, context: "Delete session")
            self.error = error as? AppError ?? .unknown(underlying: error)
            Haptics.error()
        }
    }

    /// Delete all sessions in the current workspace
    func deleteAllSessions() async {
        do {
            let summary = try await deleteAllSessionsForRuntime(
                runtime: selectedSessionRuntime,
                workspaceId: currentWorkspaceId
            )
            sessions = []
            AppLogger.log("[Dashboard] Deleted \(summary.deletedCount) \(selectedSessionRuntime.rawValue) sessions (failed: \(summary.failedCount))")

            if selectedSessionRuntime.sessionListSource == .workspaceHistory {
                // Preserve existing behavior for workspace-history runtimes.
                await logCache.clear()
                logs = []
                chatElements = []
                setSelectedSession(nil)
                hasActiveConversation = false

                let entry = LogEntry(
                    content: "🗑️ Deleted \(summary.deletedCount) sessions",
                    stream: .system
                )
                await logCache.add(entry)
                await forceLogUpdate()
            }

            if summary.failedCount == 0 {
                Haptics.success()
            } else {
                Haptics.warning()
                self.error = .commandFailed(reason: "Failed to delete \(summary.failedCount) sessions")
            }
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
            // Use userSelectedSessionId which is updated by session_id_resolved
            try await _agentRepository.stopClaude(sessionId: userSelectedSessionId, runtime: selectedSessionRuntime)
            // Update state immediately after successful stop
            // (don't wait for WebSocket event which may be delayed or missing)
            agentState = .idle
            isStreaming = false
            streamingStartTime = nil
            spinnerMessage = nil
            hasActiveConversation = false
            AppLogger.log("[Dashboard] Claude stopped via stopClaude()")
            Haptics.success()
        } catch {
            // Check if this is a "session not found" error
            // If so, the session is already gone - reset state instead of showing error
            let errorMessage = String(describing: error).lowercased()
            if errorMessage.contains("session not found") || errorMessage.contains("session_not_found") {
                AppLogger.log("[Dashboard] Session not found during stop - resetting state")
                agentState = .idle
                isStreaming = false
                streamingStartTime = nil
                spinnerMessage = nil
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
                requestId: interaction.requestId,
                runtime: selectedSessionRuntime
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
                requestId: interaction.requestId,
                runtime: selectedSessionRuntime
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
                requestId: interaction.requestId,
                runtime: selectedSessionRuntime
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
            try await _agentRepository.sendInput(sessionId: sessionId, input: "escape", runtime: selectedSessionRuntime)
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

    /// Validate that a PTY option key is valid
    /// PTY mode keys: numbers (1-9), letters (n, y, etc.), special keys (esc, enter, tab)
    /// Hook bridge mode keys: allow_once, allow_session, deny
    private func isValidPTYOptionKey(_ key: String) -> Bool {
        // PTY mode keys (keyboard shortcuts)
        let ptyKeys = Set(["1", "2", "3", "4", "5", "6", "7", "8", "9",
                           "n", "y", "esc", "escape", "enter", "return", "tab"])
        // Hook bridge mode keys (semantic actions)
        let hookBridgeKeys = Set(["allow_once", "allow_session", "deny"])

        let lowercasedKey = key.lowercased()
        return ptyKeys.contains(lowercasedKey) ||
               hookBridgeKeys.contains(lowercasedKey) ||
               key.count == 1
    }

    // MARK: - PTY Mode Permission Responses

    /// Respond to PTY permission by navigating to the selected option and pressing enter.
    /// Supports both PTY mode (session/input) and hook bridge mode (permission/respond).
    ///
    /// PTY mode: Uses arrow key navigation to reach target option and press enter.
    /// Hook bridge mode: Uses permission/respond RPC with toolUseId.
    func respondToPTYPermission(key: String) async {
        guard let interaction = pendingInteraction, interaction.isPTYMode else { return }
        Haptics.light()

        // Check if this is hook bridge mode (toolUseId present)
        if interaction.isHookBridgeMode {
            await respondToHookBridgePermission(interaction: interaction, key: key)
            return
        }

        // PTY mode: Use session/input with arrow key navigation
        await respondToPTYModePermission(interaction: interaction, key: key)
    }

    /// Respond to hook bridge permission using permission/respond RPC
    private func respondToHookBridgePermission(interaction: PendingInteraction, key: String) async {
        guard let toolUseId = interaction.toolUseId else {
            AppLogger.log("[Dashboard] Hook bridge mode but no toolUseId", type: .error)
            return
        }

        // Map key to decision and scope
        // Options typically are: "allow_once", "allow_session", "deny"
        let (decision, scope) = mapKeyToDecisionAndScope(key: key, options: interaction.ptyOptions)

        AppLogger.log("[Dashboard] Hook bridge permission: toolUseId=\(toolUseId), key=\(key), decision=\(decision.rawValue), scope=\(scope.rawValue)")

        do {
            try await _agentRepository.respondToPermission(
                toolUseId: toolUseId,
                decision: decision,
                scope: scope
            )
            pendingInteraction = nil
            AppLogger.log("[Dashboard] Hook bridge permission responded successfully", type: .success)
        } catch {
            // Check if this is a "request not found or already responded" error
            // This can happen if user responded on desktop, cancelled, or closed Claude Code
            // In this case, silently dismiss the permission UI instead of showing an error
            if isPermissionAlreadyHandledError(error) {
                AppLogger.log("[Dashboard] Permission request already handled elsewhere - dismissing silently", type: .info)
                pendingInteraction = nil
                return
            }

            self.error = error as? AppError ?? .unknown(underlying: error)
            AppLogger.log("[Dashboard] Hook bridge permission response failed: \(error)", type: .error)
        }
    }

    /// Check if error indicates the permission request was already handled elsewhere
    /// This happens when user responds on desktop, cancels request, or closes Claude Code
    private func isPermissionAlreadyHandledError(_ error: Error) -> Bool {
        // Check for JSON-RPC internal error (-32603) which is returned for "Request not found or already responded"
        if let rpcError = error as? JSONRPCClientError {
            switch rpcError {
            case .protocolError(let stdError, _) where stdError == .internalError:
                return true
            default:
                break
            }
        }

        // Also check error message for the specific text (in case error wrapping changes)
        let errorMessage = error.localizedDescription.lowercased()
        if errorMessage.contains("request not found") || errorMessage.contains("already responded") {
            return true
        }

        return false
    }

    /// Map option key to permission decision and scope for hook bridge mode
    private func mapKeyToDecisionAndScope(key: String, options: [PTYPromptOption]?) -> (PermissionDecision, PermissionScope) {
        // Find the option by key to check its label
        let option = options?.first { $0.key == key }
        let label = option?.label.lowercased() ?? ""

        // Check option key patterns from hook bridge
        // Common keys: "allow_once", "allow_session", "deny"
        switch key.lowercased() {
        case "allow_once", "1":
            return (.allow, .once)
        case "allow_session", "2":
            return (.allow, .session)
        case "deny", "n", "3":
            return (.deny, .once)
        default:
            // Infer from label if key doesn't match standard patterns
            if label.contains("session") {
                return (.allow, .session)
            } else if label.contains("yes") || label.contains("allow") {
                return (.allow, .once)
            } else if label.contains("no") || label.contains("deny") {
                return (.deny, .once)
            }
            // Default to allow once
            return (.allow, .once)
        }
    }

    /// Respond to PTY mode permission using session/input with arrow key navigation
    private func respondToPTYModePermission(interaction: PendingInteraction, key: String) async {
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
                try await _agentRepository.sendInput(sessionId: sessionId, input: direction, runtime: selectedSessionRuntime)
                AppLogger.log("[Dashboard] PTY sent '\(direction)' (\(i + 1)/\(keyPresses))")
                // Small delay between key presses to ensure they're processed in order
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }

            // Send "enter" to confirm selection
            try await _agentRepository.sendInput(sessionId: sessionId, input: "enter", runtime: selectedSessionRuntime)
            pendingInteraction = nil
            AppLogger.log("[Dashboard] PTY permission responded: navigated to option '\(key)' and pressed enter")
        } catch {
            self.error = error as? AppError ?? .unknown(underlying: error)
            AppLogger.log("[Dashboard] PTY response failed: \(error)", type: .error)
        }
    }

    /// Approve PTY permission (sends "1" for Yes / allow_once)
    func approvePTYPermission() async {
        await respondToPTYPermission(key: "1")
        Haptics.success()
    }

    /// Approve all PTY permissions (sends "2" for Yes All / allow_session)
    func approveAllPTYPermissions() async {
        await respondToPTYPermission(key: "2")
        Haptics.success()
    }

    /// Deny PTY permission (sends "n" for No / deny)
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

            // IMPORTANT: Preserve user/runtime-selected session context.
            // Note: workspace/status watchedSessionId may reflect another runtime.
            let currentSessionId = agentStatus.sessionId
            let watchedId = wsStatus.watchedSessionId
            let resolvedSessionId: String?
            if let userSelected = userSelectedSessionId, !userSelected.isEmpty {
                resolvedSessionId = userSelected
            } else if let watched = watchedId, !watched.isEmpty {
                resolvedSessionId = watched
            } else if let current = currentSessionId, !current.isEmpty {
                resolvedSessionId = current
            } else {
                resolvedSessionId = nil
            }
            AppLogger.log("[Dashboard] refreshStatus: resolving sessionId - watchedSessionId=\(watchedId ?? "nil"), currentSessionId=\(currentSessionId ?? "nil"), userSelectedSessionId=\(userSelectedSessionId ?? "nil") -> \(resolvedSessionId ?? "nil")")

            // Update agentStatus from workspace status
            agentStatus = AgentStatus(
                claudeState: agentState,  // Keep current agentState (updated via events)
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
        seenContentHashes.removeAll()
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

    private func resetStateForRuntimeSwitch() async {
        sessionHistoryLoadToken = UUID()
        isInitialLoadInProgress = false
        isReconnectionInProgress = false
        await clearLogs()
        isSessionPinnedByUser = false
        hasActiveConversation = false
        isPendingTrustFolder = false
        clearPendingTempSession(reason: "runtime switch reset", clearAll: true)
        pendingInteraction = nil
        setSelectedSession(nil)

        agentState = .idle
        isStreaming = false
        spinnerMessage = nil
        streamingStartTime = nil
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

        // Skip if waiting for session_id_resolved
        guard !isPendingTempSessionForActiveWindow() else {
            AppLogger.log("[Dashboard] loadRecentSessionHistory skipped - pending session_id_resolved")
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

        let targetWindowId = activeTerminalWindowId
        let windowOperationToken = beginWindowOperation(windowId: targetWindowId)
        func isCurrentWindowOperation(_ stage: String) -> Bool {
            let isCurrent = isWindowOperationCurrent(windowId: targetWindowId, token: windowOperationToken)
            if !isCurrent {
                AppLogger.log("[Dashboard] loadRecentSessionHistory aborted at \(stage) - stale window operation")
            }
            return isCurrent
        }
        guard isCurrentWindowOperation("start") else { return }

        let loadToken = UUID()
        sessionHistoryLoadToken = loadToken
        isInitialLoadInProgress = true
        AppLogger.log("[Dashboard] Starting loadRecentSessionHistory (reconnection: \(isReconnection))")

        defer {
            if sessionHistoryLoadToken == loadToken {
                isInitialLoadInProgress = false
                hasCompletedInitialLoad = true
                if isReconnection {
                    isReconnectionInProgress = false
                }
            }
        }

        do {
            // Determine which session to load:
            // 1. If userSelectedSessionId is set and pinned by user, keep it
            // 2. Otherwise, use the latest session from history
            var sessionId: String?

            let latestSessionId = await getMostRecentSessionId()
            guard sessionHistoryLoadToken == loadToken else {
                AppLogger.log("[Dashboard] loadRecentSessionHistory aborted - superseded")
                return
            }
            guard isCurrentWindowOperation("after getMostRecentSessionId") else { return }
            if let existingSessionId = userSelectedSessionId, !existingSessionId.isEmpty {
                // In multi-tab mode, preserve the currently selected tab session.
                // Auto-switching to "latest" causes cross-tab session convergence.
                sessionId = existingSessionId
                AppLogger.log("[Dashboard] Preserving active tab session: \(existingSessionId)")
            } else {
                sessionId = latestSessionId
                AppLogger.log("[Dashboard] Using latest session: \(sessionId ?? "none")")
            }

            guard let sessionId = sessionId, !sessionId.isEmpty else {
                AppLogger.log("[Dashboard] No session history available")
                return
            }

            AppLogger.log("[Dashboard] Loading history for session: \(sessionId)")
            guard isCurrentWindowOperation("before applying session history") else { return }

            // Only clear if loading a different session (prevents flashing on reconnect)
            let isNewSession = userSelectedSessionId != sessionId
            let beforeCount = chatElements.count

            if isNewSession {
                await logCache.clear()
                guard isCurrentWindowOperation("after clear for new session") else { return }
                chatElements = []
                seenElementIds.removeAll()  // Clear deduplication sets
                seenContentHashes.removeAll()
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
            guard isCurrentWindowOperation("after startWatchingCurrentSession") else { return }

            // Yield to let UI thread breathe before network call
            await Task.yield()
            guard isCurrentWindowOperation("after yield before fetch") else { return }

            // Get first page of messages for the session
            AppLogger.log("[Dashboard] Fetching messages for session: \(sessionId)")
            let fetchedBatch: SessionHistoryMessageBatch
            do {
                fetchedBatch = try await fetchMessagesForSessionHistory(
                    sessionId: sessionId,
                    isReconnection: isReconnection,
                    isNewSession: isNewSession
                )
            } catch {
                AppLogger.error(error, context: "Fetch session messages")
                throw error
            }

            guard sessionHistoryLoadToken == loadToken else {
                AppLogger.log("[Dashboard] loadRecentSessionHistory aborted - superseded")
                return
            }
            guard isCurrentWindowOperation("after fetchSessionHistory") else { return }

            // Update pagination state after optional catch-up pages.
            messagesHasMore = fetchedBatch.hasMore
            messagesNextOffset = fetchedBatch.nextOffset
            messagesTotalCount = fetchedBatch.total

            // Yield after network call to prevent UI starvation
            await Task.yield()

            // Only add messages if there are any
            guard !fetchedBatch.messages.isEmpty else {
                AppLogger.log("[Dashboard] Session has no messages")
                logs = []
                return
            }

            // Convert to log entries and ChatElements (skip tool messages with no text)
            // Reverse messages since API returns desc (newest first) but UI shows oldest at top
            let chronologicalMessages = Array(fetchedBatch.messages.reversed())
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

            AppLogger.log("[Dashboard] Created \(entriesAdded) log entries and \(afterCount) elements from \(fetchedBatch.messages.count) messages (deduplicated)")

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

            if isSessionNotFoundError(error) {
                AppLogger.log("[Dashboard] Session not found during history load - clearing session state")
                await handleSessionNotFound(context: "history load", refreshHistory: false)
            }
        }
        AppLogger.log("[Dashboard] loadRecentSessionHistory completed")
    }

    private struct SessionHistoryMessageBatch {
        let messages: [SessionMessagesResponse.SessionMessage]
        let total: Int
        let hasMore: Bool
        let nextOffset: Int
    }

    private func fetchMessagesForSessionHistory(
        sessionId: String,
        isReconnection: Bool,
        isNewSession: Bool
    ) async throws -> SessionHistoryMessageBatch {
        let previousKnownTotal = messagesTotalCount

        let initialPage = try await fetchSessionMessagesPage(
            runtime: selectedSessionRuntime,
            sessionId: sessionId,
            limit: messagesPageSize,
            offset: 0,
            order: "desc"
        )
        AppLogger.log("[Dashboard] Got initial page: \(initialPage.count) of \(initialPage.total), hasMore=\(initialPage.hasMore)")

        // On reconnection, fetch enough additional pages to cover messages produced while disconnected.
        // This keeps catch-up reliable without replaying the entire session.
        var messages = initialPage.messages
        var total = initialPage.total
        var hasMore = initialPage.hasMore
        var nextOffset = initialPage.nextOffset

        let shouldCatchUp = isReconnection && !isNewSession && previousKnownTotal > 0 && total > previousKnownTotal
        if shouldCatchUp {
            var remainingMissed = max(0, (total - previousKnownTotal) - messages.count)
            AppLogger.log("[Dashboard] Reconnection catch-up: previousTotal=\(previousKnownTotal), latestTotal=\(total), remainingMissed=\(remainingMissed)")

            while remainingMissed > 0 && hasMore {
                let extraPage = try await fetchSessionMessagesPage(
                    runtime: selectedSessionRuntime,
                    sessionId: sessionId,
                    limit: messagesPageSize,
                    offset: nextOffset,
                    order: "desc"
                )

                messages.append(contentsOf: extraPage.messages)
                nextOffset = extraPage.nextOffset
                hasMore = extraPage.hasMore
                total = max(total, extraPage.total)
                remainingMissed = max(0, remainingMissed - extraPage.count)

                AppLogger.log("[Dashboard] Reconnection catch-up page: +\(extraPage.count), remainingMissed=\(remainingMissed), nextOffset=\(nextOffset), hasMore=\(hasMore)")
            }
        }

        return SessionHistoryMessageBatch(
            messages: messages,
            total: total,
            hasMore: hasMore,
            nextOffset: nextOffset
        )
    }

    private func reconcileAvailableRuntimes(context: String) {
        let result = runtimeCoordinator.reconcileRuntimeSelection(currentRuntime: selectedSessionRuntime)

        if availableRuntimes != result.availableRuntimes {
            availableRuntimes = result.availableRuntimes
            AppLogger.log("[Dashboard] Available runtimes (\(context)): \(result.availableRuntimes.map { $0.rawValue }.joined(separator: ", "))")
        }

        if let fallback = result.fallbackRuntime {
            AppLogger.log(
                "[Dashboard] Runtime fallback (\(context)): \(selectedSessionRuntime.rawValue) -> \(fallback.rawValue)",
                type: .warning
            )
            selectedSessionRuntime = fallback
        }
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
                    self.reconcileAvailableRuntimes(context: "reconnect")

                    // Re-subscribe to workspace events
                    if let workspaceId = self.currentWorkspaceId {
                        AppLogger.log("[Dashboard] Reconnected - re-subscribing to workspace: \(workspaceId)")
                        try? await WorkspaceManagerService.shared.subscribe(workspaceId: workspaceId)
                    }

                    AppLogger.log("[Dashboard] Reconnected - starting loadRecentSessionHistory")
                    await self.loadRecentSessionHistory(isReconnection: true)
                    AppLogger.log("[Dashboard] Reconnected - syncing session/state")
                    await self.syncCurrentSessionRuntimeState(context: "reconnect")
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
                        // Keep session tracking/persistence consistent after reconnect.
                        if self.userSelectedSessionId == nil {
                            self.setSelectedSession(sessionId)
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
                    self.reconcileAvailableRuntimes(context: "disconnected")
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
        if shouldMarkStreamEvent(event) {
            markStreamEvent(source: event.type.rawValue)
        }

        // Route agent-specific stream events by runtime to prevent Claude/Codex cross-talk.
        // Some lifecycle events are runtime-agnostic and must pass even without agent_type.
        if !event.matchesRuntime(selectedSessionRuntime)
            && !shouldBypassRuntimeRouting(for: event)
            && !shouldAcceptLegacyUntypedEvent(event) {
            AppLogger.log("[Dashboard] Skipping \(event.type.rawValue) event for agent_type=\(event.agentType ?? "nil"), selected_runtime=\(selectedSessionRuntime.rawValue)")
            return
        }

        // Guard against cross-tab bleed when active tab has no bound session:
        // session-scoped events without session_id cannot be safely routed.
        if shouldRouteEventBySession(event),
           !isPendingTempSessionForActiveWindow(),
           (activeWindowSessionIdForRouting() == nil || activeWindowSessionIdForRouting()?.isEmpty == true),
           normalizedSessionId(event.sessionId) == nil {
            AppLogger.log("[Dashboard] Dropping unscoped session event - eventType=\(event.type.rawValue), eventSession=nil, \(routingDebugContext())")
            return
        }

        if let bufferedSessionId = shouldBufferEventForInactiveWindow(event) {
            bufferEvent(event, for: bufferedSessionId)
            AppLogger.log("[Dashboard] Buffered event for inactive window - eventType=\(event.type.rawValue), bufferedSession=\(bufferedSessionId), eventSession=\(normalizedSessionId(event.sessionId) ?? "nil"), \(routingDebugContext())")
            return
        }

        switch event.type {
        case .claudeMessage:
            // NEW: Structured message with content blocks
            // Convert to ChatElements for sophisticated UI
            if case .claudeMessage(let payload) = event.payload {
                // IMPORTANT: Validate session ID to prevent messages from other sessions
                // Skip this event if it belongs to a different session than the one we're viewing
                if let eventSessionId = payload.sessionId,
                   !eventSessionId.isEmpty,
                   let selectedSessionId = activeWindowSessionIdForRouting(),
                   !selectedSessionId.isEmpty,
                   eventSessionId != selectedSessionId {
                    AppLogger.log("[Dashboard] claude_message skipped - session mismatch (event: \(eventSessionId), selected: \(selectedSessionId))")
                    return
                }

                // Structured messages are flowing for this session - disable PTY fallback
                hasReceivedClaudeMessageForSession = true

                AppLogger.log("[Dashboard] claude_message received - uuid: \(payload.uuid ?? "nil"), role: \(payload.effectiveRole ?? "nil"), sessionId: \(payload.sessionId ?? "nil")")

                // Skip user message echoes from real-time events (already shown optimistically)
                // BUT ONLY skip messages sent by THIS CLIENT, not from other clients (e.g., Claude Code CLI)
                // ALWAYS show bash mode OUTPUT (stdout/stderr) which is server-generated
                let textContent = payload.effectiveContent?.textContent ?? ""
                if ChatContentFilter.shouldHideInternalMessage(textContent) {
                    AppLogger.log("[Dashboard] Skipping internal caveat claude_message")
                    return
                }

                if payload.effectiveRole == "user" {
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

                let isCodexRuntime = selectedSessionRuntime == .codex

                // Keep thinking text from claude_message in the bottom streaming bar.
                // For Codex, we still suppress thinking rows in chat and only show the bar.
                if let thinkingText = codexThinkingText(from: payload) {
                    spinnerMessage = codexSpinnerMessage(from: thinkingText)
                    if !isStreaming {
                        isStreaming = true
                        streamingStartTime = Date()
                    }
                    if agentState != .running {
                        agentState = .running
                    }
                }

                var elements = ChatElement.from(payload: payload)
                if isCodexRuntime {
                    elements.removeAll { $0.type == .thinking }
                }
                let beforeToolFilter = elements.count
                elements.removeAll(where: shouldHideToolElementFromChatList)
                if elements.count != beforeToolFilter {
                    AppLogger.log("[Dashboard] Filtered \(beforeToolFilter - elements.count) tool element(s) from claude_message")
                }

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
                    // Set fallback spinner message for LIVE mode (no pty_spinner events)
                    if spinnerMessage == nil {
                        spinnerMessage = "Thinking... (\(Self.mobileStopText))"
                    }
                    // Also set claude state to running if not already
                    if agentState != .running {
                        agentState = .running
                    }
                    AppLogger.log("[Dashboard] Streaming started (thinking)")
                } else if !isStillStreaming && isStreaming {
                    // Thinking blocks paused. If runtime is still running, keep the last
                    // thinking text so the bottom bar remains consistent with stop/running UI.
                    isStreaming = false
                    if agentState != .running {
                        spinnerMessage = nil
                        if let startTime = streamingStartTime {
                            let duration = Date().timeIntervalSince(startTime)
                            AppLogger.log("[Dashboard] Streaming stopped after \(String(format: "%.1f", duration))s")
                        }
                        streamingStartTime = nil
                    } else {
                        AppLogger.log("[Dashboard] Streaming flag paused while runtime still running - preserving thinking text")
                    }
                }

                // In interactive mode, update isLoading based on claude_message
                // Note: agentState is managed by pty_state events in interactive mode
                if isInteractiveMode {
                    // Reset isLoading when we receive any assistant message (Claude is responding)
                    if payload.effectiveRole == "assistant" && isLoading {
                        isLoading = false
                        AppLogger.log("[Dashboard] Interactive mode: Reset isLoading (received assistant message)")
                    }

                    // Only use stop_reason as a fallback if pty_state isn't working
                    if let stopReason = payload.stopReason, !stopReason.isEmpty {
                        // Claude finished - set to idle
                        if agentState == .running {
                            agentState = .idle
                            AppLogger.log("[Dashboard] Interactive mode: Claude finished (stop_reason: \(stopReason))")
                        }
                    }
                    // Don't set agentState = .running here - pty_state handles state transitions
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
                let previousState = agentState
                agentState = state
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
                let activeSessionId = activeWindowSessionIdForRouting()
                if let activeSessionId,
                   !activeSessionId.isEmpty,
                   activeSessionId != sessionId {
                    AppLogger.log("[Dashboard] Ignoring claude_session_info for inactive session (event=\(sessionId), active=\(activeSessionId))")
                    return
                }

                // Safety: when the active tab has no session yet and isn't pending a new session
                // resolution, do not let background session_info hijack this tab.
                if (activeSessionId == nil || activeSessionId?.isEmpty == true),
                   !isPendingTempSessionForActiveWindow() {
                    AppLogger.log("[Dashboard] Ignoring claude_session_info while active tab has no pending session (event=\(sessionId))")
                    return
                }

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
                agentState = .waiting  // Update state to show waiting indicator
                Haptics.warning()

                // Check if this is a trust_folder permission - session APIs won't work until approved
                // Also mark as pending temp session since session_id_resolved will provide real ID
                if payload.type == .trustFolder {
                    isPendingTrustFolder = true
                    setPendingTempSessionForActiveWindow()
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
                let input = payload.input ?? payload.decision ?? "unknown"
                let toolUseId = payload.toolUseId
                AppLogger.log("[Dashboard] PTY permission resolved by another device: resolvedBy=\(resolvedBy), input=\(input), toolUseId=\(toolUseId ?? "nil")")

                // Clear the pending permission UI if it matches
                // For hook bridge mode: match by toolUseId for accurate correlation
                // For PTY mode: match any pending PTY permission
                var shouldDismiss = false
                if let pending = pendingInteraction, pending.isPTYMode {
                    if let eventToolUseId = toolUseId, !eventToolUseId.isEmpty {
                        // Hook bridge mode: match by toolUseId
                        if pending.toolUseId == eventToolUseId {
                            shouldDismiss = true
                            AppLogger.log("[Dashboard] Hook bridge permission matched by toolUseId")
                        } else {
                            AppLogger.log("[Dashboard] Hook bridge permission toolUseId mismatch: pending=\(pending.toolUseId ?? "nil"), event=\(eventToolUseId)")
                        }
                    } else {
                        // PTY mode: dismiss any pending PTY permission
                        shouldDismiss = true
                        AppLogger.log("[Dashboard] PTY mode permission resolved")
                    }
                }

                if shouldDismiss {
                    pendingInteraction = nil
                    Haptics.light()
                    AppLogger.log("[Dashboard] Dismissed local permission popup - resolved by another device")

                    // Clear the badge since permission was handled
                    // NotificationService.shared.clearPermissionNotification()
                }

                // Update claude state based on the resolution
                if payload.wasApproved {
                    agentState = .running
                } else if payload.wasDenied {
                    // Permission was denied, Claude may still be waiting or idle
                    agentState = .idle
                }
            }

        case .ptyOutput:
            // PTY mode terminal output - use as fallback when claude_message isn't emitted
            guard isInteractiveMode else { return }
            guard case .ptyOutput(let payload) = event.payload,
                  let cleanTextRaw = payload.cleanText else {
                return
            }

            let cleanText = cleanTextRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { return }

            if let eventSessionId = payload.sessionId,
               let selectedSessionId = activeWindowSessionIdForRouting(),
               !selectedSessionId.isEmpty,
               eventSessionId != selectedSessionId {
                AppLogger.log("[Dashboard] PTY output skipped - session mismatch (event: \(eventSessionId), selected: \(selectedSessionId))")
                return
            }

            if cleanText == lastPtyOutputLine {
                return
            }
            lastPtyOutputLine = cleanText

            if hasReceivedClaudeMessageForSession {
                AppLogger.log("[Dashboard] PTY output ignored (structured messages active)")
                return
            }

            if let assistantText = parsePtyAssistantText(cleanText) {
                if ChatContentFilter.shouldHideInternalMessage(assistantText) {
                    return
                }

                queueChatElements([ChatElement.assistantText(assistantText)])

                let entry = LogEntry(
                    timestamp: event.timestamp,
                    content: assistantText,
                    stream: .stdout,
                    sessionId: payload.sessionId
                )
                await logCache.add(entry)
                scheduleLogUpdate()

                if isLoading {
                    isLoading = false
                }
            } else {
                AppLogger.log("[Dashboard] PTY output (ignored): \(cleanText.prefix(80))")
            }

        case .ptyState:
            // PTY state change (idle, thinking, permission, question, error)
            if case .ptyState(let payload) = event.payload {
                if let state = payload.state {
                    let previousClaudeState = agentState
                    let wasPendingTrust = isPendingTrustFolder

                    // Map PTY state to Claude state
                    switch state {
                    case .idle:
                        agentState = .idle
                        isLoading = false  // Also reset loading when idle
                        isStreaming = false
                        streamingStartTime = nil
                        spinnerMessage = nil  // Clear spinner message when idle
                    case .thinking:
                        agentState = .running
                        // Set fallback spinner message for LIVE mode (no pty_spinner events)
                        // if spinnerMessage == nil {
                        //     spinnerMessage = "Thinking... (\(Self.mobileStopText))"
                        // }
                    case .permission, .question:
                        agentState = .waiting
                        isStreaming = false
                        streamingStartTime = nil
                        spinnerMessage = nil
                    case .error:
                        agentState = .error
                        isStreaming = false
                        streamingStartTime = nil
                        spinnerMessage = nil
                    }
                    AppLogger.log("[Dashboard] PTY state: \(state) → agentState: \(previousClaudeState) → \(agentState)")

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
                // Replace keyboard shortcuts with mobile-friendly text (no esc/ctrl+c on mobile)
                var message = payload.text ?? payload.message
                message = message?
                    .replacingOccurrences(of: "esc to interrupt", with: Self.mobileStopText)
                    .replacingOccurrences(of: "ctrl+c to interrupt", with: Self.mobileStopText)
                spinnerMessage = message

                // pty_spinner indicates Claude is actively working - set to running
                if agentState != .running {
                    agentState = .running
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
                agentState = agentStatus.claudeState
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
            // This happens after:
            // 1. User accepts trust_folder for a new workspace
            // 2. Starting a new session with mode="new" (no session_id sent)
            if case .sessionIdResolved(let payload) = event.payload,
               let tempId = payload.temporaryId,
               let realId = payload.realId {
                let workspaceId = payload.workspaceId
                AppLogger.log("[Dashboard] Session ID resolved: temp=\(tempId) → real=\(realId), workspace=\(workspaceId ?? "nil")")
                AppLogger.log("[Dashboard] Current state: userSelectedSessionId=\(userSelectedSessionId ?? "nil"), agentState=\(agentState), watchingSessionId=\(watchingSessionId ?? "nil")")
                let pendingTempBefore = isPendingTempSession

                let targetWindowId = pendingWindowIdForIncomingTempSession(tempId)
                let shouldAccept = targetWindowId != nil || userSelectedSessionId == tempId
                let shouldSwitchActiveContext = targetWindowId == nil || targetWindowId == activeTerminalWindowId
                AppLogger.log("[Dashboard] session_id_resolved decision: shouldAccept=\(shouldAccept), pendingTempBefore=\(pendingTempBefore), temp=\(tempId), real=\(realId), selected=\(userSelectedSessionId ?? "nil"), targetWindow=\(targetWindowId?.uuidString ?? "nil"), activeWindow=\(activeTerminalWindowId?.uuidString ?? "nil"), switchActive=\(shouldSwitchActiveContext)")

                if shouldAccept {
                    AppLogger.log("[Dashboard] Updating session tracking to real ID: \(realId)")

                    // Persist the resolved session ID onto the window that initiated the pending session.
                    if let appState, let targetWindowId {
                        appState.setTerminalWindowSession(targetWindowId, sessionId: realId)
                        AppLogger.log("[Dashboard] session_id_resolved window update: window=\(targetWindowId), session=\(realId)")
                    }
                    if let targetWindowId {
                        pendingTempSessionIdByWindowId[targetWindowId] = realId
                    }
                    if tempId != realId,
                       let bufferedTempEvents = bufferedEventsBySessionId.removeValue(forKey: tempId),
                       !bufferedTempEvents.isEmpty {
                        var existingRealEvents = bufferedEventsBySessionId[realId] ?? []
                        existingRealEvents.append(contentsOf: bufferedTempEvents)
                        if existingRealEvents.count > maxBufferedEventsPerSession {
                            existingRealEvents.removeFirst(existingRealEvents.count - maxBufferedEventsPerSession)
                        }
                        bufferedEventsBySessionId[realId] = existingRealEvents
                        AppLogger.log("[Dashboard] Moved \(bufferedTempEvents.count) buffered event(s) temp->real (\(tempId) -> \(realId))")
                    }

                    // Clear pending temp session flag - we now have real ID
                    clearPendingTempSession(reason: "session_id_resolved", windowId: targetWindowId)
                    AppLogger.log("[Dashboard] session_id_resolved pending flag: \(pendingTempBefore) -> \(isPendingTempSession)")

                    // Update visible session context only when the pending window is active.
                    if shouldSwitchActiveContext {
                        setSelectedSession(realId)
                    } else {
                        AppLogger.log("[Dashboard] session_id_resolved applied to background window only; preserving active session \(userSelectedSessionId ?? "nil")")
                    }

                    // Update WorkspaceManagerService to keep session state consistent
                    // This ensures stopClaude and other operations use the correct session ID
                    let effectiveWorkspaceId = workspaceId ?? currentWorkspaceId
                    if let wsId = effectiveWorkspaceId {
                        let newSession = Session(
                            id: realId,
                            workspaceId: wsId,
                            status: .running,
                            startedAt: Date(),
                            lastActive: nil,
                            summary: nil,
                            messageCount: nil,
                            lastUpdated: nil,
                            claudeState: "running",
                            claudeSessionId: nil,
                            isRunning: true,
                            waitingForInput: false,
                            pendingToolUseId: nil,
                            pendingToolName: nil,
                            viewers: nil
                        )
                        WorkspaceManagerService.shared.updateWorkspaceSession(workspaceId: wsId, session: newSession)
                        AppLogger.log("[Dashboard] Updated WorkspaceManagerService with new session: \(realId)")
                    }

                    // Watch the resolved session only if it belongs to active window context.
                    if shouldSwitchActiveContext {
                        Task {
                            AppLogger.log("[Dashboard] Watching session with real ID: \(realId), workspace: \(effectiveWorkspaceId ?? "nil")")
                            let watchOwnerId = self.currentSessionWatchOwnerId()
                            let targetRuntime = targetWindowId
                                .flatMap { id in self.terminalWindows.first(where: { $0.id == id && $0.isOpen })?.runtime }
                                ?? self.selectedSessionRuntime
                            // Stop any existing watch first
                            await stopWatchingSession()

                            // Watch the new session with workspace_id from event (or fallback to currentWorkspaceId)
                            do {
                                try await webSocketService.watchSession(
                                    realId,
                                    workspaceId: effectiveWorkspaceId,
                                    runtime: targetRuntime,
                                    ownerId: watchOwnerId
                                )
                                isWatchingSession = true
                                watchingSessionId = realId
                                syncActiveTerminalWindowContext(sessionId: realId)
                                AppLogger.log("[Dashboard] Now watching session: \(realId)")
                            } catch {
                                AppLogger.log("[Dashboard] Failed to watch session \(realId): \(error)", type: .error)
                            }
                        }
                    } else if let targetWindowId {
                        Task {
                            let targetRuntime = self.terminalWindows.first(where: { $0.id == targetWindowId && $0.isOpen })?.runtime ?? self.selectedSessionRuntime
                            do {
                                try await self.webSocketService.watchSession(
                                    realId,
                                    workspaceId: effectiveWorkspaceId,
                                    runtime: targetRuntime,
                                    ownerId: self.watchOwnerId(for: targetWindowId)
                                )
                                AppLogger.log("[Dashboard] Ensured background watch for resolved session: window=\(targetWindowId), session=\(realId), runtime=\(targetRuntime.rawValue)")
                            } catch {
                                AppLogger.log("[Dashboard] Failed background watch for resolved session \(realId): \(error)", type: .warning)
                            }
                        }
                    }
                } else {
                    AppLogger.log("[Dashboard] Session ID resolution for different session (current=\(userSelectedSessionId ?? "nil"), temp=\(tempId), agentState=\(agentState))")
                    AppLogger.log("[Dashboard] session_id_resolved ignored: pendingTemp=\(isPendingTempSession), temp=\(tempId), real=\(realId)")
                }
            }

        case .sessionIdFailed:
            // Session ID resolution failed (e.g., user declined trust_folder)
            AppLogger.log("[Dashboard] Received session_id_failed event - payload type: \(type(of: event.payload))")

            // Extract payload details if available
            var tempId = "unknown"
            var failedSessionId = event.sessionId
            var workspaceId = event.workspaceId
            var reason = "unknown"
            var message = "Session failed to start"

            if case .sessionIdFailed(let payload) = event.payload {
                tempId = payload.temporaryId ?? "unknown"
                failedSessionId = payload.sessionId ?? payload.temporaryId ?? failedSessionId
                workspaceId = payload.workspaceId ?? workspaceId
                reason = payload.reason ?? "unknown"
                message = payload.message ?? "Session failed to start"
            }

            if (failedSessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && tempId != "unknown" {
                failedSessionId = tempId
            }

            AppLogger.log("[Dashboard] Session ID failed: temp=\(tempId), session=\(failedSessionId ?? "nil"), workspace=\(workspaceId ?? "nil"), reason=\(reason), message=\(message)")

            // Clear pending states since session failed
            let pendingLookupSessionId = tempId != "unknown" ? tempId : failedSessionId
            let failedPendingWindowId = pendingWindowIdForIncomingTempSession(pendingLookupSessionId)
            clearPendingTempSession(
                reason: "session_id_failed",
                windowId: failedPendingWindowId,
                clearAll: failedPendingWindowId == nil
            )
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
            agentState = .idle
            hasActiveConversation = false

            // If user declined trust, return to workspace list and mark workspace idle
            if reason == "trust_declined" {
                let targetWorkspaceId = workspaceId ?? currentWorkspaceId
                if let workspaceId = targetWorkspaceId {
                    WorkspaceManagerService.shared.markWorkspaceIdle(
                        workspaceId: workspaceId,
                        failedSessionId: failedSessionId
                    )
                } else if let failedSessionId, !failedSessionId.isEmpty {
                    WorkspaceManagerService.shared.removeSessionFromWorkspace(sessionId: failedSessionId)
                }

                await stopWatchingSession()
                WorkspaceStore.shared.clearActive()
                Task { _ = try? await WorkspaceManagerService.shared.listWorkspaces() }
                shouldShowWorkspaceList = true
                AppLogger.log("[Dashboard] Trust declined - returning to workspace list and marking workspace idle (workspace=\(targetWorkspaceId ?? "nil"), session=\(failedSessionId ?? "nil"))")
            } else {
                // Stay on Dashboard - user can send a new message to start a fresh session
                AppLogger.log("[Dashboard] Session failed - staying on Dashboard, ready for new session")
            }

        case .streamReadComplete:
            // JSONL reader caught up to end of file - signal that Claude is done
            AppLogger.log("[Dashboard] Received stream_read_complete event, payload type: \(type(of: event.payload))")
            if case .streamReadComplete(let payload) = event.payload {
                let messagesEmitted = payload.messagesEmitted ?? 0
                let fileOffset = payload.fileOffset ?? 0
                let fileSize = payload.fileSize ?? 0
                AppLogger.log("[Dashboard] Stream read complete - messages: \(messagesEmitted), offset: \(fileOffset), size: \(fileSize), agentState: \(agentState)")

                // When file_offset == file_size, we've read the entire file - Claude is done
                if fileOffset == fileSize && fileSize > 0 {
                    AppLogger.log("[Dashboard] Setting agentState to .idle (was: \(agentState))")
                    agentState = .idle
                    isStreaming = false
                    streamingStartTime = nil
                    spinnerMessage = nil
                    AppLogger.log("[Dashboard] Claude finished - stream read complete (offset == size), agentState: \(agentState)")
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
                    agentState = .idle
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
                    agentState = .idle
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

        // MARK: - Hook Events (External Claude Sessions)

        case .claudeHookSession:
            // External Claude session started (VS Code, Cursor, terminal)
            if case .hookSession(let payload) = event.payload {
                externalSessionManager.handleSessionStart(payload)
                AppLogger.log("[Dashboard] External session: \(payload.projectName)")
            }

        case .claudeHookPermission:
            // Permission prompt in external session (read-only alert)
            if case .hookPermission(let payload) = event.payload {
                externalSessionManager.handlePermission(payload)
                Haptics.warning()  // Alert user
                AppLogger.log("[Dashboard] External permission: \(payload.tool ?? "?") - \(payload.displaySummary)")
            }

        case .claudeHookToolStart:
            // Tool started in external session
            if case .hookToolStart(let payload) = event.payload {
                externalSessionManager.handleToolStart(payload)
            }

        case .claudeHookToolEnd:
            // Tool ended in external session
            if case .hookToolEnd(let payload) = event.payload {
                externalSessionManager.handleToolEnd(payload)
            }

        default:
            break
        }
    }

    // MARK: - App Lifecycle (Foreground Reconciliation)

    func handleAppDidBecomeActive() {
        AppLogger.log("[Dashboard] App became active - reconciling state")
        isAppActive = true
        startStreamWatchdog()
        Task { await reconcileAfterForeground() }
    }

    func handleAppDidEnterBackground() {
        AppLogger.log("[Dashboard] App entered background - pausing watchdog")
        isAppActive = false
        stopStreamWatchdog()
    }

    private func reconcileAfterForeground() async {
        lastStreamEventAt = Date()
        lastWatchdogStatusCheckAt = nil

        if let status = try? await _agentRepository.fetchStatus() {
            applyStatus(status, context: "foreground")
        } else {
            AppLogger.log("[Dashboard] Foreground reconcile: status/get failed", type: .warning)
        }

        await loadRecentSessionHistory(isReconnection: true)
        await syncCurrentSessionRuntimeState(context: "foreground")
        await startWatchingCurrentSession(force: true)
        await refreshStatus()
    }

    private func startStreamWatchdog() {
        streamWatchdogTask?.cancel()
        streamWatchdogTask = Task { [weak self] in
            while let self = self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.streamWatchdogInterval * 1_000_000_000))
                guard self.isAppActive else { continue }
                guard self.connectionState.isConnected else { continue }
                guard self.isStreaming || self.agentState == .running else { continue }

                let lastEvent = self.lastStreamEventAt ?? self.streamingStartTime
                if let lastEvent, Date().timeIntervalSince(lastEvent) < self.streamStaleThreshold {
                    continue
                }

                let now = Date()
                if let lastCheck = self.lastWatchdogStatusCheckAt,
                   now.timeIntervalSince(lastCheck) < self.watchdogMinStatusCheckInterval {
                    continue
                }
                self.lastWatchdogStatusCheckAt = now
                await self.reconcileStreamStatus(reason: "watchdog")
            }
        }
    }

    private func stopStreamWatchdog() {
        streamWatchdogTask?.cancel()
        streamWatchdogTask = nil
    }

    private func reconcileStreamStatus(reason: String) async {
        guard let status = try? await _agentRepository.fetchStatus() else {
            AppLogger.log("[Dashboard] Watchdog status/get failed", type: .warning)
            return
        }
        applyStatus(status, context: reason)
    }

    private func applyStatus(_ status: AgentStatus, context: String) {
        let previous = agentState
        agentState = status.claudeState

        if status.claudeState != .running {
            isStreaming = false
            spinnerMessage = nil
            streamingStartTime = nil
            if status.claudeState == .idle || status.claudeState == .stopped || status.claudeState == .error {
                pendingInteraction = nil
            }
        }

        AppLogger.log("[Dashboard] reconcileStatus(\(context)) \(previous) → \(agentState)")
    }

    private func syncCurrentSessionRuntimeState(context: String) async {
        guard let sessionId = userSelectedSessionId, !sessionId.isEmpty else {
            AppLogger.log("[Dashboard] session/state sync skipped (\(context)) - no selected session")
            return
        }

        do {
            let runtimeState = try await workspaceManager.getSessionState(sessionId: sessionId)
            let syncedState = Self.mapClaudeState(from: runtimeState)
            let previousState = agentState

            agentState = syncedState
            agentStatus = AgentStatus(
                claudeState: syncedState,
                sessionId: agentStatus.sessionId ?? sessionId,
                repoName: agentStatus.repoName,
                repoPath: agentStatus.repoPath,
                connectedClients: agentStatus.connectedClients,
                uptime: agentStatus.uptime
            )

            // Reset streaming-only UI when runtime is not actively running.
            if syncedState != .running {
                isStreaming = false
                spinnerMessage = nil
                streamingStartTime = nil
            }

            // If runtime is no longer waiting, clear stale interaction UI.
            if runtimeState.waitingForInput != true && syncedState != .waiting {
                pendingInteraction = nil
            }

            let workspaceId = runtimeState.workspaceId
            if !workspaceId.isEmpty {
                workspaceManager.updateWorkspaceSession(workspaceId: workspaceId, session: runtimeState.toSession())
            }

            AppLogger.log("[Dashboard] session/state sync (\(context)): session=\(sessionId), agentState \(previousState) → \(syncedState), isRunning=\(runtimeState.isRunning ?? false), waitingForInput=\(runtimeState.waitingForInput ?? false), pendingTool=\(runtimeState.pendingToolName ?? "nil")")
        } catch {
            if isSessionNotFoundError(error) {
                AppLogger.log("[Dashboard] session/state sync (\(context)) skipped - session not active: \(sessionId)")
            } else {
                AppLogger.log("[Dashboard] session/state sync (\(context)) failed: \(error.localizedDescription)", type: .warning)
            }
        }
    }

    private static func mapClaudeState(from runtimeState: SessionStateResponse) -> ClaudeState {
        if let raw = runtimeState.claudeState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !raw.isEmpty {
            switch raw {
            case "running", "starting":
                return .running
            case "waiting", "permission", "question":
                return .waiting
            case "idle":
                return .idle
            case "stopped", "stopping":
                return .stopped
            case "error", "failed":
                return .error
            default:
                break
            }
        }

        if runtimeState.waitingForInput == true {
            return .waiting
        }
        if runtimeState.isRunning == true {
            return .running
        }
        return .idle
    }

    private func isStreamEvent(_ type: AgentEventType) -> Bool {
        switch type {
        case .claudeMessage, .ptySpinner, .ptyState, .streamReadComplete:
            return true
        default:
            return false
        }
    }

    private func shouldMarkStreamEvent(_ event: AgentEvent) -> Bool {
        guard isStreamEvent(event.type) else { return false }
        guard event.matchesRuntime(selectedSessionRuntime) || shouldAcceptLegacyUntypedEvent(event) else { return false }
        guard let selectedSessionId = userSelectedSessionId, !selectedSessionId.isEmpty else { return true }
        if let eventSessionId = event.sessionId, !eventSessionId.isEmpty {
            return eventSessionId == selectedSessionId
        }
        return true
    }

    /// Events that should not be blocked by runtime routing.
    /// session_id_failed may be emitted without agent_type but still needs immediate UI recovery.
    private func shouldBypassRuntimeRouting(for event: AgentEvent) -> Bool {
        switch event.type {
        case .sessionIdFailed, .sessionIdResolved, .ptyPermissionResolved:
            return true
        default:
            return false
        }
    }

    /// Legacy cdev builds may omit agent_type in event envelopes.
    /// Accept untyped stream events only when they target the active/watched session.
    private func shouldAcceptLegacyUntypedEvent(_ event: AgentEvent) -> Bool {
        // TEMP (test mode): backward compatibility fallback for untyped events is disabled.
        // Re-enable old logic here if you need to support legacy servers without agent_type.
        _ = event
        return false
    }

    private func markStreamEvent(source: String) {
        lastStreamEventAt = Date()
        AppLogger.log("[Dashboard] Stream activity: \(source)")
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
        let previousSessionId = userSelectedSessionId
        userSelectedSessionId = sessionId
        sessionRepository.selectedSessionId = sessionId

        if previousSessionId != sessionId {
            hasReceivedClaudeMessageForSession = false
            lastPtyOutputLine = nil
        }

        if let id = sessionId, !id.isEmpty {
            AppLogger.log("[Dashboard] Persisted selectedSessionId: \(id)")
            updateSessionId(id)
        } else {
            AppLogger.log("[Dashboard] Cleared selectedSessionId")
            updateSessionId("")
        }

        syncActiveTerminalWindowContext(sessionId: sessionId)
        persistWindowSnapshot(for: activeTerminalWindowId)
    }

    // MARK: - Session Error Helpers

    private func isSessionNotFoundError(_ error: Error) -> Bool {
        if let rpcError = error as? JSONRPCClientError {
            if case .agentError(let agent, _) = rpcError {
                return agent == .sessionNotFound
            }
        }
        if let appError = error as? AppError {
            if case .httpRequestFailed(let statusCode, _) = appError {
                return statusCode == 404
            }
        }
        return false
    }

    private func parsePtyAssistantText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("⏺ ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("⏺") {
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func handleSessionNotFound(context: String, refreshHistory: Bool = true) async {
        AppLogger.log("[Dashboard] Session not found during \(context) - clearing session state")
        isWatchingSession = false
        watchingSessionId = nil
        clearPendingTempSession(reason: "session not found")
        isSessionPinnedByUser = false
        setSelectedSession(nil)
        hasActiveConversation = false
        if refreshHistory {
            await loadRecentSessionHistory(isReconnection: false)
        }
    }

    // MARK: - Session Validation Helpers


    /// Validate that a sessionId still exists on the server
    /// Returns true if session exists, false if not found or error
    /// Note: Checks up to 100 sessions (should cover recently used sessions)
    private func validateSessionExists(_ sessionId: String) async -> Bool {
        do {
            let sessionsResponse = try await fetchSessionsPage(
                runtime: selectedSessionRuntime,
                limit: 100,
                offset: 0
            )
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

    /// Extract normalized thinking text from structured claude_message payload.
    /// Used for Codex runtime to show thinking in the bottom streaming bar.
    private func codexThinkingText(from payload: ClaudeMessagePayload) -> String? {
        guard case .blocks(let blocks) = payload.effectiveContent else { return nil }

        let thinkingSegments = blocks
            .filter { $0.type == "thinking" }
            .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !thinkingSegments.isEmpty else { return nil }

        let merged = thinkingSegments.joined(separator: " • ")
        let normalized = normalizeThinkingMessage(merged)
        return normalized.isEmpty ? nil : normalized
    }

    /// Keep spinner text compact and readable (strip top-level markdown emphasis, collapse whitespace).
    private func normalizeThinkingMessage(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let boldHeadings = extractBoldHeadings(from: normalized)
        if !boldHeadings.isEmpty {
            normalized = boldHeadings.joined(separator: " • ")
        } else if normalized.hasPrefix("**"), normalized.hasSuffix("**"), normalized.count > 4 {
            normalized = String(normalized.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        normalized = normalized.replacingOccurrences(of: "\n", with: " ")
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return normalized
    }

    /// Extract headings wrapped in **bold** markers (Codex reasoning summaries).
    private func extractBoldHeadings(from text: String) -> [String] {
        let pattern = #"\*\*([^\n*]+)\*\*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var results: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let matchRange = Range(match.range(at: 1), in: text) else { return }
            let heading = text[matchRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heading.isEmpty else { return }
            if results.last != heading {
                results.append(heading)
            }
        }
        return results
    }

    /// Ensure spinner message always includes mobile interrupt guidance.
    private func codexSpinnerMessage(from thinkingText: String) -> String {
        if thinkingText.localizedCaseInsensitiveContains(Self.mobileStopText) {
            return thinkingText
        }
        return "\(thinkingText) (\(Self.mobileStopText))"
    }

    /// Schedule a light refresh of session history to catch session ID switches
    private func scheduleSessionHistoryRefresh(reason: String) {
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            guard let self = self else { return }
            AppLogger.log("[Dashboard] Refreshing session history (\(reason))")
            await self.loadRecentSessionHistory(isReconnection: false)
        }
    }

    /// Get the most recent session ID for the selected runtime
    private func getMostRecentSessionId() async -> String? {
        do {
            let response = try await fetchSessionsPage(
                runtime: selectedSessionRuntime,
                limit: 20,
                offset: 0
            )
            guard !response.sessions.isEmpty else {
                AppLogger.log("[Dashboard] getMostRecentSessionId: \(selectedSessionRuntime.rawValue) list empty")
                return nil
            }

            let latest = selectLatestAgentSessionId(from: response.sessions)
            AppLogger.log("[Dashboard] getMostRecentSessionId: \(selectedSessionRuntime.rawValue) latest=\(latest ?? "nil"), count=\(response.sessions.count)")
            return latest
        } catch {
            AppLogger.error(error, context: "Get most recent session ID")
            return nil
        }
    }

    private func fetchSessionsPage(
        runtime: AgentRuntime,
        limit: Int,
        offset: Int
    ) async throws -> SessionsResponse {
        try await runtimeCoordinator.fetchSessionsPage(
            runtime: runtime,
            workspaceId: currentWorkspaceId,
            limit: limit,
            offset: offset
        )
    }

    private func fetchSessionMessagesPage(
        runtime: AgentRuntime,
        sessionId: String,
        limit: Int,
        offset: Int,
        order: String
    ) async throws -> SessionMessagesResponse {
        try await runtimeCoordinator.fetchSessionMessagesPage(
            runtime: runtime,
            sessionId: sessionId,
            workspaceId: currentWorkspaceId,
            limit: limit,
            offset: offset,
            order: order
        )
    }

    private func deleteSessionForRuntime(
        runtime: AgentRuntime,
        sessionId: String,
        workspaceId: String?
    ) async throws {
        try await runtimeCoordinator.deleteSessionForRuntime(
            runtime: runtime,
            sessionId: sessionId,
            workspaceId: workspaceId
        )
    }

    private func deleteAllSessionsForRuntime(
        runtime: AgentRuntime,
        workspaceId: String?
    ) async throws -> DashboardDeleteAllSessionsSummary {
        try await runtimeCoordinator.deleteAllSessionsForRuntime(
            runtime: runtime,
            workspaceId: workspaceId,
            sessions: sessions
        )
    }

    private func selectLatestAgentSessionId(from sessions: [SessionsResponse.SessionInfo]) -> String? {
        let sorted = sessions.sorted { left, right in
            let leftDate = sessionSortDate(left)
            let rightDate = sessionSortDate(right)
            return leftDate > rightDate
        }
        return sorted.first?.sessionId
    }

    private func sessionSortDate(_ session: SessionsResponse.SessionInfo) -> Date {
        if let lastActive = parseSessionDate(session.lastActive) {
            return lastActive
        }
        if let startedAt = parseSessionDate(session.startedAt) {
            return startedAt
        }
        if let lastUpdated = parseSessionDate(session.lastUpdated) {
            return lastUpdated
        }
        return .distantPast
    }

    private func parseSessionDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: dateString) {
            return date
        }

        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]
        return formatterWithoutFractional.date(from: dateString)
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

        // Skip if waiting for session_id_resolved
        guard !isPendingTempSessionForActiveWindow() else {
            AppLogger.log("[Dashboard] startWatchingCurrentSession skipped - pending session_id_resolved")
            return
        }

        guard let sessionId = userSelectedSessionId, !sessionId.isEmpty else {
            AppLogger.log("[Dashboard] No session to watch - userSelectedSessionId is nil or empty")
            return
        }

        let watchOwnerId = currentSessionWatchOwnerId()
        syncActiveTerminalWindowContext(sessionId: sessionId)

        // Keep existing optimization log, but still call watchSession so owner registration stays current.
        if !force && isWatchingSession && watchingSessionId == sessionId {
            AppLogger.log("[Dashboard] Already watching session: \(sessionId) - ensuring owner registration (\(watchOwnerId))")
        }

        // Must be connected
        guard connectionState.isConnected else {
            AppLogger.log("[Dashboard] Cannot watch session - not connected")
            return
        }

        do {
            AppLogger.log("[Dashboard] Calling watchSession API for: \(sessionId)")
            // Use workspace-aware API if available
            try await webSocketService.watchSession(
                sessionId,
                workspaceId: currentWorkspaceId,
                runtime: selectedSessionRuntime,
                ownerId: watchOwnerId
            )
            // JSON-RPC response confirms watching - set state immediately
            isWatchingSession = true
            watchingSessionId = sessionId
            syncActiveTerminalWindowContext(sessionId: sessionId)
            persistWindowSnapshot(for: activeTerminalWindowId)
            AppLogger.log("[Dashboard] Now watching session: \(sessionId)\(currentWorkspaceId != nil ? " (workspace: \(currentWorkspaceId!))" : "")")

            // Notify server about session focus for multi-device awareness
            if let workspaceId = currentWorkspaceId {
                await SessionAwarenessManager.shared.setFocus(workspaceId: workspaceId, sessionId: sessionId)
            }
        } catch {
            if isSessionNotFoundError(error) {
                AppLogger.log("[Dashboard] Session not found during watch - refreshing history")
                await handleSessionNotFound(context: "watch session", refreshHistory: true)
                return
            }
            AppLogger.error(error, context: "Watch session")
            // Reset state on failure so next attempt will try again
            isWatchingSession = false
            watchingSessionId = nil
        }
    }

    /// Stop watching the current session
    func stopWatchingSession() async {
        let targetSessionId = watchingSessionId ?? userSelectedSessionId
        guard let targetSessionId, !targetSessionId.isEmpty else { return }
        let watchOwnerId = currentSessionWatchOwnerId()

        do {
            try await webSocketService.unwatchSession(
                sessionId: targetSessionId,
                ownerId: watchOwnerId
            )
            isWatchingSession = false
            watchingSessionId = nil
            persistWindowSnapshot(for: activeTerminalWindowId)
            AppLogger.log("[Dashboard] Stopped watching session")

            // Clear session focus for multi-device awareness
            SessionAwarenessManager.shared.clearFocus()
        } catch {
            // Still clear local state even if command fails
            isWatchingSession = false
            watchingSessionId = nil
            persistWindowSnapshot(for: activeTerminalWindowId)
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
        if shouldHideElementFromChatList(element) {
            return false
        }

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

    /// Keep Codex thinking output in the bottom thinking bar, not in chat rows.
    private func shouldHideElementFromChatList(_ element: ChatElement) -> Bool {
        if selectedSessionRuntime == .codex && element.type == .thinking {
            return true
        }

        return shouldHideToolElementFromChatList(element)
    }

    /// Hide tool rows from chat list for non-Codex runtimes.
    /// Codex should keep tool rows (Ran/Added/Updated) to match CLI behavior.
    private func shouldHideToolElementFromChatList(_ element: ChatElement) -> Bool {
        if selectedSessionRuntime == .codex {
            return false
        }

        switch element.type {
        case .toolCall, .task, .toolResult:
            return true
        default:
            return false
        }
    }

    // MARK: - Workspace Management

    /// Switch to a different workspace
    func switchWorkspace(_ workspace: Workspace) async {
        AppLogger.log("[Dashboard] Switching to workspace: \(workspace.name)")

        if WorkspaceStore.shared.activeWorkspace?.id == workspace.id {
            AppLogger.log("[Dashboard] switchWorkspace: workspace already active - preserving existing tabs")
            ensureWindowForCurrentWorkspace()

            if let workspaceId = currentWorkspaceId {
                do {
                    try await workspaceManager.subscribe(workspaceId: workspaceId)
                    AppLogger.log("[Dashboard] switchWorkspace: refreshed workspace subscription for \(workspaceId)")
                } catch {
                    AppLogger.log("[Dashboard] switchWorkspace: workspace re-subscribe failed: \(error.localizedDescription)", type: .warning)
                }
            }

            if let activeWindowSessionId = normalizedSessionId(activeWindow?.sessionId) {
                AppLogger.log("[Dashboard] switchWorkspace: forcing session reload for active tab session \(activeWindowSessionId)")
                await resumeSession(activeWindowSessionId)
            } else {
                await loadRecentSessionHistory(isReconnection: true)
            }
            await refreshStatus()
            return
        }

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
        isSessionPinnedByUser = false
        seenElementIds.removeAll()
        seenContentHashes.removeAll()

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

        // Revoke refresh token before disconnecting (explicit logout)
        await TokenManager.shared.revokeStoredRefreshToken()

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
        seenContentHashes.removeAll()
        AppLogger.log("[Dashboard] Logs and diffs cleared")

        // Clear caches in background (don't await)
        Task.detached { [logCache, diffCache] in
            await logCache.clear()
            await diffCache.clear()
        }

        userSelectedSessionId = nil
        hasActiveConversation = false
        isSessionPinnedByUser = false
        connectionState = .disconnected
        agentState = .idle
        agentStatus = AgentStatus()
        pendingInteraction = nil
        promptText = ""
        isLoading = false
        error = nil
        isStreaming = false
        streamingStartTime = nil
        isPendingTrustFolder = false
        clearPendingTempSession(reason: "disconnect and reset", clearAll: true)

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
        seenContentHashes.removeAll()
        pendingInteraction = nil
        isPendingTrustFolder = false  // Reset trust state for new workspace
        clearPendingTempSession(reason: "setWorkspaceContext", clearAll: true)  // Reset temp session state for new workspace
        isSessionPinnedByUser = false

        // IMPORTANT: When connecting to a workspace, only trust the passed sessionId.
        // A previously stored userSelectedSessionId may belong to a different runtime/workspace.
        let effectiveSessionId: String?
        if let passedSessionId = sessionId, !passedSessionId.isEmpty {
            effectiveSessionId = passedSessionId
            AppLogger.log("[Dashboard] setWorkspaceContext: using passed session \(passedSessionId)")
        } else {
            effectiveSessionId = nil
            AppLogger.log("[Dashboard] setWorkspaceContext: no session passed, clearing stored session")
        }

        // Update agentStatus with new workspace info
        agentStatus = AgentStatus(
            claudeState: agentState,
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
        syncActiveTerminalWindowContext(sessionId: effectiveSessionId)

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
            setPendingTempSessionForActiveWindow()  // Also pending temp session since we don't have real ID yet
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

        if currentWorkspaceId == workspace.id, webSocketService.isConnected {
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: workspace already active - preserving existing tabs")
            ensureWindowForCurrentWorkspace()

            if let workspaceId = currentWorkspaceId {
                do {
                    try await workspaceManager.subscribe(workspaceId: workspaceId)
                    AppLogger.log("[DashboardVM] connectToRemoteWorkspace: refreshed workspace subscription for \(workspaceId)")
                } catch {
                    AppLogger.log("[DashboardVM] connectToRemoteWorkspace: workspace re-subscribe failed: \(error.localizedDescription)", type: .warning)
                }
            }

            if let activeWindowSessionId = normalizedSessionId(activeWindow?.sessionId) {
                AppLogger.log("[DashboardVM] connectToRemoteWorkspace: forcing session reload for active tab session \(activeWindowSessionId)")
                await resumeSession(activeWindowSessionId)
            } else {
                await loadRecentSessionHistory(isReconnection: true)
            }
            await refreshStatus()
            AppLogger.log("[DashboardVM] ========== CONNECT TO REMOTE WORKSPACE END (NO-OP) ==========")
            return true
        }

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
        isSessionPinnedByUser = false
        seenElementIds.removeAll()
        seenContentHashes.removeAll()
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
            seenContentHashes.removeAll()

            // Ensure workspace window context is ready before history load.
            // Without this, loadRecentSessionHistory can capture a stale window token and abort.
            ensureWindowForCurrentWorkspace()

            // Load session history and messages
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: Loading session history...")
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: userSelectedSessionId=\(userSelectedSessionId ?? "nil"), workspaceId=\(currentWorkspaceId ?? "nil")")
            await loadRecentSessionHistory(isReconnection: true)
            AppLogger.log("[DashboardVM] connectToRemoteWorkspace: After loadRecentSessionHistory, hasCompletedInitialLoad=\(hasCompletedInitialLoad)")

            // Recovery path: if history load was aborted by stale window operation,
            // force a direct session resume for the active tab to fetch messages.
            if chatElements.isEmpty && logs.isEmpty,
               let activeWindowSessionId = normalizedSessionId(activeWindow?.sessionId) {
                AppLogger.log("[DashboardVM] connectToRemoteWorkspace: History still empty after reconnect, forcing resumeSession for active tab session \(activeWindowSessionId)")
                await resumeSession(activeWindowSessionId)
            }

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
        seenContentHashes.removeAll()
        await logCache.clear()
        await diffCache.clear()
    }

    /// Create a PairingViewModel for the pairing sheet
    func makePairingViewModel() -> PairingViewModel? {
        appState?.makePairingViewModel()
    }

    // MARK: - Image Attachment Methods

    /// Attach an image from the given source
    /// Processes the image and starts upload immediately
    func attachImage(_ image: UIImage, source: AttachedImageState.ImageSource) async {
        guard canAttachMoreImages else {
            AppLogger.log("[Dashboard] Cannot attach more images - max \(AttachedImageState.Constants.maxImages) reached")
            return
        }

        do {
            // Process image (resize, compress, generate thumbnail)
            let processingService = ImageProcessingService.shared
            let attachedImage = try await processingService.process(image, source: source)

            // Add to list immediately with pending state
            attachedImages.append(attachedImage)
            Haptics.light()

            // Start upload in background
            Task {
                await uploadImage(id: attachedImage.id)
            }
        } catch {
            AppLogger.log("[Dashboard] Failed to process image: \(error)")
            // Show error toast or alert
        }
    }

    /// Remove an attached image
    func removeAttachedImage(_ id: UUID) {
        attachedImages.removeAll { $0.id == id }
        Haptics.light()
    }

    /// Retry uploading a failed image
    func retryUpload(_ id: UUID) async {
        guard let index = attachedImages.firstIndex(where: { $0.id == id }),
              attachedImages[index].canRetry else {
            return
        }

        // Reset state to pending
        attachedImages[index].uploadState = .pending

        // Retry upload
        await uploadImage(id: id)
    }

    /// Upload a specific image to the server
    private func uploadImage(id: UUID) async {
        guard let index = attachedImages.firstIndex(where: { $0.id == id }) else { return }

        // Update state to uploading
        attachedImages[index].uploadState = .uploading(progress: 0)

        do {
            // Use shared upload service (gets connection info from WorkspaceStore)
            let response = try await ImageUploadService.shared.upload(attachedImages[index]) { progress in
                Task { @MainActor in
                    if let idx = self.attachedImages.firstIndex(where: { $0.id == id }) {
                        self.attachedImages[idx].uploadState = .uploading(progress: progress)
                    }
                }
            }

            // Update state to uploaded
            if let idx = attachedImages.firstIndex(where: { $0.id == id }) {
                attachedImages[idx].uploadState = .uploaded(imageId: response.id, localPath: response.localPath)
                attachedImages[idx].serverImageId = response.id
                attachedImages[idx].serverLocalPath = response.localPath
            }

            AppLogger.log("[Dashboard] Image uploaded: \(response.id) -> \(response.localPath)")

        } catch {
            AppLogger.log("[Dashboard] Image upload failed: \(error)")

            // Update state to failed
            if let idx = attachedImages.firstIndex(where: { $0.id == id }) {
                let errorMessage = (error as? ImageUploadError)?.localizedDescription ?? error.localizedDescription
                attachedImages[idx].uploadState = .failed(error: errorMessage)
            }
        }
    }

    /// Clear all attached images
    func clearAttachedImages() {
        attachedImages.removeAll()
    }

    /// Get uploaded image paths for sending to Claude
    func getUploadedImagePaths() -> [String] {
        attachedImages
            .filter { $0.isUploaded }
            .compactMap { $0.serverLocalPath }
    }

    /// Check if clipboard has an image
    func clipboardHasImage() -> Bool {
        UIPasteboard.general.hasImages
    }

    /// Paste image from clipboard
    func pasteImageFromClipboard() async {
        guard let image = UIPasteboard.general.image else {
            AppLogger.log("[Dashboard] No image in clipboard")
            return
        }

        await attachImage(image, source: .clipboard)
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
    /// Handles messages with "[Attached images: ...]" suffix (strips before comparing)
    /// Note: Hash is kept for 5 seconds to handle duplicate server echoes
    private func isOurOwnPrompt(_ text: String) -> Bool {
        // Log for debugging
        let trackedHashes = Array(sentPromptHashes.keys)
        AppLogger.log("[Dashboard] isOurOwnPrompt checking: '\(text.prefix(100))', tracked hashes: \(trackedHashes)")

        // First try exact match
        let hash = hashPrompt(text)
        if sentPromptHashes[hash] != nil {
            AppLogger.log("[Dashboard] ✅ Exact hash match: \(hash)")
            return true
        }

        // Try matching just the first line (in case server adds extra content)
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let firstLineHash = hashPrompt(firstLine)
        if sentPromptHashes[firstLineHash] != nil {
            AppLogger.log("[Dashboard] ✅ Matched prompt using first line only")
            return true
        }

        AppLogger.log("[Dashboard] ❌ No hash match found. Text hash: \(hash), first line hash: \(firstLineHash)")
        return false
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
