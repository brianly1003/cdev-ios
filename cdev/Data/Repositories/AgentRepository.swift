import Foundation

/// Repository for agent data operations via JSON-RPC
/// Uses session/* APIs for multi-workspace support
final class AgentRepository: AgentRepositoryProtocol {
    private let webSocketService: WebSocketServiceProtocol

    @Atomic private var _status: AgentStatus = AgentStatus()

    var status: AgentStatus {
        get async { _status }
    }

    init(webSocketService: WebSocketServiceProtocol) {
        self.webSocketService = webSocketService
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
        // For "new" mode, don't use any session ID - start fresh
        // For "continue" mode, use provided sessionId or fallback to currentSessionId
        let effectiveSessionId: String?
        if mode == .new {
            // New session - don't include session_id in request
            effectiveSessionId = nil
            AppLogger.log("[AgentRepository] Mode is 'new' - will not include session_id")
        } else {
            // Continue mode - use provided or current session
            effectiveSessionId = await MainActor.run { () -> String? in
                if let sid = sessionId, !sid.isEmpty {
                    return sid
                }
                return self.currentSessionId
            }
        }

        if let sid = effectiveSessionId {
            AppLogger.log("[AgentRepository] Using session/send API with session: \(sid), mode: continue")
            try await WorkspaceManagerService.shared.sendPrompt(
                sessionId: sid,
                prompt: prompt,
                mode: "continue"
            )
            return
        }

        // No session ID (either mode is "new" or no session exists)
        // Use session/send with mode "new" and no session_id
        let workspaceId = await MainActor.run { self.currentWorkspaceId }
        if workspaceId != nil {
            AppLogger.log("[AgentRepository] Sending prompt with mode 'new' (no session_id)")
            try await WorkspaceManagerService.shared.sendPrompt(
                sessionId: nil,  // No session_id for new sessions
                prompt: prompt,
                mode: "new"
            )
            return
        }

        // No workspace context - throw error
        throw AgentRepositoryError.noWorkspaceContext
    }

    func stopClaude(sessionId: String?) async throws {
        // Use provided sessionId or fallback to current session from workspace
        let effectiveSessionId: String?
        if let sid = sessionId, !sid.isEmpty {
            effectiveSessionId = sid
        } else {
            effectiveSessionId = await MainActor.run { self.currentSessionId }
        }

        guard let sid = effectiveSessionId else {
            AppLogger.log("[AgentRepository] No session context for stop", type: .warning)
            throw AgentRepositoryError.noSessionContext
        }

        AppLogger.log("[AgentRepository] Using session/stop API with session: \(sid)")
        try await WorkspaceManagerService.shared.stopSession(sessionId: sid)
    }

    func respondToClaude(response: String, requestId: String?, approved: Bool?) async throws {
        let sessionId = await MainActor.run { self.currentSessionId }
        guard let sid = sessionId else {
            AppLogger.log("[AgentRepository] No session context for respond", type: .warning)
            throw AgentRepositoryError.noSessionContext
        }

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
    }

    // MARK: - PTY Mode (Interactive Terminal)

    func sendInput(sessionId: String, input: String) async throws {
        AppLogger.log("[AgentRepository] Sending PTY input to session: \(sessionId), input: \(input)")
        let params = SessionInputParams(sessionId: sessionId, input: input)
        let _: SessionInputResult = try await rpcClient.request(
            method: JSONRPCMethod.sessionInput,
            params: params
        )
    }

    func sendKey(sessionId: String, key: SessionInputKey) async throws {
        AppLogger.log("[AgentRepository] Sending PTY key to session: \(sessionId), key: \(key.rawValue)")
        let params = SessionInputParams(sessionId: sessionId, key: key)
        let _: SessionInputResult = try await rpcClient.request(
            method: JSONRPCMethod.sessionInput,
            params: params
        )
    }

    // MARK: - Hook Bridge Mode (Permission Respond)

    func respondToPermission(
        toolUseId: String,
        decision: PermissionDecision,
        scope: PermissionScope
    ) async throws {
        AppLogger.log("[AgentRepository] Responding to hook bridge permission: toolUseId=\(toolUseId), decision=\(decision.rawValue), scope=\(scope.rawValue)")
        let params = PermissionRespondParams(
            toolUseId: toolUseId,
            decision: decision,
            scope: scope
        )
        let result: PermissionRespondResult = try await rpcClient.request(
            method: JSONRPCMethod.permissionRespond,
            params: params
        )
        if !result.isSuccess {
            let errorMsg = result.error ?? result.message ?? "Unknown error"
            AppLogger.log("[AgentRepository] Permission respond failed: \(errorMsg)", type: .error)
            throw AgentRepositoryError.permissionRespondFailed(errorMsg)
        }
        AppLogger.log("[AgentRepository] Permission respond succeeded", type: .success)
    }

    // MARK: - File Operations

    func getFile(path: String) async throws -> FileContentPayload {
        // Get workspace ID from active workspace
        let workspaceId = await MainActor.run { self.currentWorkspaceId }
        guard let wsId = workspaceId else {
            AppLogger.log("[AgentRepository] No workspace ID available for file get", type: .warning)
            throw AgentRepositoryError.noWorkspaceContext
        }

        let params = WorkspaceFileGetParams(workspaceId: wsId, path: path)
        let result: FileGetResult = try await rpcClient.request(
            method: JSONRPCMethod.workspaceFileGet,
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
                isNew: item.isNew,
                isTruncated: item.isTruncated
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

    func getSessions(workspaceId: String, limit: Int = 20, offset: Int = 0) async throws -> SessionsResponse {
        guard !workspaceId.isEmpty else {
            AppLogger.network("[Sessions] Error: workspaceId required for workspace/session/history", type: .error)
            throw AgentRepositoryError.workspaceIdRequired
        }

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

    func getSessionMessages(
        sessionId: String,
        workspaceId: String?,
        limit: Int = 20,
        offset: Int = 0,
        order: String = "desc"
    ) async throws -> SessionMessagesResponse {
        // Workspace ID is required for workspace/session/messages API
        guard let workspaceId = workspaceId else {
            AppLogger.network("[Sessions] Error: workspaceId required for workspace/session/messages", type: .error)
            throw AgentRepositoryError.workspaceIdRequired
        }

        AppLogger.network("[Sessions] Using workspace/session/messages for workspace: \(workspaceId)")
        let params = WorkspaceSessionMessagesParams(
            workspaceId: workspaceId,
            sessionId: sessionId,
            limit: limit,
            offset: offset,
            order: order
        )

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
    }

    func deleteSession(sessionId: String, workspaceId: String) async throws -> DeleteSessionResponse {
        AppLogger.log("[AgentRepository] Deleting session: \(sessionId) from workspace: \(workspaceId)")
        let params = WorkspaceSessionDeleteParams(workspaceId: workspaceId, sessionId: sessionId)
        let result: WorkspaceSessionDeleteResult = try await rpcClient.request(
            method: JSONRPCMethod.workspaceSessionDelete,
            params: params
        )
        AppLogger.log("[AgentRepository] Session delete result: \(result.status ?? "unknown")")
        return DeleteSessionResponse(
            message: result.status ?? "deleted",
            sessionId: sessionId
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

// MARK: - Errors

enum AgentRepositoryError: LocalizedError {
    case workspaceIdRequired
    case noWorkspaceContext
    case noSessionContext
    case permissionRespondFailed(String)  // Hook bridge permission respond failed

    var errorDescription: String? {
        switch self {
        case .workspaceIdRequired:
            return "Workspace ID is required for this operation. Please ensure a workspace is selected."
        case .noWorkspaceContext:
            return "No workspace context available. Please select a workspace first."
        case .noSessionContext:
            return "No session context available. Please start or resume a session first."
        case .permissionRespondFailed(let message):
            return "Permission response failed: \(message)"
        }
    }
}
