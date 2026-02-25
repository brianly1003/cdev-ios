import Foundation
import Speech
import AVFoundation
import Combine

/// Apple Speech Framework implementation of voice input
/// Optimized for Vietnamese language recognition with on-device processing
final class AppleSpeechService: NSObject, VoiceInputServiceProtocol {

    // MARK: - Properties

    let provider: VoiceInputProvider = .appleSpeech

    var supportedLanguages: [VoiceInputLanguage] {
        VoiceInputLanguage.all.filter { language in
            SFSpeechRecognizer(locale: Locale(identifier: language.id)) != nil
        }
    }

    var selectedLanguage: VoiceInputLanguage = .vietnamese

    private(set) var state: VoiceInputState = .idle {
        didSet {
            stateSubject.send(state)
        }
    }

    var statePublisher: AnyPublisher<VoiceInputState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var transcriptionPublisher: AnyPublisher<TranscriptionResult, Never> {
        transcriptionSubject.eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    var silenceDetectedPublisher: AnyPublisher<Void, Never> {
        silenceDetectedSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let stateSubject = CurrentValueSubject<VoiceInputState, Never>(.idle)
    private let transcriptionSubject = PassthroughSubject<TranscriptionResult, Never>()
    private let audioLevelSubject = PassthroughSubject<Float, Never>()
    private let silenceDetectedSubject = PassthroughSubject<Void, Never>()

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var audioLevelTimer: Timer?
    private var recordingStartTime: Date?
    private var lastTranscription: String = ""

    // Silence detection
    private var lastSpeechTime: Date?
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5  // 1.5 seconds of silence to auto-stop
    private var hasSpeechStarted: Bool = false

    // Configuration
    private let maxRecordingDuration: TimeInterval = 60  // 1 minute max
    private var recordingTimeoutTask: Task<Void, Never>?
    private var recordingTimeoutDeadline: Date?
    private var isAutoStopSuspended = false
    private var suspendedSilenceState: (lastSpeechTime: Date?, hasSpeechStarted: Bool)?
    private var suspendedTimeoutRemaining: TimeInterval?

    // MARK: - Initialization

    override init() {
        super.init()
        setupRecognizer(for: selectedLanguage)
    }

    private func setupRecognizer(for language: VoiceInputLanguage) {
        let locale = Locale(identifier: language.id)
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        speechRecognizer?.delegate = self
    }

    /// Check if a language is supported and what features are available
    private func checkLanguageSupport(for language: VoiceInputLanguage) -> LanguageSupportResult {
        let locale = Locale(identifier: language.id)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            // Language not supported at all - find a suggestion
            let suggestion = findAlternativeLanguage(for: language)
            return .notSupported(suggestion: suggestion)
        }

        if !recognizer.isAvailable {
            // Recognizer exists but temporarily unavailable
            return .temporarilyUnavailable
        }

        let supportsOnDevice = recognizer.supportsOnDeviceRecognition
        return .supported(onDeviceAvailable: supportsOnDevice)
    }

    /// Find an alternative language to suggest when one isn't supported
    private func findAlternativeLanguage(for language: VoiceInputLanguage) -> String? {
        // Map of language families to fallback suggestions
        let suggestions: [String: String] = [
            "vi": "Vietnamese may need to be downloaded in iOS Settings",
            "zh": "Try Chinese (Simplified) - zh-CN",
            "ja": "Try Japanese - ja-JP",
            "ko": "Try Korean - ko-KR",
            "en": "Try English (US) - en-US"
        ]

        // Extract language code from locale ID (e.g., "vi" from "vi-VN")
        let languageCode = language.id.components(separatedBy: "-").first ?? language.id
        return suggestions[languageCode]
    }

    private enum LanguageSupportResult {
        case supported(onDeviceAvailable: Bool)
        case temporarilyUnavailable
        case notSupported(suggestion: String?)
    }

    // MARK: - VoiceInputServiceProtocol

    func isAvailable() async -> Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable
    }

    func checkPermissions() async -> VoiceInputPermissionStatus {
        let micStatus = await checkMicrophonePermission()
        let speechStatus = await checkSpeechPermission()

        return VoiceInputPermissionStatus(
            microphone: micStatus,
            speechRecognition: speechStatus
        )
    }

    func requestPermissions() async throws -> Bool {
        // Request microphone permission first
        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            throw VoiceInputError.microphonePermissionDenied
        }

        // Then request speech recognition permission
        let speechGranted = await requestSpeechPermission()
        guard speechGranted else {
            throw VoiceInputError.speechRecognitionPermissionDenied
        }

        return true
    }

    func startRecording(language: VoiceInputLanguage) async throws {
        // Update recognizer if language changed
        if language.id != selectedLanguage.id {
            selectedLanguage = language
            setupRecognizer(for: language)
        }

        // Check language support with detailed error handling
        let supportResult = checkLanguageSupport(for: language)

        switch supportResult {
        case .notSupported(let suggestion):
            // Language not supported on this device
            let error = VoiceInputError.languageNotSupported(language: language.name, suggestion: suggestion)
            state = .failed(error)
            throw error

        case .temporarilyUnavailable:
            // Recognizer exists but temporarily unavailable (might need download)
            let error = VoiceInputError.languageNotDownloaded(language: language.name)
            state = .failed(error)
            throw error

        case .supported(let onDeviceAvailable):
            // Language is supported - log on-device availability
            if !onDeviceAvailable {
                AppLogger.log("[AppleSpeech] \(language.name) requires network (no on-device model)")
            }
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw VoiceInputError.recognizerUnavailable(language: language.name)
        }

        // Check permissions
        let permissions = await checkPermissions()
        if permissions.microphone != .authorized {
            throw VoiceInputError.microphonePermissionDenied
        }
        if permissions.speechRecognition != .authorized {
            throw VoiceInputError.speechRecognitionPermissionDenied
        }

        // Stop any existing recording
        await stopAudioEngine()
        stopSilenceDetection()
        cancelRecordingTimeout()
        isAutoStopSuspended = false
        suspendedSilenceState = nil
        suspendedTimeoutRemaining = nil

        state = .preparing

        do {
            try await startAudioSession()
            try await startRecognition(with: recognizer)
            startAudioLevelMonitoring()
            startRecordingTimeout()
            startSilenceDetection()

            recordingStartTime = Date()
            lastTranscription = ""
            state = .recording(audioLevel: 0)

            AppLogger.log("[AppleSpeech] Recording started for \(language.name)")
        } catch {
            state = .failed(.recordingFailed(message: error.localizedDescription))
            throw VoiceInputError.recordingFailed(message: error.localizedDescription)
        }
    }

    func stopRecording() async throws -> TranscriptionResult {
        guard case .recording = state else {
            throw VoiceInputError.recordingFailed(message: "Not recording")
        }

        state = .processing

        // Stop audio engine and recognition
        await stopAudioEngine()
        stopAudioLevelMonitoring()
        stopSilenceDetection()
        cancelRecordingTimeout()
        isAutoStopSuspended = false
        suspendedSilenceState = nil
        suspendedTimeoutRemaining = nil

        // Calculate duration
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) }

        // Wait a moment for final results
        try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms

        let finalText = lastTranscription.trimmingCharacters(in: .whitespacesAndNewlines)

        if finalText.isEmpty {
            let error = VoiceInputError.noSpeechDetected
            state = .failed(error)
            throw error
        }

        let result = TranscriptionResult(
            text: finalText,
            isFinal: true,
            confidence: nil,  // Apple doesn't provide confidence for final results
            language: selectedLanguage.id,
            provider: .appleSpeech,
            audioDuration: duration
        )

        state = .completed(result)
        AppLogger.log("[AppleSpeech] Recording stopped, text: \(finalText.prefix(50))...")

        return result
    }

    func cancelRecording() {
        Task {
            await stopAudioEngine()
        }
        stopAudioLevelMonitoring()
        stopSilenceDetection()
        cancelRecordingTimeout()
        isAutoStopSuspended = false
        suspendedSilenceState = nil
        suspendedTimeoutRemaining = nil
        lastTranscription = ""
        state = .idle
        AppLogger.log("[AppleSpeech] Recording cancelled")
    }

    func setAutoStopSuspended(_ isSuspended: Bool) {
        guard case .recording = state else { return }
        guard isAutoStopSuspended != isSuspended else { return }

        isAutoStopSuspended = isSuspended

        if isSuspended {
            suspendedSilenceState = (
                lastSpeechTime: lastSpeechTime,
                hasSpeechStarted: hasSpeechStarted
            )

            silenceTimer?.invalidate()
            silenceTimer = nil

            if let deadline = recordingTimeoutDeadline {
                suspendedTimeoutRemaining = max(0, deadline.timeIntervalSinceNow)
            } else {
                suspendedTimeoutRemaining = nil
            }
            cancelRecordingTimeout()

            AppLogger.log("[AppleSpeech] Auto-stop suspended")
            return
        }

        if let silenceState = suspendedSilenceState {
            lastSpeechTime = silenceState.lastSpeechTime
            hasSpeechStarted = silenceState.hasSpeechStarted
        } else {
            lastSpeechTime = Date()
            hasSpeechStarted = false
        }
        suspendedSilenceState = nil
        resetSilenceTimer()

        if let remaining = suspendedTimeoutRemaining {
            if remaining > 0 {
                startRecordingTimeout(duration: remaining)
            } else {
                Task { [weak self] in
                    guard let self = self else { return }
                    if case .recording = self.state {
                        AppLogger.log("[AppleSpeech] Recording timeout reached")
                        _ = try? await self.stopRecording()
                    }
                }
            }
            suspendedTimeoutRemaining = nil
        } else {
            startRecordingTimeout()
        }

        AppLogger.log("[AppleSpeech] Auto-stop resumed")
    }

    // MARK: - Private Methods - Permissions

    private func checkMicrophonePermission() async -> VoiceInputPermissionStatus.PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .granted:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    private func checkSpeechPermission() async -> VoiceInputPermissionStatus.PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Private Methods - Audio Session

    private func startAudioSession() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func stopAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLogger.log("[AppleSpeech] Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - Private Methods - Recognition

    private func startRecognition(with recognizer: SFSpeechRecognizer) async throws {
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let request = recognitionRequest else {
            throw VoiceInputError.recordingFailed(message: "Could not create recognition request")
        }

        // Configure for real-time results
        request.shouldReportPartialResults = true

        // Use on-device recognition for privacy and speed (iOS 13+)
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

        // Enable automatic punctuation (iOS 16+)
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        // Get audio input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap on audio input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognitionResult(result: result, error: error)
        }
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            // Check if it's just a cancellation
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                // Recognition was cancelled, ignore
                return
            }

            AppLogger.log("[AppleSpeech] Recognition error: \(error.localizedDescription)")
            if case .recording = state {
                state = .failed(.transcriptionFailed(message: error.localizedDescription))
            }
            return
        }

        guard let result = result else { return }

        let transcription = result.bestTranscription.formattedString

        // Detect new speech - reset silence timer
        if transcription != lastTranscription && !transcription.isEmpty {
            lastSpeechTime = Date()
            hasSpeechStarted = true
            resetSilenceTimer()
        }

        lastTranscription = transcription

        // Emit partial result
        let partialResult = TranscriptionResult(
            text: transcription,
            isFinal: result.isFinal,
            confidence: result.bestTranscription.segments.last?.confidence,
            language: selectedLanguage.id,
            provider: .appleSpeech,
            audioDuration: nil
        )

        transcriptionSubject.send(partialResult)

        if result.isFinal {
            AppLogger.log("[AppleSpeech] Final result: \(transcription.prefix(50))...")
        }
    }

    // MARK: - Silence Detection

    private func startSilenceDetection() {
        lastSpeechTime = Date()
        hasSpeechStarted = false
        resetSilenceTimer()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkForSilence()
        }
    }

    private func stopSilenceDetection() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasSpeechStarted = false
    }

    private func checkForSilence() {
        guard hasSpeechStarted,
              let lastSpeech = lastSpeechTime,
              case .recording = state else { return }

        let silenceDuration = Date().timeIntervalSince(lastSpeech)

        if silenceDuration >= silenceThreshold {
            AppLogger.log("[AppleSpeech] Silence detected after \(silenceDuration)s")
            stopSilenceDetection()
            silenceDetectedSubject.send()
        }
    }

    private func stopAudioEngine() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        stopAudioSession()
    }

    // MARK: - Private Methods - Audio Level Monitoring

    private func startAudioLevelMonitoring() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }

    private func updateAudioLevel() {
        guard audioEngine.isRunning else { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Get average power level
        // Note: This is a simplified approach. For more accurate levels,
        // you would process the actual audio buffers.
        let level = calculateAudioLevel(from: inputNode, format: format)

        audioLevelSubject.send(level)

        if case .recording = state {
            state = .recording(audioLevel: level)
        }
    }

    private func calculateAudioLevel(from inputNode: AVAudioInputNode, format: AVAudioFormat) -> Float {
        // Simplified audio level calculation
        // In a production app, you'd want to analyze the actual buffer samples
        // For now, we use a random variation to simulate audio levels
        // The actual implementation should process audio buffers

        // Get the input node's last render time to add some variation
        if let lastRenderTime = inputNode.lastRenderTime,
           lastRenderTime.isSampleTimeValid {
            let variation = Float(sin(Double(lastRenderTime.sampleTime) / 1000.0))
            let baseLevel: Float = 0.3
            let level = max(0, min(1, baseLevel + variation * 0.3))
            return level
        }

        return 0.3
    }

    // MARK: - Private Methods - Timeout

    private func startRecordingTimeout(duration: TimeInterval? = nil) {
        cancelRecordingTimeout()

        let timeoutDuration = max(0, duration ?? maxRecordingDuration)
        recordingTimeoutDeadline = Date().addingTimeInterval(timeoutDuration)

        guard timeoutDuration > 0 else {
            Task { [weak self] in
                guard let self = self else { return }
                if case .recording = self.state {
                    AppLogger.log("[AppleSpeech] Recording timeout reached")
                    _ = try? await self.stopRecording()
                }
            }
            return
        }

        let timeoutNanoseconds = UInt64(timeoutDuration * 1_000_000_000)
        recordingTimeoutTask = Task { [weak self] in
            guard let self = self else { return }

            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }

            if case .recording = self.state, !self.isAutoStopSuspended {
                AppLogger.log("[AppleSpeech] Recording timeout reached")
                _ = try? await self.stopRecording()
            }
        }
    }

    private func cancelRecordingTimeout() {
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = nil
        recordingTimeoutDeadline = nil
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension AppleSpeechService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        AppLogger.log("[AppleSpeech] Availability changed: \(available)")

        if !available && state.isRecording {
            cancelRecording()
            state = .failed(.recognizerUnavailable(language: selectedLanguage.name))
        }
    }
}
