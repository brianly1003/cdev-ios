import Foundation

/// Use case for sending prompts to the selected runtime (Claude/Codex)
protocol SendPromptUseCase {
    func execute(
        prompt: String,
        mode: SessionMode,
        sessionId: String?,
        runtime: AgentRuntime,
        yoloMode: Bool
    ) async throws
}

final class DefaultSendPromptUseCase: SendPromptUseCase {
    private let agentRepository: AgentRepositoryProtocol

    init(agentRepository: AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    func execute(
        prompt: String,
        mode: SessionMode = .new,
        sessionId: String? = nil,
        runtime: AgentRuntime = .claude,
        yoloMode: Bool = false
    ) async throws {
        // Validate prompt
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.commandFailed(reason: "Prompt cannot be empty")
        }

        AppLogger.log("Sending prompt (runtime: \(runtime.rawValue), mode: \(mode.rawValue))")

        try await agentRepository.runClaude(
            prompt: prompt,
            mode: mode,
            sessionId: sessionId,
            runtime: runtime,
            yoloMode: yoloMode
        )

        AppLogger.log("Prompt sent successfully", type: .success)
    }
}
