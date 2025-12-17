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
}

struct DismissKeyboardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
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
