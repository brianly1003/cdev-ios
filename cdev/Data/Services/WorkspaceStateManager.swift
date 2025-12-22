import Foundation

/// Tracks live connection and Claude states for all workspaces
/// Provides O(1) lookup for workspace states to power Quick Switcher status badges
@MainActor
final class WorkspaceStateManager: ObservableObject {
    // MARK: - Published State

    /// Map of workspace ID -> live state
    @Published private(set) var workspaceStates: [UUID: WorkspaceState] = [:]

    // MARK: - Singleton

    static let shared = WorkspaceStateManager()

    private init() {}

    // MARK: - Public Methods

    /// Update connection state for a workspace
    func updateConnection(workspaceId: UUID, isConnected: Bool) {
        if var state = workspaceStates[workspaceId] {
            state.isConnected = isConnected
            workspaceStates[workspaceId] = state
        } else {
            // Create new state entry
            guard let workspace = WorkspaceStore.shared.workspaces.first(where: { $0.id == workspaceId }) else {
                return
            }
            workspaceStates[workspaceId] = WorkspaceState(
                workspace: workspace,
                isConnected: isConnected,
                claudeState: .idle
            )
        }
    }

    /// Update Claude state for a workspace
    func updateClaudeState(workspaceId: UUID, claudeState: ClaudeState) {
        if var state = workspaceStates[workspaceId] {
            state.claudeState = claudeState
            workspaceStates[workspaceId] = state
        } else {
            // Create new state entry
            guard let workspace = WorkspaceStore.shared.workspaces.first(where: { $0.id == workspaceId }) else {
                return
            }
            workspaceStates[workspaceId] = WorkspaceState(
                workspace: workspace,
                isConnected: false,
                claudeState: claudeState
            )
        }
    }

    /// Update both connection and Claude state atomically
    func updateState(workspaceId: UUID, isConnected: Bool, claudeState: ClaudeState) {
        if var state = workspaceStates[workspaceId] {
            state.isConnected = isConnected
            state.claudeState = claudeState
            workspaceStates[workspaceId] = state
        } else {
            // Create new state entry
            guard let workspace = WorkspaceStore.shared.workspaces.first(where: { $0.id == workspaceId }) else {
                return
            }
            workspaceStates[workspaceId] = WorkspaceState(
                workspace: workspace,
                isConnected: isConnected,
                claudeState: claudeState
            )
        }
    }

    /// Get current state for a workspace
    func getState(workspaceId: UUID) -> WorkspaceState? {
        workspaceStates[workspaceId]
    }

    /// Refresh workspace models from WorkspaceStore
    /// Call this when workspaces are added/removed/updated
    func syncWithStore() {
        let allWorkspaces = WorkspaceStore.shared.workspaces

        // Update workspace models in existing states
        for (id, state) in workspaceStates {
            if let updatedWorkspace = allWorkspaces.first(where: { $0.id == id }) {
                workspaceStates[id] = WorkspaceState(
                    workspace: updatedWorkspace,
                    isConnected: state.isConnected,
                    claudeState: state.claudeState
                )
            }
        }

        // Remove states for deleted workspaces
        let validIds = Set(allWorkspaces.map { $0.id })
        workspaceStates = workspaceStates.filter { validIds.contains($0.key) }
    }

    /// Clear all workspace states (e.g., on logout)
    func clearAll() {
        workspaceStates.removeAll()
    }
}
