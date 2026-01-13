//
//  ExternalSession.swift
//  Cdev
//
//  Model for tracking external Claude sessions (VS Code, Cursor, terminal)
//  These sessions are read-only - user can monitor but not interact
//

import Foundation

// MARK: - External Session

/// Represents an external Claude Code session running outside of cdev
/// (e.g., in VS Code, Cursor, or terminal)
///
/// External sessions are read-only - the iOS app can monitor activity
/// but cannot send prompts, approve permissions, or stop the session.
struct ExternalSession: Identifiable, Codable, Equatable {
    let id: String                      // session_id from hook
    let workingDirectory: String        // cwd where Claude was started
    let gitBranch: String?              // Git branch if in a repo
    let startTime: Date                 // When session was detected
    var lastActivity: Date              // Last event received
    var currentTool: String?            // Currently running tool (nil if idle)
    var hasPendingPermission: Bool      // Whether permission prompt is active
    var pendingPermission: PendingExternalPermission?  // Permission details
    var toolHistory: [ToolExecution]    // Recent tool executions

    /// Project name extracted from working directory
    var projectName: String {
        (workingDirectory as NSString).lastPathComponent
    }

    /// Status for display
    var status: ExternalSessionStatus {
        if hasPendingPermission {
            return .permissionPending
        }
        if currentTool != nil {
            return .toolRunning
        }
        return .idle
    }

    /// Time since last activity
    var timeSinceLastActivity: TimeInterval {
        Date().timeIntervalSince(lastActivity)
    }

    /// Whether session is considered stale (no activity for 5 minutes)
    var isStale: Bool {
        timeSinceLastActivity > 300  // 5 minutes
    }

    // MARK: - Initialization

    init(
        id: String,
        workingDirectory: String,
        gitBranch: String? = nil,
        startTime: Date = Date(),
        lastActivity: Date = Date(),
        currentTool: String? = nil,
        hasPendingPermission: Bool = false,
        pendingPermission: PendingExternalPermission? = nil,
        toolHistory: [ToolExecution] = []
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.startTime = startTime
        self.lastActivity = lastActivity
        self.currentTool = currentTool
        self.hasPendingPermission = hasPendingPermission
        self.pendingPermission = pendingPermission
        self.toolHistory = toolHistory
    }

    /// Create from hook session payload
    init(from payload: HookSessionPayload) {
        self.id = payload.sessionId ?? UUID().uuidString
        self.workingDirectory = payload.cwd ?? "Unknown"
        self.gitBranch = payload.gitBranch
        self.startTime = Date()
        self.lastActivity = Date()
        self.currentTool = nil
        self.hasPendingPermission = false
        self.pendingPermission = nil
        self.toolHistory = []
    }
}

// MARK: - External Session Status

enum ExternalSessionStatus: String, Codable {
    case idle              // No active tool or permission
    case toolRunning       // Tool is executing
    case permissionPending // Waiting for permission response on desktop

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .toolRunning: return "Running"
        case .permissionPending: return "Permission"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "checkmark.circle"
        case .toolRunning: return "gearshape.fill"
        case .permissionPending: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Pending Permission

/// Permission pending in an external session
/// User must respond on desktop - this is informational only
struct PendingExternalPermission: Codable, Equatable, Identifiable {
    var id: String { "\(sessionId)-\(tool)" }

    let sessionId: String
    let tool: String           // Tool requesting permission
    let description: String    // Human-readable description
    let command: String?       // Command to execute (for Bash)
    let path: String?          // File path (for Write/Edit)
    let timestamp: Date        // When permission was requested

    /// Create from hook permission payload
    init(from payload: HookPermissionPayload) {
        self.sessionId = payload.sessionId ?? ""
        self.tool = payload.tool ?? "Unknown"
        self.description = payload.description ?? ""
        self.command = payload.command
        self.path = payload.path
        self.timestamp = Date()
    }

    /// Summary for display
    var displaySummary: String {
        if let command = command, !command.isEmpty {
            return command
        }
        if let path = path, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return description.isEmpty ? tool : description
    }
}

// MARK: - Tool Execution

/// Record of a tool execution in an external session
struct ToolExecution: Identifiable, Codable, Equatable {
    let id: String
    let toolName: String
    let inputSummary: String?   // Brief summary of input
    let startTime: Date
    var endTime: Date?          // nil if still running
    var outputSummary: String?  // Brief summary of output (truncated)
    var isError: Bool

    /// Duration of execution (nil if still running)
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    /// Whether this tool is still running
    var isRunning: Bool {
        endTime == nil
    }

    /// Formatted duration string
    var durationString: String {
        guard let duration = duration else { return "..." }
        if duration < 1 {
            return "<1s"
        } else if duration < 60 {
            return "\(Int(duration))s"
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        toolName: String,
        inputSummary: String? = nil,
        startTime: Date = Date(),
        endTime: Date? = nil,
        outputSummary: String? = nil,
        isError: Bool = false
    ) {
        self.id = id
        self.toolName = toolName
        self.inputSummary = inputSummary
        self.startTime = startTime
        self.endTime = endTime
        self.outputSummary = outputSummary
        self.isError = isError
    }

    /// Create from hook tool start payload
    init(from payload: HookToolStartPayload) {
        self.id = UUID().uuidString
        self.toolName = payload.toolName ?? "Unknown"
        self.inputSummary = payload.inputSummary
        self.startTime = Date()
        self.endTime = nil
        self.outputSummary = nil
        self.isError = false
    }
}
