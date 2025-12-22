import SwiftUI

/// Non-blocking connection status banner
/// Shows connection issues inline without blocking user interaction
/// Design: Compact, animated, and dismissible
/// Responsive: Uses centralized ResponsiveLayout for iPhone/iPad adaptation
struct ConnectionBanner: View {
    let connectionState: ConnectionState
    let onRetry: () -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isExpanded = false
    @State private var isDismissed = false
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var previousState: ConnectionState?

    /// Centralized responsive layout
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Whether to show the banner
    private var shouldShow: Bool {
        guard !isDismissed else { return false }
        switch connectionState {
        case .connecting, .reconnecting, .failed, .disconnected:
            return true
        case .connected:
            return false
        }
    }

    /// State-specific configuration
    private var stateConfig: (icon: String, color: Color, message: String, showProgress: Bool) {
        switch connectionState {
        case .disconnected:
            return ("wifi.slash", ColorSystem.warning, "Disconnected from agent", false)
        case .connecting:
            return ("antenna.radiowaves.left.and.right", ColorSystem.info, "Connecting...", true)
        case .reconnecting(let attempt):
            return (
                "arrow.triangle.2.circlepath",
                ColorSystem.warning,
                "Reconnecting... (\(attempt)/\(Constants.Network.maxReconnectAttempts))",
                true
            )
        case .failed(let reason):
            return ("exclamationmark.triangle.fill", ColorSystem.error, reason, false)
        case .connected:
            return ("checkmark.circle.fill", ColorSystem.success, "Connected", false)
        }
    }

    var body: some View {
        if shouldShow {
            VStack(spacing: 0) {
                // Main banner content
                HStack(spacing: Spacing.sm) {
                    // Animated status indicator
                    statusIndicator

                    // Message and details
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stateConfig.message)
                            .font(Typography.bodyBold)
                            .foregroundStyle(ColorSystem.textPrimary)
                            .lineLimit(1)

                        // Progress details for reconnecting
                        if case .reconnecting(let attempt) = connectionState {
                            HStack(spacing: 4) {
                                ProgressView(value: Double(attempt), total: Double(Constants.Network.maxReconnectAttempts))
                                    .tint(ColorSystem.warning)
                                    .frame(width: 60)

                                Text("~\(estimatedWaitTime(attempt: attempt))s")
                                    .font(Typography.terminalSmall)
                                    .foregroundStyle(ColorSystem.textTertiary)
                            }
                        }
                    }

                    Spacer()

                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal, layout.standardPadding)
                .padding(.vertical, Spacing.xs)
                .background(bannerBackground)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        withAnimation(Animations.stateChange) {
                            isExpanded.toggle()
                        }
                        Haptics.selection()
                    }
                )

                // Expanded details
                if isExpanded {
                    expandedDetails
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .shadow(color: stateConfig.color.opacity(0.2), radius: 4, y: 2)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(Animations.bannerTransition, value: connectionState)
            .onChange(of: connectionState) { oldState, newState in
                // Reset dismissed state when connection state changes
                if !areStatesEquivalent(oldState, newState) {
                    isDismissed = false
                }
                previousState = oldState
            }
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(stateConfig.color.opacity(0.2))
                .frame(width: layout.indicatorSize, height: layout.indicatorSize)
                .scaleEffect(pulseScale)

            // Progress ring for connecting/reconnecting
            if stateConfig.showProgress {
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                stateConfig.color.opacity(0.1),
                                stateConfig.color.opacity(0.5),
                                stateConfig.color
                            ]),
                            center: .center
                        ),
                        lineWidth: layout.borderWidthThick
                    )
                    .frame(width: layout.indicatorSize - 6, height: layout.indicatorSize - 6)
                    .rotationEffect(.degrees(rotationAngle))
            }

            // Icon
            Image(systemName: stateConfig.icon)
                .font(.system(size: layout.iconMedium, weight: .semibold))
                .foregroundStyle(stateConfig.color)
                .scaleEffect(stateConfig.showProgress ? 0.9 : 1.0)
        }
        .frame(width: layout.indicatorSize, height: layout.indicatorSize)
        .onAppear {
            startAnimations()
        }
        .onChange(of: stateConfig.showProgress) { _, showProgress in
            if showProgress {
                startAnimations()
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: Spacing.xs) {
            // Retry button (for disconnected or failed states)
            if case .disconnected = connectionState {
                retryButton
            } else if case .failed = connectionState {
                retryButton
            }

            // Cancel button (for connecting/reconnecting)
            if stateConfig.showProgress {
                Button {
                    onCancel()
                    Haptics.light()
                } label: {
                    Text("Cancel")
                        .font(Typography.caption1)
                        .foregroundStyle(ColorSystem.textSecondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                }
                .buttonStyle(.plain)
            }

            // Dismiss button
            Button {
                withAnimation(Animations.stateChange) {
                    isDismissed = true
                }
                Haptics.light()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var retryButton: some View {
        Button {
            onRetry()
            Haptics.medium()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: layout.iconSmall, weight: .bold))
                Text("Retry")
                    .font(layout.labelFont)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, layout.smallPadding / 2)
            .background(ColorSystem.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pressEffect()
    }

    // MARK: - Expanded Details

    @ViewBuilder
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            Divider()
                .background(ColorSystem.terminalBgHighlight)

            // Connection tips
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.warning)

                Text(connectionTip)
                    .font(layout.captionFont)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            // Features still available
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.success)

                Text("You can still browse cached data")
                    .font(layout.captionFont)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, layout.smallPadding)
        .background(ColorSystem.terminalBg.opacity(0.5))
    }

    // MARK: - Background

    private var bannerBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                stateConfig.color.opacity(0.15),
                stateConfig.color.opacity(0.08)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(stateConfig.color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var connectionTip: String {
        switch connectionState {
        case .disconnected:
            return "Check if cdev-agent is running on your machine"
        case .connecting:
            return "Establishing secure connection..."
        case .reconnecting:
            return "Connection will resume automatically"
        case .failed:
            return "Tap Retry to attempt connection again"
        case .connected:
            return "All systems operational"
        }
    }

    private func estimatedWaitTime(attempt: Int) -> Int {
        // Exponential backoff calculation
        let delay = min(
            Constants.Network.reconnectDelay * pow(2.0, Double(attempt - 1)),
            Constants.Network.maxReconnectDelay
        )
        return Int(delay)
    }

    private func startAnimations() {
        // Rotation animation for progress ring
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
        // Pulse animation for glow
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }

    /// Check if two states are equivalent (same case, ignoring associated values)
    private func areStatesEquivalent(_ state1: ConnectionState, _ state2: ConnectionState) -> Bool {
        switch (state1, state2) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting): return true
        case (.connected, .connected): return true
        case (.reconnecting, .reconnecting): return true
        case (.failed, .failed): return true
        default: return false
        }
    }
}

// MARK: - Connection Status Indicator (for StatusBar)

/// Compact, animated connection status indicator for the status bar
/// Shows different animations based on connection state
/// Responsive: Uses centralized ResponsiveLayout for iPhone/iPad adaptation
struct ConnectionStatusIndicator: View {
    let state: ConnectionState

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3

    /// Centralized responsive layout
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Configuration for each state
    private var config: (icon: String, color: Color, label: String, animate: Bool) {
        switch state {
        case .connected:
            return ("circle.fill", ColorSystem.success, "Online", false)
        case .connecting:
            return ("antenna.radiowaves.left.and.right", ColorSystem.info, "Connecting", true)
        case .reconnecting(let attempt):
            return ("arrow.triangle.2.circlepath", ColorSystem.warning, "Retry \(attempt)", true)
        case .disconnected:
            return ("wifi.slash", ColorSystem.textTertiary, "Offline", false)
        case .failed:
            return ("exclamationmark.triangle.fill", ColorSystem.error, "Failed", false)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            // Animated indicator
            ZStack {
                // Glow ring for connecting/reconnecting
                if config.animate {
                    Circle()
                        .stroke(config.color.opacity(glowOpacity), lineWidth: layout.borderWidth)
                        .frame(width: layout.indicatorSizeSmall, height: layout.indicatorSizeSmall)
                        .scaleEffect(pulseScale)

                    // Rotating arc
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(config.color, lineWidth: layout.borderWidth)
                        .frame(width: layout.indicatorSizeSmall, height: layout.indicatorSizeSmall)
                        .rotationEffect(.degrees(rotationAngle))
                }

                // Icon or dot
                if state.isConnected {
                    Circle()
                        .fill(config.color)
                        .frame(width: layout.dotSize, height: layout.dotSize)
                        .shadow(color: config.color.opacity(0.5), radius: 2)
                } else if config.animate {
                    // Small center dot during animation
                    Circle()
                        .fill(config.color)
                        .frame(width: layout.dotSize - 2, height: layout.dotSize - 2)
                } else {
                    // Icon for disconnected/failed
                    Image(systemName: config.icon)
                        .font(.system(size: layout.iconSmall, weight: .semibold))
                        .foregroundStyle(config.color)
                }
            }
            .frame(width: layout.indicatorSizeSmall + 2, height: layout.indicatorSizeSmall + 2)

            // Status label
            Text(config.label)
                .font(Typography.statusLabel)
                .foregroundStyle(config.color)
        }
        .onAppear {
            if config.animate {
                startAnimations()
            }
        }
        .onChange(of: state) { _, _ in
            if config.animate {
                startAnimations()
            } else {
                // Reset animations
                rotationAngle = 0
                pulseScale = 1.0
                glowOpacity = 0.3
            }
        }
    }

    private func startAnimations() {
        // Rotation
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
        // Pulse
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.3
            glowOpacity = 0.6
        }
    }
}

// MARK: - Reconnection Toast

/// Toast notification shown when connection is restored
/// Responsive: Uses centralized ResponsiveLayout for iPhone/iPad adaptation
struct ReconnectedToast: View {
    @Binding var isPresented: Bool
    let message: String

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var offset: CGFloat = -100

    /// Centralized responsive layout
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        if isPresented {
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: layout.iconLarge))
                    .foregroundStyle(ColorSystem.success)

                Text(message)
                    .font(layout.bodyFont)
                    .foregroundStyle(ColorSystem.textPrimary)
            }
            .padding(.horizontal, layout.largePadding)
            .padding(.vertical, layout.standardPadding)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .fill(ColorSystem.terminalBgElevated)
                    .shadow(color: ColorSystem.successGlow, radius: layout.shadowRadiusLarge)
            )
            .offset(y: offset)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    offset = 0
                }
                // Auto-dismiss after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    dismiss()
                }
            }
            .onTapGesture {
                dismiss()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            offset = -100
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ConnectionBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Spacing.md) {
            ConnectionBanner(
                connectionState: .disconnected,
                onRetry: {},
                onCancel: {}
            )

            ConnectionBanner(
                connectionState: .connecting,
                onRetry: {},
                onCancel: {}
            )

            ConnectionBanner(
                connectionState: .reconnecting(attempt: 3),
                onRetry: {},
                onCancel: {}
            )

            ConnectionBanner(
                connectionState: .failed(reason: "Connection refused"),
                onRetry: {},
                onCancel: {}
            )
        }
        .padding()
        .background(ColorSystem.terminalBg)
    }
}
#endif
