import Foundation

/// Current agent status
struct AgentStatus: Equatable {
    let claudeState: ClaudeState
    let sessionId: String?
    let repoName: String?
    let repoPath: String?
    let connectedClients: Int
    let uptime: TimeInterval
    let lastUpdated: Date

    init(
        claudeState: ClaudeState = .idle,
        sessionId: String? = nil,
        repoName: String? = nil,
        repoPath: String? = nil,
        connectedClients: Int = 0,
        uptime: TimeInterval = 0,
        lastUpdated: Date = Date()
    ) {
        self.claudeState = claudeState
        self.sessionId = sessionId
        self.repoName = repoName
        self.repoPath = repoPath
        self.connectedClients = connectedClients
        self.uptime = uptime
        self.lastUpdated = lastUpdated
    }

    /// Create from status response payload
    static func from(payload: StatusResponsePayload) -> AgentStatus {
        AgentStatus(
            claudeState: payload.claudeState ?? .idle,
            sessionId: payload.sessionId,
            repoName: payload.repoName,
            repoPath: payload.repoPath,
            connectedClients: payload.connectedClients ?? 0,
            uptime: TimeInterval(payload.uptime ?? 0)
        )
    }

    /// Create from JSON-RPC status/get result
    static func from(rpcResult: StatusGetResult) -> AgentStatus {
        // Parse agent state string to ClaudeState
        let claudeState: ClaudeState
        switch rpcResult.agentState?.lowercased() {
        case "running", "starting":
            claudeState = .running
        case "idle":
            claudeState = .idle
        case "waiting":
            claudeState = .waiting
        case "error":
            claudeState = .error
        case "stopped", "stopping":
            claudeState = .stopped
        default:
            claudeState = .idle
        }

        return AgentStatus(
            claudeState: claudeState,
            sessionId: rpcResult.sessionId,
            repoName: rpcResult.repoName,
            repoPath: rpcResult.repoPath,
            connectedClients: rpcResult.connectedClients ?? 0,
            uptime: TimeInterval(rpcResult.uptimeSeconds ?? 0)
        )
    }

    /// Formatted uptime string
    var uptimeString: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: uptime) ?? "0s"
    }

    /// Status badge text
    var statusBadge: String {
        switch claudeState {
        case .running:
            return "Running"
        case .idle:
            return "Idle"
        case .waiting:
            return "Waiting"
        case .error:
            return "Error"
        case .stopped:
            return "Stopped"
        }
    }
}

/// Pending interaction (question or permission request)
struct PendingInteraction: Identifiable, Equatable {
    let id: String
    let type: InteractionType
    let description: String
    let requestId: String?
    let options: [QuestionOption]?
    let ptyOptions: [PTYPromptOption]?  // PTY mode options with key shortcuts
    let timestamp: Date

    enum InteractionType: Equatable {
        case question
        case permission(tool: String)
        case ptyPermission(type: PTYPermissionType, toolName: String?)  // PTY mode permission
    }

    init(
        id: String,
        type: InteractionType,
        description: String,
        requestId: String? = nil,
        options: [QuestionOption]? = nil,
        ptyOptions: [PTYPromptOption]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.requestId = requestId
        self.options = options
        self.ptyOptions = ptyOptions
        self.timestamp = timestamp
    }

    /// Whether this is a PTY mode interaction (requires session/input response)
    var isPTYMode: Bool {
        if case .ptyPermission = type { return true }
        return false
    }

    /// Create from waiting event
    static func fromWaiting(event: AgentEvent) -> PendingInteraction? {
        guard case .claudeWaiting(let payload) = event.payload else { return nil }

        return PendingInteraction(
            id: event.id,
            type: .question,
            description: payload.question ?? payload.description ?? "Claude is waiting for input",
            requestId: payload.requestId,
            options: payload.options,
            timestamp: event.timestamp
        )
    }

    /// Create from permission event
    static func fromPermission(event: AgentEvent) -> PendingInteraction? {
        guard case .claudePermission(let payload) = event.payload,
              let tool = payload.tool else { return nil }

        return PendingInteraction(
            id: event.id,
            type: .permission(tool: tool),
            description: payload.description ?? "Permission requested for \(tool)",
            requestId: payload.requestId,
            options: nil,
            timestamp: event.timestamp
        )
    }

    /// Create from PTY permission event (interactive terminal mode)
    static func fromPTYPermission(event: AgentEvent) -> PendingInteraction? {
        guard case .ptyPermission(let payload) = event.payload else { return nil }

        let permissionType = payload.type ?? .unknown
        let toolName = payload.toolName

        return PendingInteraction(
            id: event.id,
            type: .ptyPermission(type: permissionType, toolName: toolName),
            description: payload.displayDescription,
            requestId: nil,  // PTY mode doesn't use request IDs
            options: nil,
            ptyOptions: payload.options,
            timestamp: event.timestamp
        )
    }
}
