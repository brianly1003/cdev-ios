import SwiftUI

// MARK: - Conditional Modifiers

extension View {
    /// Apply modifier conditionally
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Apply modifier conditionally with else clause
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        if ifTransform: (Self) -> TrueContent,
        else elseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }

    /// Apply modifier if value is not nil
    @ViewBuilder
    func ifLet<Value, Content: View>(
        _ value: Value?,
        transform: (Self, Value) -> Content
    ) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Loading Overlay

extension View {
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        if let message = message {
                            Text(message)
                                .font(Typography.callout)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(Spacing.lg)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                }
            }
        }
    }
}

// MARK: - Error Alert

extension View {
    func errorAlert(_ error: Binding<AppError?>) -> some View {
        alert(
            "Error",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            ),
            presenting: error.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            VStack {
                Text(error.localizedDescription)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Animations

extension View {
    /// Standard spring animation
    func springAnimation<Value: Equatable>(value: Value) -> some View {
        animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
    }

    /// Quick fade animation
    func fadeAnimation<Value: Equatable>(value: Value) -> some View {
        animation(.easeInOut(duration: 0.2), value: value)
    }
}

// MARK: - Keyboard Dismissal

extension View {
    /// Dismiss keyboard when tapping outside text fields
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardModifier())
    }

    /// Programmatically dismiss keyboard
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Execute action when keyboard shows
    func onKeyboardShow(perform action: @escaping () -> Void) -> some View {
        modifier(KeyboardShowModifier(onShow: action))
    }
}

struct DismissKeyboardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            )
    }
}

struct KeyboardShowModifier: ViewModifier {
    let onShow: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                onShow()
            }
    }
}

// MARK: - Keyboard Adaptive Modifier

/// Tracks keyboard height and provides it as padding
/// Use this when automatic keyboard avoidance doesn't work (e.g., with TabView .page style)
struct KeyboardAdaptiveModifier: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.easeOut(duration: animationDuration)) {
                    keyboardHeight = keyboardFrame.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.easeOut(duration: animationDuration)) {
                    keyboardHeight = 0
                }
            }
    }
}

extension View {
    /// Adds padding equal to keyboard height when keyboard is shown
    /// Use when automatic keyboard avoidance doesn't work
    func keyboardAdaptive() -> some View {
        modifier(KeyboardAdaptiveModifier())
    }
}

// MARK: - Button Press Effect

struct ButtonPressEffect: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func pressEffect() -> some View {
        modifier(ButtonPressEffect())
    }
}

// MARK: - Responsive Sheet Presentation

/// Modifier for device-appropriate sheet presentation
/// - iPhone: Medium and large detents (swipeable)
/// - iPad: Large only (full height for more content)
/// Note: Uses UIDevice.current.userInterfaceIdiom instead of @Environment(\.horizontalSizeClass)
/// because sheets have their own environment context that may not reflect the actual device type.
struct ResponsiveSheetModifier: ViewModifier {
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    func body(content: Content) -> some View {
        content
            .presentationDetents(isPhone ? [.medium, .large] : [.large])
            .presentationDragIndicator(.visible)
    }
}

extension View {
    /// Apply responsive sheet presentation detents
    /// - iPhone: [.medium, .large] for swipeable half/full
    /// - iPad: [.large] for full height
    func responsiveSheet() -> some View {
        modifier(ResponsiveSheetModifier())
    }
}

// MARK: - Debug Logging Modifiers

#if DEBUG
/// Logs view lifecycle events (onAppear/onDisappear) in debug builds
struct ViewLifecycleLogger: ViewModifier {
    let viewName: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppLogger.log("[\(viewName)] onAppear")
            }
            .onDisappear {
                AppLogger.log("[\(viewName)] onDisappear")
            }
    }
}

extension View {
    /// Log view lifecycle events (onAppear/onDisappear) in debug builds
    /// - Parameter name: The name to identify this view in logs
    func logLifecycle(_ name: String) -> some View {
        modifier(ViewLifecycleLogger(viewName: name))
    }

    /// Present a sheet with automatic logging of presentation and dismissal
    /// - Parameters:
    ///   - item: Binding to identifiable item that triggers sheet
    ///   - name: Name to identify this sheet in logs
    ///   - content: View builder for sheet content
    func loggedSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        name: String,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        self.sheet(item: item, onDismiss: {
            AppLogger.log("[\(name)] Sheet dismissed")
        }) { item in
            content(item)
                .onAppear {
                    AppLogger.log("[\(name)] Sheet presented: \(item.id)")
                }
        }
    }

    /// Present a sheet with automatic logging (boolean binding version)
    /// - Parameters:
    ///   - isPresented: Binding to boolean that triggers sheet
    ///   - name: Name to identify this sheet in logs
    ///   - content: View builder for sheet content
    func loggedSheet<Content: View>(
        isPresented: Binding<Bool>,
        name: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.sheet(isPresented: isPresented, onDismiss: {
            AppLogger.log("[\(name)] Sheet dismissed")
        }) {
            content()
                .onAppear {
                    AppLogger.log("[\(name)] Sheet presented")
                }
        }
    }

    /// Log state changes with old and new values
    /// - Parameters:
    ///   - value: The value to observe
    ///   - name: Name to identify this state in logs
    func logStateChange<V: Equatable>(of value: V, name: String) -> some View {
        self.onChange(of: value) { oldValue, newValue in
            AppLogger.log("[\(name)] state changed: '\(oldValue)' → '\(newValue)'")
        }
    }
}
#else
// No-op versions for release builds
extension View {
    func logLifecycle(_ name: String) -> some View { self }

    func loggedSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        name: String,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        self.sheet(item: item, content: content)
    }

    func loggedSheet<Content: View>(
        isPresented: Binding<Bool>,
        name: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.sheet(isPresented: isPresented, content: content)
    }

    func logStateChange<V: Equatable>(of value: V, name: String) -> some View { self }
}
#endif
