import SwiftUI
import AVFoundation

// MARK: - Pairing View (Redesigned)

/// QR Code pairing view - Pulse Terminal Design System
/// Sophisticated, responsive, theme-aware UI for connecting to cdev-agent
struct PairingView: View {
    @StateObject var viewModel: PairingViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Adaptive layout for iPad
    private var isCompact: Bool {
        sizeClass == .compact
    }

    /// Dismiss keyboard
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background - tap to dismiss keyboard
                ColorSystem.terminalBg
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissKeyboard()
                    }

                // Content
                if isCompact {
                    // iPhone: Vertical stack
                    compactLayout
                } else {
                    // iPad: Side-by-side
                    regularLayout
                }

                // Connecting overlay
                if viewModel.isConnecting {
                    ConnectingOverlay()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(Typography.buttonLabel)
                            .foregroundStyle(ColorSystem.textSecondary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "link")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ColorSystem.primary)
                        Text("Connect")
                            .font(Typography.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(ColorSystem.textPrimary)
                    }
                }
            }
            .toolbarBackground(ColorSystem.terminalBgElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: viewModel.isConnected) { _, connected in
                if connected {
                    Haptics.success()
                    dismiss()
                }
            }
            .errorAlert($viewModel.error)
            .alert("QR Code Expired", isPresented: $viewModel.showTokenExpiredAlert) {
                Button("Scan Again") {
                    viewModel.dismissTokenExpiredAlert()
                }
            } message: {
                Text(viewModel.tokenExpiredMessage)
            }
        }
    }

    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header
                PairingHeaderView()
                    .padding(.top, Spacing.md)

                // Scanner section
                ScannerSectionView(
                    hasCameraPermission: viewModel.hasCameraPermission,
                    onCodeScanned: { code in
                        Task { await viewModel.handleScannedCode(code) }
                    },
                    onRequestPermission: {
                        viewModel.requestCameraPermission()
                    }
                )
                .padding(.horizontal, Spacing.md)

                // Divider with text
                DividerWithLabel(text: "or enter manually")
                    .padding(.horizontal, Spacing.lg)

                // Manual entry
                ManualEntryView(
                    url: $viewModel.manualURL,
                    onConnect: {
                        Task { await viewModel.connectManually() }
                    }
                )
                .padding(.horizontal, Spacing.md)

                // Future: Recent connections placeholder
                RecentConnectionsView()
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)

                Spacer(minLength: Spacing.xl)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded { dismissKeyboard() }
            )
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Regular Layout (iPad)

    private var regularLayout: some View {
        HStack(spacing: 0) {
            // Left: Scanner
            VStack(spacing: Spacing.lg) {
                PairingHeaderView()
                    .padding(.top, Spacing.lg)

                ScannerSectionView(
                    hasCameraPermission: viewModel.hasCameraPermission,
                    onCodeScanned: { code in
                        Task { await viewModel.handleScannedCode(code) }
                    },
                    onRequestPermission: {
                        viewModel.requestCameraPermission()
                    }
                )
                .padding(.horizontal, Spacing.lg)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(ColorSystem.terminalBg)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded { dismissKeyboard() }
            )

            // Divider
            Rectangle()
                .fill(ColorSystem.terminalBgHighlight)
                .frame(width: 1)

            // Right: Manual entry + Recent
            VStack(spacing: Spacing.lg) {
                Spacer()

                // Manual entry section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorSystem.primary)
                        Text("Manual Connection")
                            .font(Typography.bodyBold)
                            .foregroundStyle(ColorSystem.textPrimary)
                    }

                    ManualEntryView(
                        url: $viewModel.manualURL,
                        onConnect: {
                            Task { await viewModel.connectManually() }
                        }
                    )
                }
                .padding(.horizontal, Spacing.lg)

                // Recent connections
                RecentConnectionsView()
                    .padding(.horizontal, Spacing.lg)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(ColorSystem.terminalBgElevated)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded { dismissKeyboard() }
            )
        }
    }
}

// MARK: - Header View

private struct PairingHeaderView: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Icon with glow effect
            ZStack {
                // Glow
                Circle()
                    .fill(ColorSystem.primaryGlow)
                    .frame(width: 80, height: 80)
                    .blur(radius: 20)

                // Icon
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(ColorSystem.primary)
            }

            VStack(spacing: Spacing.xxs) {
                Text("Scan QR Code")
                    .font(Typography.title2)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("Point camera at QR code from cdev-agent")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Scanner Section

private struct ScannerSectionView: View {
    let hasCameraPermission: Bool
    let onCodeScanned: (String) -> Void
    let onRequestPermission: () -> Void

    var body: some View {
        if hasCameraPermission {
            // Camera preview with overlay
            QRScannerView(onCodeScanned: onCodeScanned)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                .overlay {
                    // Scanner frame overlay - same size as camera
                    ScannerFrameOverlay()
                }
                .frame(maxHeight: 320)
        } else {
            // Permission request
            CameraPermissionView(onRequest: onRequestPermission)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: 320)
        }
    }
}

// MARK: - Scanner Frame Overlay

private struct ScannerFrameOverlay: View {
    @State private var isAnimating = false

    // Inset from edges for corner brackets
    private let inset: CGFloat = 24
    private let bracketSize: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Semi-transparent overlay
                Rectangle()
                    .fill(ColorSystem.terminalBg.opacity(0.2))

                // Animated scan line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorSystem.primary.opacity(0),
                                ColorSystem.primary.opacity(0.8),
                                ColorSystem.primary.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .offset(y: isAnimating ? height / 3 : -height / 3)
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: isAnimating
                    )

                // Corner brackets - positioned at actual corners
                // Top-left
                CornerBracket()
                    .position(x: inset + bracketSize / 2, y: inset + bracketSize / 2)

                // Top-right
                CornerBracket()
                    .rotationEffect(.degrees(90))
                    .position(x: width - inset - bracketSize / 2, y: inset + bracketSize / 2)

                // Bottom-left
                CornerBracket()
                    .rotationEffect(.degrees(-90))
                    .position(x: inset + bracketSize / 2, y: height - inset - bracketSize / 2)

                // Bottom-right
                CornerBracket()
                    .rotationEffect(.degrees(180))
                    .position(x: width - inset - bracketSize / 2, y: height - inset - bracketSize / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(ColorSystem.primary.opacity(0.4), lineWidth: 1)
            )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Corner Bracket

private struct CornerBracket: View {
    private let length: CGFloat = 28
    private let thickness: CGFloat = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Horizontal line (top)
            Rectangle()
                .fill(ColorSystem.primary)
                .frame(width: length, height: thickness)

            // Vertical line (left)
            Rectangle()
                .fill(ColorSystem.primary)
                .frame(width: thickness, height: length)
        }
        .frame(width: length, height: length)
        .shadow(color: ColorSystem.primaryGlow, radius: 6)
    }
}

// MARK: - Camera Permission View

private struct CameraPermissionView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(ColorSystem.terminalBgHighlight)
                    .frame(width: 80, height: 80)

                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            VStack(spacing: Spacing.xxs) {
                Text("Camera Access Required")
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("Allow camera to scan QR codes")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)
            }

            Button {
                onRequest()
                Haptics.light()
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "camera")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Enable Camera")
                        .font(Typography.buttonLabel)
                }
                .foregroundStyle(ColorSystem.terminalBg)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(ColorSystem.primary)
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(ColorSystem.terminalBgHighlight, lineWidth: 1)
        )
    }
}

// MARK: - Divider with Label

private struct DividerWithLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Rectangle()
                .fill(ColorSystem.terminalBgHighlight)
                .frame(height: 1)

            Text(text)
                .font(Typography.caption2)
                .foregroundStyle(ColorSystem.textTertiary)

            Rectangle()
                .fill(ColorSystem.terminalBgHighlight)
                .frame(height: 1)
        }
    }
}

// MARK: - Manual Entry View

private struct ManualEntryView: View {
    @Binding var url: String
    let onConnect: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Label
            Text("WebSocket URL")
                .font(Typography.caption2)
                .foregroundStyle(ColorSystem.textTertiary)

            // Input row
            HStack(spacing: Spacing.sm) {
                // Protocol badge
                Text("ws://")
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.primary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(ColorSystem.primary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

                // URL input
                TextField("192.168.1.x:8765", text: $url)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .focused($isFocused)

                // Connect button
                Button {
                    onConnect()
                    Haptics.light()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(url.isBlank ? ColorSystem.textQuaternary : ColorSystem.primary)
                }
                .disabled(url.isBlank)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(
                        isFocused ? ColorSystem.primary.opacity(0.5) : ColorSystem.terminalBgSelected,
                        lineWidth: 1
                    )
            )

            // Help text
            Text("Enter the WebSocket address shown by cdev-agent")
                .font(Typography.caption2)
                .foregroundStyle(ColorSystem.textQuaternary)
        }
    }
}

// MARK: - Recent Connections View (Future: Multi-repo)

private struct RecentConnectionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(ColorSystem.textTertiary)
                Text("Recent")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textTertiary)

                Spacer()

                // Future: "Manage" button for multi-repo
                // Button("Manage") { }
                //     .font(Typography.caption2)
                //     .foregroundStyle(ColorSystem.primary)
            }

            // Empty state (future: list of recent connections)
            HStack(spacing: Spacing.xs) {
                Image(systemName: "tray")
                    .font(.system(size: 10))
                    .foregroundStyle(ColorSystem.textQuaternary)
                Text("No recent connections")
                    .font(Typography.caption2)
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(ColorSystem.terminalBgHighlight.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
    }
}

// MARK: - Connecting Overlay

private struct ConnectingOverlay: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Dimmed background
            ColorSystem.terminalBg.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
                // Animated ring
                ZStack {
                    Circle()
                        .stroke(ColorSystem.terminalBgHighlight, lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(ColorSystem.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(rotation))
                }

                VStack(spacing: Spacing.xxs) {
                    Text("Connecting")
                        .font(Typography.bodyBold)
                        .foregroundStyle(ColorSystem.textPrimary)

                    Text("Establishing secure connection...")
                        .font(Typography.caption1)
                        .foregroundStyle(ColorSystem.textSecondary)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - QR Scanner View (UIKit wrapper)

struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastScannedCode: String?
    private var lastScanTime: Date?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(ColorSystem.terminalBg)
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        self.captureSession = session
        self.previewLayer = previewLayer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func startScanning() {
        lastScannedCode = nil
        lastScanTime = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func stopScanning() {
        captureSession?.stopRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let code = object.stringValue else {
            return
        }

        // Debounce: prevent rapid repeated scans of same code
        let now = Date()
        if let lastCode = lastScannedCode,
           let lastTime = lastScanTime,
           lastCode == code,
           now.timeIntervalSince(lastTime) < 2.0 {
            return
        }

        lastScannedCode = code
        lastScanTime = now

        // Haptic feedback and stop scanning
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        stopScanning()

        onCodeScanned?(code)
    }
}

// MARK: - Preview

// Preview disabled - requires full DI container initialization
// To preview, run the app and navigate to the pairing screen
