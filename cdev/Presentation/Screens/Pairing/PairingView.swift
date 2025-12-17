import SwiftUI
import AVFoundation

/// QR Code pairing view - scan to connect
struct PairingView: View {
    @StateObject var viewModel: PairingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                // Instructions
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.primaryBlue)

                    Text("Scan QR Code")
                        .font(Typography.title2)

                    Text("Point your camera at the QR code displayed by cdev-agent")
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Spacing.xl)

                // Scanner
                if viewModel.hasCameraPermission {
                    QRScannerView(onCodeScanned: { code in
                        Task {
                            await viewModel.handleScannedCode(code)
                        }
                    })
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.large)
                            .stroke(Color.primaryBlue, lineWidth: 2)
                    )
                    .frame(height: 280)
                    .padding(.horizontal, Spacing.lg)
                } else {
                    CameraPermissionView(onRequest: {
                        viewModel.requestCameraPermission()
                    })
                    .frame(height: 280)
                    .padding(.horizontal, Spacing.lg)
                }

                // Manual entry option
                VStack(spacing: Spacing.sm) {
                    Text("Or enter manually")
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)

                    HStack(spacing: Spacing.sm) {
                        TextField("ws://192.168.1.x:8765", text: $viewModel.manualURL)
                            .font(Typography.code)
                            .textFieldStyle(.plain)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(Spacing.sm)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

                        Button {
                            Task {
                                await viewModel.connectManually()
                            }
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.primaryBlue)
                        }
                        .disabled(viewModel.manualURL.isBlank)
                    }
                    .padding(.horizontal, Spacing.lg)
                }

                Spacer()

                // Status
                if viewModel.isConnecting {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("Connecting...")
                            .font(Typography.callout)
                    }
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.isConnected) { _, connected in
                if connected {
                    dismiss()
                }
            }
            .errorAlert($viewModel.error)
        }
    }
}

// MARK: - Camera Permission View

struct CameraPermissionView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(Typography.bodyBold)

            Text("Allow camera access to scan QR codes")
                .font(Typography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Allow Camera") {
                onRequest()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
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

    override func viewDidLoad() {
        super.viewDidLoad()
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

        // Vibrate and stop scanning
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        stopScanning()

        onCodeScanned?(code)
    }
}
