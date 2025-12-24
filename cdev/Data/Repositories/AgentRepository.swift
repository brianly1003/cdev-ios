import Foundation

/// Repository for agent data operations via JSON-RPC
/// Supports both legacy agent/* APIs and new session/* APIs (multi-workspace)
final class AgentRepository: AgentRepositoryProtocol {
    private let webSocketService: WebSocketServiceProtocol
    private let httpService: HTTPServiceProtocol?

    /// Temporary flag to use HTTP fallback for session/messages (for testing)
    private let useHTTPForMessages = false  // Set to false to use RPC

    /// Use new session/* APIs for multi-workspace support
    /// When true, uses session/send, session/stop, session/respond instead of agent/* APIs
    private let useSessionAPIs: Bool = true

    @Atomic private var _status: AgentStatus = AgentStatus()

    var status: AgentStatus {
        get async { _status }
    }

    init(webSocketService: WebSocketServiceProtocol, httpService: HTTPServiceProtocol? = nil) {
        self.webSocketService = webSocketService
        self.httpService = httpService
    }

    // MARK: - JSON-RPC Client

    /// Get the JSON-RPC client
    private var rpcClient: JSONRPCClient {
        guard let wsService = webSocketService as? WebSocketService else {
            fatalError("WebSocketService must be used for JSON-RPC")
        }
        return wsService.getJSONRPCClient()
    }

    /// Check if connected
    private var isConnected: Bool {
        webSocketService.isConnected
    }

    // MARK: - Session Context (Multi-Workspace)

    /// Get the current session ID from the active workspace
    /// Returns nil if no active session (will fall back to legacy APIs)
    @MainActor
    private var currentSessionId: String? {
        // Try to get from WorkspaceManagerService (remote workspaces)
        let workspaces = WorkspaceManagerService.shared.workspaces
        for workspace in workspaces {
            if let session = workspace.activeSession {
                return session.id
            }
        }
        // Fall back to local WorkspaceStore session ID
        return WorkspaceStore.shared.activeWorkspace?.sessionId
    }

    /// Get the current workspace ID
    @MainActor
    private var currentWorkspaceId: String? {
        let workspaces = WorkspaceManagerService.shared.workspaces
        return workspaces.first { $0.hasActiveSession }?.id
    }

    // MARK: - Status

    func fetchStatus() async throws -> AgentStatus {
        let result: StatusGetResult = try await rpcClient.request(
            method: JSONRPCMethod.statusGet,
            params: nil as EmptyParams?
        )
        let status = AgentStatus.from(rpcResult: result)
        _status = status
        return status
    }

    // MARK: - Claude Control

    func runClaude(prompt: String, mode: SessionMode, sessionId: String?) async throws {
        // Try to use new session/* APIs for multi-workspace support
        if useSessionAPIs {
            // Get session ID - use provided sessionId or get from active workspace
            let effectiveSessionId = await MainActor.run { () -> String? in
                if let sid = sessionId, !sid.isEmpty {
                    return sid
                }
                return self.currentSessionId
            }

            if let sid = effectiveSessionId {
                AppLogger.log("[AgentRepository] Using session/send API with session: \(sid)")
                try await WorkspaceManagerService.shared.sendPrompt(
                    sessionId: sid,
                    prompt: prompt,
                    mode: mode == .new ? "new" : "continue"
                )
                return
            }

            // If no session exists, try to start one
            let workspaceId = await MainActor.run { self.currentWorkspaceId }
            if let wsId = workspaceId {
                AppLogger.log("[AgentRepository] Starting new session for workspace: \(wsId)")
                let session = try await WorkspaceManagerService.shared.startSession(workspaceId: wsId)
                try await WorkspaceManagerService.shared.sendPrompt(
                    sessionId: session.id,
                    prompt: prompt,
                    mode: "new"
                )
                return
            }

            // Fall through to legacy API if no workspace context
            AppLogger.log("[AgentRepository] No session context, falling back to legacy agent/run API")
        }

        // Legacy API (for backward compatibility)
        let params = AgentRunParams(
            prompt: prompt,
            mode: mode.rawValue,
            sessionId: mode != .new ? sessionId : nil,
            agentType: nil  // Use default (claude)
        )
        let _: AgentRunResult = try await rpcClient.request(
            method: JSONRPCMethod.agentRun,
            params: params
        )
    }

    func stopClaude() async throws {
        // Try to use new session/* APIs for multi-workspace support
        if useSessionAPIs {
            let sessionId = await MainActor.run { self.currentSessionId }
            if let sid = sessionId {
                AppLogger.log("[AgentRepository] Using session/stop API with session: \(sid)")
                try await WorkspaceManagerService.shared.stopSession(sessionId: sid)
                return
            }
            // Fall through to legacy API if no session context
            AppLogger.log("[AgentRepository] No session context, falling back to legacy agent/stop API")
        }

        // Legacy API (for backward compatibility)
        let _: AgentStopResult = try await rpcClient.request(
            method: JSONRPCMethod.agentStop,
            params: nil as EmptyParams?
        )
    }

    func respondToClaude(response: String, requestId: String?, approved: Bool?) async throws {
        // Try to use new session/* APIs for multi-workspace support
        if useSessionAPIs {
            let sessionId = await MainActor.run { self.currentSessionId }
            if let sid = sessionId {
                // Determine response type and value
                let responseType: String
                let responseValue: String

                if approved != nil {
                    // Permission response
                    responseType = "permission"
                    responseValue = approved! ? "yes" : "no"
                } else {
                    // Question response (free text)
                    responseType = "question"
                    responseValue = response
                }

                AppLogger.log("[AgentRepository] Using session/respond API with session: \(sid), type: \(responseType)")
                try await WorkspaceManagerService.shared.respond(
                    sessionId: sid,
                    type: responseType,
                    response: responseValue
                )
                return
            }
            // Fall through to legacy API if no session context
            AppLogger.log("[AgentRepository] No session context, falling back to legacy agent/respond API")
        }

        // Legacy API (for backward compatibility)
        let params = AgentRespondParams(
            toolUseId: requestId ?? "",
            response: approved != nil ? (approved! ? "yes" : "no") : response,
            isError: false
        )
        let _: AgentRespondResult = try await rpcClient.request(
            method: JSONRPCMethod.agentRespond,
            params: params
        )
    }

    // MARK: - File Operations

    func getFile(path: String) async throws -> FileContentPayload {
        let params = FileGetParams(path: path)
        let result: FileGetResult = try await rpcClient.request(
            method: JSONRPCMethod.fileGet,
            params: params
        )
        return FileContentPayload(
            path: result.path,
            content: result.content,
            encoding: "utf-8",
            truncated: result.truncated
        )
    }

    // MARK: - Git Operations

    func getGitStatus() async throws -> GitStatusResponse {
        let result: GitStatusResult = try await rpcClient.request(
            method: JSONRPCMethod.gitStatus,
            params: nil as EmptyParams?
        )

        // Convert to GitStatusResponse with GitFileStatus array
        var files: [GitStatusResponse.GitFileStatus] = []

        // Staged files
        for file in result.staged ?? [] {
            files.append(GitStatusResponse.GitFileStatus(
                path: file.path,
                status: file.status ?? "M ",
                isStaged: true,
                isUntracked: false
            ))
        }

        // Unstaged files
        for file in result.unstaged ?? [] {
            files.append(GitStatusResponse.GitFileStatus(
                path: file.path,
                status: file.status ?? " M",
                isStaged: false,
                isUntracked: false
            ))
        }

        // Untracked files
        for file in result.untracked ?? [] {
            files.append(GitStatusResponse.GitFileStatus(
                path: file.path,
                status: file.status ?? "?",
                isStaged: false,
                isUntracked: true
            ))
        }

        // Conflicted files
        for file in result.conflicted ?? [] {
            files.append(GitStatusResponse.GitFileStatus(
                path: file.path,
                status: file.status ?? "U",
                isStaged: false,
                isUntracked: false
            ))
        }

        return GitStatusResponse(
            files: files,
            repoName: result.repoName,
            repoRoot: result.repoRoot
        )
    }

    func getGitStatusExtended() async throws -> GitStatusExtendedResponse {
        // Use same RPC call, return as extended response
        let result: GitStatusResult = try await rpcClient.request(
            method: JSONRPCMethod.gitStatus,
            params: nil as EmptyParams?
        )

        // Convert GitStatusFileInfo to GitFileInfo objects
        let stagedFiles = (result.staged ?? []).map {
            GitStatusExtendedResponse.GitFileInfo(path: $0.path, status: $0.status ?? "M")
        }
        let unstagedFiles = (result.unstaged ?? []).map {
            GitStatusExtendedResponse.GitFileInfo(path: $0.path, status: $0.status ?? "M")
        }
        let untrackedFiles = (result.untracked ?? []).map {
            GitStatusExtendedResponse.GitFileInfo(path: $0.path, status: $0.status ?? "?")
        }
        let conflictedFiles = (result.conflicted ?? []).map {
            GitStatusExtendedResponse.GitFileInfo(path: $0.path, status: $0.status ?? "U")
        }

        return GitStatusExtendedResponse(
            branch: result.branch ?? "unknown",
            upstream: result.upstream,
            ahead: result.ahead,
            behind: result.behind,
            staged: stagedFiles,
            unstaged: unstagedFiles,
            untracked: untrackedFiles,
            conflicted: conflictedFiles,
            repoName: result.repoName,
            repoRoot: result.repoRoot
        )
    }

    func getGitDiff(file: String?, workspaceId: String?) async throws -> [GitDiffPayload] {
        // Require workspaceId for workspace-aware API
        guard let workspaceId = workspaceId else {
            AppLogger.log("[GitDiff] No workspaceId provided, returning empty", type: .warning)
            return []
        }

        AppLogger.log("[GitDiff] Using workspace/git/diff for workspace: \(workspaceId), file: \(file ?? "all")")
        let params = WorkspaceGitDiffParams(workspaceId: workspaceId, staged: false, path: file)
        let result: GitDiffResponse = try await rpcClient.request(
            method: JSONRPCMethod.workspaceGitDiff,
            params: params
        )

        // Convert GitDiffResponse to [GitDiffPayload]
        // Use allDiffs to handle both single-file and multi-file response formats
        let diffs = result.allDiffs
        return diffs.map { item in
            GitDiffPayload(
                file: item.path,
                diff: item.diff,
                additions: nil,
                deletions: nil,
                isNew: item.isNew
            )
        }
    }

    // MARK: - Git Operations (Source Control)

    @discardableResult
    func gitStage(paths: [String]) async throws -> GitOperationResponse {
        let params = GitPathsParams(paths: paths)
        let result: GitOperationResult = try await rpcClient.request(
            method: JSONRPCMethod.gitStage,
            params: params
        )
        return GitOperationResponse(success: result.isSuccess, message: result.message)
    }

    @discardableResult
    func gitUnstage(paths: [String]) async throws -> GitOperationResponse {
        let params = GitPathsParams(paths: paths)
        let result: GitOperationResult = try await rpcClient.request(
            method: JSONRPCMethod.gitUnstage,
            params: params
        )
        return GitOperationResponse(success: result.isSuccess, message: result.message)
    }

    @discardableResult
    func gitDiscard(paths: [String]) async throws -> GitOperationResponse {
        let params = GitPathsParams(paths: paths)
        let result: GitOperationResult = try await rpcClient.request(
            method: JSONRPCMethod.gitDiscard,
            params: params
        )
        return GitOperationResponse(success: result.isSuccess, message: result.message)
    }

    @discardableResult
    func gitCommit(message: String, push: Bool) async throws -> GitCommitResponse {
        let params = GitCommitParams(message: message, push: push)
        let result: GitCommitResult = try await rpcClient.request(
            method: JSONRPCMethod.gitCommit,
            params: params
        )
        return GitCommitResponse(
            success: result.isSuccess,
            commitHash: result.resolvedCommitHash,
            message: result.message
        )
    }

    @discardableResult
    func gitPush() async throws -> GitSyncResponse {
        let result: GitOperationResult = try await rpcClient.request(
            method: JSONRPCMethod.gitPush,
            params: nil as EmptyParams?
        )
        return GitSyncResponse(success: result.isSuccess, message: result.message, error: result.error)
    }

    @discardableResult
    func gitPull() async throws -> GitSyncResponse {
        let result: GitOperationResult = try await rpcClient.request(
            method: JSONRPCMethod.gitPull,
            params: nil as EmptyParams?
        )
        return GitSyncResponse(success: result.isSuccess, message: result.message, error: result.error)
    }

    // MARK: - Sessions

    func getSessions(workspaceId: String? = nil, limit: Int = 20, offset: Int = 0) async throws -> SessionsResponse {
        // Use workspace-aware workspace/session/history API when workspaceId is provided
        if let workspaceId = workspaceId {
            let params = SessionHistoryParams(workspaceId: workspaceId, limit: limit)
            let result: SessionHistoryResult = try await rpcClient.request(
                method: JSONRPCMethod.workspaceSessionHistory,
                params: params
            )

            // Convert to SessionsResponse
            let sessions = (result.sessions ?? []).map { session in
                SessionsResponse.SessionInfo(
                    sessionId: session.sessionId,
                    summary: session.summary ?? "Session \(session.sessionId.prefix(8))",
                    messageCount: session.messageCount ?? 0,
                    lastUpdated: session.lastUpdated ?? "",
                    branch: session.branch
                )
            }

            return SessionsResponse(
                sessions: sessions,
                current: nil,
                total: result.total ?? sessions.count,
                limit: limit,
                offset: offset
            )
        }

        // Legacy: use session/list when no workspaceId
        let params = SessionListParams(agentType: nil, limit: limit)
        let result: SessionListResult = try await rpcClient.request(
            method: JSONRPCMethod.sessionList,
            params: params
        )

        // Convert to SessionsResponse
        let sessions = (result.sessions ?? []).map { session in
            SessionsResponse.SessionInfo(
                sessionId: session.resolvedId,
                summary: session.summary ?? "Session \(session.resolvedId.prefix(8))",
                messageCount: session.messageCount ?? 0,
                lastUpdated: session.lastUpdated ?? session.startTime ?? "",
                branch: nil
            )
        }

        return SessionsResponse(
            sessions: sessions,
            current: nil,
            total: sessions.count,
            limit: limit,
            offset: offset
        )
    }

    func getSessionMessages(
        sessionId: String,
        workspaceId: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        order: String = "desc"
    ) async throws -> SessionMessagesResponse {
        // Use HTTP fallback for testing
        if useHTTPForMessages, let httpService = httpService {
            AppLogger.network("[Sessions] Using HTTP fallback for session/messages")
            let queryItems = [
                URLQueryItem(name: "session_id", value: sessionId),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "order", value: order)
            ]
            return try await httpService.get(
                path: "/api/claude/sessions/messages",
                queryItems: queryItems
            )
        }

        // Use workspace-aware API if workspaceId is provided
        if let workspaceId = workspaceId {
            AppLogger.network("[Sessions] Using workspace/session/messages for workspace: \(workspaceId)")
            let params = WorkspaceSessionMessagesParams(
                workspaceId: workspaceId,
                sessionId: sessionId,
                limit: limit,
                offset: offset,
                order: order
            )

            do {
                let result: WorkspaceSessionMessagesResult = try await rpcClient.request(
                    method: JSONRPCMethod.workspaceSessionMessages,
                    params: params
                )

                // Convert workspace messages to SessionMessage format
                let messages: [SessionMessagesResponse.SessionMessage] = (result.messages ?? []).compactMap { msg -> SessionMessagesResponse.SessionMessage? in
                    guard let message = msg.message,
                          let type = msg.type else { return nil }
                    return SessionMessagesResponse.SessionMessage(
                        type: type,
                        uuid: msg.uuid,
                        sessionId: msg.sessionId,
                        timestamp: msg.timestamp,
                        gitBranch: msg.gitBranch,
                        message: message,
                        isContextCompaction: msg.isContextCompaction
                    )
                }

                return SessionMessagesResponse(
                    sessionId: result.sessionId ?? sessionId,
                    messages: messages,
                    total: result.total ?? messages.count,
                    limit: result.limit ?? limit,
                    offset: result.offset ?? offset,
                    hasMore: result.hasMore ?? false,
                    cacheHit: nil,
                    queryTimeMs: result.queryTimeMs
                )
            } catch {
                AppLogger.network("workspace/session/messages decode error: \(error)", type: .error)
                // Fall back to legacy API
            }
        }

        // JSON-RPC implementation (legacy) - uses same message format as HTTP API
        let params = SessionMessagesParams(
            sessionId: sessionId,
            agentType: nil,
            limit: limit,
            offset: offset,
            order: order
        )

        do {
            let result: SessionMessagesResult = try await rpcClient.request(
                method: JSONRPCMethod.sessionMessages,
                params: params
            )

            // Messages are already in the correct format (same as HTTP API)
            return SessionMessagesResponse(
                sessionId: result.sessionId ?? sessionId,
                messages: result.messages ?? [],
                total: result.total ?? (result.messages?.count ?? 0),
                limit: result.limit ?? limit,
                offset: result.offset ?? offset,
                hasMore: result.hasMore ?? false,
                cacheHit: nil,
                queryTimeMs: result.queryTimeMs
            )
        } catch {
            AppLogger.network("session/messages decode error: \(error)", type: .error)
            // Return empty response on decode failure (server may return different format)
            return SessionMessagesResponse(
                sessionId: sessionId,
                messages: [],
                total: 0,
                limit: limit,
                offset: offset,
                hasMore: false
            )
        }
    }

    func deleteSession(sessionId: String) async throws -> DeleteSessionResponse {
        let params = SessionDeleteParams(sessionId: sessionId, agentType: nil)
        let result: SessionDeleteResult = try await rpcClient.request(
            method: JSONRPCMethod.sessionDelete,
            params: params
        )
        return DeleteSessionResponse(
            message: result.status ?? "deleted",
            sessionId: sessionId
        )
    }

    func deleteAllSessions() async throws -> DeleteAllSessionsResponse {
        // Delete all by not providing a session_id
        let params = SessionDeleteParams(sessionId: nil, agentType: nil)
        let result: SessionDeleteResult = try await rpcClient.request(
            method: JSONRPCMethod.sessionDelete,
            params: params
        )
        return DeleteAllSessionsResponse(
            message: result.status ?? "deleted",
            deleted: result.deleted ?? 0
        )
    }

    // MARK: - Workspace Status

    func getWorkspaceStatus(workspaceId: String) async throws -> WorkspaceStatusResult {
        let params = WorkspaceStatusParams(workspaceId: workspaceId)
        let result: WorkspaceStatusResult = try await rpcClient.request(
            method: JSONRPCMethod.workspaceStatus,
            params: params
        )
        return result
    }

    // MARK: - Multi-Device Session Awareness

    /// Notify server that this device is focusing on a specific session
    /// Returns information about other devices viewing the same session
    func setSessionFocus(workspaceId: String, sessionId: String) async throws -> SessionFocusResult {
        let params = SessionFocusParams(workspaceId: workspaceId, sessionId: sessionId)
        let result: SessionFocusResult = try await rpcClient.request(
            method: JSONRPCMethod.clientSessionFocus,
            params: params
        )
        AppLogger.log("[AgentRepository] Session focus set: workspace=\(workspaceId), session=\(sessionId), viewers=\(result.viewerCount ?? 0)")
        return result
    }

    /// Activate a session for a workspace (set as the active/selected session)
    /// Called when user resumes a session from the session picker
    func activateSession(workspaceId: String, sessionId: String) async throws -> SessionActivateResult {
        let params = SessionActivateParams(workspaceId: workspaceId, sessionId: sessionId)
        let result: SessionActivateResult = try await rpcClient.request(
            method: JSONRPCMethod.workspaceSessionActivate,
            params: params
        )
        AppLogger.log("[AgentRepository] Session activated: workspace=\(workspaceId), session=\(sessionId), success=\(result.success ?? false)")
        return result
    }

    // MARK: - Internal

    func updateStatus(from payload: StatusResponsePayload) {
        _status = AgentStatus.from(payload: payload)
    }

    func updateClaudeState(_ state: ClaudeState) {
        _status = AgentStatus(
            claudeState: state,
            sessionId: _status.sessionId,
            repoName: _status.repoName,
            repoPath: _status.repoPath,
            connectedClients: _status.connectedClients,
            uptime: _status.uptime
        )
    }
}
