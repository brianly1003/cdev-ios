import Foundation

/// Session list source strategy per runtime.
enum SessionListSource: Sendable {
    case workspaceHistory
    case runtimeScoped
}

/// Session messages source strategy per runtime.
enum SessionMessagesSource: Sendable {
    case workspaceScoped
    case runtimeScoped
}

/// Session watch strategy per runtime.
enum SessionWatchSource: Sendable {
    case workspaceScoped
    case runtimeScoped
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

    // MARK: - Display Properties

    /// Full display name for lists and headers
    var displayName: String {
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
        switch self {
        case .claude: return .workspaceHistory
        case .codex: return .workspaceHistory
        }
    }

    /// How this runtime loads session messages.
    var sessionMessagesSource: SessionMessagesSource {
        switch self {
        case .claude: return .workspaceScoped
        case .codex: return .workspaceScoped
        }
    }

    /// How this runtime watches live session events.
    var sessionWatchSource: SessionWatchSource {
        switch self {
        case .claude: return .workspaceScoped
        case .codex: return .workspaceScoped
        }
    }

    /// Whether resuming a session should call workspace/session/activate.
    var requiresWorkspaceActivationOnResume: Bool {
        switch self {
        case .claude: return true
        case .codex: return false
        }
    }

    /// Whether a new session waits for session_id_resolved before loading APIs.
    var requiresSessionResolutionOnNewSession: Bool {
        switch self {
        case .claude: return true
        case .codex: return false
        }
    }

    // MARK: - Capabilities

    /// Whether this agent supports session resume
    var supportsResume: Bool {
        switch self {
        case .claude: return true
        case .codex: return true
        }
    }

    /// Whether this agent supports interactive questions
    var supportsInteractiveQuestions: Bool {
        switch self {
        case .claude: return true
        case .codex: return true
        }
    }

    /// Whether this agent supports permission requests
    var supportsPermissions: Bool {
        switch self {
        case .claude: return true
        case .codex: return true
        }
    }
}
