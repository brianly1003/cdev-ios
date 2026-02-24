import Foundation

struct DashboardRuntimeReconcileResult {
    let availableRuntimes: [AgentRuntime]
    let selectedRuntime: AgentRuntime
    let fallbackRuntime: AgentRuntime?
}

struct DashboardDeleteAllSessionsSummary {
    let deletedCount: Int
    let failedCount: Int
}

@MainActor
final class DashboardRuntimeCoordinator {
    typealias AsyncStep = () async -> Void
    typealias RuntimeProvider = () -> AgentRuntime
    typealias CancellationProvider = () -> Bool

    private let webSocketService: WebSocketServiceProtocol
    private let agentRepository: AgentRepositoryProtocol
    private let workspaceManager: WorkspaceManagerService

    init(
        webSocketService: WebSocketServiceProtocol,
        agentRepository: AgentRepositoryProtocol,
        workspaceManager: WorkspaceManagerService
    ) {
        self.webSocketService = webSocketService
        self.agentRepository = agentRepository
        self.workspaceManager = workspaceManager
    }

    func reconcileRuntimeSelection(currentRuntime: AgentRuntime) -> DashboardRuntimeReconcileResult {
        let supported = AgentRuntime.availableRuntimes()
        let fallback = resolveFallbackRuntime(from: currentRuntime, supported: supported)
        return DashboardRuntimeReconcileResult(
            availableRuntimes: supported,
            selectedRuntime: fallback,
            fallbackRuntime: fallback == currentRuntime ? nil : fallback
        )
    }

    func handleRuntimeSwitch(
        from oldRuntime: AgentRuntime,
        to newRuntime: AgentRuntime,
        selectedRuntime: RuntimeProvider,
        isCancelled: CancellationProvider,
        watchOwnerIdProvider: () -> String,
        stopWatching: AsyncStep,
        clearRuntimeState: AsyncStep,
        loadSessions: AsyncStep,
        loadRecentHistory: AsyncStep,
        refreshStatus: AsyncStep
    ) async {
        guard oldRuntime != newRuntime else { return }

        AppLogger.log("[Dashboard] Runtime switch: \(oldRuntime.rawValue) -> \(newRuntime.rawValue)")

        // Stop active watch first to avoid stale event routing from previous runtime.
        await stopWatching()

        // Best effort unwatch in case local watch flags drifted from server state.
        do {
            try await webSocketService.unwatchSession(
                sessionId: nil,
                ownerId: watchOwnerIdProvider()
            )
        } catch {
            AppLogger.log("[Dashboard] Runtime switch unwatch fallback: \(error.localizedDescription)")
        }
        SessionAwarenessManager.shared.clearFocus()

        guard !isCancelled(), selectedRuntime() == newRuntime else { return }

        // Reset local state to avoid cross-runtime session leakage.
        await clearRuntimeState()

        guard !isCancelled(), selectedRuntime() == newRuntime else { return }
        await loadSessions()

        guard !isCancelled(), selectedRuntime() == newRuntime else { return }
        await loadRecentHistory()

        guard !isCancelled(), selectedRuntime() == newRuntime else { return }
        await refreshStatus()
    }

    func fetchSessionsPage(
        runtime: AgentRuntime,
        workspaceId: String?,
        limit: Int,
        offset: Int
    ) async throws -> SessionsResponse {
        switch runtime.sessionListSource {
        case .runtimeScoped:
            guard let workspaceId, !workspaceId.isEmpty else {
                AppLogger.log("[Dashboard] Cannot load \(runtime.rawValue) sessions - no workspace ID", type: .warning)
                return SessionsResponse(sessions: [], total: 0, limit: limit, offset: offset)
            }
            return try await agentRepository.getAgentSessions(
                runtime: runtime,
                workspaceId: workspaceId,
                limit: limit,
                offset: offset
            )

        case .workspaceHistory:
            guard let workspaceId, !workspaceId.isEmpty else {
                AppLogger.log("[Dashboard] Cannot load sessions - no workspace ID", type: .warning)
                return SessionsResponse(sessions: [], total: 0, limit: limit, offset: offset)
            }

            // workspace/session/history currently has no offset support.
            guard offset == 0 else {
                return SessionsResponse(sessions: [], total: 0, limit: limit, offset: offset)
            }

            let historyResponse = try await workspaceManager.getSessionHistory(
                workspaceId: workspaceId,
                limit: limit,
                runtime: runtime
            )
            let mapped = (historyResponse.sessions ?? []).map { historySession in
                let status = historySession.status.flatMap { SessionsResponse.SessionStatus(rawValue: $0) }
                return SessionsResponse.SessionInfo(
                    sessionId: historySession.sessionId,
                    summary: historySession.summary ?? "No summary",
                    messageCount: historySession.messageCount ?? 0,
                    lastUpdated: historySession.lastUpdated ?? "",
                    branch: historySession.branch,
                    agentType: runtime,
                    status: status,
                    workspaceId: workspaceId,
                    startedAt: historySession.startedAt,
                    lastActive: historySession.lastActive,
                    viewers: historySession.viewers
                )
            }

            // Force total to mapped.count so hasMore remains false for this API.
            return SessionsResponse(
                sessions: mapped,
                total: mapped.count,
                limit: limit,
                offset: 0
            )
        }
    }

    func fetchSessionMessagesPage(
        runtime: AgentRuntime,
        sessionId: String,
        workspaceId: String?,
        limit: Int,
        offset: Int,
        order: String
    ) async throws -> SessionMessagesResponse {
        switch runtime.sessionMessagesSource {
        case .runtimeScoped:
            return try await agentRepository.getAgentSessionMessages(
                runtime: runtime,
                sessionId: sessionId,
                limit: limit,
                offset: offset,
                order: order
            )
        case .workspaceScoped:
            guard let workspaceId, !workspaceId.isEmpty else {
                throw AppError.workspaceIdRequired
            }
            return try await agentRepository.getSessionMessages(
                runtime: runtime,
                sessionId: sessionId,
                workspaceId: workspaceId,
                limit: limit,
                offset: offset,
                order: order
            )
        }
    }

    func deleteSessionForRuntime(
        runtime: AgentRuntime,
        sessionId: String,
        workspaceId: String?
    ) async throws {
        switch runtime.sessionListSource {
        case .runtimeScoped:
            _ = try await agentRepository.deleteAgentSession(runtime: runtime, sessionId: sessionId)
        case .workspaceHistory:
            guard let workspaceId, !workspaceId.isEmpty else {
                throw AppError.workspaceIdRequired
            }
            _ = try await agentRepository.deleteSession(runtime: runtime, sessionId: sessionId, workspaceId: workspaceId)
        }
    }

    func deleteAllSessionsForRuntime(
        runtime: AgentRuntime,
        workspaceId: String?,
        sessions: [SessionsResponse.SessionInfo]
    ) async throws -> DashboardDeleteAllSessionsSummary {
        switch runtime.sessionListSource {
        case .runtimeScoped:
            let response = try await agentRepository.deleteAllAgentSessions(runtime: runtime)
            return DashboardDeleteAllSessionsSummary(deletedCount: response.deleted, failedCount: 0)

        case .workspaceHistory:
            guard let workspaceId, !workspaceId.isEmpty else {
                throw AppError.workspaceIdRequired
            }

            var deletedCount = 0
            var failedCount = 0
            for session in sessions {
                do {
                    _ = try await agentRepository.deleteSession(runtime: runtime, sessionId: session.sessionId, workspaceId: workspaceId)
                    deletedCount += 1
                } catch {
                    failedCount += 1
                    AppLogger.log("[Dashboard] Failed to delete session \(session.sessionId): \(error)", type: .error)
                }
            }

            return DashboardDeleteAllSessionsSummary(deletedCount: deletedCount, failedCount: failedCount)
        }
    }

    private func resolveFallbackRuntime(from currentRuntime: AgentRuntime, supported: [AgentRuntime]) -> AgentRuntime {
        guard !supported.isEmpty else {
            return AgentRuntime.defaultRuntime
        }

        if supported.contains(currentRuntime) {
            return currentRuntime
        }

        let preferred = RuntimeCapabilityRegistryStore.shared.defaultRuntime()
        if supported.contains(preferred) {
            return preferred
        }

        return supported.first ?? AgentRuntime.defaultRuntime
    }
}
