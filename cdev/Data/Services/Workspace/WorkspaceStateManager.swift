import Foundation

/// Tracks live connection and Claude states for all workspaces
/// Provides O(1) lookup for workspace states to power Quick Switcher status badges
/// Features:
/// - 30s state caching to reduce API calls
/// - Connection pool (5 most recent workspaces kept warm)
/// - Automatic cache invalidation on state changes
@MainActor
final class WorkspaceStateManager: ObservableObject {
    // MARK: - Published State

    /// Map of workspace ID -> live state
    @Published private(set) var workspaceStates: [UUID: WorkspaceState] = [:]

    // MARK: - Private State

    /// Cache timestamps for workspace states (30s TTL)
    private var stateCacheTimestamps: [UUID: Date] = [:]

    /// Connection pool: Most recent 5 workspace IDs kept warm
    private var connectionPool: [UUID] = []

    /// Maximum connections to keep in pool
    private let maxPoolSize = 5

    /// Cache timeout: 30 seconds
    private let cacheTimeout: TimeInterval = 30

    // MARK: - Singleton

    static let shared = WorkspaceStateManager()

    private init() {
        startCacheCleanupTimer()
    }

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

        // Update cache timestamp and connection pool
        refreshCache(for: workspaceId)
        if isConnected {
            addToConnectionPool(workspaceId)
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

        // Update cache timestamp
        refreshCache(for: workspaceId)
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

        // Update cache timestamp and connection pool
        refreshCache(for: workspaceId)
        if isConnected {
            addToConnectionPool(workspaceId)
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
        stateCacheTimestamps.removeAll()
        connectionPool.removeAll()
    }

    // MARK: - Cache Management

    /// Check if cached state is still valid
    func isCacheValid(for workspaceId: UUID) -> Bool {
        guard let timestamp = stateCacheTimestamps[workspaceId] else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < cacheTimeout
    }

    /// Refresh cache timestamp for a workspace
    private func refreshCache(for workspaceId: UUID) {
        stateCacheTimestamps[workspaceId] = Date()
    }

    /// Invalidate cache for a workspace
    func invalidateCache(for workspaceId: UUID) {
        stateCacheTimestamps.removeValue(forKey: workspaceId)
    }

    /// Start periodic cache cleanup timer (every 60s)
    private func startCacheCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupStaleCache()
            }
        }
    }

    /// Remove expired cache entries
    private func cleanupStaleCache() {
        let now = Date()
        stateCacheTimestamps = stateCacheTimestamps.filter { _, timestamp in
            now.timeIntervalSince(timestamp) < cacheTimeout
        }
    }

    // MARK: - Connection Pool

    /// Add workspace to connection pool (LRU eviction)
    private func addToConnectionPool(_ workspaceId: UUID) {
        // Remove if already in pool
        connectionPool.removeAll { $0 == workspaceId }

        // Add to front (most recent)
        connectionPool.insert(workspaceId, at: 0)

        // Trim to max size (evict least recently used)
        if connectionPool.count > maxPoolSize {
            connectionPool = Array(connectionPool.prefix(maxPoolSize))
        }
    }

    /// Get workspaces in connection pool (most recent first)
    var pooledWorkspaces: [UUID] {
        connectionPool
    }

    /// Check if workspace is in connection pool
    func isInPool(_ workspaceId: UUID) -> Bool {
        connectionPool.contains(workspaceId)
    }
}
