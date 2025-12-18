import Foundation

// MARK: - HTTP Request/Response Types

struct RunClaudeRequest: Encodable {
    let prompt: String
    let mode: SessionMode
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case mode
        case sessionId = "session_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(mode.rawValue, forKey: .mode)
        // Only include session_id for continue/resume modes, never for "new" mode
        if mode != .new, let sessionId = sessionId, !sessionId.isEmpty {
            try container.encode(sessionId, forKey: .sessionId)
        }
    }
}

struct RunClaudeResponse: Decodable {
    let status: String
    let prompt: String
    let pid: Int?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case prompt
        case pid
        case sessionId = "session_id"
    }
}

struct RespondToClaudeRequest: Encodable {
    let toolUseId: String
    let response: String
    let isError: Bool

    enum CodingKeys: String, CodingKey {
        case toolUseId = "tool_use_id"
        case response
        case isError = "is_error"
    }
}

struct EmptyBody: Encodable {}

/// Repository for agent data operations
final class AgentRepository: AgentRepositoryProtocol {
    private let webSocketService: WebSocketServiceProtocol
    private let httpService: HTTPServiceProtocol

    @Atomic private var _status: AgentStatus = AgentStatus()

    var status: AgentStatus {
        get async { _status }
    }

    init(
        webSocketService: WebSocketServiceProtocol,
        httpService: HTTPServiceProtocol
    ) {
        self.webSocketService = webSocketService
        self.httpService = httpService
    }

    // MARK: - Status

    func fetchStatus() async throws -> AgentStatus {
        // Try HTTP first for immediate response
        do {
            let response: StatusResponsePayload = try await httpService.get(path: "/api/status", queryItems: nil)
            let status = AgentStatus.from(payload: response)
            _status = status
            return status
        } catch {
            // Fallback to WebSocket command
            try await webSocketService.send(command: .getStatus())
            return _status
        }
    }

    // MARK: - Claude Control

    func runClaude(prompt: String, mode: SessionMode, sessionId: String?) async throws {
        // Use HTTP API for running Claude
        let body = RunClaudeRequest(prompt: prompt, mode: mode, sessionId: sessionId)
        let _: RunClaudeResponse = try await httpService.post(path: "/api/claude/run", body: body)
    }

    func stopClaude() async throws {
        // Use HTTP API for stopping Claude
        try await httpService.post(path: "/api/claude/stop", body: EmptyBody())
    }

    func respondToClaude(response: String, requestId: String?, approved: Bool?) async throws {
        // Use HTTP API for responding to Claude
        let body = RespondToClaudeRequest(
            toolUseId: requestId ?? "",
            response: approved != nil ? (approved! ? "yes" : "no") : response,
            isError: false
        )
        try await httpService.post(path: "/api/claude/respond", body: body)
    }

    // MARK: - File Operations

    func getFile(path: String) async throws -> FileContentPayload {
        try await httpService.get(
            path: "/api/file",
            queryItems: [URLQueryItem(name: "path", value: path)]
        )
    }

    // MARK: - Git Operations

    func getGitStatus() async throws -> GitStatusResponse {
        try await httpService.get(path: "/api/git/status", queryItems: nil)
    }

    func getGitDiff(file: String?) async throws -> [GitDiffPayload] {
        if let file = file {
            // Single file request - API returns single object
            let queryItems = [URLQueryItem(name: "path", value: file)]
            let payload: GitDiffPayload = try await httpService.get(path: "/api/git/diff", queryItems: queryItems)
            return [payload]
        } else {
            // All files request - API returns array
            return try await httpService.get(path: "/api/git/diff", queryItems: nil)
        }
    }

    // MARK: - Sessions

    func getSessions(limit: Int = 20, offset: Int = 0) async throws -> SessionsResponse {
        let queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        return try await httpService.get(path: "/api/claude/sessions", queryItems: queryItems)
    }

    func getSessionMessages(sessionId: String) async throws -> SessionMessagesResponse {
        try await httpService.get(
            path: "/api/claude/sessions/messages",
            queryItems: [URLQueryItem(name: "session_id", value: sessionId)]
        )
    }

    func deleteSession(sessionId: String) async throws -> DeleteSessionResponse {
        try await httpService.delete(
            path: "/api/claude/sessions",
            queryItems: [URLQueryItem(name: "session_id", value: sessionId)]
        )
    }

    func deleteAllSessions() async throws -> DeleteAllSessionsResponse {
        try await httpService.delete(path: "/api/claude/sessions", queryItems: nil)
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
