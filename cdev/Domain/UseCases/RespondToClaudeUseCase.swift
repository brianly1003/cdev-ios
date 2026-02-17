import Foundation

/// Use case for responding to Claude (questions or permissions)
protocol RespondToClaudeUseCase {
    /// Answer a question
    func answerQuestion(response: String, requestId: String?, runtime: AgentRuntime) async throws

    /// Approve or deny permission
    func handlePermission(approved: Bool, requestId: String?, runtime: AgentRuntime) async throws
}

final class DefaultRespondToClaudeUseCase: RespondToClaudeUseCase {
    private let agentRepository: AgentRepositoryProtocol

    init(agentRepository: AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    func answerQuestion(response: String, requestId: String?, runtime: AgentRuntime) async throws {
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.commandFailed(reason: "Response cannot be empty")
        }

        AppLogger.log("Answering Claude question")

        try await agentRepository.respondToClaude(
            response: response,
            requestId: requestId,
            approved: nil,
            runtime: runtime
        )

        AppLogger.log("Response sent", type: .success)
    }

    func handlePermission(approved: Bool, requestId: String?, runtime: AgentRuntime) async throws {
        AppLogger.log("Handling permission: \(approved ? "approved" : "denied")")

        try await agentRepository.respondToClaude(
            response: approved ? "yes" : "no",
            requestId: requestId,
            approved: approved,
            runtime: runtime
        )

        AppLogger.log("Permission response sent", type: .success)
    }
}
