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
struct ResponsiveSheetModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    func body(content: Content) -> some View {
        content
            .presentationDetents(isCompact ? [.medium, .large] : [.large])
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
