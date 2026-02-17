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
    /// Dynamic offset to position button above input bar (accounts for multi-line expansion)
    /// Default is 0 - pass actual height only for views with an action bar (e.g., DashboardView)
    var inputBarHeight: CGFloat = 0
    /// Prompt text to calculate dynamic height based on line count
    var promptText: String = ""
    /// Whether bash mode is enabled (adds extra height for bash mode indicator)
    var isBashMode: Bool = false

    @State private var isKeyboardVisible = false
    @State private var keyboardTopScreen: CGFloat = 0  // Keyboard top in screen coordinates

    /// Calculate extra offset based on prompt text lines
    private var textHeightOffset: CGFloat {
        let lineCount = promptText.components(separatedBy: "\n").count
        let estimatedLines = max(lineCount, Int(ceil(Double(promptText.count) / 40)))  // ~40 chars per line
        let extraLines = max(0, min(estimatedLines - 1, 6))  // Cap at 6 extra lines
        return CGFloat(extraLines) * 16  // 16pt per extra line
    }

    /// Extra offset for bash mode indicator
    private var bashModeOffset: CGFloat {
        isBashMode ? 20 : 0  // Height of "bash mode enabled" text + padding
    }

    var body: some View {
        GeometryReader { geometry in
            let globalFrame = geometry.frame(in: .global)
            // Convert keyboard screen position to local coordinates
            let keyboardTopLocal = keyboardTopScreen - globalFrame.minY
            // Position button above the input bar
            // Base offset of 22 accounts for button center (44pt button / 2) plus gap
            // Extra spacing ensures it clears the action bar even with multiline input
            let totalOffset = inputBarHeight + textHeightOffset + bashModeOffset + 22 + 32
            let buttonY = keyboardTopLocal - totalOffset

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
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isKeyboardVisible)
        .animation(.easeOut(duration: 0.15), value: inputBarHeight)
        .animation(.easeOut(duration: 0.1), value: textHeightOffset)
        .animation(.easeOut(duration: 0.15), value: isBashMode)  // Animate when bash mode toggles
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
