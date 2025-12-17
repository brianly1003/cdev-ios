import Foundation

/// Protocol for agent data repository
protocol AgentRepositoryProtocol {
    /// Current agent status
    var status: AgentStatus { get async }

    /// Get current status from agent
    func fetchStatus() async throws -> AgentStatus

    /// Run Claude with prompt
    func runClaude(prompt: String, mode: SessionMode, sessionId: String?) async throws

    /// Stop Claude
    func stopClaude() async throws

    /// Respond to Claude (answer question or approve/deny permission)
    func respondToClaude(response: String, requestId: String?, approved: Bool?) async throws

    /// Get file content
    func getFile(path: String) async throws -> FileContentPayload

    /// Get git status
    func getGitStatus() async throws -> GitStatusResponse

    /// Get git diff for file
    func getGitDiff(file: String?) async throws -> [GitDiffPayload]
}

/// Git status response from HTTP API
struct GitStatusResponse: Codable {
    let files: [GitFileStatus]
    let branch: String?
    let clean: Bool

    struct GitFileStatus: Codable, Identifiable {
        var id: String { path }
        let path: String
        let status: String
        let staged: Bool
    }
}
