import Foundation

/// Use case for sending prompts to Claude
protocol SendPromptUseCase {
    func execute(prompt: String, mode: SessionMode, sessionId: String?) async throws
}

final class DefaultSendPromptUseCase: SendPromptUseCase {
    private let agentRepository: AgentRepositoryProtocol

    init(agentRepository: AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    func execute(prompt: String, mode: SessionMode = .new, sessionId: String? = nil) async throws {
        // Validate prompt
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.commandFailed(reason: "Prompt cannot be empty")
        }

        AppLogger.log("Sending prompt to Claude (mode: \(mode.rawValue))")

        try await agentRepository.runClaude(prompt: prompt, mode: mode, sessionId: sessionId)

        AppLogger.log("Prompt sent successfully", type: .success)
    }
}
