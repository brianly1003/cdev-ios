import SwiftUI

/// Floating button that appears when keyboard is visible and dismisses it when tapped.
/// Use as an overlay on any view that has text input.
///
/// Usage:
/// ```swift
/// SomeView()
///     .floatingKeyboardDismissButton()
/// ```
struct FloatingKeyboardDismissButton: View {
    @State private var isKeyboardVisible = false

    var body: some View {
        Group {
            if isKeyboardVisible {
                Button {
                    hideKeyboard()
                    Haptics.light()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(ColorSystem.primary)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    /// Dismiss keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

// MARK: - View Modifier

/// View modifier that adds a floating keyboard dismiss button
struct FloatingKeyboardDismissModifier: ViewModifier {
    let alignment: Alignment
    let padding: EdgeInsets

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                FloatingKeyboardDismissButton()
                    .padding(.top, padding.top)
                    .padding(.leading, padding.leading)
                    .padding(.bottom, padding.bottom)
                    .padding(.trailing, padding.trailing)
            }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a floating keyboard dismiss button that appears when keyboard is visible.
    /// - Parameters:
    ///   - alignment: Where to position the button (default: .bottomTrailing)
    ///   - padding: Padding from the edge (default: 16pt on bottom and trailing)
    /// - Returns: View with floating keyboard dismiss button overlay
    func floatingKeyboardDismissButton(
        alignment: Alignment = .bottomTrailing,
        padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: Spacing.md, trailing: Spacing.md)
    ) -> some View {
        modifier(FloatingKeyboardDismissModifier(alignment: alignment, padding: padding))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        TextField("Type something...", text: .constant(""))
            .textFieldStyle(.roundedBorder)
            .padding()

        Spacer()
    }
    .floatingKeyboardDismissButton()
}
