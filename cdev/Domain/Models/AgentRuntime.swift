import Foundation

/// Session list source strategy per runtime.
enum SessionListSource: String, Sendable {
    case workspaceHistory
    case runtimeScoped

    static func parse(_ rawValue: String?) -> SessionListSource? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionListSource(rawValue: normalized)
    }
}

/// Session messages source strategy per runtime.
enum SessionMessagesSource: String, Sendable {
    case workspaceScoped
    case runtimeScoped

    static func parse(_ rawValue: String?) -> SessionMessagesSource? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionMessagesSource(rawValue: normalized)
    }
}

/// Session watch strategy per runtime.
enum SessionWatchSource: String, Sendable {
    case workspaceScoped
    case runtimeScoped

    static func parse(_ rawValue: String?) -> SessionWatchSource? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionWatchSource(rawValue: normalized)
    }
}

/// AI Agent Runtime - Extensible enum for all supported AI coding agents
/// Add new agents here - UI components will automatically adapt
///
/// Design note: This is the single source of truth for agent definitions.
/// ColorSystem.Agent provides corresponding colors for each agent.
enum AgentRuntime: String, CaseIterable, Identifiable, Codable, Sendable {
    // MARK: - Active Agents (visible in UI)
    case claude      // Anthropic Claude Code
    case codex       // OpenAI Codex CLI

    // MARK: - Coming Soon (add to allCases when ready)
    // case gemini      // Google Gemini CLI
    // case openrouter  // OpenRouter multi-model
    // case aider       // Aider coding assistant
    // case cursor      // Cursor AI

    var id: String { rawValue }

    // MARK: - Defaults

    static let defaultRuntime: AgentRuntime = .claude
    static let defaultRuntimeOrder: [AgentRuntime] = [.claude, .codex]

    static func availableRuntimes() -> [AgentRuntime] {
        RuntimeCapabilityRegistryStore.shared.availableRuntimes()
    }

    static func runtimeForID(_ rawID: String?) -> AgentRuntime? {
        guard let rawID else { return nil }
        let normalized = rawID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return AgentRuntime(rawValue: normalized)
    }

    static func normalizeKnownRuntimeIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in ids {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            guard AgentRuntime(rawValue: normalized) != nil else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }

    // MARK: - Display Properties

    /// Full display name for lists and headers
    var displayName: String {
        if let remoteName = RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?
            .displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteName.isEmpty {
            return remoteName
        }

        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Short display name for compact UI (2-3 chars max)
    /// Used in the segmented agent selector
    var shortName: String {
        switch self {
        case .claude: return "C."
        case .codex: return "Cx"
        }
    }

    /// Description for tooltips/accessibility
    var description: String {
        switch self {
        case .claude: return "Anthropic Claude Code - AI pair programming"
        case .codex: return "OpenAI Codex CLI - Terminal-based coding"
        }
    }

    // MARK: - Visual Identity

    /// SF Symbol icon name - choose icons that represent the agent's character
    var iconName: String {
        switch self {
        case .claude: return "sparkle"           // Claude's sparkle/magic feel
        case .codex: return "terminal"           // Codex terminal-centric
        }
    }

    /// Alternative icon for selected/active state (optional)
    var iconNameFilled: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "terminal.fill"
        }
    }

    // MARK: - Color Keys (resolved via ColorSystem.Agent)

    /// Color family identifier - used by ColorSystem.Agent
    var colorKey: String { rawValue }

    // MARK: - Runtime Strategies

    /// How this runtime loads session history.
    var sessionListSource: SessionListSource {
        if let source = SessionListSource.parse(
            RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?.sessionListSource
        ) {
            return source
        }

        switch self {
        case .claude: return .workspaceHistory
        case .codex: return .workspaceHistory
        }
    }

    /// How this runtime loads session messages.
    var sessionMessagesSource: SessionMessagesSource {
        if let source = SessionMessagesSource.parse(
            RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?.sessionMessagesSource
        ) {
            return source
        }

        switch self {
        case .claude: return .workspaceScoped
        case .codex: return .workspaceScoped
        }
    }

    /// How this runtime watches live session events.
    var sessionWatchSource: SessionWatchSource {
        if let source = SessionWatchSource.parse(
            RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?.sessionWatchSource
        ) {
            return source
        }

        switch self {
        case .claude: return .workspaceScoped
        case .codex: return .workspaceScoped
        }
    }

    /// Whether resuming a session should call workspace/session/activate.
    var requiresWorkspaceActivationOnResume: Bool {
        if let value = RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?
            .requiresWorkspaceActivationOnResume {
            return value
        }

        switch self {
        case .claude: return true
        case .codex: return false
        }
    }

    /// Whether a new session waits for session_id_resolved before loading APIs.
    var requiresSessionResolutionOnNewSession: Bool {
        if let value = RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?
            .requiresSessionResolutionOnNewSession {
            return value
        }

        switch self {
        case .claude: return true
        case .codex: return false
        }
    }

    // MARK: - Capabilities

    /// Whether this agent supports session resume
    var supportsResume: Bool {
        if let value = RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?
            .supportsResume {
            return value
        }

        switch self {
        case .claude: return true
        case .codex: return true
        }
    }

    /// Whether this agent supports interactive questions
    var supportsInteractiveQuestions: Bool {
        if let value = RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?
            .supportsInteractiveQuestions {
            return value
        }

        switch self {
        case .claude: return true
        case .codex: return true
        }
    }

    /// Whether this agent supports permission requests
    var supportsPermissions: Bool {
        if let value = RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?
            .supportsPermissions {
            return value
        }

        switch self {
        case .claude: return true
        case .codex: return true
        }
    }

    // MARK: - RPC Method Mapping

    var watchMethodName: String {
        if let method = normalizedRegistryMethod(RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?
            .methods?
            .watch) {
            return method
        }

        switch sessionWatchSource {
        case .workspaceScoped:
            return JSONRPCMethod.workspaceSessionWatch
        case .runtimeScoped:
            return JSONRPCMethod.sessionWatch
        }
    }

    var unwatchMethodName: String {
        if let method = normalizedRegistryMethod(RuntimeCapabilityRegistryStore.shared.descriptor(for: self)?
            .methods?
            .unwatch) {
            return method
        }

        switch sessionWatchSource {
        case .workspaceScoped:
            return JSONRPCMethod.workspaceSessionUnwatch
        case .runtimeScoped:
            return JSONRPCMethod.sessionUnwatch
        }
    }

    var usesWorkspaceScopedWatchMethod: Bool {
        methodScope(for: watchMethodName, fallback: sessionWatchSource) == .workspaceScoped
    }

    var usesWorkspaceScopedUnwatchMethod: Bool {
        methodScope(for: unwatchMethodName, fallback: sessionWatchSource) == .workspaceScoped
    }

    private func normalizedRegistryMethod(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func methodScope(
        for method: String,
        fallback: SessionWatchSource
    ) -> SessionWatchSource {
        let normalized = method.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == JSONRPCMethod.workspaceSessionWatch.lowercased() ||
            normalized.hasPrefix("workspace/") {
            return .workspaceScoped
        }
        if normalized == JSONRPCMethod.sessionWatch.lowercased() ||
            normalized.hasPrefix("session/") {
            return .runtimeScoped
        }
        return fallback
    }
}
