import SwiftUI

/// Compact microphone button for voice input in ActionBarView
/// Shows pulsing animation when recording
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
                    // Outer pulse ring
                    Circle()
                        .stroke(ColorSystem.error.opacity(0.3), lineWidth: 2)
                        .scaleEffect(1.0 + CGFloat(viewModel.audioLevel) * 0.4)
                        .animation(.easeOut(duration: 0.1), value: viewModel.audioLevel)

                    // Inner pulse ring
                    Circle()
                        .stroke(ColorSystem.error.opacity(0.5), lineWidth: 1.5)
                        .scaleEffect(1.0 + CGFloat(viewModel.audioLevel) * 0.2)
                        .animation(.easeOut(duration: 0.08), value: viewModel.audioLevel)
                }

                // Microphone icon
                Image(systemName: iconName)
                    .font(.system(size: layout.iconAction, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.pulse, isActive: viewModel.isRecording)
            }
            .frame(width: layout.indicatorSize, height: layout.indicatorSize)
            .background(backgroundColor)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(borderColor, lineWidth: 1.5)
            )
            .shadow(color: shadowColor, radius: viewModel.isRecording ? 4 : 0)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessing)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch viewModel.state {
        case .recording:
            return "mic.fill"
        case .processing:
            return "waveform"
        case .failed:
            return "mic.slash"
        default:
            return "mic"
        }
    }

    private var iconColor: Color {
        switch viewModel.state {
        case .recording:
            return ColorSystem.error
        case .processing:
            return ColorSystem.warning
        case .failed:
            return ColorSystem.error.opacity(0.7)
        default:
            return ColorSystem.textTertiary
        }
    }

    private var backgroundColor: Color {
        switch viewModel.state {
        case .recording:
            return ColorSystem.error.opacity(0.15)
        case .processing:
            return ColorSystem.warning.opacity(0.15)
        case .failed:
            return ColorSystem.error.opacity(0.1)
        default:
            return ColorSystem.terminalBgHighlight
        }
    }

    private var borderColor: Color {
        switch viewModel.state {
        case .recording:
            return ColorSystem.error.opacity(0.4)
        case .processing:
            return ColorSystem.warning.opacity(0.3)
        default:
            return .clear
        }
    }

    private var shadowColor: Color {
        viewModel.isRecording ? ColorSystem.error.opacity(0.4) : .clear
    }

    private var accessibilityLabel: String {
        switch viewModel.state {
        case .recording:
            return "Stop recording"
        case .processing:
            return "Processing voice"
        default:
            return "Voice input"
        }
    }

    private var accessibilityHint: String {
        switch viewModel.state {
        case .recording:
            return "Tap to stop recording and transcribe"
        case .processing:
            return "Wait for transcription to complete"
        default:
            return "Tap to start voice input"
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 16) {
        // Idle state
        VoiceInputButton(viewModel: VoiceInputViewModel())

        // Recording state (simulated)
        VoiceInputButton(viewModel: {
            let vm = VoiceInputViewModel()
            return vm
        }())
    }
    .padding()
    .background(ColorSystem.terminalBg)
}
