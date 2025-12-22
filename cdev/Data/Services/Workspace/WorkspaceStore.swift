import Foundation

// MARK: - Workspace Store

/// Manages saved workspaces with persistence
/// Enables quick switching between cdev-agent instances
@MainActor
final class WorkspaceStore: ObservableObject {
    // MARK: - Published State

    @Published private(set) var workspaces: [Workspace] = []
    @Published var activeWorkspaceId: UUID?

    // MARK: - Singleton

    static let shared = WorkspaceStore()

    // MARK: - Private

    private let userDefaultsKey = "cdev.saved_workspaces"
    private let maxRecentWorkspaces = 10

    // MARK: - Init

    private init() {
        loadWorkspaces()
    }

    // MARK: - Computed Properties

    /// Currently active workspace
    var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }
    }

    /// Workspaces sorted by last connected (most recent first)
    var recentWorkspaces: [Workspace] {
        workspaces.sorted { $0.lastConnected > $1.lastConnected }
    }

    /// Other workspaces (not active)
    var otherWorkspaces: [Workspace] {
        recentWorkspaces.filter { $0.id != activeWorkspaceId }
    }

    // MARK: - Public Methods

    /// Add or update a workspace
    func saveWorkspace(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            // Update existing
            workspaces[index] = workspace
        } else if let index = workspaces.firstIndex(where: {
            $0.webSocketURL == workspace.webSocketURL
        }) {
            // Update by URL match (same server, different session)
            var updated = workspace
            updated = Workspace(
                id: workspaces[index].id,
                name: workspace.name,
                webSocketURL: workspace.webSocketURL,
                httpURL: workspace.httpURL,
                lastConnected: workspace.lastConnected,
                sessionId: workspace.sessionId,
                branch: workspace.branch
            )
            workspaces[index] = updated
        } else {
            // Add new
            workspaces.append(workspace)
        }

        // Trim to max
        if workspaces.count > maxRecentWorkspaces {
            let sorted = workspaces.sorted { $0.lastConnected > $1.lastConnected }
            workspaces = Array(sorted.prefix(maxRecentWorkspaces))
        }

        persistWorkspaces()
    }

    /// Set active workspace and update last connected time
    func setActive(_ workspace: Workspace) {
        activeWorkspaceId = workspace.id

        // Update last connected time
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index].lastConnected = Date()
            persistWorkspaces()
        }
    }

    /// Set active by connection info (finds or creates workspace)
    func setActive(from connectionInfo: ConnectionInfo, repoName: String) {
        // Find existing or create new
        if let existing = workspaces.first(where: {
            $0.webSocketURL == connectionInfo.webSocketURL
        }) {
            // Update existing workspace
            var updated = existing
            updated.lastConnected = Date()
            updated.sessionId = connectionInfo.sessionId
            saveWorkspace(Workspace(
                id: existing.id,
                name: repoName.isEmpty ? existing.name : repoName,
                webSocketURL: connectionInfo.webSocketURL,
                httpURL: connectionInfo.httpURL,
                lastConnected: Date(),
                sessionId: connectionInfo.sessionId,
                branch: updated.branch
            ))
            activeWorkspaceId = existing.id
        } else {
            // Create new workspace
            let workspace = Workspace.from(connectionInfo: connectionInfo, repoName: repoName)
            saveWorkspace(workspace)
            activeWorkspaceId = workspace.id
        }
    }

    /// Clear active workspace (disconnect)
    func clearActive() {
        activeWorkspaceId = nil
    }

    /// Remove a workspace from saved list
    func removeWorkspace(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
        if activeWorkspaceId == workspace.id {
            activeWorkspaceId = nil
        }
        persistWorkspaces()
    }

    /// Clear all saved workspaces
    func clearAll() {
        workspaces = []
        activeWorkspaceId = nil
        persistWorkspaces()
    }

    /// Update workspace branch
    func updateBranch(_ branch: String?, for workspaceId: UUID) {
        if let index = workspaces.firstIndex(where: { $0.id == workspaceId }) {
            workspaces[index] = Workspace(
                id: workspaces[index].id,
                name: workspaces[index].name,
                webSocketURL: workspaces[index].webSocketURL,
                httpURL: workspaces[index].httpURL,
                lastConnected: workspaces[index].lastConnected,
                sessionId: workspaces[index].sessionId,
                branch: branch
            )
            persistWorkspaces()
        }
    }

    // MARK: - Persistence

    private func loadWorkspaces() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([Workspace].self, from: data) else {
            return
        }
        workspaces = decoded
    }

    private func persistWorkspaces() {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
