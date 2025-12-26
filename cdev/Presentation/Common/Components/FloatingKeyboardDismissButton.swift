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
    @State private var keyboardTopScreen: CGFloat = 0  // Keyboard top in screen coordinates

    var body: some View {
        GeometryReader { geometry in
            let globalFrame = geometry.frame(in: .global)
            // Convert keyboard screen position to local coordinates
            let keyboardTopLocal = keyboardTopScreen - globalFrame.minY
            // Position button above keyboard (clamped to visible area)
            let editTextOffset: CGFloat = 60
            let buttonY = min(keyboardTopLocal - 30, geometry.size.height - 30) - editTextOffset

            if isKeyboardVisible && buttonY > 0 {
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
                .opacity(0.8)
                .position(
                    x: geometry.size.width - 16,
                    y: buttonY
                )
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    AppLogger.log("[FloatingKeyboardDismiss] Button position - globalFrame=\(globalFrame), keyboardTopLocal=\(keyboardTopLocal), buttonY=\(buttonY)")
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardTopScreen = frame.origin.y
                isKeyboardVisible = true
                AppLogger.log("[FloatingKeyboardDismiss] Keyboard SHOW - keyboardTopScreen=\(keyboardTopScreen)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            AppLogger.log("[FloatingKeyboardDismiss] Keyboard HIDE")
            isKeyboardVisible = false
            keyboardTopScreen = 0
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
