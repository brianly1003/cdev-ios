import Foundation
import Combine

/// Persistent settings for voice input feature
/// Stores user preferences in UserDefaults
final class VoiceInputSettingsStore: ObservableObject {

    // MARK: - Singleton

    static let shared = VoiceInputSettingsStore()

    // MARK: - Published Properties

    /// Whether voice input is enabled (beta feature flag)
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    /// Selected language for voice input
    @Published var selectedLanguage: VoiceInputLanguage {
        didSet {
            defaults.set(selectedLanguage.id, forKey: Keys.selectedLanguage)
        }
    }

    /// Selected provider (Apple Speech, Whisper API, etc.)
    @Published var selectedProvider: VoiceInputProvider {
        didSet {
            defaults.set(selectedProvider.rawValue, forKey: Keys.selectedProvider)
        }
    }

    /// Whether to show waveform visualization
    @Published var showWaveform: Bool {
        didSet {
            defaults.set(showWaveform, forKey: Keys.showWaveform)
        }
    }

    /// Whether to use haptic feedback
    @Published var hapticFeedback: Bool {
        didSet {
            defaults.set(hapticFeedback, forKey: Keys.hapticFeedback)
        }
    }

    /// Whether to auto-punctuate (iOS 16+)
    @Published var autoPunctuation: Bool {
        didSet {
            defaults.set(autoPunctuation, forKey: Keys.autoPunctuation)
        }
    }

    /// Whether to auto-send after silence detection
    /// When enabled: speak → pause → auto-send to Claude
    @Published var autoSendOnSilence: Bool {
        didSet {
            defaults.set(autoSendOnSilence, forKey: Keys.autoSendOnSilence)
        }
    }

    /// Whisper API key (stored separately in Keychain for security)
    /// This is just a flag indicating if a key is set
    @Published var hasWhisperAPIKey: Bool = false

    // MARK: - Private Properties

    private let defaults = UserDefaults.standard
    private let keychain = KeychainService()
    private let whisperAPIKeyName = "whisper_api_key"

    private enum Keys {
        static let isEnabled = "voiceInput.isEnabled"
        static let selectedLanguage = "voiceInput.selectedLanguage"
        static let selectedProvider = "voiceInput.selectedProvider"
        static let showWaveform = "voiceInput.showWaveform"
        static let hapticFeedback = "voiceInput.hapticFeedback"
        static let autoPunctuation = "voiceInput.autoPunctuation"
        static let autoSendOnSilence = "voiceInput.autoSendOnSilence"
    }

    // MARK: - Initialization

    private init() {
        // Load settings from UserDefaults with defaults

        // Voice input is enabled by default for testing (beta feature)
        // Users can disable it in settings if needed
        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true

        // Default language is Vietnamese
        if let languageId = defaults.string(forKey: Keys.selectedLanguage),
           let language = VoiceInputLanguage.find(byId: languageId) {
            self.selectedLanguage = language
        } else {
            self.selectedLanguage = .vietnamese
        }

        // Default provider is Apple Speech
        if let providerRaw = defaults.string(forKey: Keys.selectedProvider),
           let provider = VoiceInputProvider(rawValue: providerRaw) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .appleSpeech
        }

        // UI preferences - defaults to enabled
        self.showWaveform = defaults.object(forKey: Keys.showWaveform) as? Bool ?? true
        self.hapticFeedback = defaults.object(forKey: Keys.hapticFeedback) as? Bool ?? true
        self.autoPunctuation = defaults.object(forKey: Keys.autoPunctuation) as? Bool ?? true

        // Auto-send on silence - enabled by default for fast workflow
        self.autoSendOnSilence = defaults.object(forKey: Keys.autoSendOnSilence) as? Bool ?? true

        // Check if Whisper API key exists in Keychain
        checkWhisperAPIKey()
    }

    // MARK: - Public Methods

    /// Reset all voice input settings to defaults
    func resetToDefaults() {
        isEnabled = false
        selectedLanguage = .vietnamese
        selectedProvider = .appleSpeech
        showWaveform = true
        hapticFeedback = true
        autoPunctuation = true
        autoSendOnSilence = true
    }

    /// Save Whisper API key to Keychain
    func saveWhisperAPIKey(_ key: String) {
        do {
            if key.isEmpty {
                try keychain.delete(forKey: whisperAPIKeyName)
                hasWhisperAPIKey = false
            } else {
                try keychain.save(key, forKey: whisperAPIKeyName)
                hasWhisperAPIKey = true
            }
            AppLogger.log("[VoiceInputSettings] Whisper API key updated")
        } catch {
            AppLogger.log("[VoiceInputSettings] Failed to save Whisper API key: \(error)")
        }
    }

    /// Get Whisper API key from Keychain
    func getWhisperAPIKey() -> String? {
        do {
            return try keychain.loadString(forKey: whisperAPIKeyName)
        } catch {
            AppLogger.log("[VoiceInputSettings] Failed to load Whisper API key: \(error)")
            return nil
        }
    }

    /// Delete Whisper API key from Keychain
    func deleteWhisperAPIKey() {
        do {
            try keychain.delete(forKey: whisperAPIKeyName)
            hasWhisperAPIKey = false
            AppLogger.log("[VoiceInputSettings] Whisper API key deleted")
        } catch {
            AppLogger.log("[VoiceInputSettings] Failed to delete Whisper API key: \(error)")
        }
    }

    // MARK: - Private Methods

    private func checkWhisperAPIKey() {
        hasWhisperAPIKey = getWhisperAPIKey() != nil
    }
}

// MARK: - Beta Feature Check

extension VoiceInputSettingsStore {
    /// Whether voice input feature is available and enabled
    /// This is the main check to use before showing voice UI
    var isVoiceInputAvailable: Bool {
        isEnabled && selectedProvider.isAvailable
    }

    /// Description of why voice input is unavailable (for settings UI)
    var unavailabilityReason: String? {
        if !isEnabled {
            return "Voice input is disabled. Enable it in Settings."
        }
        if !selectedProvider.isAvailable {
            return "\(selectedProvider.displayName) is not available on this device."
        }
        if selectedProvider == .whisperAPI && !hasWhisperAPIKey {
            return "Whisper API requires an API key. Add it in Settings."
        }
        return nil
    }
}
