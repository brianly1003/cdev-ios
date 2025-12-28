import Foundation

/// Repository for session and settings storage
final class SessionRepository: SessionStorageProtocol, SettingsStorageProtocol {
    private let keychain: KeychainService
    private let defaults: UserDefaults

    init(
        keychain: KeychainService = KeychainService(),
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.defaults = defaults
    }

    // MARK: - SessionStorageProtocol

    func saveConnection(_ info: ConnectionInfo) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(info)
        try keychain.save(data, forKey: Constants.Keychain.serverURLKey)

        // Also save to UserDefaults for quick access
        defaults.set(info.webSocketURL.absoluteString, forKey: Constants.UserDefaults.lastConnectedServer)
    }

    func loadLastConnection() async throws -> ConnectionInfo? {
        guard let data = try keychain.load(forKey: Constants.Keychain.serverURLKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ConnectionInfo.self, from: data)
    }

    func clearConnection() async throws {
        try keychain.delete(forKey: Constants.Keychain.serverURLKey)
        defaults.removeObject(forKey: Constants.UserDefaults.lastConnectedServer)
    }

    func saveSessionToken(_ token: String) async throws {
        try keychain.save(token, forKey: Constants.Keychain.sessionTokenKey)
    }

    func loadSessionToken() async throws -> String? {
        try keychain.loadString(forKey: Constants.Keychain.sessionTokenKey)
    }

    func clearSessionToken() async throws {
        try keychain.delete(forKey: Constants.Keychain.sessionTokenKey)
    }

    // MARK: - SettingsStorageProtocol

    var autoReconnect: Bool {
        get {
            // Default to true if not set
            if defaults.object(forKey: Constants.UserDefaults.autoReconnect) == nil {
                return true
            }
            return defaults.bool(forKey: Constants.UserDefaults.autoReconnect)
        }
        set { defaults.set(newValue, forKey: Constants.UserDefaults.autoReconnect) }
    }

    var showTimestamps: Bool {
        get { defaults.object(forKey: Constants.UserDefaults.showTimestamps) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Constants.UserDefaults.showTimestamps) }
    }

    var hapticFeedback: Bool {
        get { defaults.object(forKey: Constants.UserDefaults.hapticFeedback) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Constants.UserDefaults.hapticFeedback) }
    }

    var theme: AppTheme {
        get {
            guard let value = defaults.string(forKey: Constants.UserDefaults.theme) else {
                return .system
            }
            return AppTheme(rawValue: value) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Constants.UserDefaults.theme) }
    }

    // MARK: - Session Selection

    /// Currently selected session ID (persisted across app launches)
    var selectedSessionId: String? {
        get { defaults.string(forKey: Constants.UserDefaults.selectedSessionId) }
        set {
            if let value = newValue, !value.isEmpty {
                defaults.set(value, forKey: Constants.UserDefaults.selectedSessionId)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.selectedSessionId)
            }
        }
    }

    /// Clear the selected session ID
    func clearSelectedSessionId() {
        defaults.removeObject(forKey: Constants.UserDefaults.selectedSessionId)
    }
}
