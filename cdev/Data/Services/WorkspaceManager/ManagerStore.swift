import Foundation
import Combine

// MARK: - Manager Store

/// Persistent storage for workspace manager connections
/// Remembers the last connected manager for auto-reconnect
@MainActor
final class ManagerStore: ObservableObject {
    // MARK: - Published State

    /// Saved manager connection (single manager for simplicity)
    @Published private(set) var savedManager: ManagerConnection?

    /// Whether we have a saved manager
    var hasManager: Bool {
        savedManager != nil
    }

    // MARK: - Storage Keys

    private static let storageKey = "cdev.manager_connection"

    // MARK: - Singleton

    static let shared = ManagerStore()

    private init() {
        load()
    }

    // MARK: - CRUD Operations

    /// Save a manager connection
    func save(_ manager: ManagerConnection) {
        var updated = manager
        updated.lastConnected = Date()
        savedManager = updated
        persist()

        AppLogger.log("[ManagerStore] Saved manager: \(manager.displayName)")
    }

    /// Update last connected timestamp
    func updateLastConnected() {
        guard var manager = savedManager else { return }
        manager.lastConnected = Date()
        savedManager = manager
        persist()
    }

    /// Remove saved manager
    func clear() {
        savedManager = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)

        AppLogger.log("[ManagerStore] Cleared saved manager")
    }

    /// Create manager from host string (convenience)
    /// Token is stored in memory for the current connection, not persisted to disk
    func saveHost(_ host: String, name: String? = nil, token: String? = nil) {
        let manager = ManagerConnection(
            host: host,
            name: name,
            token: token
        )
        save(manager)
        if token != nil {
            AppLogger.log("[ManagerStore] Host saved with auth token")
        }
    }

    // MARK: - Persistence

    private func persist() {
        guard let manager = savedManager else {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
            return
        }

        do {
            let data = try JSONEncoder().encode(manager)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            AppLogger.error(error, context: "ManagerStore persist")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            return
        }

        do {
            savedManager = try JSONDecoder().decode(ManagerConnection.self, from: data)
            AppLogger.log("[ManagerStore] Loaded saved manager: \(savedManager?.displayName ?? "none")")
        } catch {
            AppLogger.error(error, context: "ManagerStore load")
        }
    }
}

// MARK: - Quick Access Extensions

extension ManagerStore {
    /// Last saved host for quick reconnect
    var lastHost: String? {
        savedManager?.host
    }

    /// Auth token for current connection (not persisted)
    var lastToken: String? {
        savedManager?.token
    }

    /// WebSocket URL for quick reconnect (defaults to local)
    var lastWebSocketURL: URL? {
        savedManager?.webSocketURL(isLocal: true)
    }

    /// HTTP URL for quick reconnect (defaults to local)
    var lastHTTPURL: URL? {
        savedManager?.httpURL(isLocal: true)
    }
}
