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
    /// Returns the saved workspace (with its final ID - may differ from input if URL matched existing)
    @discardableResult
    func saveWorkspace(_ workspace: Workspace) -> Workspace {
        var savedWorkspace = workspace

        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            // Update existing
            workspaces[index] = workspace
            savedWorkspace = workspace
        } else if let index = workspaces.firstIndex(where: {
            $0.webSocketURL == workspace.webSocketURL
        }) {
            // Update by URL match (same server, different session)
            // Keep the existing ID to avoid duplicate entries
            // Prefer new remoteWorkspaceId if provided, otherwise keep existing
            savedWorkspace = Workspace(
                id: workspaces[index].id,
                name: workspace.name,
                webSocketURL: workspace.webSocketURL,
                httpURL: workspace.httpURL,
                lastConnected: workspace.lastConnected,
                sessionId: workspace.sessionId,
                branch: workspace.branch,
                remoteWorkspaceId: workspace.remoteWorkspaceId ?? workspaces[index].remoteWorkspaceId
            )
            workspaces[index] = savedWorkspace
        } else {
            // Add new
            workspaces.append(workspace)
            savedWorkspace = workspace
        }

        // Trim to max
        if workspaces.count > maxRecentWorkspaces {
            let sorted = workspaces.sorted { $0.lastConnected > $1.lastConnected }
            workspaces = Array(sorted.prefix(maxRecentWorkspaces))
        }

        persistWorkspaces()
        return savedWorkspace
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
                branch: branch,
                remoteWorkspaceId: workspaces[index].remoteWorkspaceId  // Preserve remoteWorkspaceId
            )
            persistWorkspaces()
        }
    }

    /// Update workspace remote ID from server response
    /// Call this after workspace/list to sync server-side workspace IDs
    func updateRemoteWorkspaceId(_ remoteId: String, for workspaceId: UUID) {
        if let index = workspaces.firstIndex(where: { $0.id == workspaceId }) {
            workspaces[index] = Workspace(
                id: workspaces[index].id,
                name: workspaces[index].name,
                webSocketURL: workspaces[index].webSocketURL,
                httpURL: workspaces[index].httpURL,
                lastConnected: workspaces[index].lastConnected,
                sessionId: workspaces[index].sessionId,
                branch: workspaces[index].branch,
                remoteWorkspaceId: remoteId
            )
            persistWorkspaces()
            AppLogger.log("[WorkspaceStore] Updated remoteWorkspaceId for \(workspaces[index].name): \(remoteId)")
        }
    }

    /// Sync remote workspace IDs from server workspace list
    /// Matches by path and updates local workspace with server-side ID
    func syncRemoteWorkspaceIds(from remoteWorkspaces: [RemoteWorkspace]) {
        var updated = false
        for remote in remoteWorkspaces {
            // Find matching local workspace by path
            if let index = workspaces.firstIndex(where: { localWorkspace in
                // Match by path (removing trailing slashes for comparison)
                let localPath = localWorkspace.name  // Local workspace uses name as identifier
                let remotePath = remote.path
                let remoteName = remote.name

                // Match if name matches OR if this is the active workspace
                return localPath == remoteName ||
                       (activeWorkspaceId == localWorkspace.id && localWorkspace.remoteWorkspaceId == nil)
            }) {
                // Update with remote workspace ID if not already set or different
                if workspaces[index].remoteWorkspaceId != remote.id {
                    workspaces[index] = Workspace(
                        id: workspaces[index].id,
                        name: workspaces[index].name,
                        webSocketURL: workspaces[index].webSocketURL,
                        httpURL: workspaces[index].httpURL,
                        lastConnected: workspaces[index].lastConnected,
                        sessionId: workspaces[index].sessionId,
                        branch: workspaces[index].branch,
                        remoteWorkspaceId: remote.id
                    )
                    updated = true
                    AppLogger.log("[WorkspaceStore] Synced remoteWorkspaceId for \(workspaces[index].name): \(remote.id)")
                }
            }
        }

        if updated {
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
