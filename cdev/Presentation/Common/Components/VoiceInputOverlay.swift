import SwiftUI

/// Full-screen overlay for voice input with waveform visualization
/// Optimized for fast developer workflow with silence detection and auto-send
struct VoiceInputOverlay: View {
    @ObservedObject var viewModel: VoiceInputViewModel
    let onDismiss: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    @State private var showLanguagePicker = false
    @State private var recordingPulse = false
    @StateObject private var settings = VoiceInputSettingsStore.shared

    var body: some View {
        ZStack {
            // Dimmed background - tap to cancel
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.cancelRecording()
                    onDismiss()
                }

            // Main content - compact card for fast access
            VStack(spacing: layout.sectionSpacing) {
                Spacer()

                // Compact status + language row
                statusRow

                // Audio waveform visualization
                AudioWaveformView(audioLevel: viewModel.audioLevel, isActive: viewModel.isRecording)
                    .frame(height: layout.isCompact ? 50 : 60)
                    .padding(.horizontal, layout.largePadding)

                // Real-time transcription
                transcriptionView
                    .frame(minHeight: 60, maxHeight: layout.isCompact ? 120 : 150)

                Spacer()

                // Auto-send indicator
                if settings.autoSendOnSilence && viewModel.isRecording {
                    autoSendHint
                }

                // Action buttons - compact row
                actionButtons
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.bottom, layout.largePadding)
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(
                selectedLanguage: $viewModel.selectedLanguage,
                languages: viewModel.availableLanguages
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Status Row (Compact) - LIVE-style indicator

    private var statusRow: some View {
        HStack(spacing: layout.contentSpacing) {
            // Status indicator with LIVE-style glow on dot only
            HStack(spacing: 4) {
                // Animated glow dot (like LIVE indicator)
                ZStack {
                    // Glow layer (pulsing)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .blur(radius: recordingPulse ? 4 : 0)
                        .opacity(recordingPulse ? 0.8 : 0)

                    // Solid dot
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                }
                .frame(width: 14, height: 14) // Fixed frame prevents jumping

                Text(statusLabel)
                    .font(Typography.badge)
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())

            Spacer()

            // Language selector - always accessible
            languageButton
        }
        .padding(.horizontal, layout.standardPadding)
        .onChange(of: viewModel.isRecording) { _, recording in
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                recordingPulse = recording
            }
        }
        .onAppear {
            // Start animation if already recording when view appears
            if viewModel.isRecording {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    recordingPulse = true
                }
            }
        }
    }

    private var statusLabel: String {
        switch viewModel.state {
        case .recording:
            return "LISTENING"
        case .processing:
            return "PROCESSING"
        case .failed:
            return "ERROR"
        case .completed:
            return "DONE"
        default:
            return "READY"
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .recording:
            return ColorSystem.error
        case .processing:
            return ColorSystem.warning
        case .failed:
            return ColorSystem.error
        default:
            // Use light gray for dark overlay background (Light Mode safe)
            return Color.white.opacity(0.5)
        }
    }

    // MARK: - Language Button (Compact)

    private var languageButton: some View {
        Button {
            // Can change language anytime (will restart recording if needed)
            showLanguagePicker = true
            Haptics.selection()
        } label: {
            HStack(spacing: Spacing.xxs) {
                Text(viewModel.selectedLanguage.flag)
                    .font(.system(size: layout.isCompact ? 16 : 18))

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: layout.iconSmall - 1, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.horizontal, layout.smallPadding)
            .padding(.vertical, layout.tightSpacing)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transcription View

    private var transcriptionView: some View {
        ScrollView {
            Text(viewModel.currentTranscription.isEmpty
                 ? "Listening..."
                 : viewModel.currentTranscription)
                .font(layout.isCompact ? Typography.body : Typography.bodyBold)
                // Always use light colors on dark overlay background (ignores Light/Dark mode)
                .foregroundStyle(
                    viewModel.currentTranscription.isEmpty
                        ? Color.white.opacity(0.5)
                        : Color.white.opacity(0.95)
                )
                .multilineTextAlignment(.center)
                .padding(.horizontal, layout.largePadding)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Auto-send Hint

    private var autoSendHint: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "bolt.fill")
                .font(.system(size: layout.iconSmall))
                .foregroundStyle(ColorSystem.primary)

            Text("Auto-send on pause")
                .font(Typography.caption1)
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.horizontal, layout.smallPadding)
        .padding(.vertical, layout.tightSpacing)
        .background(ColorSystem.primary.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: layout.contentSpacing) {
            // Cancel button
            Button {
                viewModel.cancelRecording()
                onDismiss()
                Haptics.light()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: layout.iconMedium, weight: .semibold))
                    // Use light color on dark overlay background (ignores Light/Dark mode)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: layout.buttonHeight, height: layout.buttonHeight)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Main action button - full width
            Button {
                handleMainAction()
            } label: {
                HStack(spacing: Spacing.xs) {
                    if viewModel.isRecording {
                        // Stop icon
                        Image(systemName: "stop.fill")
                            .font(.system(size: layout.iconMedium))
                    } else if viewModel.isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        // Send icon
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: layout.iconMedium))
                    }

                    Text(mainButtonText)
                        .font(Typography.buttonLabel)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: layout.buttonHeight)
                .background(mainButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: layout.buttonHeight / 2))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing || (!viewModel.isRecording && viewModel.currentTranscription.isEmpty))
        }
        .padding(.horizontal, layout.standardPadding)
    }

    private var mainButtonText: String {
        if viewModel.isRecording {
            return "Stop"
        } else if viewModel.isProcessing {
            return "Processing..."
        } else {
            return "Send"
        }
    }

    private var mainButtonColor: Color {
        if viewModel.isRecording {
            return ColorSystem.error
        } else if viewModel.isProcessing {
            return ColorSystem.warning
        } else if viewModel.currentTranscription.isEmpty {
            return ColorSystem.textQuaternary
        } else {
            return ColorSystem.primary
        }
    }

    private func handleMainAction() {
        if viewModel.isRecording {
            viewModel.stopRecording()
            Haptics.medium()
        } else if !viewModel.currentTranscription.isEmpty {
            viewModel.completeAndSend()
        }
    }
}

// MARK: - Audio Waveform View

/// Animated waveform visualization during recording
struct AudioWaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    private var barCount: Int { layout.isCompact ? 20 : 28 }
    @State private var barHeights: [CGFloat] = []

    var body: some View {
        HStack(spacing: layout.isCompact ? 2 : 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: layout.isCompact ? 3 : 4, height: max(4, barHeight(for: index)))
            }
        }
        .onAppear {
            barHeights = Array(repeating: 0.15, count: barCount)
        }
        .onChange(of: audioLevel) { _, newLevel in
            if isActive {
                updateBars(level: newLevel)
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                withAnimation(.easeOut(duration: 0.3)) {
                    barHeights = Array(repeating: 0.15, count: barCount)
                }
            }
        }
        .animation(.easeOut(duration: 0.08), value: barHeights)
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard index < barHeights.count else { return 4 }
        let maxHeight: CGFloat = layout.isCompact ? 46 : 56
        return barHeights[index] * maxHeight
    }

    private func barColor(for index: Int) -> Color {
        let centerIndex = barCount / 2
        let distance = abs(index - centerIndex)
        let opacity = 1.0 - (Double(distance) / Double(centerIndex) * 0.5)

        if isActive {
            return ColorSystem.primary.opacity(opacity * 0.9)
        } else {
            return ColorSystem.textQuaternary.opacity(opacity * 0.5)
        }
    }

    private func updateBars(level: Float) {
        guard barHeights.count == barCount else {
            barHeights = Array(repeating: 0.15, count: barCount)
            return
        }

        var newHeights = barHeights
        let centerIndex = barCount / 2
        let normalizedLevel = CGFloat(max(0.15, min(1.0, level)))

        // Shift bars outward from center
        for i in 0..<centerIndex {
            newHeights[i] = barHeights[i + 1]
        }
        for i in stride(from: barCount - 1, to: centerIndex, by: -1) {
            newHeights[i] = barHeights[i - 1]
        }

        // Set center bars to current level with slight variation
        let variation = CGFloat.random(in: -0.1...0.1)
        newHeights[centerIndex] = normalizedLevel + variation
        if centerIndex > 0 {
            newHeights[centerIndex - 1] = normalizedLevel * 0.8 + variation
        }
        if centerIndex < barCount - 1 {
            newHeights[centerIndex + 1] = normalizedLevel * 0.8 + variation
        }

        barHeights = newHeights
    }
}

// MARK: - Language Picker Sheet

/// Sheet for selecting voice input language
struct LanguagePickerSheet: View {
    @Binding var selectedLanguage: VoiceInputLanguage
    let languages: [VoiceInputLanguage]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        NavigationStack {
            List(languages) { language in
                Button {
                    selectedLanguage = language
                    Haptics.selection()
                    dismiss()
                } label: {
                    HStack(spacing: layout.contentSpacing) {
                        Text(language.flag)
                            .font(.system(size: layout.isCompact ? 22 : 26))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.name)
                                .font(layout.bodyFont)
                                .foregroundStyle(ColorSystem.textPrimary)

                            Text(language.nativeName)
                                .font(layout.captionFont)
                                .foregroundStyle(ColorSystem.textTertiary)
                        }

                        Spacer()

                        if language.id == selectedLanguage.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: layout.iconMedium, weight: .semibold))
                                .foregroundStyle(ColorSystem.primary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(ColorSystem.primary)
                }
            }
        }
    }
}

// MARK: - Error View

/// Error view shown when voice input fails
struct VoiceInputErrorView: View {
    let error: VoiceInputError
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(spacing: layout.sectionSpacing) {
            // Error icon
            Image(systemName: "mic.slash.fill")
                .font(.system(size: layout.iconXLarge + 10))
                .foregroundStyle(ColorSystem.error)

            // Error message
            Text(error.localizedDescription)
                .font(layout.bodyFont)
                .foregroundStyle(ColorSystem.textPrimary)
                .multilineTextAlignment(.center)

            // Recovery suggestion
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(layout.captionFont)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Actions
            HStack(spacing: layout.contentSpacing) {
                if error.requiresSettings {
                    Button("Open Settings") {
                        onOpenSettings()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else if error.isRetryable {
                    Button("Try Again") {
                        onRetry()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(layout.largePadding)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
    }
}

// MARK: - Button Styles

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.buttonLabel)
            .foregroundStyle(.white)
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, layout.smallPadding)
            .background(ColorSystem.primary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.buttonLabel)
            .foregroundStyle(ColorSystem.textSecondary)
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, layout.smallPadding)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Preview

#Preview {
    VoiceInputOverlay(
        viewModel: VoiceInputViewModel(),
        onDismiss: {}
    )
}
