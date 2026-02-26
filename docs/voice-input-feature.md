# Voice Input Feature - Technical Design

This document describes the voice input feature for cdev-ios, specifically optimized for Vietnamese language support.

## Problem Statement

Apple's built-in keyboard dictation has significant limitations for Vietnamese:

| Issue | Impact |
|-------|--------|
| **Tonal recognition** | Vietnamese has 6 tones (à, á, ả, ã, ạ, a) that change word meaning. Built-in dictation often misidentifies tones. |
| **Diacritics accuracy** | Complex diacritics (ư, ơ, ă, đ) are frequently transcribed incorrectly. |
| **Context awareness** | Same phonemes map to different words based on tone; dictation lacks context. |
| **No language lock** | Keyboard dictation may switch languages unexpectedly. |
| **Limited customization** | Cannot tune recognition for developer terminology. |

## Feature Overview

### Goals

1. **Accurate Vietnamese transcription** - Leverage best-in-class speech recognition for tonal languages
2. **Seamless integration** - Voice input feels native alongside text input
3. **Real-time feedback** - Show transcription as user speaks
4. **Minimal friction** - One-tap to start/stop recording
5. **Flexible providers** - Support multiple speech recognition backends

### Non-Goals

- Voice commands (e.g., "send message", "clear input")
- Continuous listening / wake word detection
- Voice output / text-to-speech
- Call/phone integration

## Architecture

### Layer Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                     Presentation Layer                           │
├─────────────────────────────────────────────────────────────────┤
│  VoiceInputButton          - Microphone button with animations  │
│  VoiceInputOverlay         - Recording feedback UI              │
│  VoiceInputSettingsView    - Provider & language configuration  │
│  ActionBarView (modified)  - Integrate voice button             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Domain Layer                               │
├─────────────────────────────────────────────────────────────────┤
│  VoiceInputServiceProtocol - Abstract interface for providers   │
│  TranscriptionResult       - Transcribed text with metadata     │
│  VoiceInputError           - Domain error types                 │
│  VoiceInputUseCase         - Orchestrates recording flow        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Data Layer                                │
├─────────────────────────────────────────────────────────────────┤
│  AppleSpeechService        - SFSpeechRecognizer (vi-VN)         │
│  WhisperAPIService         - OpenAI Whisper REST API            │
│  WhisperOnDeviceService    - Local whisper.cpp (future)         │
│  AudioRecorderService      - AVAudioEngine wrapper              │
│  VoiceInputSettingsStore   - UserDefaults persistence           │
└─────────────────────────────────────────────────────────────────┘
```

### Dependency Flow

```
Presentation → Domain ← Data
     │            │        │
     │            ▼        │
     │       VoiceInput    │
     │       Protocol      │
     │            ▲        │
     └────────────┴────────┘
```

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           ActionBarView                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌──────────────────────────┐ ┌───┐ ┌──────┐   │
│  │ 🎤  │ │ 💻  │ │ ⏹  │ │    RainbowTextField      │ │ ✕ │ │ Send │   │
│  │     │ │     │ │     │ │                          │ │   │ │      │   │
│  │Voice│ │Bash │ │Stop │ │  "Ask Claude..."         │ │Clr│ │  ➤   │   │
│  └──┬──┘ └─────┘ └─────┘ └──────────────────────────┘ └───┘ └──────┘   │
│     │                                                                    │
└─────┼────────────────────────────────────────────────────────────────────┘
      │
      │ tap
      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        VoiceInputOverlay                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│     ┌─────────────────────────────────────────────────────────┐         │
│     │                                                         │         │
│     │              ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉                 │         │
│     │              Audio Level Waveform                       │         │
│     │                                                         │         │
│     │     "Xin chào, tôi muốn hỏi về..."                     │         │
│     │     Real-time transcription                             │         │
│     │                                                         │         │
│     │              ┌─────────────────┐                        │         │
│     │              │   🎤 Đang ghi   │                        │         │
│     │              │   Tap to stop   │                        │         │
│     │              └─────────────────┘                        │         │
│     │                                                         │         │
│     │     [VI Vietnamese ▼]              [Cancel]  [Done]     │         │
│     │                                                         │         │
│     └─────────────────────────────────────────────────────────┘         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Provider Comparison

### Apple Speech Framework (SFSpeechRecognizer)

| Aspect | Details |
|--------|---------|
| **Locale** | `vi-VN` (Vietnamese - Vietnam) |
| **Mode** | On-device (iOS 13+) or server-based |
| **Latency** | ~100-300ms for partial results |
| **Accuracy** | 70-80% for Vietnamese (estimated) |
| **Cost** | Free |
| **Offline** | Yes (on-device mode) |
| **Privacy** | Audio processed on-device or Apple servers |

**Configuration:**
```swift
let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN"))
request.requiresOnDeviceRecognition = true  // Privacy + speed
request.shouldReportPartialResults = true    // Real-time feedback
if #available(iOS 16.0, *) {
    request.addsPunctuation = true           // Auto punctuation
}
```

### OpenAI Whisper API

| Aspect | Details |
|--------|---------|
| **Model** | `whisper-1` |
| **Languages** | 99 languages including Vietnamese |
| **Latency** | 1-3 seconds (upload + processing) |
| **Accuracy** | 90-95% for Vietnamese (excellent) |
| **Cost** | $0.006 / minute |
| **Offline** | No |
| **Privacy** | Audio sent to OpenAI servers |

**API Endpoint:**
```
POST https://api.openai.com/v1/audio/transcriptions

Headers:
  Authorization: Bearer $OPENAI_API_KEY
  Content-Type: multipart/form-data

Body:
  file: audio.m4a (binary)
  model: whisper-1
  language: vi
  response_format: json
```

**Response:**
```json
{
  "text": "Xin chào, tôi muốn hỏi về cách sử dụng Claude API"
}
```

### Whisper On-Device (Future)

| Aspect | Details |
|--------|---------|
| **Library** | whisper.cpp / WhisperKit |
| **Model Size** | tiny: 39MB, base: 74MB, small: 244MB |
| **Latency** | 2-5 seconds (depends on model/device) |
| **Accuracy** | 85-92% for Vietnamese (model dependent) |
| **Cost** | Free (after initial download) |
| **Offline** | Yes |
| **Privacy** | Fully on-device |

## Domain Models

### TranscriptionResult

```swift
/// Result from voice transcription
struct TranscriptionResult: Equatable, Sendable {
    /// Transcribed text
    let text: String

    /// Whether this is a final result or partial/interim
    let isFinal: Bool

    /// Confidence score (0.0 - 1.0), if available
    let confidence: Float?

    /// Language detected or used
    let language: String

    /// Provider that generated this result
    let provider: VoiceInputProvider

    /// Duration of audio processed (seconds)
    let audioDuration: TimeInterval?
}
```

### VoiceInputProvider

```swift
/// Available voice input providers
enum VoiceInputProvider: String, CaseIterable, Codable {
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

    var requiresAPIKey: Bool {
        self == .whisperAPI
    }

    var supportsRealtime: Bool {
        self == .appleSpeech
    }

    var vietnameseAccuracy: String {
        switch self {
        case .appleSpeech: return "Good"
        case .whisperAPI: return "Excellent"
        case .whisperOnDevice: return "Very Good"
        }
    }
}
```

### VoiceInputError

```swift
/// Voice input domain errors
enum VoiceInputError: LocalizedError {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case recognizerUnavailable(language: String)
    case audioSessionFailed(underlying: Error)
    case recordingFailed(underlying: Error)
    case transcriptionFailed(underlying: Error)
    case apiKeyMissing
    case networkUnavailable
    case quotaExceeded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access denied. Enable in Settings."
        case .speechRecognitionPermissionDenied:
            return "Speech recognition denied. Enable in Settings."
        case .recognizerUnavailable(let language):
            return "Speech recognition unavailable for \(language)."
        case .audioSessionFailed(let error):
            return "Audio session error: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .apiKeyMissing:
            return "Whisper API key not configured."
        case .networkUnavailable:
            return "Network connection required for Whisper API."
        case .quotaExceeded:
            return "API quota exceeded. Try again later."
        case .cancelled:
            return "Recording cancelled."
        }
    }
}
```

### VoiceInputState

```swift
/// Voice input state machine
enum VoiceInputState: Equatable {
    case idle
    case requestingPermission
    case preparing
    case recording(audioLevel: Float)
    case processing
    case completed(TranscriptionResult)
    case failed(VoiceInputError)

    var isActive: Bool {
        switch self {
        case .recording, .processing, .preparing:
            return true
        default:
            return false
        }
    }
}
```

## Protocol Definition

```swift
/// Protocol for voice input providers
protocol VoiceInputServiceProtocol: AnyObject {
    /// Current state of voice input
    var state: VoiceInputState { get }

    /// Publisher for state changes
    var statePublisher: AnyPublisher<VoiceInputState, Never> { get }

    /// Publisher for real-time transcription (partial results)
    var transcriptionPublisher: AnyPublisher<TranscriptionResult, Never> { get }

    /// Publisher for audio level (0.0 - 1.0)
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }

    /// Supported languages
    var supportedLanguages: [Locale] { get }

    /// Check if provider is available
    func isAvailable() async -> Bool

    /// Request necessary permissions
    func requestPermissions() async throws -> Bool

    /// Start recording and transcription
    /// - Parameter language: Target language locale (e.g., "vi-VN")
    func startRecording(language: Locale) async throws

    /// Stop recording and get final transcription
    func stopRecording() async throws -> TranscriptionResult

    /// Cancel recording without result
    func cancelRecording()
}
```

## UI Components

### VoiceInputButton

Compact microphone button for ActionBarView.

```swift
struct VoiceInputButton: View {
    @ObservedObject var viewModel: VoiceInputViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        Button {
            viewModel.toggleRecording()
        } label: {
            ZStack {
                // Pulsing ring when recording
                if viewModel.isRecording {
                    Circle()
                        .stroke(ColorSystem.error.opacity(0.4), lineWidth: 2)
                        .scaleEffect(1.0 + CGFloat(viewModel.audioLevel) * 0.3)
                }

                // Microphone icon
                Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: layout.iconAction, weight: .semibold))
                    .foregroundStyle(buttonColor)
            }
            .frame(width: layout.indicatorSize, height: layout.indicatorSize)
            .background(backgroundColor)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(borderColor, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessing)
    }

    private var buttonColor: Color {
        switch viewModel.state {
        case .recording: return ColorSystem.error
        case .processing: return ColorSystem.warning
        default: return ColorSystem.textTertiary
        }
    }

    private var backgroundColor: Color {
        switch viewModel.state {
        case .recording: return ColorSystem.error.opacity(0.15)
        case .processing: return ColorSystem.warning.opacity(0.15)
        default: return ColorSystem.terminalBgHighlight
        }
    }

    private var borderColor: Color {
        viewModel.isRecording ? ColorSystem.error.opacity(0.3) : .clear
    }
}
```

### VoiceInputOverlay

Full-screen overlay during recording with waveform visualization.

```swift
struct VoiceInputOverlay: View {
    @ObservedObject var viewModel: VoiceInputViewModel
    let onDismiss: () -> Void
    let onComplete: (String) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(spacing: layout.sectionSpacing) {
            Spacer()

            // Audio waveform visualization
            AudioWaveformView(audioLevel: viewModel.audioLevel)
                .frame(height: 60)
                .padding(.horizontal, layout.standardPadding)

            // Real-time transcription
            ScrollView {
                Text(viewModel.currentTranscription.isEmpty
                     ? "Listening..."
                     : viewModel.currentTranscription)
                    .font(Typography.body)
                    .foregroundStyle(viewModel.currentTranscription.isEmpty
                                     ? ColorSystem.textTertiary
                                     : ColorSystem.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, layout.largePadding)
            }
            .frame(maxHeight: 120)

            // Recording indicator
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(ColorSystem.error)
                    .frame(width: 8, height: 8)
                    .opacity(viewModel.isRecording ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: viewModel.isRecording)

                Text(viewModel.isRecording ? "Recording..." : "Processing...")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Spacer()

            // Language selector
            LanguagePicker(
                selectedLanguage: $viewModel.selectedLanguage,
                languages: viewModel.availableLanguages
            )
            .padding(.horizontal, layout.standardPadding)

            // Action buttons
            HStack(spacing: layout.contentSpacing) {
                Button("Cancel") {
                    viewModel.cancelRecording()
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(viewModel.isRecording ? "Stop" : "Done") {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        onComplete(viewModel.currentTranscription)
                        onDismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.currentTranscription.isEmpty && !viewModel.isRecording)
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.bottom, layout.largePadding)
        }
        .background(ColorSystem.terminalBg.opacity(0.95))
        .ignoresSafeArea()
    }
}
```

### AudioWaveformView

Animated waveform visualization during recording.

```swift
struct AudioWaveformView: View {
    let audioLevel: Float

    private let barCount = 20
    @State private var barHeights: [CGFloat] = Array(repeating: 0.1, count: 20)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(ColorSystem.primary.opacity(0.8))
                    .frame(width: 4, height: max(4, barHeights[index] * 60))
            }
        }
        .onChange(of: audioLevel) { _, newLevel in
            updateBars(level: newLevel)
        }
        .animation(.easeOut(duration: 0.1), value: barHeights)
    }

    private func updateBars(level: Float) {
        // Shift existing values and add new level
        var newHeights = Array(barHeights.dropFirst())
        newHeights.append(CGFloat(level))
        barHeights = newHeights
    }
}
```

### VoiceInputSettingsView

Settings screen for voice input configuration.

```swift
struct VoiceInputSettingsView: View {
    @ObservedObject var settingsStore: VoiceInputSettingsStore
    @State private var showAPIKeyInput = false

    var body: some View {
        List {
            // Provider selection
            Section {
                ForEach(VoiceInputProvider.allCases, id: \.self) { provider in
                    ProviderRow(
                        provider: provider,
                        isSelected: settingsStore.selectedProvider == provider,
                        onSelect: { settingsStore.selectedProvider = provider }
                    )
                }
            } header: {
                Text("Speech Recognition Provider")
            } footer: {
                Text(providerFooterText)
            }

            // Language selection
            Section("Language") {
                Picker("Primary Language", selection: $settingsStore.primaryLanguage) {
                    Text("Vietnamese").tag("vi-VN")
                    Text("English").tag("en-US")
                    Text("Auto-detect").tag("auto")
                }
            }

            // Whisper API configuration
            if settingsStore.selectedProvider == .whisperAPI {
                Section("Whisper API") {
                    SecureField("API Key", text: $settingsStore.whisperAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    if !settingsStore.whisperAPIKey.isEmpty {
                        Button("Test API Key") {
                            Task { await testAPIKey() }
                        }
                    }
                }
            }

            // Advanced options
            Section("Advanced") {
                Toggle("Auto-punctuation", isOn: $settingsStore.autoPunctuation)
                Toggle("Haptic Feedback", isOn: $settingsStore.hapticFeedback)
                Toggle("Show Waveform", isOn: $settingsStore.showWaveform)
            }
        }
        .navigationTitle("Voice Input")
    }

    private var providerFooterText: String {
        switch settingsStore.selectedProvider {
        case .appleSpeech:
            return "Uses Apple's built-in speech recognition. Good accuracy for Vietnamese, works offline."
        case .whisperAPI:
            return "Uses OpenAI's Whisper model. Excellent Vietnamese accuracy but requires internet and API key."
        case .whisperOnDevice:
            return "Runs Whisper model locally. Very good accuracy, works offline, but uses more battery."
        }
    }
}
```

## Implementation Phases

### Phase 1: Foundation (Apple Speech)

**Goal:** Basic voice input with Apple's Speech framework

**Tasks:**

1. **Audio Infrastructure**
   - [ ] Create `AudioRecorderService` with AVAudioEngine
   - [ ] Implement audio level metering
   - [ ] Handle audio session configuration
   - [ ] Add `NSMicrophoneUsageDescription` to Info.plist
   - [ ] Add `NSSpeechRecognitionUsageDescription` to Info.plist

2. **Apple Speech Provider**
   - [ ] Create `AppleSpeechService` implementing `VoiceInputServiceProtocol`
   - [ ] Configure SFSpeechRecognizer with `vi-VN` locale
   - [ ] Enable on-device recognition
   - [ ] Implement real-time partial results
   - [ ] Handle permission requests

3. **UI Components**
   - [ ] Create `VoiceInputButton` component
   - [ ] Create `VoiceInputOverlay` with waveform
   - [ ] Create `AudioWaveformView` animation
   - [ ] Integrate button into `ActionBarView`

4. **ViewModel & State**
   - [ ] Create `VoiceInputViewModel` with state machine
   - [ ] Connect to `DashboardViewModel` for text injection
   - [ ] Handle error states and recovery

5. **Settings**
   - [ ] Create `VoiceInputSettingsStore`
   - [ ] Add language selection
   - [ ] Add provider selection (prepare for Phase 2)

### Phase 2: Whisper API Integration

**Goal:** Add OpenAI Whisper as premium provider for better Vietnamese accuracy

**Tasks:**

1. **Whisper API Service**
   - [ ] Create `WhisperAPIService` implementing `VoiceInputServiceProtocol`
   - [ ] Implement audio file encoding (M4A/WAV)
   - [ ] Handle API authentication
   - [ ] Implement retry logic with exponential backoff
   - [ ] Add usage tracking (optional)

2. **API Key Management**
   - [ ] Secure storage in Keychain
   - [ ] API key validation endpoint
   - [ ] Settings UI for key entry

3. **Provider Switching**
   - [ ] Implement provider factory
   - [ ] Smooth switching between providers
   - [ ] Fallback logic (Whisper → Apple if network fails)

4. **Enhanced UI**
   - [ ] Provider indicator in overlay
   - [ ] Accuracy comparison in settings
   - [ ] Usage statistics (if tracking enabled)

### Phase 3: On-Device Whisper (Future)

**Goal:** Fully offline, privacy-preserving Whisper

**Tasks:**

1. **Model Integration**
   - [ ] Evaluate whisper.cpp vs WhisperKit
   - [ ] Implement model download manager
   - [ ] Core ML optimization (if applicable)
   - [ ] Model size selector (tiny/base/small)

2. **Performance Optimization**
   - [ ] Background processing
   - [ ] Memory management
   - [ ] Battery impact minimization

3. **UI Enhancements**
   - [ ] Model download progress
   - [ ] Storage usage indicator
   - [ ] Processing progress for longer audio

## Info.plist Additions

```xml
<!-- Microphone access -->
<key>NSMicrophoneUsageDescription</key>
<string>cdev needs microphone access to transcribe your voice input for sending prompts to Claude.</string>

<!-- Speech recognition -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>cdev uses speech recognition to convert your voice to text for Claude prompts.</string>
```

## Error Handling

### Permission Flow

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Tap Mic     │────▶│ Check Mic        │────▶│ Check Speech    │
│ Button      │     │ Permission       │     │ Permission      │
└─────────────┘     └──────────────────┘     └─────────────────┘
                            │                        │
                    ┌───────┴───────┐        ┌───────┴───────┐
                    ▼               ▼        ▼               ▼
              ┌──────────┐   ┌──────────┐ ┌──────────┐ ┌──────────┐
              │ Granted  │   │ Denied   │ │ Granted  │ │ Denied   │
              └────┬─────┘   └────┬─────┘ └────┬─────┘ └────┬─────┘
                   │              │            │            │
                   │              ▼            │            ▼
                   │        ┌──────────┐       │      ┌──────────┐
                   │        │ Show     │       │      │ Show     │
                   │        │ Settings │       │      │ Settings │
                   │        │ Alert    │       │      │ Alert    │
                   │        └──────────┘       │      └──────────┘
                   │                           │
                   └───────────────────────────┘
                                 │
                                 ▼
                         ┌─────────────┐
                         │ Start       │
                         │ Recording   │
                         └─────────────┘
```

### Error Recovery Strategies

| Error | Recovery |
|-------|----------|
| Permission denied | Show settings deep link |
| Network unavailable (Whisper) | Fallback to Apple Speech |
| Recognizer unavailable | Try alternative language or provider |
| Audio session conflict | Wait and retry, or show conflict alert |
| API quota exceeded | Show upgrade prompt or fallback |
| Recording timeout | Auto-stop and process what was captured |

## Testing Strategy

### Unit Tests

```swift
// VoiceInputViewModelTests.swift
final class VoiceInputViewModelTests: XCTestCase {
    var sut: VoiceInputViewModel!
    var mockService: MockVoiceInputService!

    func test_startRecording_updatesStateToRecording() async {
        // Given
        mockService.startRecordingResult = .success(())

        // When
        await sut.startRecording()

        // Then
        XCTAssertTrue(sut.isRecording)
        XCTAssertEqual(sut.state, .recording(audioLevel: 0))
    }

    func test_stopRecording_updatesStateToCompleted() async {
        // Given
        let expectedText = "Xin chào"
        mockService.stopRecordingResult = .success(TranscriptionResult(
            text: expectedText,
            isFinal: true,
            confidence: 0.95,
            language: "vi-VN",
            provider: .appleSpeech,
            audioDuration: 2.5
        ))
        sut.state = .recording(audioLevel: 0.5)

        // When
        await sut.stopRecording()

        // Then
        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(sut.currentTranscription, expectedText)
    }

    func test_permissionDenied_showsError() async {
        // Given
        mockService.requestPermissionsResult = .failure(.microphonePermissionDenied)

        // When
        await sut.startRecording()

        // Then
        XCTAssertEqual(sut.state, .failed(.microphonePermissionDenied))
    }
}
```

### UI Tests

```swift
// VoiceInputUITests.swift
final class VoiceInputUITests: XCTestCase {
    func test_micButtonShowsOverlay() {
        let app = XCUIApplication()
        app.launch()

        // Navigate to dashboard
        // ...

        // Tap microphone button
        app.buttons["voiceInputButton"].tap()

        // Verify overlay appears
        XCTAssertTrue(app.otherElements["voiceInputOverlay"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Listening..."].exists)
    }

    func test_cancelButtonDismissesOverlay() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["voiceInputButton"].tap()
        app.buttons["Cancel"].tap()

        XCTAssertFalse(app.otherElements["voiceInputOverlay"].exists)
    }
}
```

### Manual Testing Checklist

- [ ] Vietnamese sentence with all 6 tones transcribes correctly
- [ ] Diacritics (ư, ơ, ă, đ, ê, ô) are accurate
- [ ] Mixed Vietnamese/English transcribes reasonably
- [ ] Long audio (60+ seconds) processes successfully
- [ ] Background noise doesn't crash recognition
- [ ] Permission denied shows helpful alert
- [ ] Network loss during Whisper API gracefully fails
- [ ] Audio waveform animates smoothly
- [ ] iPad layout looks correct
- [ ] iPhone compact layout works

## Security Considerations

1. **API Key Storage**
   - Store Whisper API key in Keychain, never UserDefaults
   - Never log API keys
   - Clear keys on app uninstall (Keychain persistence)

2. **Audio Data**
   - Don't persist audio files after transcription
   - Use temporary directory with auto-cleanup
   - For Whisper API, use HTTPS only

3. **Privacy**
   - Default to on-device recognition (Apple Speech)
   - Clearly indicate when audio leaves device
   - Don't transcribe in background without user action

4. **Permissions**
   - Request permissions only when user initiates voice input
   - Explain usage clearly in permission dialogs
   - Respect user's decision (don't re-prompt aggressively)

## Accessibility

- VoiceOver announcements for recording state changes
- Haptic feedback for start/stop (configurable)
- Visual alternatives to audio waveform
- Sufficient contrast in all states
- Support for reduced motion preferences

## Metrics & Analytics (Optional)

Consider tracking (with user consent):
- Provider usage distribution
- Average transcription length
- Error rates by provider
- Vietnamese vs other language usage
- Feature adoption rate

---

## File Structure

```
cdev/
├── Domain/
│   ├── Models/
│   │   ├── TranscriptionResult.swift
│   │   ├── VoiceInputProvider.swift
│   │   ├── VoiceInputState.swift
│   │   └── VoiceInputError.swift
│   ├── Interfaces/
│   │   └── VoiceInputServiceProtocol.swift
│   └── UseCases/
│       └── VoiceInputUseCase.swift
├── Data/
│   └── Services/
│       ├── Voice/
│       │   ├── AudioRecorderService.swift
│       │   ├── AppleSpeechService.swift
│       │   ├── WhisperAPIService.swift
│       │   └── VoiceInputServiceFactory.swift
│       └── VoiceInputSettingsStore.swift
└── Presentation/
    ├── Common/
    │   └── Components/
    │       ├── VoiceInputButton.swift
    │       ├── VoiceInputOverlay.swift
    │       └── AudioWaveformView.swift
    └── Screens/
        ├── Dashboard/
        │   └── ViewModels/
        │       └── VoiceInputViewModel.swift
        └── Settings/
            └── VoiceInputSettingsView.swift
```
