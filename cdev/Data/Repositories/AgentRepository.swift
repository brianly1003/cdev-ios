import Foundation

/// Repository for agent data operations via JSON-RPC
final class AgentRepository: AgentRepositoryProtocol {
    private let webSocketService: WebSocketServiceProtocol
    private let httpService: HTTPServiceProtocol?

    /// Temporary flag to use HTTP fallback for session/messages (for testing)
    private let useHTTPForMessages = false  // Set to false to use RPC

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
        let _: AgentStopResult = try await rpcClient.request(
            method: JSONRPCMethod.agentStop,
            params: nil as EmptyParams?
        )
    }

    func respondToClaude(response: String, requestId: String?, approved: Bool?) async throws {
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

    func getGitDiff(file: String?) async throws -> [GitDiffPayload] {
        if let file = file {
            let params = GitDiffParams(path: file)
            let result: GitDiffResult = try await rpcClient.request(
                method: JSONRPCMethod.gitDiff,
                params: params
            )
            let payload = GitDiffPayload(
                file: result.path ?? file,
                diff: result.diff,
                additions: nil,
                deletions: nil,
                isNew: result.isNew
            )
            return [payload]
        } else {
            // For all files, we need to get status first then diff each
            let status = try await getGitStatus()
            var diffs: [GitDiffPayload] = []

            for fileStatus in status.files {
                let params = GitDiffParams(path: fileStatus.path)
                if let result: GitDiffResult = try? await rpcClient.request(
                    method: JSONRPCMethod.gitDiff,
                    params: params
                ) {
                    diffs.append(GitDiffPayload(
                        file: result.path ?? fileStatus.path,
                        diff: result.diff,
                        additions: nil,
                        deletions: nil,
                        isNew: result.isNew
                    ))
                }
            }
            return diffs
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

    func getSessions(limit: Int = 20, offset: Int = 0) async throws -> SessionsResponse {
        let params = SessionListParams(agentType: nil, limit: limit)
        let result: SessionListResult = try await rpcClient.request(
            method: JSONRPCMethod.sessionList,
            params: params
        )

        // Debug: log raw session data
        if let sessions = result.sessions {
            for (index, session) in sessions.enumerated() {
                AppLogger.network("[Sessions] Raw session[\(index)]: id=\(session.id ?? "nil"), session_id=\(session.sessionId ?? "nil"), resolvedId=\(session.resolvedId)")
            }
        } else {
            AppLogger.network("[Sessions] No sessions in result")
        }

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

        // JSON-RPC implementation - uses same message format as HTTP API
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
