import SwiftUI
import UIKit

// MARK: - Force Touch Button Wrapper

/// UIViewRepresentable that wraps the button and handles ALL touch events
/// Detects force touch (3D Touch) or long press (Haptic Touch fallback), normal taps, and drags
private struct ForceTouchButtonWrapper<Content: View>: UIViewRepresentable {
    let content: Content
    let buttonSize: CGFloat
    let onTap: () -> Void
    let onDragStart: () -> Void
    let onDragChange: (CGSize) -> Void
    let onDragEnd: (CGSize) -> Void
    let onForceActivated: () -> Void
    let onForceEnded: () -> Void
    let onForceDrag: (CGPoint) -> Void

    /// Force threshold (0.0 - 1.0, where 1.0 is maximum force)
    private let forceThreshold: CGFloat = 0.4

    /// Long press duration for devices without 3D Touch (Haptic Touch fallback)
    private let longPressDuration: TimeInterval = 0.4

    /// Distance threshold to distinguish tap from drag
    private let dragThreshold: CGFloat = 10

    func makeUIView(context: Context) -> ForceTouchContainerView {
        let size = buttonSize + 20
        let view = ForceTouchContainerView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.backgroundColor = .clear
        view.delegate = context.coordinator

        // Add SwiftUI content as hosted view
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(x: 0, y: 0, width: size, height: size)
        hostingController.view.isUserInteractionEnabled = false // Let container handle touches

        view.addSubview(hostingController.view)

        context.coordinator.hostingController = hostingController
        context.coordinator.containerSize = size

        return view
    }

    func updateUIView(_ uiView: ForceTouchContainerView, context: Context) {
        context.coordinator.hostingController?.rootView = content
        // Update frame when SwiftUI layout changes
        let size = context.coordinator.containerSize
        uiView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        context.coordinator.hostingController?.view.frame = CGRect(x: 0, y: 0, width: size, height: size)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ForceTouchContainerView, context: Context) -> CGSize? {
        let size = buttonSize + 20
        return CGSize(width: size, height: size)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            forceThreshold: forceThreshold,
            longPressDuration: longPressDuration,
            dragThreshold: dragThreshold,
            onTap: onTap,
            onDragStart: onDragStart,
            onDragChange: onDragChange,
            onDragEnd: onDragEnd,
            onForceActivated: onForceActivated,
            onForceEnded: onForceEnded,
            onForceDrag: onForceDrag
        )
    }

    class Coordinator: NSObject, ForceTouchContainerDelegate {
        var hostingController: UIHostingController<Content>?

        let forceThreshold: CGFloat
        let longPressDuration: TimeInterval
        let dragThreshold: CGFloat
        let onTap: () -> Void
        let onDragStart: () -> Void
        let onDragChange: (CGSize) -> Void
        let onDragEnd: (CGSize) -> Void
        let onForceActivated: () -> Void
        let onForceEnded: () -> Void
        let onForceDrag: (CGPoint) -> Void

        // Touch state
        var isForceActive = false
        var isDragging = false
        var initialTouchLocation: CGPoint = .zero
        var currentTranslation: CGSize = .zero
        var touchStartTime: Date?
        var longPressTimer: Timer?
        var has3DTouch = false  // Will be determined on first touch
        var containerSize: CGFloat = 68  // Default size, will be updated

        init(forceThreshold: CGFloat,
             longPressDuration: TimeInterval,
             dragThreshold: CGFloat,
             onTap: @escaping () -> Void,
             onDragStart: @escaping () -> Void,
             onDragChange: @escaping (CGSize) -> Void,
             onDragEnd: @escaping (CGSize) -> Void,
             onForceActivated: @escaping () -> Void,
             onForceEnded: @escaping () -> Void,
             onForceDrag: @escaping (CGPoint) -> Void) {
            self.forceThreshold = forceThreshold
            self.longPressDuration = longPressDuration
            self.dragThreshold = dragThreshold
            self.onTap = onTap
            self.onDragStart = onDragStart
            self.onDragChange = onDragChange
            self.onDragEnd = onDragEnd
            self.onForceActivated = onForceActivated
            self.onForceEnded = onForceEnded
            self.onForceDrag = onForceDrag
        }

        func touchBegan(at location: CGPoint, force: CGFloat, maximumForce: CGFloat) {
            initialTouchLocation = location
            currentTranslation = .zero
            isDragging = false
            isForceActive = false
            touchStartTime = Date()

            // Determine if device has 3D Touch (maximumForce > 0)
            has3DTouch = maximumForce > 0

            if has3DTouch {
                // 3D Touch device - check force immediately
                checkForce(force: force, maximumForce: maximumForce, location: location)
            } else {
                // No 3D Touch - start long press timer as fallback
                startLongPressTimer(at: location)
            }
        }

        func touchMoved(at location: CGPoint, force: CGFloat, maximumForce: CGFloat) {
            let dx = location.x - initialTouchLocation.x
            let dy = location.y - initialTouchLocation.y
            let distance = sqrt(dx * dx + dy * dy)

            // If moved too far before long press, cancel the timer
            if !isForceActive && !isDragging && distance > dragThreshold {
                cancelLongPressTimer()
            }

            if has3DTouch {
                // 3D Touch device - check force
                checkForce(force: force, maximumForce: maximumForce, location: location)
            }

            if isForceActive {
                // Force/long press mode - report drag offset for scroll direction
                DispatchQueue.main.async {
                    self.onForceDrag(CGPoint(x: dx, y: dy))
                }
            } else if !isForceActive {
                // Normal drag mode
                if !isDragging && distance > dragThreshold {
                    isDragging = true
                    cancelLongPressTimer()
                    DispatchQueue.main.async {
                        self.onDragStart()
                    }
                }

                if isDragging {
                    currentTranslation = CGSize(width: dx, height: dy)
                    DispatchQueue.main.async {
                        self.onDragChange(self.currentTranslation)
                    }
                }
            }
        }

        func touchEnded(at location: CGPoint) {
            cancelLongPressTimer()

            if isForceActive {
                isForceActive = false
                DispatchQueue.main.async {
                    self.onForceEnded()
                }
            } else if isDragging {
                isDragging = false
                DispatchQueue.main.async {
                    self.onDragEnd(self.currentTranslation)
                }
            } else {
                // It's a tap
                DispatchQueue.main.async {
                    self.onTap()
                }
            }

            currentTranslation = .zero
            touchStartTime = nil
        }

        func touchCancelled() {
            cancelLongPressTimer()

            if isForceActive {
                isForceActive = false
                DispatchQueue.main.async {
                    self.onForceEnded()
                }
            } else if isDragging {
                isDragging = false
                DispatchQueue.main.async {
                    self.onDragEnd(self.currentTranslation)
                }
            }

            currentTranslation = .zero
            touchStartTime = nil
        }

        private func checkForce(force: CGFloat, maximumForce: CGFloat, location: CGPoint) {
            guard maximumForce > 0, !isForceActive else { return }

            let normalizedForce = force / maximumForce

            if normalizedForce >= forceThreshold {
                activateForceMode(at: location)
            }
        }

        private func startLongPressTimer(at location: CGPoint) {
            cancelLongPressTimer()
            longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
                guard let self = self, !self.isDragging, !self.isForceActive else { return }
                self.activateForceMode(at: location)
            }
        }

        private func cancelLongPressTimer() {
            longPressTimer?.invalidate()
            longPressTimer = nil
        }

        private func activateForceMode(at location: CGPoint) {
            isForceActive = true
            isDragging = false
            initialTouchLocation = location
            cancelLongPressTimer()
            DispatchQueue.main.async {
                self.onForceActivated()
            }
        }
    }
}

/// Protocol for force touch container delegate
private protocol ForceTouchContainerDelegate: AnyObject {
    func touchBegan(at location: CGPoint, force: CGFloat, maximumForce: CGFloat)
    func touchMoved(at location: CGPoint, force: CGFloat, maximumForce: CGFloat)
    func touchEnded(at location: CGPoint)
    func touchCancelled()
}

/// Custom UIView container that captures all touch events
private class ForceTouchContainerView: UIView {
    weak var delegate: ForceTouchContainerDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Ensure the view can receive touches
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Expand hit test area slightly for better touch detection
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = bounds.insetBy(dx: -10, dy: -10)
        return expandedBounds.contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        delegate?.touchBegan(at: location, force: touch.force, maximumForce: touch.maximumPossibleForce)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        delegate?.touchMoved(at: location, force: touch.force, maximumForce: touch.maximumPossibleForce)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        delegate?.touchEnded(at: location)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        delegate?.touchCancelled()
    }
}

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

// MARK: - Scroll Direction

/// Direction for scroll gesture
enum ScrollDirection {
    case top
    case bottom
}

// MARK: - Floating Toolkit Button

/// AssistiveTouch-style floating button with expandable toolkit menu
/// Draggable, remembers position, compact design
/// Automatically hides when keyboard is visible
/// 3D Touch (force press) + swipe up/down for scroll to top/bottom
struct FloatingToolkitButton: View {
    let items: [ToolkitItem]

    /// Callback for scroll actions (triggered by force touch + swipe)
    var onScrollRequest: ((ScrollDirection) -> Void)?

    @State private var isExpanded = false
    @State private var position: CGPoint = .zero

    // Drag state - managed by UIKit touch handler
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    // Force touch scroll state
    @State private var isForceTouchActive = false
    @State private var forceTouchDragOffset: CGPoint = .zero
    @State private var hoveredScrollDirection: ScrollDirection?

    // Idle state - fade to 0.5 opacity after 4 seconds of inactivity
    @State private var isIdle = false
    @State private var idleTimer: Timer?
    private let idleTimeout: TimeInterval = 4.0
    private let idleOpacity: Double = 0.5

    // Threshold to distinguish tap from drag (in points)
    private let tapThreshold: CGFloat = 10

    // Force touch scroll thresholds
    private let scrollArrowDistance: CGFloat = 70  // Distance from button to arrow
    private let scrollActivationThreshold: CGFloat = 40  // How far to drag to activate

    // Observer tokens for proper cleanup (prevent memory leaks)
    @State private var orientationObserver: NSObjectProtocol?

    // Track screen size to detect orientation changes
    @State private var lastScreenSize: CGSize = .zero

    // Keyboard tracking
    @State private var keyboardHeight: CGFloat = 0
    @State private var positionBeforeKeyboard: CGPoint?
    @State private var safeAreaTop: CGFloat = 0

    @AppStorage("toolkit_position_x") private var savedX: Double = -1
    @AppStorage("toolkit_position_y") private var savedY: Double = -1

    private let buttonSize: CGFloat = 54
    private let menuItemSize: CGFloat = 44
    private let expandedRadius: CGFloat = 75

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background when expanded
                if isExpanded {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeMenu()
                        }
                        .transition(.opacity)
                }

                // Menu items positioned around the button
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

                    // Scroll guide arrows (visible during force touch)
                    if isForceTouchActive {
                        let btnPos = currentPosition(in: geometry)

                        // Up arrow
                        ScrollGuideArrow(
                            direction: .top,
                            isHovered: hoveredScrollDirection == .top,
                            size: 44
                        )
                        .position(x: btnPos.x, y: btnPos.y - scrollArrowDistance)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(3)

                        // Down arrow
                        ScrollGuideArrow(
                            direction: .bottom,
                            isHovered: hoveredScrollDirection == .bottom,
                            size: 44
                        )
                        .position(x: btnPos.x, y: btnPos.y + scrollArrowDistance)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(3)
                    }

                    // Main floating button with SwiftUI gestures
                    MainButtonView(
                        isExpanded: isExpanded,
                        isDragging: isDragging,
                        isForceTouchActive: isForceTouchActive,
                        size: buttonSize
                    )
                    .opacity(isIdle && !isExpanded && !isDragging && !isForceTouchActive ? idleOpacity : 1.0)
                    .position(currentPosition(in: geometry))
                    .gesture(longPressScrollGesture())
                    .simultaneousGesture(tapAndDragGesture(in: geometry))
                    .zIndex(2)
                    .transition(.scale.combined(with: .opacity))
            }
            // Note: Removed implicit .animation() modifiers to prevent timing conflicts
            // All animations are now handled explicitly via withAnimation in handlers
            .onAppear {
                AppLogger.log("[FloatingToolkit] onAppear called")
                initializePosition(in: geometry)
                startIdleTimer()
                lastScreenSize = geometry.size
                safeAreaTop = geometry.safeAreaInsets.top
            }
            .onDisappear {
                AppLogger.log("[FloatingToolkit] onDisappear called")
                cancelIdleTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                handleKeyboardWillShow(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                handleKeyboardWillHide()
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                // Update safe area for keyboard handling
                safeAreaTop = geometry.safeAreaInsets.top

                // Detect orientation change (screen size changed significantly)
                if lastScreenSize != .zero && lastScreenSize != newSize {
                    AppLogger.log("[FloatingToolkit] Screen size changed: \(oldSize) -> \(newSize)")
                    handleScreenSizeChange(newSize: newSize, in: geometry)
                }
                lastScreenSize = newSize
            }
        }
    }

    // MARK: - Orientation Handling

    /// Handle screen size change (rotation) - clamp position to valid bounds or reset to default
    private func handleScreenSizeChange(newSize: CGSize, in geometry: GeometryProxy) {
        // Guard against invalid screen sizes during keyboard animation
        guard newSize.width > 0 && newSize.height > 100 else { return }

        // Use screen bounds for consistent positioning
        // This prevents the button from being repositioned when keyboard appears/disappears
        let screenBounds = UIScreen.main.bounds

        // Only handle actual orientation changes (width change), not keyboard (height-only change)
        // Keyboard changes height but not width
        if abs(newSize.width - lastScreenSize.width) < 1 {
            // Width unchanged - this is likely keyboard, not rotation
            return
        }

        let padding: CGFloat = 10
        let minX = buttonSize / 2 + padding
        let maxX = max(minX + 1, screenBounds.width - buttonSize / 2 - padding)
        let minY = buttonSize / 2 + padding + geometry.safeAreaInsets.top
        let maxY = max(minY + 1, screenBounds.height - buttonSize / 2 - padding - geometry.safeAreaInsets.bottom - 50)

        // Check if current position is outside new bounds
        let isOutOfBounds = position.x < minX || position.x > maxX ||
                           position.y < minY || position.y > maxY

        if isOutOfBounds {
            AppLogger.log("[FloatingToolkit] Position out of bounds after rotation, resetting to default")
            // Reset to default position (bottom-left corner)
            let defaultX = buttonSize / 2 + 20
            let defaultY = max(minY, newSize.height - buttonSize / 2 - 120)

            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                position = CGPoint(x: defaultX, y: defaultY)
            }

            // Save new position
            savedX = defaultX
            savedY = defaultY
        } else {
            // Position is still valid, just ensure it's clamped
            let clampedX = max(minX, min(maxX, position.x))
            let clampedY = max(minY, min(maxY, position.y))

            if clampedX != position.x || clampedY != position.y {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    position = CGPoint(x: clampedX, y: clampedY)
                }
                savedX = clampedX
                savedY = clampedY
            }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            isIdle = false
        }
        startIdleTimer()
    }

    // MARK: - Keyboard Handling

    /// Handle keyboard appearing - move toolkit above keyboard if overlapping
    private func handleKeyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        // Use keyboard frame's Y position directly (more accurate than calculating from height)
        let keyboardTop = keyboardFrame.origin.y
        keyboardHeight = keyboardFrame.height

        // Get animation duration, default to 0.25 if not available
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25

        // Account for app's input bar above keyboard (typically 50-70pt)
        // Use larger clearance to ensure toolkit is fully visible
        let inputBarHeight: CGFloat = 70
        let effectiveKeyboardTop = keyboardTop - inputBarHeight

        // Check if toolkit would overlap with keyboard + input bar area
        let toolkitBottom = position.y + buttonSize / 2

        AppLogger.log("[FloatingToolkit] Keyboard show: keyboardTop=\(keyboardTop), effectiveTop=\(effectiveKeyboardTop), toolkitBottom=\(toolkitBottom), position.y=\(position.y)")

        // If toolkit overlaps keyboard area (including input bar), move it above
        if toolkitBottom > effectiveKeyboardTop {
            // Save position before keyboard (only if not already saved)
            if positionBeforeKeyboard == nil {
                positionBeforeKeyboard = position
            }

            let newY = effectiveKeyboardTop - buttonSize / 2 - 20  // 20pt above effective keyboard area
            let minY = buttonSize / 2 + 10 + safeAreaTop

            withAnimation(.easeOut(duration: duration)) {
                position.y = max(minY, newY)
            }

            AppLogger.log("[FloatingToolkit] Moved above keyboard: newY=\(newY), final=\(max(minY, newY))")
        }
    }

    /// Handle keyboard hiding - restore position if it was moved
    private func handleKeyboardWillHide() {
        keyboardHeight = 0

        // Restore position if we moved it for keyboard
        if let originalPosition = positionBeforeKeyboard {
            withAnimation(.easeOut(duration: 0.25)) {
                position = originalPosition
            }
            positionBeforeKeyboard = nil
            AppLogger.log("[FloatingToolkit] Restored position after keyboard hide")
        }
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
        // Guard against invalid screen sizes during keyboard animation
        guard geometry.size.height > 100 else { return }

        if savedX < 0 || savedY < 0 {
            // Default: bottom-LEFT corner (away from Settings button in top-right)
            let defaultX = buttonSize / 2 + 20
            let minY = buttonSize / 2 + 10 + geometry.safeAreaInsets.top
            let defaultY = max(minY, geometry.size.height - buttonSize / 2 - 120)
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

    /// Calculate all menu item positions at once
    /// - Normal: Single-layer 180° fan at same radius
    /// - Corner: Multi-layer fan radiating outward (Layer 1: 2 buttons, Layer 2: up to 5, Layer 3: overflow)
    private func menuItemPositions(total: Int, in geometry: GeometryProxy) -> [CGPoint] {
        guard total > 0 else { return [] }

        let currentPos = currentPosition(in: geometry)
        // Use actual screen bounds, not keyboard-adjusted geometry height
        // This prevents menu items from jumping when keyboard appears
        let screenBounds = UIScreen.main.bounds
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height

        // Detect corner position
        let cornerThreshold: CGFloat = 100
        let nearLeft = currentPos.x < cornerThreshold
        let nearRight = currentPos.x > screenWidth - cornerThreshold
        let nearTop = currentPos.y < geometry.safeAreaInsets.top + cornerThreshold
        let nearBottom = currentPos.y > screenHeight - geometry.safeAreaInsets.bottom - cornerThreshold - 50
        let isInCorner = (nearLeft || nearRight) && (nearTop || nearBottom)

        // Screen bounds for clamping
        let itemPadding: CGFloat = menuItemSize / 2 + 25
        let minX = itemPadding
        let maxX = max(minX + 1, screenWidth - itemPadding)
        let minY = geometry.safeAreaInsets.top + itemPadding
        let maxY = max(minY + 1, screenHeight - geometry.safeAreaInsets.bottom - itemPadding - 50)

        var positions = [CGPoint]()
        positions.reserveCapacity(total)

        // Fan blade layout: 180° arc centered on optimal direction
        let baseAngle = calculateOptimalBaseAngle(for: currentPos, in: geometry)
        let angleSpread: Double = 180

        // Determine if we need to reverse order to maintain consistent item positioning
        // When on right side (baseAngle ~180°), reverse the sweep to keep items in same visual order
        let shouldReverseOrder = nearRight

        if isInCorner {
            // Corner layout: multi-layer arc to prevent overlap when clamped to screen edges
            // Layer 1 (inner): up to 2 items at 80pt radius
            // Layer 2 (outer): remaining items at 130pt radius
            let innerRadius: CGFloat = 80
            let outerRadius: CGFloat = 130
            let anglePerItem: Double = 45  // Generous spacing

            let layer1Count = min(2, total)
            let layer2Count = total - layer1Count

            // Helper to add positions for a corner layer
            func addCornerLayerPositions(count: Int, radius: CGFloat, startIndex: Int) {
                guard count > 0 else { return }
                let spread: Double = Double(max(1, count - 1)) * anglePerItem
                let step = count > 1 ? spread / Double(count - 1) : 0

                for i in 0..<count {
                    let idx = shouldReverseOrder ? (count - 1 - i) : i
                    let angle = baseAngle - spread / 2 + step * Double(idx)
                    let radians = angle * .pi / 180
                    let rawX = currentPos.x + CGFloat(Darwin.cos(radians)) * radius
                    let rawY = currentPos.y + CGFloat(Darwin.sin(radians)) * radius
                    positions.append(CGPoint(
                        x: max(minX, min(maxX, rawX)),
                        y: max(minY, min(maxY, rawY))
                    ))
                }
            }

            addCornerLayerPositions(count: layer1Count, radius: innerRadius, startIndex: 0)
            addCornerLayerPositions(count: layer2Count, radius: outerRadius, startIndex: layer1Count)

        } else if total == 2 {
            // Special case for exactly 2 items: Settings and Debug
            let radius: CGFloat = 75   // Distance from button center

            // When near top or bottom edge, use horizontal layout (Settings left, Debug right)
            // Otherwise use vertical layout (Settings above, Debug below)
            let useHorizontalLayout = nearTop || nearBottom

            if useHorizontalLayout {
                // Horizontal layout: Settings on left, Debug on right
                let leftAngle = 180.0 * .pi / 180.0   // Left
                let rightAngle = 0.0 * .pi / 180.0   // Right

                // Settings (index 0) positioned to the left
                let rawX1 = currentPos.x + CGFloat(Darwin.cos(leftAngle)) * radius
                let rawY1 = currentPos.y + CGFloat(Darwin.sin(leftAngle)) * radius
                positions.append(CGPoint(
                    x: max(minX, min(maxX, rawX1)),
                    y: max(minY, min(maxY, rawY1))
                ))

                // Debug (index 1) positioned to the right
                let rawX2 = currentPos.x + CGFloat(Darwin.cos(rightAngle)) * radius
                let rawY2 = currentPos.y + CGFloat(Darwin.sin(rightAngle)) * radius
                positions.append(CGPoint(
                    x: max(minX, min(maxX, rawX2)),
                    y: max(minY, min(maxY, rawY2))
                ))
            } else {
                // Vertical layout: Settings above, Debug below
                let upwardAngle = -90.0 * .pi / 180.0
                let downwardAngle = 90.0 * .pi / 180.0

                // Settings (index 0) positioned above the button
                let rawX1 = currentPos.x + CGFloat(Darwin.cos(upwardAngle)) * radius
                let rawY1 = currentPos.y + CGFloat(Darwin.sin(upwardAngle)) * radius
                positions.append(CGPoint(
                    x: max(minX, min(maxX, rawX1)),
                    y: max(minY, min(maxY, rawY1))
                ))

                // Debug (index 1) positioned below the button
                let rawX2 = currentPos.x + CGFloat(Darwin.cos(downwardAngle)) * radius
                let rawY2 = currentPos.y + CGFloat(Darwin.sin(downwardAngle)) * radius
                positions.append(CGPoint(
                    x: max(minX, min(maxX, rawX2)),
                    y: max(minY, min(maxY, rawY2))
                ))
            }

        } else {
            // Normal case: 180° fan, multi-layer if more than 5 buttons
            // Layer 1: up to 5 buttons at standard radius
            // Layer 2: buttons 6-8 at outer radius
            let maxPerLayer = 5
            let layer1Radius = expandedRadius
            let layer2Radius = expandedRadius * 1.45

            let layer1Count = min(maxPerLayer, total)
            let layer2Count = total - layer1Count

            // Helper to add positions for a layer
            func addLayerPositions(count: Int, radius: CGFloat) {
                guard count > 0 else { return }
                let step = count > 1 ? angleSpread / Double(count - 1) : 0
                for i in 0..<count {
                    // Reverse index when on right side to maintain consistent visual order
                    let idx = shouldReverseOrder ? (count - 1 - i) : i
                    let angle = baseAngle - angleSpread / 2 + step * Double(idx)
                    let radians = angle * .pi / 180
                    let rawX = currentPos.x + CGFloat(Darwin.cos(radians)) * radius
                    let rawY = currentPos.y + CGFloat(Darwin.sin(radians)) * radius
                    positions.append(CGPoint(
                        x: max(minX, min(maxX, rawX)),
                        y: max(minY, min(maxY, rawY))
                    ))
                }
            }

            addLayerPositions(count: layer1Count, radius: layer1Radius)
            addLayerPositions(count: layer2Count, radius: layer2Radius)
        }

        return positions
    }

    /// Calculate optimal base angle - lightweight, no allocations
    /// Points menu items toward the center of available screen space
    @inline(__always)
    private func calculateOptimalBaseAngle(for position: CGPoint, in geometry: GeometryProxy) -> Double {
        // Use actual screen bounds, not keyboard-adjusted geometry
        // This prevents menu direction from changing when keyboard appears
        let screenBounds = UIScreen.main.bounds
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height
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

    // MARK: - Drag Handlers (called by UIKit wrapper)

    private func handleDragStart() {
        withAnimation(.easeOut(duration: 0.1)) {
            isDragging = true
        }
        resetIdleState()
        if isExpanded {
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded = false
            }
        }
        AppLogger.log("[FloatingToolkit] Drag started")
    }

    private func handleDragChange(translation: CGSize) {
        // Update position directly during drag for smooth movement
        // Don't use dragOffset since UIViewRepresentable position doesn't update smoothly
        // Instead, we update position temporarily and finalize on drag end
        dragOffset = translation
        AppLogger.log("[FloatingToolkit] Drag change: \(translation)")
    }

    private func handleDragEnd(translation: CGSize, in geometry: GeometryProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            isDragging = false
        }
        dragOffset = .zero
        finalizeDrag(with: translation, in: geometry)
        AppLogger.log("[FloatingToolkit] Drag ended: \(translation)")
    }

    // MARK: - Force Touch Handlers

    /// Called when force touch is activated (user pressed hard)
    private func handleForceActivated() {
        guard !isForceTouchActive else { return }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            isForceTouchActive = true
            isExpanded = false
        }
        Haptics.medium()
        cancelIdleTimer()
        AppLogger.log("[FloatingToolkit] Force touch activated")
    }

    /// Called when force touch ends
    private func handleForceEnded() {
        // Trigger scroll if direction is hovered
        if let direction = hoveredScrollDirection {
            Haptics.success()
            AppLogger.log("[FloatingToolkit] Force touch ended - triggering scroll direction=\(direction), forceTouchDragOffset=\(forceTouchDragOffset)")
            onScrollRequest?(direction)
            AppLogger.log("[FloatingToolkit] onScrollRequest callback completed")
        } else {
            AppLogger.log("[FloatingToolkit] Force touch ended - no scroll (hoveredScrollDirection=nil, forceTouchDragOffset=\(forceTouchDragOffset))")
        }

        // Reset state
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            isForceTouchActive = false
            hoveredScrollDirection = nil
        }
        forceTouchDragOffset = .zero
        startIdleTimer()
    }

    /// Called when user drags after force touch activation
    private func handleForceDrag(offset: CGPoint) {
        guard isForceTouchActive else { return }

        forceTouchDragOffset = offset

        // Determine which arrow is hovered based on vertical drag
        let newDirection: ScrollDirection?
        if offset.y < -scrollActivationThreshold {
            newDirection = .top
        } else if offset.y > scrollActivationThreshold {
            newDirection = .bottom
        } else {
            newDirection = nil
        }

        // Haptic feedback when crossing threshold
        if newDirection != hoveredScrollDirection {
            if newDirection != nil {
                Haptics.selection()
            }
            hoveredScrollDirection = newDirection
        }
    }

    /// Finalize drag with proper state transitions
    private func finalizeDrag(with translation: CGSize, in geometry: GeometryProxy) {
        // Calculate final snapped position
        let finalPosition = calculateFinalPosition(with: translation, in: geometry)

        // Update position to release point first
        position = CGPoint(
            x: position.x + translation.width,
            y: position.y + translation.height
        )

        // Reset idle state
        isIdle = false
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

        // Use screen bounds to allow dragging near keyboard
        // geometry.size shrinks when keyboard appears, but we want full screen bounds
        let screenBounds = UIScreen.main.bounds
        let padding: CGFloat = 10
        let minX = buttonSize / 2 + padding
        let maxX = max(minX + 1, screenBounds.width - buttonSize / 2 - padding)
        let minY = buttonSize / 2 + padding + geometry.safeAreaInsets.top
        let maxY = max(minY + 1, screenBounds.height - buttonSize / 2 - padding - geometry.safeAreaInsets.bottom - 50)

        newX = max(minX, min(maxX, newX))
        newY = max(minY, min(maxY, newY))

        // Snap to edges
        let snapThreshold: CGFloat = 50
        if newX < minX + snapThreshold { newX = minX }
        else if newX > maxX - snapThreshold { newX = maxX }

        return CGPoint(x: newX, y: newY)
    }

    // MARK: - SwiftUI Gestures

    /// Long press gesture to activate scroll mode (Haptic Touch fallback)
    private func longPressScrollGesture() -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                handleForceActivated()
            }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    // Long press succeeded, now tracking drag for scroll direction
                    if let drag = drag {
                        handleForceDrag(offset: CGPoint(x: drag.translation.width, y: drag.translation.height))
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                switch value {
                case .second(true, _):
                    // Long press + drag ended
                    handleForceEnded()
                default:
                    break
                }
            }
    }

    /// Combined tap and drag gesture for menu toggle and repositioning
    private func tapAndDragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Only start drag if moved past threshold
                let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))

                if distance > tapThreshold {
                    if !isDragging {
                        handleDragStart()
                    }
                    handleDragChange(translation: value.translation)
                }
            }
            .onEnded { value in
                let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))

                if isDragging {
                    // Was dragging - finalize position
                    handleDragEnd(translation: value.translation, in: geometry)
                } else if distance <= tapThreshold && !isForceTouchActive {
                    // Small movement and not in force touch mode - it's a tap
                    toggleMenu()
                }
            }
    }
}

// MARK: - Scroll Guide Arrow Component

/// Sophisticated blurred chevron arrows - smaller than floating button
/// Style inspired by modern glassmorphism with white color and blur effects
private struct ScrollGuideArrow: View {
    let direction: ScrollDirection
    let isHovered: Bool
    let size: CGFloat

    // Chevron configuration - compact size (smaller than 48pt button)
    private let chevronWidth: CGFloat = 28
    private let chevronHeight: CGFloat = 10
    private let chevronSpacing: CGFloat = 6
    private let strokeWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            // Blurred background layers (creates the sophisticated blur effect)
            ForEach(0..<2, id: \.self) { layer in
                BlurredChevronLayer(
                    direction: direction,
                    width: chevronWidth + CGFloat(layer) * 8,
                    height: chevronHeight + CGFloat(layer) * 4,
                    spacing: chevronSpacing + CGFloat(layer) * 2,
                    blurRadius: CGFloat(layer + 1) * 8,
                    opacity: isHovered ? 0.6 - Double(layer) * 0.2 : 0.3 - Double(layer) * 0.1
                )
            }

            // Sharp chevron on top (the crisp outline)
            VStack(spacing: chevronSpacing) {
                // First chevron (outer/dimmer)
                ChevronShape()
                    .stroke(
                        Color.white.opacity(isHovered ? 0.5 : 0.3),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: chevronWidth, height: chevronHeight)

                // Second chevron (inner/brighter)
                ChevronShape()
                    .stroke(
                        Color.white.opacity(isHovered ? 0.9 : 0.6),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: chevronWidth - 4, height: chevronHeight - 2)
            }
            .rotationEffect(.degrees(direction == .top ? 180 : 0))
        }
        .frame(width: 40, height: 40)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }
}

/// Blurred chevron background layer for glow effect
private struct BlurredChevronLayer: View {
    let direction: ScrollDirection
    let width: CGFloat
    let height: CGFloat
    let spacing: CGFloat
    let blurRadius: CGFloat
    let opacity: Double

    var body: some View {
        VStack(spacing: spacing) {
            ChevronShape()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: width, height: height)

            ChevronShape()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: width - 4, height: height - 2)
        }
        .rotationEffect(.degrees(direction == .top ? 180 : 0))
        .blur(radius: blurRadius)
        .opacity(opacity)
    }
}

/// Custom chevron shape (V shape pointing down)
private struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let midX = rect.midX
        let topY = rect.minY
        let bottomY = rect.maxY
        let leftX = rect.minX
        let rightX = rect.maxX

        // Draw V shape pointing down
        path.move(to: CGPoint(x: leftX, y: topY))
        path.addLine(to: CGPoint(x: midX, y: bottomY))
        path.addLine(to: CGPoint(x: rightX, y: topY))

        return path
    }
}

// MARK: - Main Button Component

/// Visual-only button view - tap/drag handled by parent gesture
private struct MainButtonView: View {
    let isExpanded: Bool
    let isDragging: Bool
    var isForceTouchActive: Bool = false
    let size: CGFloat

    private var showGradientBackground: Bool {
        isExpanded || isForceTouchActive
    }

    var body: some View {
        ZStack {
            // Outer glow (only when expanded/force touch)
            Circle()
                .fill(ColorSystem.brand.opacity(isForceTouchActive ? 0.4 : 0.2))
                .frame(width: size + (isForceTouchActive ? 16 : 8), height: size + (isForceTouchActive ? 16 : 8))
                .blur(radius: isForceTouchActive ? 8 : 4)
                .opacity(showGradientBackground ? 1 : 0)

            // Gradient circle background (only when expanded/force touch)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [ColorSystem.brand, ColorSystem.brandDim],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: ColorSystem.brandGlow, radius: isDragging || isForceTouchActive ? 12 : 6)
                .opacity(showGradientBackground ? 1 : 0)

            // App Logo glow (only when collapsed)
            Circle()
                .fill(ColorSystem.brand.opacity(0.25))
                .frame(width: size + 6, height: size + 6)
                .blur(radius: 6)
                .opacity(showGradientBackground ? 0 : 1)

            // App Logo (only when collapsed)
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .shadow(color: ColorSystem.brand.opacity(0.3), radius: isDragging ? 12 : 8)
                .opacity(showGradientBackground ? 0 : 1)

            // Icon (only when expanded/force touch)
            Image(systemName: isForceTouchActive ? "arrow.up.arrow.down" : "xmark")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .opacity(showGradientBackground ? 1 : 0)
        }
        .scaleEffect(isForceTouchActive ? 1.1 : (isDragging ? 1.15 : 1.0))
        // Note: Animations are handled by withAnimation in parent's state change handlers
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
