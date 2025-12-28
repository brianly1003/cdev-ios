import Foundation
import Combine

/// Protocol for voice input providers
/// Implementations include AppleSpeechService, WhisperAPIService, etc.
protocol VoiceInputServiceProtocol: AnyObject {

    // MARK: - State

    /// Current state of voice input
    var state: VoiceInputState { get }

    /// Publisher for state changes
    var statePublisher: AnyPublisher<VoiceInputState, Never> { get }

    /// Publisher for real-time transcription (partial results)
    var transcriptionPublisher: AnyPublisher<TranscriptionResult, Never> { get }

    /// Publisher for audio level (0.0 - 1.0, updates during recording)
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }

    /// Publisher for silence detection (fires when user stops speaking)
    var silenceDetectedPublisher: AnyPublisher<Void, Never> { get }

    // MARK: - Configuration

    /// The provider type for this service
    var provider: VoiceInputProvider { get }

    /// Supported language locales
    var supportedLanguages: [VoiceInputLanguage] { get }

    /// Currently selected language
    var selectedLanguage: VoiceInputLanguage { get set }

    // MARK: - Availability

    /// Check if the provider is available on this device
    func isAvailable() async -> Bool

    /// Check current permission status without prompting
    func checkPermissions() async -> VoiceInputPermissionStatus

    /// Request necessary permissions (microphone, speech recognition)
    /// Returns true if all permissions granted
    func requestPermissions() async throws -> Bool

    // MARK: - Recording

    /// Start recording and transcription
    /// - Parameter language: Target language locale (e.g., "vi-VN")
    /// - Throws: VoiceInputError if recording cannot start
    func startRecording(language: VoiceInputLanguage) async throws

    /// Stop recording and get final transcription
    /// - Returns: Final transcription result
    /// - Throws: VoiceInputError if transcription fails
    func stopRecording() async throws -> TranscriptionResult

    /// Cancel recording without result
    func cancelRecording()
}

// MARK: - Permission Status

/// Permission status for voice input
struct VoiceInputPermissionStatus: Equatable, Sendable {
    let microphone: PermissionState
    let speechRecognition: PermissionState

    enum PermissionState: Equatable, Sendable {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    var isFullyAuthorized: Bool {
        microphone == .authorized && speechRecognition == .authorized
    }

    var needsRequest: Bool {
        microphone == .notDetermined || speechRecognition == .notDetermined
    }

    var isDenied: Bool {
        microphone == .denied || speechRecognition == .denied
    }

    static let unknown = VoiceInputPermissionStatus(
        microphone: .notDetermined,
        speechRecognition: .notDetermined
    )
}

// MARK: - Default Implementations

extension VoiceInputServiceProtocol {
    /// Default language is Vietnamese
    var defaultLanguage: VoiceInputLanguage {
        .vietnamese
    }

    /// Whether the service supports real-time partial results
    var supportsRealtimeTranscription: Bool {
        provider.supportsRealtime
    }
}
