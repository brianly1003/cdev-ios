import SwiftUI
import AVFoundation

// MARK: - Manager Setup View

/// Setup sheet for connecting to a workspace manager
/// Supports QR code scanning and manual IP entry - reuses PairingView's sophisticated UI
struct ManagerSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Callback when user enters a host to connect (host, optional token)
    let onConnect: (String, String?) -> Void

    // State
    @State private var hostInput: String = ""
    @State private var tokenInput: String? = nil  // Auth token from QR code
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var hasCameraPermission: Bool = false
    @State private var isConnecting: Bool = false
    @State private var clipboardHost: String? = nil

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }
    private var isCompact: Bool { sizeClass == .compact }

    // UserDefaults key for last host
    private static let lastHostKey = "cdev.manager.lastHost"

    /// Dismiss keyboard
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorSystem.terminalBg
                    .ignoresSafeArea()

                // Content - keyboard dismissal handled via simultaneousGesture in layouts
                if isCompact {
                    compactLayout
                } else {
                    regularLayout
                }

                // Connecting overlay
                if isConnecting {
                    ManagerConnectingOverlay()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(ColorSystem.textSecondary)
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "laptopcomputer.and.iphone")
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
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                checkCameraPermission()
                checkClipboard()
                loadLastHost()
            }
        }
    }

    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Header text (no icon)
                    VStack(spacing: Spacing.xs) {
                        Text("Connect to Workspaces")
                            .font(Typography.title2)
                            .foregroundStyle(ColorSystem.textPrimary)

                        Text("Scan QR or enter your laptop's IP address")
                            .font(Typography.caption1)
                            .foregroundStyle(ColorSystem.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Spacing.sm)

                    // Scanner section
                    ManagerScannerSection(
                        hasCameraPermission: hasCameraPermission,
                        onCodeScanned: { code in
                            handleScannedCode(code)
                        },
                        onRequestPermission: {
                            requestCameraPermission()
                        }
                    )
                    .padding(.horizontal, Spacing.md)

                    // Divider
                    ManagerDivider(text: "or enter manually")
                        .padding(.horizontal, Spacing.lg)

                    // Clipboard paste (if valid URL detected)
                    if let clipboardHost = clipboardHost {
                        ClipboardPasteButton(host: clipboardHost) {
                            hostInput = clipboardHost
                            connectWithHost()
                        }
                        .padding(.horizontal, Spacing.md)
                    }

                    // Manual entry
                    ManagerManualEntry(
                        host: $hostInput,
                        onConnect: {
                            connectWithHost()
                        },
                        onFocusChange: { isFocused in
                            if isFocused {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo("manualEntry", anchor: .center)
                                }
                            }
                        }
                    )
                    .id("manualEntry")
                    .padding(.horizontal, Spacing.md)

                    // Help text
                    ManagerHelpText()
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)

                    // Extra bottom padding for keyboard
                    Spacer(minLength: 200)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { dismissKeyboard() }
                )
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Regular Layout (iPad)

    private var regularLayout: some View {
        HStack(spacing: 0) {
            // Left: Scanner
            VStack(spacing: Spacing.lg) {
                // Header text (no icon)
                VStack(spacing: Spacing.xs) {
                    Text("Connect to Workspaces")
                        .font(Typography.title2)
                        .foregroundStyle(ColorSystem.textPrimary)

                    Text("Scan QR or enter your laptop's IP address")
                        .font(Typography.caption1)
                        .foregroundStyle(ColorSystem.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Spacing.lg)

                ManagerScannerSection(
                    hasCameraPermission: hasCameraPermission,
                    onCodeScanned: { code in
                        handleScannedCode(code)
                    },
                    onRequestPermission: {
                        requestCameraPermission()
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

            // Right: Manual entry
            VStack(spacing: Spacing.lg) {
                Spacer()

                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorSystem.primary)
                        Text("Manual Connection")
                            .font(Typography.bodyBold)
                            .foregroundStyle(ColorSystem.textPrimary)
                    }

                    // Clipboard paste (if valid URL detected)
                    if let clipboardHost = clipboardHost {
                        ClipboardPasteButton(host: clipboardHost) {
                            hostInput = clipboardHost
                            connectWithHost()
                        }
                    }

                    ManagerManualEntry(
                        host: $hostInput,
                        onConnect: {
                            connectWithHost()
                        }
                    )
                }
                .padding(.horizontal, Spacing.lg)

                ManagerHelpText()
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

    // MARK: - Last Host Persistence

    private func loadLastHost() {
        if let savedHost = UserDefaults.standard.string(forKey: Self.lastHostKey), !savedHost.isEmpty {
            hostInput = savedHost
        }
    }

    private func saveLastHost(_ host: String) {
        UserDefaults.standard.set(host, forKey: Self.lastHostKey)
    }

    // MARK: - Clipboard Detection

    private func checkClipboard() {
        guard let clipboardString = UIPasteboard.general.string else { return }

        // Try to extract a valid host from clipboard
        if let host = extractHost(from: clipboardString) {
            clipboardHost = host
        }
    }

    /// Extract valid host from various URL formats
    private func extractHost(from text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip URL schemes
        let schemes = ["https://", "http://", "wss://", "ws://", "cdev-manager://"]
        for scheme in schemes {
            if host.hasPrefix(scheme) {
                host = String(host.dropFirst(scheme.count))
                break
            }
        }

        // Remove path components
        if let slashIndex = host.firstIndex(of: "/") {
            host = String(host[..<slashIndex])
        }

        // Remove default port suffix
        if host.hasSuffix(":8765") {
            host = String(host.dropLast(":8765".count))
        }

        // Validate
        guard !host.isEmpty && isValidHost(host) else { return nil }

        return host
    }

    // MARK: - Camera Permission

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraPermission = true
        case .notDetermined:
            // Auto-request permission like PairingView does
            requestCameraPermission()
        case .denied, .restricted:
            hasCameraPermission = false
        @unknown default:
            hasCameraPermission = false
        }
    }

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                hasCameraPermission = granted
                if !granted {
                    errorMessage = "Camera access is required to scan QR codes. You can enable it in Settings or enter IP manually."
                    showError = true
                }
            }
        }
    }

    // MARK: - QR Code Handling

    private func handleScannedCode(_ code: String) {
        // Extract host from QR code
        // Supported formats:
        // 1. JSON PairingInfo: {"ws":"ws://host:8766/ws","http":"...","session":"...","repo":"..."}
        // 2. Plain IP: "192.168.1.100"
        // 3. Host:port: "192.168.1.100:8766"
        // 4. URL format: "cdev-manager://192.168.1.100:8766"
        // 5. WebSocket URL: "ws://192.168.1.100:8766/ws"

        var host: String?
        var token: String?

        // First, try to parse as JSON (PairingInfo format from cdev server)
        if let jsonData = code.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let wsURLString = json["ws"] as? String,
           let wsURL = URL(string: wsURLString),
           let wsHost = wsURL.host {
            // Extract just the host (without port) - port will be added by connect function
            // For dev tunnels, the full hostname is used (e.g., abc123x4-8766.devtunnels.ms)
            host = wsHost
            // Extract auth token if present
            token = json["token"] as? String
            AppLogger.log("[ManagerSetup] Parsed JSON QR code, host: \(host ?? "nil"), token: \(token != nil ? "present" : "none")")
        }

        // If not JSON, try plain URL/host formats
        if host == nil {
            var rawHost = code.trimmingCharacters(in: .whitespacesAndNewlines)

            // Strip URL schemes
            let schemes = ["cdev-manager://", "wss://", "ws://", "https://", "http://"]
            for scheme in schemes {
                if rawHost.hasPrefix(scheme) {
                    rawHost = String(rawHost.dropFirst(scheme.count))
                    break
                }
            }

            // Remove path components (keep only host:port)
            if let slashIndex = rawHost.firstIndex(of: "/") {
                rawHost = String(rawHost[..<slashIndex])
            }

            // Remove default ports
            if rawHost.hasSuffix(":8765") {
                rawHost = String(rawHost.dropLast(":8765".count))
            } else if rawHost.hasSuffix(":8766") {
                rawHost = String(rawHost.dropLast(":8766".count))
            }

            host = rawHost
        }

        // Validate
        guard let finalHost = host, isValidHost(finalHost) else {
            errorMessage = "Invalid QR code. Please scan the QR code from cdev-agent."
            showError = true
            return
        }

        // Connect - store token for connection
        Haptics.success()
        hostInput = finalHost
        tokenInput = token  // Store the extracted token
        connectWithHost()
    }

    // MARK: - Connect

    private func connectWithHost() {
        var host = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty else { return }

        // Strip URL schemes (same logic as QR code handling)
        if host.hasPrefix("https://") {
            host = String(host.dropFirst("https://".count))
        } else if host.hasPrefix("http://") {
            host = String(host.dropFirst("http://".count))
        } else if host.hasPrefix("wss://") {
            host = String(host.dropFirst("wss://".count))
        } else if host.hasPrefix("ws://") {
            host = String(host.dropFirst("ws://".count))
        } else if host.hasPrefix("cdev-manager://") {
            host = String(host.dropFirst("cdev-manager://".count))
        }

        // Remove path components (keep only host:port)
        if let slashIndex = host.firstIndex(of: "/") {
            host = String(host[..<slashIndex])
        }

        // Extract port if present (for dev tunnels, port is in subdomain like abc123x4-8765)
        // Don't strip port from hostname for tunnels, only strip default :8765 suffix
        if host.hasSuffix(":8765") {
            host = String(host.dropLast(":8765".count))
        }

        guard isValidHost(host) else {
            errorMessage = "Please enter a valid IP address or hostname"
            showError = true
            return
        }

        // Save for next time
        saveLastHost(host)

        Haptics.medium()
        onConnect(host, tokenInput)  // Pass both host and token
        dismiss()
    }

    private func isValidHost(_ host: String) -> Bool {
        // Split off port if present
        let hostWithoutPort: String
        if let colonIndex = host.lastIndex(of: ":"),
           let portPart = Int(host[host.index(after: colonIndex)...]),
           portPart > 0 && portPart <= 65535 {
            hostWithoutPort = String(host[..<colonIndex])
        } else {
            hostWithoutPort = host
        }

        // IP address pattern
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#

        // Hostname pattern - allows subdomains with numbers and hyphens (e.g., abc123x4-8765.asse.devtunnels.ms)
        let hostnamePattern = #"^[a-zA-Z0-9][a-zA-Z0-9-]*(\.[a-zA-Z0-9][a-zA-Z0-9-]*)*$"#

        let ipRegex = try? NSRegularExpression(pattern: ipPattern)
        let hostnameRegex = try? NSRegularExpression(pattern: hostnamePattern)

        let range = NSRange(hostWithoutPort.startIndex..., in: hostWithoutPort)

        return ipRegex?.firstMatch(in: hostWithoutPort, range: range) != nil ||
               hostnameRegex?.firstMatch(in: hostWithoutPort, range: range) != nil ||
               hostWithoutPort == "localhost"
    }
}

// MARK: - Manager Header View

private struct ManagerHeaderView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            // Icon with glow effect
            ZStack {
                Circle()
                    .fill(ColorSystem.primaryGlow)
                    .frame(width: 80, height: 80)
                    .blur(radius: 20)

                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(ColorSystem.primary)
            }

            VStack(spacing: Spacing.xs) {
                Text("Scan QR Code")
                    .font(Typography.title2)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("Scan the manager QR from your laptop")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
            }
        }
    }
}

// MARK: - Manager Scanner Section

private struct ManagerScannerSection: View {
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
                    ManagerScannerFrameOverlay()
                }
                .frame(maxHeight: 320)
        } else {
            // Permission request
            ManagerCameraPermissionView(onRequest: onRequestPermission)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: 320)
        }
    }
}

// MARK: - Scanner Frame Overlay

private struct ManagerScannerFrameOverlay: View {
    @State private var isAnimating = false

    private let inset: CGFloat = 24
    private let bracketSize: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
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

                // Corner brackets
                ManagerCornerBracket()
                    .position(x: inset + bracketSize / 2, y: inset + bracketSize / 2)

                ManagerCornerBracket()
                    .rotationEffect(.degrees(90))
                    .position(x: width - inset - bracketSize / 2, y: inset + bracketSize / 2)

                ManagerCornerBracket()
                    .rotationEffect(.degrees(-90))
                    .position(x: inset + bracketSize / 2, y: height - inset - bracketSize / 2)

                ManagerCornerBracket()
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

private struct ManagerCornerBracket: View {
    private let length: CGFloat = 28
    private let thickness: CGFloat = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(ColorSystem.primary)
                .frame(width: length, height: thickness)

            Rectangle()
                .fill(ColorSystem.primary)
                .frame(width: thickness, height: length)
        }
        .frame(width: length, height: length)
        .shadow(color: ColorSystem.primaryGlow, radius: 6)
    }
}

// MARK: - Camera Permission View

private struct ManagerCameraPermissionView: View {
    let onRequest: () -> Void

    private var isDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .denied
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(ColorSystem.terminalBgHighlight)
                    .frame(width: 80, height: 80)

                Image(systemName: isDenied ? "camera.badge.ellipsis" : "camera.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            VStack(spacing: Spacing.xxs) {
                Text("Camera Access Required")
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text(isDenied ? "Enable camera in Settings to scan QR codes" : "Allow camera to scan QR codes")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if isDenied {
                Button {
                    // Open app settings
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    Haptics.light()
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "gear")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Open Settings")
                            .font(Typography.buttonLabel)
                    }
                    .foregroundStyle(ColorSystem.terminalBg)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(ColorSystem.primary)
                    .clipShape(Capsule())
                }
            } else {
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

// MARK: - Divider

private struct ManagerDivider: View {
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

private struct ManagerManualEntry: View {
    @Binding var host: String
    let onConnect: () -> Void
    var onFocusChange: ((Bool) -> Void)? = nil
    @FocusState private var isFocused: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.tightSpacing) {
            Text("IP Address / Hostname")
                .font(layout.captionFont)
                .foregroundStyle(ColorSystem.textTertiary)

            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "network")
                    .font(.system(size: layout.iconMedium))
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("192.168.1.100 or domain.com", text: $host)
                    .font(layout.terminalFont)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .focused($isFocused)
                    .submitLabel(.go)
                    .onSubmit {
                        onConnect()
                    }

                // Clear button
                if !host.isEmpty {
                    Button {
                        host = ""
                        Haptics.light()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: layout.iconLarge))
                            .foregroundStyle(ColorSystem.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                // Connect button
                Button {
                    onConnect()
                    Haptics.light()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: layout.iconXLarge))
                        .foregroundStyle(host.isEmpty ? ColorSystem.textQuaternary : ColorSystem.primary)
                }
                .disabled(host.isEmpty)
            }
            .padding(.horizontal, layout.smallPadding)
            .padding(.vertical, layout.smallPadding)
            .frame(minHeight: layout.inputHeight)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(
                        isFocused ? ColorSystem.primary.opacity(0.5) : ColorSystem.terminalBgSelected,
                        lineWidth: layout.borderWidth
                    )
            )

            Text("Enter the IP address or hostname of your laptop")
                .font(Typography.caption2)
                .foregroundStyle(ColorSystem.textQuaternary)
        }
        .onChange(of: isFocused) { _, newValue in
            onFocusChange?(newValue)
        }
    }
}

// MARK: - Clipboard Paste Button

private struct ClipboardPasteButton: View {
    let host: String
    let onPaste: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        Button {
            Haptics.medium()
            onPaste()
        } label: {
            HStack(spacing: layout.contentSpacing) {
                // Clipboard icon with glow
                ZStack {
                    Circle()
                        .fill(ColorSystem.primary.opacity(0.15))
                        .frame(width: layout.avatarSize, height: layout.avatarSize)

                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: layout.iconLarge))
                        .foregroundStyle(ColorSystem.primary)
                }

                // Host preview
                VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                    Text("Paste & Connect")
                        .font(layout.labelFont)
                        .fontWeight(.semibold)
                        .foregroundStyle(ColorSystem.textPrimary)

                    Text(truncatedHost)
                        .font(layout.terminalFont)
                        .foregroundStyle(ColorSystem.primary)
                        .lineLimit(1)
                }

                Spacer()

                // Arrow indicator
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: layout.iconXLarge))
                    .foregroundStyle(ColorSystem.primary)
            }
            .padding(.horizontal, layout.smallPadding)
            .padding(.vertical, layout.smallPadding)
            .background(ColorSystem.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(ColorSystem.primary.opacity(0.3), lineWidth: layout.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var truncatedHost: String {
        let maxLength = layout.isCompact ? 30 : 45
        if host.count > maxLength {
            let start = host.prefix(maxLength / 2)
            let end = host.suffix(maxLength / 3)
            return "\(start)...\(end)"
        }
        return host
    }
}

// MARK: - Help Text

private struct ManagerHelpText: View {
    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text("Start cdev agent on your laptop first")
                .font(Typography.caption1)
                .foregroundStyle(ColorSystem.textSecondary)
                .multilineTextAlignment(.center)

            Text("cdev start")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textTertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(ColorSystem.terminalBgElevated)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
        .padding(.bottom, Spacing.xl)
    }
}

// MARK: - Connecting Overlay

private struct ManagerConnectingOverlay: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            ColorSystem.terminalBg.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
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

                    Text("Connecting to workspace manager...")
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

// MARK: - Preview

#Preview {
    ManagerSetupView { host, token in
        print("Connect to: \(host), token: \(token != nil ? "present" : "none")")
    }
}
