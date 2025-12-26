import SwiftUI
import Combine

// MARK: - Server Connection Status

/// Status of connection to the workspace manager server
enum ServerConnectionStatus: Equatable {
    case connected
    case connecting(attempt: Int, maxAttempts: Int)
    case disconnected
    case unreachable(lastError: String?)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .connected:
            return "Connected"
        case .connecting(let attempt, let max):
            return "Connecting... (\(attempt)/\(max))"
        case .disconnected:
            return "Disconnected"
        case .unreachable:
            return "Server Unreachable"
        }
    }

    var statusColor: Color {
        switch self {
        case .connected: return ColorSystem.success
        case .connecting: return ColorSystem.warning
        case .disconnected, .unreachable: return ColorSystem.error
        }
    }
}

// MARK: - Workspace Operation Type

/// Type of operation being performed on a workspace
enum WorkspaceOperation: Equatable {
    case starting
    case stopping
    case connecting

    var displayText: String {
        switch self {
        case .starting: return "Starting..."
        case .stopping: return "Stopping..."
        case .connecting: return "Connecting..."
        }
    }
}

// MARK: - Workspace Manager ViewModel

/// ViewModel for managing remote workspaces
/// Single-port architecture: handles session lifecycle operations
@MainActor
final class WorkspaceManagerViewModel: ObservableObject {
    // MARK: - Published State

    /// All workspaces from manager
    @Published private(set) var workspaces: [RemoteWorkspace] = []

    /// Filtered workspaces based on search
    @Published var searchText: String = ""

    /// Loading states
    @Published private(set) var isLoading: Bool = false

    /// Per-workspace loading state (tracks which workspace is being operated on)
    @Published private(set) var loadingWorkspaceId: String?
    @Published private(set) var currentOperation: WorkspaceOperation?

    /// Track workspaces that failed to connect (observed from service)
    @Published private(set) var unreachableWorkspaceIds: Set<String> = []

    /// Error state (now used for inline display, not popup)
    @Published var error: WorkspaceManagerError?
    @Published var showError: Bool = false

    /// Server connection status (non-blocking)
    @Published private(set) var serverStatus: ServerConnectionStatus = .disconnected

    /// Retry configuration
    let maxRetryAttempts = 10
    private var currentRetryAttempt = 0
    private var connectionCancelled = false

    /// Currently active workspace (connected to agent)
    @Published var currentWorkspaceId: String?

    /// Show setup sheet
    @Published var showSetupSheet: Bool = false

    /// Show discovery sheet
    @Published var showDiscoverySheet: Bool = false

    /// Show manual add sheet
    @Published var showManualAddSheet: Bool = false

    // MARK: - Dependencies

    private let managerService: WorkspaceManagerService
    private let managerStore: ManagerStore
    private let webSocketService: WebSocketServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// Filtered workspaces based on search text
    var filteredWorkspaces: [RemoteWorkspace] {
        guard !searchText.isEmpty else { return workspaces }
        let query = searchText.lowercased()
        return workspaces.filter { workspace in
            workspace.name.lowercased().contains(query) ||
            workspace.path.lowercased().contains(query)
        }
    }

    /// Running workspaces count (workspaces with active sessions)
    var runningCount: Int {
        workspaces.filter { $0.hasActiveSession }.count
    }

    /// Has saved manager connection
    var hasSavedManager: Bool {
        managerStore.hasManager
    }

    /// Saved manager host
    var savedHost: String? {
        managerStore.lastHost
    }

    /// Check if connected to server (WebSocket is active)
    var isConnected: Bool {
        serverStatus.isConnected
    }

    /// Loading state for connecting
    @Published private(set) var isConnecting: Bool = false

    /// Whether initial connection check is complete
    /// Used to prevent "Not Connected" flash on appear
    @Published private(set) var hasCheckedConnection: Bool = false

    // MARK: - Initialization

    init(
        managerService: WorkspaceManagerService = .shared,
        managerStore: ManagerStore = .shared,
        webSocketService: WebSocketServiceProtocol = DependencyContainer.shared.webSocketService
    ) {
        self.managerService = managerService
        self.managerStore = managerStore
        self.webSocketService = webSocketService

        // Initialize currentWorkspaceId from the active workspace's remoteWorkspaceId
        // This ensures "Current" badge shows correctly when reopening the view
        self.currentWorkspaceId = WorkspaceStore.shared.activeWorkspace?.remoteWorkspaceId

        // Initialize serverStatus based on current WebSocket state
        if webSocketService.isConnected {
            self.serverStatus = .connected
            self.hasCheckedConnection = true
        } else if !managerStore.hasManager {
            self.serverStatus = .disconnected
            self.hasCheckedConnection = true
        } else {
            // Has saved manager but not connected - will try to connect
            self.serverStatus = .disconnected
            self.hasCheckedConnection = false
        }

        setupBindings()
    }

    private func setupBindings() {
        // Observe workspaces from service
        managerService.$workspaces
            .receive(on: DispatchQueue.main)
            .assign(to: &$workspaces)

        // Observe loading state
        managerService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        // Observe unreachable workspace IDs from service
        managerService.$unreachableWorkspaceIds
            .receive(on: DispatchQueue.main)
            .assign(to: &$unreachableWorkspaceIds)

        // Observe errors
        managerService.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.error = error
                    self?.showError = true
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Connection

    /// Connect to saved manager host
    /// In single-port architecture, this just saves the host and refreshes workspaces
    func connectToSavedManager() async {
        guard let host = managerStore.lastHost else {
            isConnecting = false
            hasCheckedConnection = true
            serverStatus = .disconnected
            showSetupSheet = true
            return
        }

        await connectWithRetry(to: host)
    }

    /// Connect to server with automatic retry
    /// Shows progress in serverStatus
    func connectWithRetry(to host: String) async {
        // Skip if already connected (prevents duplicate connections from AppState + WorkspaceManagerView race)
        if webSocketService.isConnected {
            AppLogger.log("[WorkspaceManager] Skipping connect - already connected")
            serverStatus = .connected
            isConnecting = false
            hasCheckedConnection = true
            await refreshWorkspaces()
            return
        }

        // Reset cancellation flag
        connectionCancelled = false
        currentRetryAttempt = 0

        isConnecting = true
        hasCheckedConnection = true  // Mark as checked immediately so UI doesn't show initial loading

        // Save the host early so UI can show it
        managerStore.saveHost(host)
        managerService.setCurrentHost(host)

        // Build connection info
        let connectionInfo = buildConnectionInfo(for: host)

        // Retry loop
        while currentRetryAttempt < maxRetryAttempts && !connectionCancelled {
            currentRetryAttempt += 1
            serverStatus = .connecting(attempt: currentRetryAttempt, maxAttempts: maxRetryAttempts)
            AppLogger.log("[WorkspaceManager] Connection attempt \(currentRetryAttempt)/\(maxRetryAttempts) to \(host)")

            do {
                try await webSocketService.connect(to: connectionInfo)
                // Success!
                serverStatus = .connected
                isConnecting = false
                currentRetryAttempt = 0
                await refreshWorkspaces()
                Haptics.success()
                AppLogger.log("[WorkspaceManager] Connected successfully to \(host)")
                return
            } catch {
                AppLogger.log("[WorkspaceManager] Connection attempt \(currentRetryAttempt) failed: \(error.localizedDescription)")

                // Check if cancelled
                if connectionCancelled {
                    AppLogger.log("[WorkspaceManager] Connection cancelled by user")
                    serverStatus = .disconnected
                    isConnecting = false
                    return
                }

                // If not last attempt, wait before retry
                if currentRetryAttempt < maxRetryAttempts {
                    // Sleep in small increments to check for cancellation
                    for _ in 0..<20 {  // 20 x 100ms = 2 seconds
                        if connectionCancelled { break }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                } else {
                    // All retries exhausted
                    serverStatus = .unreachable(lastError: error.localizedDescription)
                    self.error = .rpcError(code: -1, message: "Could not connect after \(maxRetryAttempts) attempts")
                    Haptics.error()
                }
            }
        }

        // Final check if cancelled during loop
        if connectionCancelled {
            serverStatus = .disconnected
        }
        isConnecting = false
    }

    /// Single connection attempt (for manual retry)
    func connect(to host: String) async {
        await connectWithRetry(to: host)
    }

    /// Retry connection to current saved host
    func retryConnection() async {
        guard let host = managerStore.lastHost else {
            showSetupSheet = true
            return
        }
        await connectWithRetry(to: host)
    }

    /// Cancel ongoing connection attempts
    func cancelConnection() {
        connectionCancelled = true
        currentRetryAttempt = 0
        isConnecting = false
        if !webSocketService.isConnected {
            serverStatus = .disconnected
        }
        AppLogger.log("[WorkspaceManager] Connection cancelled by user")
    }

    /// Build connection info for a host
    private func buildConnectionInfo(for host: String) -> ConnectionInfo {
        let isLocal = isLocalHost(host)
        let wsScheme = isLocal ? "ws" : "wss"
        let httpScheme = isLocal ? "http" : "https"

        let wsURL: URL
        let httpURL: URL

        if isLocal {
            wsURL = URL(string: "\(wsScheme)://\(host):\(ServerConnection.serverPort)/ws")!
            httpURL = URL(string: "\(httpScheme)://\(host):\(ServerConnection.serverPort)")!
        } else {
            wsURL = URL(string: "\(wsScheme)://\(host)/ws")!
            httpURL = URL(string: "\(httpScheme)://\(host)")!
        }

        return ConnectionInfo(
            webSocketURL: wsURL,
            httpURL: httpURL,
            sessionId: "",
            repoName: "Workspaces"
        )
    }

    /// Check if host is a local network address
    private func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" {
            return true
        }
        // IP address pattern
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        if let regex = try? NSRegularExpression(pattern: ipPattern),
           regex.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil {
            return true
        }
        // .local domains (Bonjour)
        if host.hasSuffix(".local") {
            return true
        }
        return false
    }

    // MARK: - Workspace Operations

    /// Refresh workspace list
    func refreshWorkspaces() async {
        do {
            _ = try await managerService.listWorkspaces()
        } catch let error as WorkspaceManagerError {
            self.error = error
            self.showError = true
        } catch {
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
        }
    }

    /// Start a session for a workspace
    func startWorkspace(_ workspace: RemoteWorkspace) async {
        // Debounce: Prevent multiple rapid taps
        guard loadingWorkspaceId == nil else {
            AppLogger.log("[WorkspaceManager] Ignoring start - already loading workspace: \(loadingWorkspaceId ?? "unknown")")
            return
        }

        loadingWorkspaceId = workspace.id
        currentOperation = .starting
        defer {
            loadingWorkspaceId = nil
            currentOperation = nil
        }

        do {
            // Start a new session for this workspace
            _ = try await managerService.startSession(workspaceId: workspace.id)
            Haptics.success()
        } catch let error as WorkspaceManagerError {
            self.error = error
            self.showError = true
            Haptics.error()
        } catch {
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
            Haptics.error()
        }
    }

    /// Stop all sessions for a workspace
    func stopWorkspace(_ workspace: RemoteWorkspace) async {
        // Debounce: Prevent multiple rapid taps
        guard loadingWorkspaceId == nil else {
            AppLogger.log("[WorkspaceManager] Ignoring stop - already loading workspace: \(loadingWorkspaceId ?? "unknown")")
            return
        }

        loadingWorkspaceId = workspace.id
        currentOperation = .stopping
        defer {
            loadingWorkspaceId = nil
            currentOperation = nil
        }

        do {
            // Stop all active sessions for this workspace
            for session in workspace.sessions where session.status == .running {
                try await managerService.stopSession(sessionId: session.id)
            }
            // Also clear unreachable status when stopped
            managerService.clearUnreachableStatus(workspace.id)
            Haptics.light()
        } catch let error as WorkspaceManagerError {
            self.error = error
            self.showError = true
            Haptics.error()
        } catch {
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
            Haptics.error()
        }
    }

    /// Connect to a workspace (start session if needed, then switch to it)
    func connectToWorkspace(_ workspace: RemoteWorkspace) async -> RemoteWorkspace? {
        AppLogger.log("[WorkspaceManagerVM] connectToWorkspace called for: \(workspace.name), hasActiveSession: \(workspace.hasActiveSession)")

        // Debounce: Prevent multiple rapid taps from creating multiple sessions
        guard loadingWorkspaceId == nil else {
            AppLogger.log("[WorkspaceManagerVM] Ignoring connect - already loading workspace: \(loadingWorkspaceId ?? "unknown")")
            return nil
        }

        loadingWorkspaceId = workspace.id
        currentOperation = .connecting
        defer {
            AppLogger.log("[WorkspaceManagerVM] connectToWorkspace defer - clearing loadingWorkspaceId")
            loadingWorkspaceId = nil
            currentOperation = nil
        }

        do {
            // If already has active session, just return directly - no need to refresh
            if workspace.hasActiveSession {
                AppLogger.log("[WorkspaceManagerVM] Workspace already has active session - returning directly")
                currentWorkspaceId = workspace.id
                Haptics.success()
                return workspace
            }

            // Start new session
            AppLogger.log("[WorkspaceManagerVM] Starting new session for workspace")
            currentOperation = .starting
            _ = try await managerService.startSession(workspaceId: workspace.id)
            AppLogger.log("[WorkspaceManagerVM] Session started")

            // Refresh to get updated workspace with sessions (only after starting)
            AppLogger.log("[WorkspaceManagerVM] Refreshing workspace list")
            _ = try await managerService.listWorkspaces()

            // Find the updated workspace
            guard let updatedWorkspace = workspaces.first(where: { $0.id == workspace.id }) else {
                AppLogger.log("[WorkspaceManagerVM] ERROR: Workspace not found after refresh")
                self.error = .workspaceFailed(workspace.id)
                self.showError = true
                Haptics.error()
                return nil
            }

            AppLogger.log("[WorkspaceManagerVM] SUCCESS: Returning workspace \(updatedWorkspace.name)")
            currentOperation = .connecting
            currentWorkspaceId = updatedWorkspace.id
            Haptics.success()
            return updatedWorkspace
        } catch let error as WorkspaceManagerError {
            AppLogger.log("[WorkspaceManagerVM] ERROR (WorkspaceManagerError): \(error)")
            self.error = error
            self.showError = true
            Haptics.error()
            // Refresh to get actual status from manager
            await refreshWorkspaces()
            return nil
        } catch {
            AppLogger.log("[WorkspaceManagerVM] ERROR (generic): \(error)")
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
            Haptics.error()
            // Refresh to get actual status from manager
            await refreshWorkspaces()
            return nil
        }
    }

    /// Called when connection to a workspace agent fails
    /// Marks workspace as unreachable and refreshes status from manager
    func handleConnectionFailure(workspaceId: String) async {
        if currentWorkspaceId == workspaceId {
            currentWorkspaceId = nil
        }
        // Mark as unreachable via service - shows "Unreachable" instead of "Active"
        managerService.markWorkspaceUnreachable(workspaceId)
        // Refresh workspace list to get actual status
        await refreshWorkspaces()
    }

    /// Check if a workspace is marked as unreachable
    func isWorkspaceUnreachable(_ workspace: RemoteWorkspace) -> Bool {
        managerService.isWorkspaceUnreachable(workspace.id)
    }

    /// Clear unreachable status for a workspace (called when successfully connected or restarted)
    func clearUnreachableStatus(_ workspaceId: String) {
        managerService.clearUnreachableStatus(workspaceId)
    }

    /// Check if a workspace is currently loading
    func isWorkspaceLoading(_ workspace: RemoteWorkspace) -> Bool {
        loadingWorkspaceId == workspace.id
    }

    /// Get the operation type for a loading workspace
    func operationFor(_ workspace: RemoteWorkspace) -> WorkspaceOperation? {
        guard loadingWorkspaceId == workspace.id else { return nil }
        return currentOperation
    }

    /// Start and connect to workspace (convenience)
    func startAndConnect(_ workspace: RemoteWorkspace) async -> RemoteWorkspace? {
        return await connectToWorkspace(workspace)
    }

    // MARK: - Manual Workspace Add

    /// Add a workspace manually by path
    /// Used as an alternative to Discovery Repos when user knows exact path
    func addWorkspaceManually(path: String) async throws {
        let workspace = try await managerService.addWorkspace(path: path)
        AppLogger.log("[WorkspaceManager] Manually added workspace: \(workspace.name)")
    }

    // MARK: - Remove Workspace

    /// Remove a workspace from the manager
    /// This removes the workspace from the list but does not delete files
    func removeWorkspace(_ workspace: RemoteWorkspace) async {
        // Debounce: Prevent multiple rapid taps
        guard loadingWorkspaceId == nil else {
            AppLogger.log("[WorkspaceManager] Ignoring remove - already loading workspace: \(loadingWorkspaceId ?? "unknown")")
            return
        }

        loadingWorkspaceId = workspace.id
        defer {
            loadingWorkspaceId = nil
            currentOperation = nil
        }

        do {
            // Stop all sessions first if any are running
            for session in workspace.sessions where session.status == .running {
                try await managerService.stopSession(sessionId: session.id)
            }

            // Remove workspace from manager
            try await managerService.removeWorkspace(workspace.id)

            // Clear from current if it was selected
            if currentWorkspaceId == workspace.id {
                currentWorkspaceId = nil
            }

            // Clear unreachable status
            managerService.clearUnreachableStatus(workspace.id)

            AppLogger.log("[WorkspaceManager] Removed workspace: \(workspace.name)")
            Haptics.success()
        } catch let error as WorkspaceManagerError {
            self.error = error
            self.showError = true
            Haptics.error()
        } catch {
            self.error = .rpcError(code: -1, message: error.localizedDescription)
            self.showError = true
            Haptics.error()
        }
    }

    // MARK: - Setup

    /// Clear saved manager and show setup
    func resetManager() {
        managerStore.clear()
        managerService.reset()
        showSetupSheet = true
    }

    /// Mark connection check as complete (used when connection failed previously)
    func markConnectionChecked() {
        hasCheckedConnection = true
    }
}

// MARK: - Preview Helpers

extension WorkspaceManagerViewModel {
    /// Create a preview instance with mock data
    static var preview: WorkspaceManagerViewModel {
        let vm = WorkspaceManagerViewModel()
        // Note: Can't easily mock the service, but previews can use real service
        return vm
    }
}
