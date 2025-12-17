import Foundation

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
        let command = AgentCommand.runClaude(prompt: prompt, mode: mode, sessionId: sessionId)
        try await webSocketService.send(command: command)
    }

    func stopClaude() async throws {
        try await webSocketService.send(command: .stopClaude())
    }

    func respondToClaude(response: String, requestId: String?, approved: Bool?) async throws {
        let command: AgentCommand
        if let approved = approved {
            command = AgentCommand.approvePermission(requestId: requestId ?? "", approved: approved)
        } else {
            command = AgentCommand.respondToClaude(response: response, requestId: requestId)
        }
        try await webSocketService.send(command: command)
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
        var queryItems: [URLQueryItem]? = nil
        if let file = file {
            queryItems = [URLQueryItem(name: "file", value: file)]
        }
        return try await httpService.get(path: "/api/git/diff", queryItems: queryItems)
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
