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

    @AppStorage("toolkit_position_x") private var savedX: Double = -1
    @AppStorage("toolkit_position_y") private var savedY: Double = -1

    private let buttonSize: CGFloat = 48
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
                    .animation(.easeInOut(duration: 0.3), value: isIdle)
                    .position(currentPosition(in: geometry))
                    .gesture(longPressScrollGesture())
                    .simultaneousGesture(tapAndDragGesture(in: geometry))
                    .zIndex(2)
                    .transition(.scale.combined(with: .opacity))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isForceTouchActive)
            .animation(.easeInOut(duration: 0.15), value: hoveredScrollDirection)
            .onAppear {
                AppLogger.log("[FloatingToolkit] onAppear called")
                initializePosition(in: geometry)
                startIdleTimer()
                lastScreenSize = geometry.size
            }
            .onDisappear {
                AppLogger.log("[FloatingToolkit] onDisappear called")
                cancelIdleTimer()
            }
            .onChange(of: geometry.size) { oldSize, newSize in
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

        let padding: CGFloat = 10
        let minX = buttonSize / 2 + padding
        let maxX = max(minX + 1, newSize.width - buttonSize / 2 - padding)
        let minY = buttonSize / 2 + padding + geometry.safeAreaInsets.top
        let maxY = max(minY + 1, newSize.height - buttonSize / 2 - padding - geometry.safeAreaInsets.bottom - 50)

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
        let maxX = max(minX + 1, geometry.size.width - itemPadding) // Guard against negative
        let minY = geometry.safeAreaInsets.top + itemPadding
        let maxY = max(minY + 1, geometry.size.height - geometry.safeAreaInsets.bottom - itemPadding - 50) // Guard against negative

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

    // MARK: - Drag Handlers (called by UIKit wrapper)

    private func handleDragStart() {
        isDragging = true
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
        isDragging = false
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

        // Bounds (with guards against negative values during keyboard animation)
        let padding: CGFloat = 10
        let minX = buttonSize / 2 + padding
        let maxX = max(minX + 1, geometry.size.width - buttonSize / 2 - padding)
        let minY = buttonSize / 2 + padding + geometry.safeAreaInsets.top
        let maxY = max(minY + 1, geometry.size.height - buttonSize / 2 - padding - geometry.safeAreaInsets.bottom - 50)

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

    var body: some View {
        ZStack {
            // Outer glow (intensified during force touch)
            Circle()
                .fill(ColorSystem.brand.opacity(isForceTouchActive ? 0.4 : 0.2))
                .frame(width: size + (isForceTouchActive ? 16 : 8), height: size + (isForceTouchActive ? 16 : 8))
                .blur(radius: isForceTouchActive ? 8 : 4)

            // Main circle
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

            // Icon (changes during force touch)
            Image(systemName: isForceTouchActive ? "arrow.up.arrow.down" : (isExpanded ? "xmark" : "wrench.and.screwdriver.fill"))
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .scaleEffect(isForceTouchActive ? 1.1 : (isDragging ? 1.15 : 1.0))
        .animation(.spring(response: 0.2), value: isDragging)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isForceTouchActive)
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
