import SwiftUI

// MARK: - Toolkit Item Protocol

/// Protocol for toolkit items - implement this to create custom tools
protocol ToolkitItemProtocol: Identifiable {
    var id: String { get }
    var icon: String { get }
    var label: String { get }
    var color: Color { get }
    func execute()
}

// MARK: - Standard Toolkit Item

/// Standard toolkit item - simple struct for quick tool creation
struct ToolkitItem: ToolkitItemProtocol {
    let id: String
    let icon: String
    let label: String
    let color: Color
    private let action: () -> Void

    init(
        id: String,
        icon: String,
        label: String,
        color: Color = ColorSystem.primary,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.icon = icon
        self.label = label
        self.color = color
        self.action = action
    }

    func execute() {
        action()
    }
}

// MARK: - Predefined Tools (Easy Extension Point)

/// Predefined toolkit tools - Add new cases here to extend the toolkit
/// Each tool defines its own icon, label, color, and can be easily added to any toolkit
enum PredefinedTool {
    case debugLogs(action: () -> Void)
    case refresh(action: () -> Void)
    case copySessionId(sessionId: String?)
    case clearLogs(action: () -> Void)
    case settings(action: () -> Void)
    case reconnect(action: () -> Void)
    case stopClaude(action: () -> Void)
    case newSession(action: () -> Void)

    /// Convert to ToolkitItem
    var item: ToolkitItem {
        switch self {
        case .debugLogs(let action):
            return ToolkitItem(
                id: "debug",
                icon: "ladybug.fill",
                label: "Debug",
                color: ColorSystem.warning,
                action: action
            )

        case .refresh(let action):
            return ToolkitItem(
                id: "refresh",
                icon: "arrow.clockwise",
                label: "Refresh",
                color: ColorSystem.primary,
                action: action
            )

        case .copySessionId(let sessionId):
            return ToolkitItem(
                id: "copy",
                icon: "doc.on.doc",
                label: "Copy ID",
                color: ColorSystem.accent
            ) {
                if let id = sessionId, !id.isEmpty {
                    UIPasteboard.general.string = id
                    Haptics.success()
                } else {
                    Haptics.error()
                }
            }

        case .clearLogs(let action):
            return ToolkitItem(
                id: "clear",
                icon: "trash",
                label: "Clear",
                color: ColorSystem.error,
                action: action
            )

        case .settings(let action):
            return ToolkitItem(
                id: "settings",
                icon: "gearshape.fill",
                label: "Settings",
                color: ColorSystem.textSecondary,
                action: action
            )

        case .reconnect(let action):
            return ToolkitItem(
                id: "reconnect",
                icon: "wifi.exclamationmark",
                label: "Reconnect",
                color: ColorSystem.info,
                action: action
            )

        case .stopClaude(let action):
            return ToolkitItem(
                id: "stop",
                icon: "stop.fill",
                label: "Stop",
                color: ColorSystem.error,
                action: action
            )

        case .newSession(let action):
            return ToolkitItem(
                id: "new",
                icon: "plus.circle.fill",
                label: "New",
                color: ColorSystem.success,
                action: action
            )
        }
    }
}

// MARK: - Toolkit Builder (Fluent API)

/// Builder for creating toolkit configurations with fluent API
/// Usage:
/// ```
/// ToolkitBuilder()
///     .add(.debugLogs { showDebug = true })
///     .add(.refresh { refresh() })
///     .addCustom(id: "custom", icon: "star", label: "Custom") { doSomething() }
///     .build()
/// ```
final class ToolkitBuilder {
    private var items: [ToolkitItem] = []

    /// Add a predefined tool
    @discardableResult
    func add(_ tool: PredefinedTool) -> ToolkitBuilder {
        items.append(tool.item)
        return self
    }

    /// Add a custom tool with minimal parameters
    @discardableResult
    func addCustom(
        id: String,
        icon: String,
        label: String,
        color: Color = ColorSystem.primary,
        action: @escaping () -> Void
    ) -> ToolkitBuilder {
        items.append(ToolkitItem(id: id, icon: icon, label: label, color: color, action: action))
        return self
    }

    /// Build the final toolkit items array
    func build() -> [ToolkitItem] {
        return items
    }
}

// MARK: - Floating Toolkit Button

/// AssistiveTouch-style floating button with expandable toolkit menu
/// Draggable, remembers position, compact design
/// Automatically hides when keyboard is visible
struct FloatingToolkitButton: View {
    let items: [ToolkitItem]

    @State private var isExpanded = false
    @State private var position: CGPoint = .zero
    @State private var isKeyboardVisible = false

    // Drag state - GestureState for smooth 120Hz tracking
    @GestureState private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    // Idle state - fade to 0.5 opacity after 4 seconds of inactivity
    @State private var isIdle = false
    @State private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = 4.0
    private let idleOpacity: Double = 0.5

    // Threshold to distinguish tap from drag (in points)
    private let tapThreshold: CGFloat = 10

    // Observer tokens for proper cleanup (prevent memory leaks)
    @State private var keyboardShowObserver: NSObjectProtocol?
    @State private var keyboardHideObserver: NSObjectProtocol?

    @AppStorage("toolkit_position_x") private var savedX: Double = -1
    @AppStorage("toolkit_position_y") private var savedY: Double = -1

    private let buttonSize: CGFloat = 48
    private let menuItemSize: CGFloat = 44
    private let expandedRadius: CGFloat = 75

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background when expanded
                if isExpanded && !isKeyboardVisible {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeMenu()
                        }
                        .transition(.opacity)
                }

                // Menu items positioned around the button
                if !isKeyboardVisible {
                    // Calculate all positions once (O(1) per item, computed together)
                    let positions = menuItemPositions(total: items.count, in: geometry)

                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if isExpanded {
                            MenuItemView(item: item, size: menuItemSize) {
                                closeMenu()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    item.execute()
                                }
                            }
                            .position(positions[index])
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(1)
                        }
                    }

                    // Main floating button - tap/drag detected in single gesture
                    MainButtonView(
                        isExpanded: isExpanded,
                        isDragging: isDragging,
                        size: buttonSize
                    )
                    .opacity(isIdle && !isExpanded && !isDragging ? idleOpacity : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: isIdle)
                    .position(currentPosition(in: geometry))
                    .gesture(dragGesture(in: geometry))
                    .zIndex(2)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
            .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
            .onAppear {
                AppLogger.log("[FloatingToolkit] onAppear called")
                initializePosition(in: geometry)
                setupKeyboardObservers()
                startIdleTimer()
            }
            .onDisappear {
                AppLogger.log("[FloatingToolkit] onDisappear called")
                removeKeyboardObservers()
                cancelIdleTimer()
            }
        }
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardObservers() {
        // Remove any existing observers first
        removeKeyboardObservers()
        AppLogger.log("[FloatingToolkit] Setting up keyboard observers")

        // Store observer tokens for proper cleanup
        keyboardShowObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            // Guard against duplicate notifications
            guard !isKeyboardVisible else {
                AppLogger.log("[FloatingToolkit] Keyboard show - SKIPPED (already visible)")
                return
            }
            AppLogger.log("[FloatingToolkit] Keyboard will show - hiding toolkit (time: \(Date().timeIntervalSince1970))")
            withAnimation(.easeInOut(duration: 0.2)) {
                isKeyboardVisible = true
                if isExpanded { isExpanded = false }
            }
        }

        keyboardHideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            // Guard against duplicate notifications
            guard isKeyboardVisible else {
                AppLogger.log("[FloatingToolkit] Keyboard hide - SKIPPED (already hidden)")
                return
            }
            AppLogger.log("[FloatingToolkit] Keyboard will hide - showing toolkit (time: \(Date().timeIntervalSince1970))")
            withAnimation(.easeInOut(duration: 0.2)) {
                isKeyboardVisible = false
            }
        }
    }

    private func removeKeyboardObservers() {
        // Remove using stored tokens (correct way for block-based observers)
        if let observer = keyboardShowObserver {
            NotificationCenter.default.removeObserver(observer)
            keyboardShowObserver = nil
        }
        if let observer = keyboardHideObserver {
            NotificationCenter.default.removeObserver(observer)
            keyboardHideObserver = nil
        }
    }

    // MARK: - Idle Timer

    /// Start the idle timer - button fades after timeout
    private func startIdleTimer() {
        cancelIdleTimer()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { _ in
            withAnimation {
                isIdle = true
            }
        }
    }

    /// Cancel the idle timer
    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    /// Reset idle state on user interaction
    private func resetIdleState() {
        isIdle = false
        startIdleTimer()
    }

    // MARK: - Actions

    private func toggleMenu() {
        resetIdleState()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            isExpanded.toggle()
        }
        Haptics.light()
    }

    private func closeMenu() {
        resetIdleState()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            isExpanded = false
        }
    }

    // MARK: - Position Management

    private func initializePosition(in geometry: GeometryProxy) {
        if savedX < 0 || savedY < 0 {
            // Default: bottom-LEFT corner (away from Settings button in top-right)
            let defaultX = buttonSize / 2 + 20
            let defaultY = geometry.size.height - buttonSize / 2 - 120
            position = CGPoint(x: defaultX, y: defaultY)
            savedX = defaultX
            savedY = defaultY
        } else {
            position = CGPoint(x: savedX, y: savedY)
        }
    }

    private func currentPosition(in geometry: GeometryProxy) -> CGPoint {
        CGPoint(
            x: position.x + dragOffset.width,
            y: position.y + dragOffset.height
        )
    }

    /// Calculate all menu item positions at once (single base angle calculation)
    /// Returns array of CGPoints for each menu item - O(n) with minimal overhead
    /// Items are arranged so that item[0] (Debug Logs) is always at the bottom of the arc
    /// Positions are clamped to stay within screen bounds
    private func menuItemPositions(total: Int, in geometry: GeometryProxy) -> [CGPoint] {
        guard total > 0 else { return [] }

        let currentPos = currentPosition(in: geometry)
        let screenCenter = geometry.size.width / 2

        // Calculate base angle once for all items
        let baseAngle = calculateOptimalBaseAngle(for: currentPos, in: geometry)

        let angleSpread: Double = min(Double(total - 1) * 40, 160)
        let angleStep = total > 1 ? angleSpread / Double(total - 1) : 0

        // Determine if we're on the left side of screen
        let isOnLeftSide = currentPos.x < screenCenter

        // Screen bounds for clamping (with padding for menu item size + label)
        let itemPadding: CGFloat = menuItemSize / 2 + 30  // Extra space for label
        let minX = itemPadding
        let maxX = geometry.size.width - itemPadding
        let minY = geometry.safeAreaInsets.top + itemPadding
        let maxY = geometry.size.height - geometry.safeAreaInsets.bottom - itemPadding - 50

        // Pre-allocate array for efficiency
        var positions = [CGPoint]()
        positions.reserveCapacity(total)

        for index in 0..<total {
            // On left side: start from bottom of arc (higher angle = more downward)
            // On right side: start from bottom of arc (lower angle = more downward for negative angles)
            let adjustedIndex: Int
            if isOnLeftSide {
                // Left side: reverse order so item[0] is at bottom
                adjustedIndex = total - 1 - index
            } else {
                // Right side: normal order, item[0] at bottom
                adjustedIndex = index
            }

            let startAngle = baseAngle - angleSpread / 2
            let angle = startAngle + Double(adjustedIndex) * angleStep
            let radians = angle * .pi / 180

            // Calculate position and clamp to screen bounds
            let rawX = currentPos.x + CGFloat(Darwin.cos(radians)) * expandedRadius
            let rawY = currentPos.y + CGFloat(Darwin.sin(radians)) * expandedRadius

            positions.append(CGPoint(
                x: max(minX, min(maxX, rawX)),
                y: max(minY, min(maxY, rawY))
            ))
        }

        return positions
    }

    /// Calculate optimal base angle - lightweight, no allocations
    /// Points menu items toward the center of available screen space
    @inline(__always)
    private func calculateOptimalBaseAngle(for position: CGPoint, in geometry: GeometryProxy) -> Double {
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height
        let menuSpace = expandedRadius + menuItemSize / 2 + 10
        let threshold: CGFloat = 20

        // Simple edge detection using boolean flags
        let nearLeft = position.x - menuSpace < threshold
        let nearRight = screenWidth - position.x - menuSpace < threshold
        let nearTop = position.y - geometry.safeAreaInsets.top - menuSpace < threshold
        let nearBottom = screenHeight - position.y - geometry.safeAreaInsets.bottom - menuSpace - 50 < threshold

        // Fast switch on edge combinations
        // Angles: 0 = right, 90 = down, 180 = left, -90 = up
        if nearLeft && nearTop { return 45 }        // Top-left → down-right
        if nearRight && nearTop { return 135 }      // Top-right → down-left
        if nearLeft && nearBottom { return -45 }    // Bottom-left → up-right
        if nearRight && nearBottom { return -135 }  // Bottom-right → up-left
        if nearLeft { return 0 }                     // Left edge → right
        if nearRight { return 180 }                  // Right edge → left
        if nearTop { return 90 }                     // Top edge → down
        if nearBottom { return -90 }                 // Bottom edge → up
        return -90                                   // Default: up
    }

    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            // GestureState for smooth 120Hz finger tracking
            .updating($dragOffset) { value, state, _ in
                state = value.translation

                // Mark as dragging once past threshold
                if !isDragging && (abs(value.translation.width) > tapThreshold ||
                                   abs(value.translation.height) > tapThreshold) {
                    DispatchQueue.main.async {
                        isDragging = true
                        if isExpanded {
                            withAnimation(.easeOut(duration: 0.15)) {
                                isExpanded = false
                            }
                        }
                    }
                }
            }
            .onEnded { value in
                handleGestureEnd(translation: value.translation, in: geometry)
            }
    }

    /// Handle gesture end - detect tap vs drag based on translation distance
    private func handleGestureEnd(translation: CGSize, in geometry: GeometryProxy) {
        let distance = sqrt(translation.width * translation.width +
                           translation.height * translation.height)

        if distance < tapThreshold {
            // It's a TAP - toggle menu
            isDragging = false
            toggleMenu()
            Haptics.light()
        } else {
            // It's a DRAG - update position
            finalizeDrag(with: translation, in: geometry)
        }
    }

    /// Finalize drag with proper state transitions to prevent visual jump-back
    private func finalizeDrag(with translation: CGSize, in geometry: GeometryProxy) {
        // Calculate final snapped position
        let finalPosition = calculateFinalPosition(with: translation, in: geometry)

        // GestureState resets automatically, so we need to update position
        // to where the finger was released BEFORE the reset causes a jump
        // IMPORTANT: Reset idle state within the same transaction to prevent
        // animation interference (idle animation would otherwise cause jump)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            // Reset idle state first (no animation due to transaction)
            isIdle = false

            position = CGPoint(
                x: position.x + translation.width,
                y: position.y + translation.height
            )
            isDragging = false
        }

        // Restart idle timer after transaction completes
        startIdleTimer()

        // Animate from release point to snapped final position
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            position = finalPosition
        }

        // Persist final position
        savedX = finalPosition.x
        savedY = finalPosition.y
        Haptics.light()
    }

    /// Calculate final position with bounds and edge snapping
    private func calculateFinalPosition(with translation: CGSize, in geometry: GeometryProxy) -> CGPoint {
        var newX = position.x + translation.width
        var newY = position.y + translation.height

        // Bounds
        let padding: CGFloat = 10
        let minX = buttonSize / 2 + padding
        let maxX = geometry.size.width - buttonSize / 2 - padding
        let minY = buttonSize / 2 + padding + geometry.safeAreaInsets.top
        let maxY = geometry.size.height - buttonSize / 2 - padding - geometry.safeAreaInsets.bottom - 50

        newX = max(minX, min(maxX, newX))
        newY = max(minY, min(maxY, newY))

        // Snap to edges
        let snapThreshold: CGFloat = 50
        if newX < minX + snapThreshold { newX = minX }
        else if newX > maxX - snapThreshold { newX = maxX }

        return CGPoint(x: newX, y: newY)
    }
}

// MARK: - Main Button Component

/// Visual-only button view - tap/drag handled by parent gesture
private struct MainButtonView: View {
    let isExpanded: Bool
    let isDragging: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(ColorSystem.primary.opacity(0.2))
                .frame(width: size + 8, height: size + 8)
                .blur(radius: 4)

            // Main circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [ColorSystem.primary, ColorSystem.primaryDim],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: ColorSystem.primaryGlow, radius: isDragging ? 12 : 6)

            // Icon
            Image(systemName: isExpanded ? "xmark" : "wrench.and.screwdriver.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .scaleEffect(isDragging ? 1.15 : 1.0)
        .animation(.spring(response: 0.2), value: isDragging)
        .contentShape(Circle()) // Ensure the entire circle is tappable
    }
}

// MARK: - Menu Item Component

private struct MenuItemView: View {
    let item: ToolkitItem
    let size: CGFloat
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Background
                    Circle()
                        .fill(ColorSystem.terminalBgElevated)
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.3), radius: 4)

                    // Border
                    Circle()
                        .stroke(item.color.opacity(0.5), lineWidth: 1.5)
                        .frame(width: size, height: size)

                    // Icon
                    Image(systemName: item.icon)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(item.color)
                }

                // Label
                Text(item.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ColorSystem.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ColorSystem.terminalBgElevated.opacity(0.95))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 2)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Floating Toolkit") {
    ZStack {
        ColorSystem.terminalBg.ignoresSafeArea()

        VStack {
            Text("Main Content Area")
                .foregroundStyle(ColorSystem.textSecondary)
        }

        FloatingToolkitButton(
            items: ToolkitBuilder()
                .add(.debugLogs { print("Debug") })
                .build()
        )
    }
}
