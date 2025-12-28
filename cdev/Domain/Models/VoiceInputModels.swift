import Foundation

// MARK: - Voice Input Provider

/// Available voice input providers
enum VoiceInputProvider: String, CaseIterable, Codable, Sendable {
    case appleSpeech = "apple_speech"
    case whisperAPI = "whisper_api"
    case whisperOnDevice = "whisper_local"

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple (Built-in)"
        case .whisperAPI: return "Whisper API"
        case .whisperOnDevice: return "Whisper (On-Device)"
        }
    }

    var shortName: String {
        switch self {
        case .appleSpeech: return "Apple"
        case .whisperAPI: return "Whisper"
        case .whisperOnDevice: return "Local"
        }
    }

    var requiresAPIKey: Bool {
        self == .whisperAPI
    }

    var supportsRealtime: Bool {
        self == .appleSpeech
    }

    var requiresNetwork: Bool {
        self == .whisperAPI
    }

    var vietnameseAccuracyRating: String {
        switch self {
        case .appleSpeech: return "Good"
        case .whisperAPI: return "Excellent"
        case .whisperOnDevice: return "Very Good"
        }
    }

    /// Whether this provider is currently available for use
    var isAvailable: Bool {
        switch self {
        case .appleSpeech: return true
        case .whisperAPI: return true
        case .whisperOnDevice: return false  // Future implementation
        }
    }
}

// MARK: - Transcription Result

/// Result from voice transcription
struct TranscriptionResult: Equatable, Sendable {
    /// Transcribed text
    let text: String

    /// Whether this is a final result or partial/interim
    let isFinal: Bool

    /// Confidence score (0.0 - 1.0), if available
    let confidence: Float?

    /// Language locale used for recognition
    let language: String

    /// Provider that generated this result
    let provider: VoiceInputProvider

    /// Duration of audio processed (seconds)
    let audioDuration: TimeInterval?

    /// Timestamp when transcription was generated
    let timestamp: Date

    init(
        text: String,
        isFinal: Bool = true,
        confidence: Float? = nil,
        language: String = "vi-VN",
        provider: VoiceInputProvider = .appleSpeech,
        audioDuration: TimeInterval? = nil,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.language = language
        self.provider = provider
        self.audioDuration = audioDuration
        self.timestamp = timestamp
    }

    /// Empty result for initial state
    static let empty = TranscriptionResult(text: "", isFinal: false)
}

// MARK: - Voice Input State

/// Voice input state machine
enum VoiceInputState: Equatable, Sendable {
    case idle
    case requestingPermission
    case preparing
    case recording(audioLevel: Float)
    case processing
    case completed(TranscriptionResult)
    case failed(VoiceInputError)

    var isActive: Bool {
        switch self {
        case .recording, .processing, .preparing, .requestingPermission:
            return true
        default:
            return false
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }

    var canStart: Bool {
        switch self {
        case .idle, .completed, .failed:
            return true
        default:
            return false
        }
    }

    /// Current audio level (0.0 if not recording)
    var audioLevel: Float {
        if case .recording(let level) = self {
            return level
        }
        return 0
    }

    /// Status text for UI display
    var statusText: String {
        switch self {
        case .idle:
            return "Tap to speak"
        case .requestingPermission:
            return "Requesting permission..."
        case .preparing:
            return "Preparing..."
        case .recording:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .completed:
            return "Done"
        case .failed(let error):
            return error.shortDescription
        }
    }
}

// MARK: - Voice Input Error

/// Voice input domain errors
enum VoiceInputError: LocalizedError, Equatable, Sendable {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case recognizerUnavailable(language: String)
    case languageNotDownloaded(language: String)
    case languageNotSupported(language: String, suggestion: String?)
    case onDeviceRecognitionUnavailable(language: String)
    case audioSessionFailed(message: String)
    case recordingFailed(message: String)
    case transcriptionFailed(message: String)
    case noSpeechDetected
    case apiKeyMissing
    case networkUnavailable
    case quotaExceeded
    case cancelled
    case timeout
    case unknown(message: String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access denied. Enable in Settings to use voice input."
        case .speechRecognitionPermissionDenied:
            return "Speech recognition denied. Enable in Settings to use voice input."
        case .recognizerUnavailable(let language):
            return "Speech recognition temporarily unavailable for \(language)."
        case .languageNotDownloaded(let language):
            return "\(language) speech model not downloaded. Download it in iOS Settings."
        case .languageNotSupported(let language, let suggestion):
            if let suggestion = suggestion {
                return "\(language) is not supported on this device. Try \(suggestion) instead."
            }
            return "\(language) is not supported on this device."
        case .onDeviceRecognitionUnavailable(let language):
            return "On-device recognition unavailable for \(language). Network required."
        case .audioSessionFailed(let message):
            return "Audio session error: \(message)"
        case .recordingFailed(let message):
            return "Recording failed: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .noSpeechDetected:
            return "No speech detected. Please try again."
        case .apiKeyMissing:
            return "Whisper API key not configured. Add it in Settings."
        case .networkUnavailable:
            return "Network connection required for Whisper API."
        case .quotaExceeded:
            return "API quota exceeded. Try again later."
        case .cancelled:
            return "Recording cancelled."
        case .timeout:
            return "Recording timed out. Please try again."
        case .unknown(let message):
            return "Voice input error: \(message)"
        }
    }

    /// Short description for compact UI display
    var shortDescription: String {
        switch self {
        case .microphonePermissionDenied:
            return "Mic denied"
        case .speechRecognitionPermissionDenied:
            return "Speech denied"
        case .recognizerUnavailable:
            return "Unavailable"
        case .languageNotDownloaded:
            return "Not downloaded"
        case .languageNotSupported:
            return "Not supported"
        case .onDeviceRecognitionUnavailable:
            return "Needs network"
        case .audioSessionFailed:
            return "Audio error"
        case .recordingFailed:
            return "Recording error"
        case .transcriptionFailed:
            return "Failed"
        case .noSpeechDetected:
            return "No speech"
        case .apiKeyMissing:
            return "No API key"
        case .networkUnavailable:
            return "No network"
        case .quotaExceeded:
            return "Quota exceeded"
        case .cancelled:
            return "Cancelled"
        case .timeout:
            return "Timeout"
        case .unknown:
            return "Error"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied, .speechRecognitionPermissionDenied:
            return "Open Settings and enable permissions for Cdev."
        case .recognizerUnavailable:
            return "Try again in a moment or switch to a different language."
        case .languageNotDownloaded:
            return "Go to iOS Settings > General > Keyboard > Dictation Languages and download the language."
        case .languageNotSupported:
            return "Select a different language from the language picker."
        case .onDeviceRecognitionUnavailable:
            return "Connect to the internet for server-based recognition, or try English (US) for offline use."
        case .noSpeechDetected:
            return "Speak clearly and try again."
        case .apiKeyMissing:
            return "Go to Settings > Voice Input and add your API key."
        case .networkUnavailable:
            return "Check your internet connection or switch to Apple Speech."
        case .timeout:
            return "Tap the microphone and speak within the time limit."
        default:
            return nil
        }
    }

    /// Whether this error can be recovered by retrying
    var isRetryable: Bool {
        switch self {
        case .recordingFailed, .transcriptionFailed, .noSpeechDetected,
             .networkUnavailable, .timeout, .unknown,
             .onDeviceRecognitionUnavailable:  // May work if network becomes available
            return true
        case .languageNotDownloaded, .languageNotSupported:
            return false  // Requires user action in Settings
        default:
            return false
        }
    }

    /// Whether this error requires opening Settings
    var requiresSettings: Bool {
        switch self {
        case .microphonePermissionDenied, .speechRecognitionPermissionDenied, .apiKeyMissing,
             .languageNotDownloaded:  // Need to download from iOS Settings
            return true
        default:
            return false
        }
    }

    // MARK: - Equatable

    static func == (lhs: VoiceInputError, rhs: VoiceInputError) -> Bool {
        switch (lhs, rhs) {
        case (.microphonePermissionDenied, .microphonePermissionDenied),
             (.speechRecognitionPermissionDenied, .speechRecognitionPermissionDenied),
             (.noSpeechDetected, .noSpeechDetected),
             (.apiKeyMissing, .apiKeyMissing),
             (.networkUnavailable, .networkUnavailable),
             (.quotaExceeded, .quotaExceeded),
             (.cancelled, .cancelled),
             (.timeout, .timeout):
            return true
        case (.recognizerUnavailable(let l), .recognizerUnavailable(let r)):
            return l == r
        case (.languageNotDownloaded(let l), .languageNotDownloaded(let r)):
            return l == r
        case (.languageNotSupported(let lLang, let lSuggestion), .languageNotSupported(let rLang, let rSuggestion)):
            return lLang == rLang && lSuggestion == rSuggestion
        case (.onDeviceRecognitionUnavailable(let l), .onDeviceRecognitionUnavailable(let r)):
            return l == r
        case (.audioSessionFailed(let l), .audioSessionFailed(let r)):
            return l == r
        case (.recordingFailed(let l), .recordingFailed(let r)):
            return l == r
        case (.transcriptionFailed(let l), .transcriptionFailed(let r)):
            return l == r
        case (.unknown(let l), .unknown(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - Supported Languages

/// Supported languages for voice input
struct VoiceInputLanguage: Identifiable, Equatable, Sendable {
    let id: String  // Locale identifier (e.g., "vi-VN")
    let name: String
    let nativeName: String
    let flag: String

    static let vietnamese = VoiceInputLanguage(
        id: "vi-VN",
        name: "Vietnamese",
        nativeName: "Tiếng Việt",
        flag: "🇻🇳"
    )

    static let english = VoiceInputLanguage(
        id: "en-US",
        name: "English",
        nativeName: "English",
        flag: "🇺🇸"
    )

    static let englishUK = VoiceInputLanguage(
        id: "en-GB",
        name: "English (UK)",
        nativeName: "English",
        flag: "🇬🇧"
    )

    static let chinese = VoiceInputLanguage(
        id: "zh-CN",
        name: "Chinese (Simplified)",
        nativeName: "中文",
        flag: "🇨🇳"
    )

    static let japanese = VoiceInputLanguage(
        id: "ja-JP",
        name: "Japanese",
        nativeName: "日本語",
        flag: "🇯🇵"
    )

    static let korean = VoiceInputLanguage(
        id: "ko-KR",
        name: "Korean",
        nativeName: "한국어",
        flag: "🇰🇷"
    )

    /// All supported languages (Vietnamese first as primary target)
    static let all: [VoiceInputLanguage] = [
        .vietnamese,
        .english,
        .englishUK,
        .chinese,
        .japanese,
        .korean
    ]

    /// Find language by locale ID
    static func find(byId id: String) -> VoiceInputLanguage? {
        all.first { $0.id == id }
    }
}
