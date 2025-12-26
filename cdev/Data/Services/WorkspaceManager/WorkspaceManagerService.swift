import Foundation

// MARK: - Workspace Manager Service

/// Service for workspace and session management via cdev server
/// Single-port architecture: uses main WebSocket connection on port 8766
/// Provides JSON-RPC methods for workspace listing, session management, and subscriptions
@MainActor
final class WorkspaceManagerService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var workspaces: [RemoteWorkspace] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: WorkspaceManagerError?

    /// Current server host (if connected)
    @Published private(set) var currentHost: String?

    /// Currently subscribed workspace IDs
    @Published private(set) var subscribedWorkspaceIds: Set<String> = []

    /// Track workspaces that failed to connect (agent not responding)
    @Published private(set) var unreachableWorkspaceIds: Set<String> = []

    /// Track if repository discovery is in progress (shared across all callers)
    @Published private(set) var isDiscovering: Bool = false

    /// Last discovery response with cache metadata
    @Published private(set) var lastDiscoveryResponse: DiscoveryResponse?

    /// Current discovery task for cancellation
    private var discoveryTask: Task<[DiscoveredRepository], Error>?

    // MARK: - Dependencies

    private weak var webSocketService: WebSocketServiceProtocol?

    // MARK: - JSON Coding

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Use custom date decoding to handle ISO8601 with fractional seconds
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            // Try with fractional seconds first
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            // Fall back to standard ISO8601 without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }()

    // MARK: - Singleton

    static let shared = WorkspaceManagerService()

    private init() {}

    // MARK: - Configuration

    /// Configure the service with a WebSocket service
    /// Must be called before any operations
    /// Note: nonisolated to allow calling from non-main actor contexts during setup
    nonisolated func configure(webSocketService: WebSocketServiceProtocol) {
        Task { @MainActor in
            self.webSocketService = webSocketService
        }
    }

    /// Set current host (called when WebSocket connects)
    func setCurrentHost(_ host: String?) {
        currentHost = host
    }

    /// Check if connected to server
    var isConnected: Bool {
        webSocketService?.isConnected ?? false
    }

    // MARK: - Unreachable Workspace Tracking

    /// Mark a workspace as unreachable (session not responding)
    func markWorkspaceUnreachable(_ workspaceId: String) {
        unreachableWorkspaceIds.insert(workspaceId)
        AppLogger.log("[WorkspaceManager] Marked workspace as unreachable: \(workspaceId)")
    }

    /// Clear unreachable status for a workspace
    func clearUnreachableStatus(_ workspaceId: String) {
        if unreachableWorkspaceIds.remove(workspaceId) != nil {
            AppLogger.log("[WorkspaceManager] Cleared unreachable status: \(workspaceId)")
        }
    }

    /// Check if a workspace is marked as unreachable
    func isWorkspaceUnreachable(_ workspaceId: String) -> Bool {
        unreachableWorkspaceIds.contains(workspaceId)
    }

    /// Clear all unreachable statuses (e.g., on disconnect)
    func clearAllUnreachableStatus() {
        unreachableWorkspaceIds.removeAll()
    }

    // MARK: - Local Workspace State Updates

    /// Update a workspace with a new/updated session (without full list refresh)
    func updateWorkspaceSession(workspaceId: String, session: Session) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceId }) else {
            AppLogger.log("[WorkspaceManager] Workspace not found for session update: \(workspaceId)", type: .warning)
            return
        }

        var workspace = workspaces[index]
        // Check if session already exists, update it; otherwise add new
        if let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == session.id }) {
            workspace.sessions[sessionIndex] = session
        } else {
            workspace.sessions.append(session)
        }
        workspaces[index] = workspace
        AppLogger.log("[WorkspaceManager] Updated workspace \(workspaceId) with session \(session.id)")
    }

    /// Remove a session from its workspace (without full list refresh)
    func removeSessionFromWorkspace(sessionId: String) {
        for (index, workspace) in workspaces.enumerated() {
            if let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionId }) {
                var updatedWorkspace = workspace
                updatedWorkspace.sessions.remove(at: sessionIndex)
                workspaces[index] = updatedWorkspace
                AppLogger.log("[WorkspaceManager] Removed session \(sessionId) from workspace \(workspace.id)")
                return
            }
        }
        AppLogger.log("[WorkspaceManager] Session not found for removal: \(sessionId)", type: .warning)
    }

    // MARK: - Workspace Operations

    /// List all workspaces from the server
    func listWorkspaces() async throws -> [RemoteWorkspace] {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        let client = ws.getJSONRPCClient()
        let response: WorkspaceListResponse = try await client.request(
            method: "workspace/list",
            params: EmptyParams()
        )

        // Sort workspaces alphabetically by name (case-insensitive)
        workspaces = response.workspaces.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Sync remote workspace IDs to local WorkspaceStore
        // This enables workspace-aware APIs (workspace/session/*) instead of legacy APIs
        WorkspaceStore.shared.syncRemoteWorkspaceIds(from: response.workspaces)

        // Cleanup: Remove unreachable IDs for workspaces that no longer exist
        let currentWorkspaceIds = Set(response.workspaces.map(\.id))
        let staleIds = unreachableWorkspaceIds.subtracting(currentWorkspaceIds)
        if !staleIds.isEmpty {
            unreachableWorkspaceIds = unreachableWorkspaceIds.intersection(currentWorkspaceIds)
            AppLogger.log("[WorkspaceManager] Cleaned up \(staleIds.count) stale unreachable IDs")
        }

        AppLogger.log("[WorkspaceManager] Listed \(workspaces.count) workspaces")
        return workspaces
    }

    /// Get a specific workspace
    func getWorkspace(_ id: String) async throws -> RemoteWorkspace {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: RemoteWorkspace = try await client.request(
            method: "workspace/get",
            params: WorkspaceIdParams(id: id)
        )

        // Update local state
        if let index = workspaces.firstIndex(where: { $0.id == id }) {
            workspaces[index] = response
        }

        return response
    }

    /// Add a new workspace (register a repository)
    /// - Parameters:
    ///   - path: Absolute path to the git repository
    ///   - name: Display name (if nil, derived from path's last component)
    func addWorkspace(path: String, name: String? = nil) async throws -> RemoteWorkspace {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        // Derive name from path if not provided (last path component)
        let workspaceName = name ?? URL(fileURLWithPath: path).lastPathComponent

        let client = ws.getJSONRPCClient()
        let response: RemoteWorkspace = try await client.request(
            method: "workspace/add",
            params: AddWorkspaceParams(path: path, name: workspaceName)
        )

        // Add to local workspaces list and maintain alphabetical sort
        if !workspaces.contains(where: { $0.id == response.id }) {
            workspaces.append(response)
            workspaces.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        Haptics.success()
        AppLogger.log("[WorkspaceManager] Added workspace: \(response.name)")
        return response
    }

    /// Remove a workspace
    func removeWorkspace(_ id: String) async throws {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let _: EmptyResponse = try await client.request(
            method: "workspace/remove",
            params: WorkspaceIdParams(id: id)
        )

        // Remove from local state
        workspaces.removeAll { $0.id == id }
        unreachableWorkspaceIds.remove(id)
        subscribedWorkspaceIds.remove(id)

        Haptics.light()
        AppLogger.log("[WorkspaceManager] Removed workspace: \(id)")
    }

    // MARK: - Session Operations

    /// Start a new Claude session for a workspace
    func startSession(workspaceId: String) async throws -> Session {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: SessionStartResponse = try await client.request(
            method: "session/start",
            params: WMSessionStartParams(workspaceId: workspaceId)
        )

        // Clear unreachable status on successful session start
        clearUnreachableStatus(workspaceId)

        // Update only the specific workspace's sessions (no full list refresh)
        let newSession = Session(
            id: response.id,
            workspaceId: response.workspaceId,
            status: response.status,
            startedAt: response.startedAt,
            lastActive: response.lastActive
        )
        updateWorkspaceSession(workspaceId: workspaceId, session: newSession)

        Haptics.success()
        AppLogger.log("[WorkspaceManager] Started session: \(response.id) for workspace: \(workspaceId)")

        return Session(
            id: response.id,
            workspaceId: response.workspaceId,
            status: response.status,
            startedAt: response.startedAt,
            lastActive: response.lastActive
        )
    }

    /// Stop a session
    func stopSession(sessionId: String) async throws {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()

        do {
            let _: EmptyResponse = try await client.request(
                method: "session/stop",
                params: SessionIdParams(sessionId: sessionId)
            )
        } catch let error as JSONRPCClientError {
            // Convert RPC errors to WorkspaceManager errors for better UI handling
            if case .timeout(_, let method) = error {
                AppLogger.log("[WorkspaceManager] Timeout stopping session: \(sessionId) - method: \(method)", type: .error)
                throw WorkspaceManagerError.timeout
            }
            throw WorkspaceManagerError.rpcError(code: error.code, message: error.errorDescription ?? "Unknown error")
        }

        // Remove the session from local state (no full list refresh)
        removeSessionFromWorkspace(sessionId: sessionId)

        Haptics.light()
        AppLogger.log("[WorkspaceManager] Stopped session: \(sessionId)")
    }

    /// Send a prompt to a session
    /// Uses permission_mode: "interactive" to enable PTY mode for terminal-like permission prompts
    func sendPrompt(sessionId: String, prompt: String, mode: String = "new") async throws {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let _: SessionSendResponse = try await client.request(
            method: "session/send",
            params: WMSessionSendParams(
                sessionId: sessionId,
                prompt: prompt,
                mode: mode,
                permissionMode: "interactive"
            )
        )

        AppLogger.log("[WorkspaceManager] Sent prompt to session: \(sessionId) (interactive mode)")
    }

    /// Respond to a permission request or question
    func respond(sessionId: String, type: String, response: String) async throws {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let _: EmptyResponse = try await client.request(
            method: "session/respond",
            params: WMSessionRespondParams(sessionId: sessionId, type: type, response: response)
        )

        AppLogger.log("[WorkspaceManager] Responded to session: \(sessionId)")
    }

    /// Get session state (for reconnection sync)
    func getSessionState(sessionId: String) async throws -> SessionStateResponse {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: SessionStateResponse = try await client.request(
            method: "session/state",
            params: SessionIdParams(sessionId: sessionId)
        )

        AppLogger.log("[WorkspaceManager] Got state for session: \(sessionId)")
        return response
    }

    /// List active sessions (optionally filtered by workspace)
    func listActiveSessions(workspaceId: String? = nil) async throws -> [Session] {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()

        let params: ActiveSessionsParams
        if let workspaceId = workspaceId {
            params = ActiveSessionsParams(workspaceId: workspaceId)
        } else {
            params = ActiveSessionsParams(workspaceId: nil)
        }

        let response: ActiveSessionsResponse = try await client.request(
            method: "session/active",
            params: params
        )

        AppLogger.log("[WorkspaceManager] Listed \(response.sessions.count) active sessions")
        return response.sessions
    }

    /// Get session history for a workspace (workspace-aware API)
    func getSessionHistory(workspaceId: String, limit: Int = 50) async throws -> SessionHistoryResult {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: SessionHistoryResult = try await client.request(
            method: JSONRPCMethod.workspaceSessionHistory,
            params: SessionHistoryParams(workspaceId: workspaceId, limit: limit)
        )

        AppLogger.log("[WorkspaceManager] Got session history: \(response.sessions?.count ?? 0) sessions for workspace \(workspaceId)")
        return response
    }

    // MARK: - Subscription Operations

    /// Subscribe to events from a workspace
    func subscribe(workspaceId: String) async throws {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: WorkspaceSubscribeResponse = try await client.request(
            method: "workspace/subscribe",
            params: WorkspaceIdParams(id: workspaceId)
        )

        subscribedWorkspaceIds = Set(response.subscribed)
        AppLogger.log("[WorkspaceManager] Subscribed to workspace: \(workspaceId)")
    }

    /// Unsubscribe from workspace events
    func unsubscribe(workspaceId: String) async throws {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let _: EmptyResponse = try await client.request(
            method: "workspace/unsubscribe",
            params: WorkspaceIdParams(id: workspaceId)
        )

        subscribedWorkspaceIds.remove(workspaceId)
        AppLogger.log("[WorkspaceManager] Unsubscribed from workspace: \(workspaceId)")
    }

    /// Get current subscriptions
    func getSubscriptions() async throws -> WorkspaceSubscriptionsResponse {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: WorkspaceSubscriptionsResponse = try await client.request(
            method: "workspace/subscriptions",
            params: EmptyParams()
        )

        subscribedWorkspaceIds = Set(response.workspaces)
        AppLogger.log("[WorkspaceManager] Got subscriptions: \(response.count) workspaces")
        return response
    }

    /// Subscribe to all workspaces (reset filter)
    func subscribeAll() async throws {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let _: EmptyResponse = try await client.request(
            method: "workspace/subscribeAll",
            params: EmptyParams()
        )

        subscribedWorkspaceIds.removeAll()
        AppLogger.log("[WorkspaceManager] Subscribed to all workspaces")
    }

    // MARK: - Repository Discovery

    /// Discover Git repositories on the host machine
    /// Uses shared isDiscovering state to prevent duplicate concurrent requests
    /// - Parameters:
    ///   - paths: Custom paths to scan (uses defaults if nil)
    ///   - fresh: Force fresh scan, ignore cache
    /// - Returns: Array of discovered repositories
    func discoverRepositories(paths: [String]? = nil, fresh: Bool = false) async throws -> [DiscoveredRepository] {
        // Skip if already discovering - prevents duplicate requests from multiple callers
        // But allow fresh scan to proceed (it will cancel existing task)
        guard !isDiscovering || fresh else {
            AppLogger.log("[WorkspaceManager] Skipping discovery - already in progress")
            // Wait for existing task and return its result
            if let existingTask = discoveryTask {
                return try await existingTask.value
            }
            return []
        }

        // If fresh scan requested, cancel existing task
        if fresh && isDiscovering {
            cancelDiscovery()
        }

        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        isDiscovering = true

        // Create and store task for potential reuse/cancellation
        // Discovery can take longer as it scans the filesystem - use 120s timeout
        let task = Task<[DiscoveredRepository], Error> { [weak self] in
            let client = ws.getJSONRPCClient()
            let response: DiscoveryResponse = try await client.request(
                method: "workspace/discover",
                params: DiscoverParams(paths: paths, fresh: fresh ? true : nil),
                timeout: 120.0
            )

            // Store response for cache metadata access
            await MainActor.run {
                self?.lastDiscoveryResponse = response
            }

            let cacheInfo = response.isCached ? " (cached, \(response.cacheAgeDescription ?? "unknown age"))" : " (fresh scan)"
            AppLogger.log("[WorkspaceManager] Discovered \(response.count) repositories\(cacheInfo)")

            if response.isRefreshing {
                AppLogger.log("[WorkspaceManager] Background refresh in progress")
            }

            return response.repositories
        }

        discoveryTask = task

        do {
            let result = try await task.value
            isDiscovering = false
            discoveryTask = nil
            return result
        } catch {
            isDiscovering = false
            discoveryTask = nil
            throw error
        }
    }

    /// Cancel any in-progress discovery request
    func cancelDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        isDiscovering = false
        AppLogger.log("[WorkspaceManager] Discovery cancelled")
    }

    // MARK: - Git Operations

    /// Get git status for a workspace
    func getGitStatus(workspaceId: String) async throws -> GitStatusExtendedResponse {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: GitStatusExtendedResponse = try await client.request(
            method: "workspace/git/status",
            params: WorkspaceIdParams(id: workspaceId)
        )

        return response
    }

    /// Get git diff for a workspace
    func getGitDiff(workspaceId: String, staged: Bool = false) async throws -> GitDiffResponse {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: GitDiffResponse = try await client.request(
            method: "workspace/git/diff",
            params: WorkspaceGitDiffParams(workspaceId: workspaceId, staged: staged)
        )

        return response
    }

    /// Stage files for a workspace
    @discardableResult
    func gitStage(workspaceId: String, paths: [String]) async throws -> GitOperationResponse {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: GitOperationResponse = try await client.request(
            method: JSONRPCMethod.workspaceGitStage,
            params: WorkspaceGitPathsParams(workspaceId: workspaceId, paths: paths)
        )

        return response
    }

    /// Unstage files for a workspace
    @discardableResult
    func gitUnstage(workspaceId: String, paths: [String]) async throws -> GitOperationResponse {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: GitOperationResponse = try await client.request(
            method: JSONRPCMethod.workspaceGitUnstage,
            params: WorkspaceGitPathsParams(workspaceId: workspaceId, paths: paths)
        )

        return response
    }

    /// Discard changes in files for a workspace
    @discardableResult
    func gitDiscard(workspaceId: String, paths: [String]) async throws -> GitOperationResponse {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: GitOperationResponse = try await client.request(
            method: JSONRPCMethod.workspaceGitDiscard,
            params: WorkspaceGitPathsParams(workspaceId: workspaceId, paths: paths)
        )

        return response
    }

    /// Commit staged changes for a workspace
    @discardableResult
    func gitCommit(workspaceId: String, message: String, push: Bool = false) async throws -> GitCommitResponse {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: GitCommitResponse = try await client.request(
            method: JSONRPCMethod.workspaceGitCommit,
            params: WorkspaceGitCommitParams(workspaceId: workspaceId, message: message, push: push)
        )

        return response
    }

    /// Push commits for a workspace
    @discardableResult
    func gitPush(workspaceId: String, force: Bool = false, setUpstream: Bool = false) async throws -> WorkspaceGitPushResult {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: WorkspaceGitPushResult = try await client.request(
            method: JSONRPCMethod.workspaceGitPush,
            params: WorkspaceGitPushParams(workspaceId: workspaceId, force: force, setUpstream: setUpstream)
        )

        return response
    }

    /// Pull changes for a workspace
    @discardableResult
    func gitPull(workspaceId: String, rebase: Bool = false) async throws -> WorkspaceGitPullResult {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: WorkspaceGitPullResult = try await client.request(
            method: JSONRPCMethod.workspaceGitPull,
            params: WorkspaceGitPullParams(workspaceId: workspaceId, rebase: rebase)
        )

        return response
    }

    /// Get branches for a workspace
    func getBranches(workspaceId: String) async throws -> WorkspaceGitBranchesResult {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: WorkspaceGitBranchesResult = try await client.request(
            method: JSONRPCMethod.workspaceGitBranches,
            params: WorkspaceGitBranchesParams(workspaceId: workspaceId)
        )

        return response
    }

    /// Checkout a branch for a workspace
    @discardableResult
    func gitCheckout(workspaceId: String, branch: String, create: Bool = false) async throws -> WorkspaceGitCheckoutResult {
        guard let ws = webSocketService else {
            throw WorkspaceManagerError.notConnected
        }

        let client = ws.getJSONRPCClient()
        let response: WorkspaceGitCheckoutResult = try await client.request(
            method: JSONRPCMethod.workspaceGitCheckout,
            params: WorkspaceGitCheckoutParams(workspaceId: workspaceId, branch: branch, create: create)
        )

        return response
    }

    // MARK: - State Reset

    /// Reset all state (on disconnect)
    func reset() {
        // Cancel any pending discovery to prevent memory leaks
        cancelDiscovery()

        workspaces = []
        subscribedWorkspaceIds.removeAll()
        unreachableWorkspaceIds.removeAll()
        currentHost = nil
        error = nil
        isLoading = false
        AppLogger.log("[WorkspaceManager] Reset state")
    }
}

// MARK: - Request Parameter Types

private struct WorkspaceIdParams: Encodable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "workspace_id"
    }
}

private struct AddWorkspaceParams: Encodable {
    let path: String
    let name: String  // Required by API - derived from path if not provided
}

private struct DiscoverParams: Encodable {
    let paths: [String]?
    let fresh: Bool?      // Force fresh scan, ignore cache
}

private struct WMSessionStartParams: Encodable {
    let workspaceId: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }
}

private struct SessionIdParams: Encodable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

private struct WMSessionSendParams: Encodable {
    let sessionId: String
    let prompt: String
    let mode: String
    let permissionMode: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case prompt
        case mode
        case permissionMode = "permission_mode"
    }
}

private struct WMSessionRespondParams: Encodable {
    let sessionId: String
    let type: String
    let response: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case type
        case response
    }
}

private struct ActiveSessionsParams: Encodable {
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
    }
}

// Note: WorkspaceGitDiffParams, WorkspaceGitPathsParams, and other workspace git types
// are defined in JSONRPCMethods.swift

private struct EmptyResponse: Decodable {}

// MARK: - Git Diff Response

/// Response from workspace/git/diff JSON-RPC method
/// Handles both single file response and multi-file response formats
struct GitDiffResponse: Codable {
    // Multi-file response format: { "diffs": [...] }
    let diffs: [GitDiffItem]?

    // Single file response format: { "diff": "...", "path": "...", ... }
    let diff: String?
    let path: String?
    let isNew: Bool?
    let isStaged: Bool?

    enum CodingKeys: String, CodingKey {
        case diffs, diff, path
        case isNew = "is_new"
        case isStaged = "is_staged"
    }

    struct GitDiffItem: Codable {
        let path: String
        let diff: String
        let isNew: Bool?
        let isStaged: Bool?

        enum CodingKeys: String, CodingKey {
            case path, diff
            case isNew = "is_new"
            case isStaged = "is_staged"
        }
    }

    /// Get all diff items (handles both response formats)
    var allDiffs: [GitDiffItem] {
        // If we have the array format, use it
        if let diffs = diffs, !diffs.isEmpty {
            return diffs
        }
        // If we have single file format, convert to array
        if let diff = diff, let path = path {
            return [GitDiffItem(path: path, diff: diff, isNew: isNew, isStaged: isStaged)]
        }
        return []
    }
}

// MARK: - Errors

enum WorkspaceManagerError: LocalizedError {
    case notConnected
    case encodingFailed
    case noResult
    case timeout
    case workspaceFailed(String)
    case sessionFailed(String)
    case rpcError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .encodingFailed:
            return "Failed to encode request"
        case .noResult:
            return "No result in response"
        case .timeout:
            return "Request timed out. The server did not respond in time. Please try again."
        case .workspaceFailed(let id):
            return "Workspace operation failed: \(id)"
        case .sessionFailed(let id):
            return "Session operation failed: \(id)"
        case .rpcError(let code, let message):
            return "[\(code)] \(message)"
        }
    }
}
