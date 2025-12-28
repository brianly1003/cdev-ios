import Foundation
import Combine

/// ViewModel for voice input functionality
/// Manages voice recording state and transcription
@MainActor
final class VoiceInputViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: VoiceInputState = .idle
    @Published private(set) var currentTranscription: String = ""
    @Published private(set) var audioLevel: Float = 0
    @Published var showOverlay: Bool = false
    @Published var permissionError: VoiceInputError?

    /// Selected language - synced with settings store
    var selectedLanguage: VoiceInputLanguage {
        get { settings.selectedLanguage }
        set {
            settings.selectedLanguage = newValue
            objectWillChange.send()
        }
    }

    // MARK: - Computed Properties

    var isRecording: Bool {
        state.isRecording
    }

    var isProcessing: Bool {
        state.isProcessing
    }

    var isActive: Bool {
        state.isActive
    }

    var canStart: Bool {
        state.canStart
    }

    var availableLanguages: [VoiceInputLanguage] {
        voiceService.supportedLanguages
    }

    var statusText: String {
        state.statusText
    }

    var hasError: Bool {
        if case .failed = state { return true }
        return false
    }

    var currentError: VoiceInputError? {
        if case .failed(let error) = state {
            return error
        }
        return nil
    }

    // MARK: - Dependencies

    private let voiceService: VoiceInputServiceProtocol
    private let settings = VoiceInputSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()

    // Callback for when transcription is complete and should be sent
    var onTranscriptionComplete: ((String) -> Void)?

    // Countdown for silence detection (visual feedback)
    @Published private(set) var silenceCountdown: Double = 0

    // MARK: - Initialization

    init(voiceService: VoiceInputServiceProtocol = AppleSpeechService()) {
        self.voiceService = voiceService
        setupBindings()
    }

    private func setupBindings() {
        // Bind service state to view model
        voiceService.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.state = state
                if case .recording(let level) = state {
                    self?.audioLevel = level
                }
            }
            .store(in: &cancellables)

        // Bind transcription updates
        voiceService.transcriptionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.currentTranscription = result.text
            }
            .store(in: &cancellables)

        // Bind audio level updates
        voiceService.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)

        // Handle silence detection - auto-stop and optionally auto-send
        voiceService.silenceDetectedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSilenceDetected()
            }
            .store(in: &cancellables)
    }

    private func handleSilenceDetected() {
        guard isRecording, !currentTranscription.isEmpty else { return }

        AppLogger.log("[VoiceInput] Silence detected, auto-stopping")

        Task {
            do {
                let result = try await voiceService.stopRecording()
                currentTranscription = result.text
                Haptics.medium()

                // Auto-send if enabled
                if settings.autoSendOnSilence && !result.text.isEmpty {
                    AppLogger.log("[VoiceInput] Auto-sending transcription")
                    // Short delay for visual feedback
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    completeAndSend()
                }
            } catch {
                AppLogger.log("[VoiceInput] Error stopping after silence: \(error)")
            }
        }
    }

    // MARK: - Public Methods

    /// Toggle recording on/off
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Start voice recording
    func startRecording() {
        guard canStart else { return }

        showOverlay = true
        currentTranscription = ""
        permissionError = nil

        Task {
            do {
                // Check and request permissions if needed
                let permissions = await voiceService.checkPermissions()

                if permissions.needsRequest {
                    _ = try await voiceService.requestPermissions()
                } else if permissions.isDenied {
                    if permissions.microphone == .denied {
                        throw VoiceInputError.microphonePermissionDenied
                    } else {
                        throw VoiceInputError.speechRecognitionPermissionDenied
                    }
                }

                // Start recording
                try await voiceService.startRecording(language: selectedLanguage)
                Haptics.light()
            } catch let error as VoiceInputError {
                handleError(error)
            } catch {
                handleError(.recordingFailed(message: error.localizedDescription))
            }
        }
    }

    /// Stop recording and get transcription
    /// Does NOT auto-dismiss - user must tap Done to confirm
    func stopRecording() {
        guard isRecording else { return }

        Task {
            do {
                let result = try await voiceService.stopRecording()
                Haptics.medium()

                // Update current transcription with final result
                // User will tap "Done" to confirm and send
                currentTranscription = result.text

            } catch let error as VoiceInputError {
                handleError(error)
            } catch {
                handleError(.transcriptionFailed(message: error.localizedDescription))
            }
        }
    }

    /// Complete voice input and send to chat
    /// Called when user taps "Done" or "Send"
    func completeAndSend() {
        let text = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onTranscriptionComplete?(text)
        }
        showOverlay = false
        currentTranscription = ""
        Haptics.medium()
    }

    /// Cancel recording without result
    func cancelRecording() {
        voiceService.cancelRecording()
        currentTranscription = ""
        showOverlay = false
        Haptics.light()
    }

    /// Apply current transcription (used when user confirms in overlay)
    func applyTranscription() {
        let text = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onTranscriptionComplete?(text)
        }
        showOverlay = false
    }

    /// Dismiss overlay (cancel or after completion)
    func dismissOverlay() {
        if isRecording {
            cancelRecording()
        } else {
            showOverlay = false
        }
    }

    /// Clear any error state
    func clearError() {
        if case .failed = state {
            state = .idle
        }
        permissionError = nil
    }

    /// Check if voice input is available
    func checkAvailability() async -> Bool {
        await voiceService.isAvailable()
    }

    // MARK: - Private Methods

    private func handleError(_ error: VoiceInputError) {
        AppLogger.log("[VoiceInput] Error: \(error.localizedDescription)")

        if error.requiresSettings {
            permissionError = error
        }

        state = .failed(error)
        Haptics.error()

        // Auto-dismiss overlay after error (unless it's a permission issue)
        if !error.requiresSettings {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
                if case .failed = state {
                    showOverlay = false
                    state = .idle
                }
            }
        }
    }
}
