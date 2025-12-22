import SwiftUI
import UIKit

/// Keyboard shortcut handler for Quick Switcher
/// Supports ⌘K to open, ⌘1-9 for quick select, arrow keys for navigation
struct KeyboardShortcutModifier: ViewModifier {
    let isQuickSwitcherVisible: Bool
    let onQuickSwitcherToggle: () -> Void
    let onQuickSelect: (Int) -> Void  // ⌘1-9
    let onMoveUp: () -> Void         // ↑
    let onMoveDown: () -> Void       // ↓
    let onSelectCurrent: () -> Void  // Enter
    let onEscape: () -> Void         // ESC

    func body(content: Content) -> some View {
        content
            .background(
                KeyboardShortcutRepresentable(
                    isQuickSwitcherVisible: isQuickSwitcherVisible,
                    onQuickSwitcherToggle: onQuickSwitcherToggle,
                    onQuickSelect: onQuickSelect,
                    onMoveUp: onMoveUp,
                    onMoveDown: onMoveDown,
                    onSelectCurrent: onSelectCurrent,
                    onEscape: onEscape
                )
            )
    }
}

/// UIViewRepresentable wrapper for keyboard commands
private struct KeyboardShortcutRepresentable: UIViewRepresentable {
    let isQuickSwitcherVisible: Bool
    let onQuickSwitcherToggle: () -> Void
    let onQuickSelect: (Int) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSelectCurrent: () -> Void
    let onEscape: () -> Void

    func makeUIView(context: Context) -> KeyboardShortcutView {
        let view = KeyboardShortcutView()
        view.callbacks = KeyboardCallbacks(
            isQuickSwitcherVisible: { isQuickSwitcherVisible },
            onQuickSwitcherToggle: onQuickSwitcherToggle,
            onQuickSelect: onQuickSelect,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onSelectCurrent: onSelectCurrent,
            onEscape: onEscape
        )
        return view
    }

    func updateUIView(_ uiView: KeyboardShortcutView, context: Context) {
        uiView.callbacks = KeyboardCallbacks(
            isQuickSwitcherVisible: { isQuickSwitcherVisible },
            onQuickSwitcherToggle: onQuickSwitcherToggle,
            onQuickSelect: onQuickSelect,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onSelectCurrent: onSelectCurrent,
            onEscape: onEscape
        )
    }
}

struct KeyboardCallbacks {
    let isQuickSwitcherVisible: () -> Bool
    let onQuickSwitcherToggle: () -> Void
    let onQuickSelect: (Int) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSelectCurrent: () -> Void
    let onEscape: () -> Void
}

/// Custom UIView that can become first responder for keyboard commands
class KeyboardShortcutView: UIView {
    var callbacks: KeyboardCallbacks?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []

        // ⌘K - Toggle Quick Switcher (always available)
        commands.append(UIKeyCommand(
            input: "k",
            modifierFlags: .command,
            action: #selector(handleQuickSwitcherToggle)
        ))

        // Only add switcher-specific commands when visible
        if callbacks?.isQuickSwitcherVisible() == true {
            // ⌘1-9 - Quick select
            for i in 1...9 {
                commands.append(UIKeyCommand(
                    input: "\(i)",
                    modifierFlags: .command,
                    action: #selector(handleQuickSelect(_:))
                ))
            }

            // Arrow keys - Navigation
            commands.append(UIKeyCommand(
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                action: #selector(handleMoveUp)
            ))

            commands.append(UIKeyCommand(
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                action: #selector(handleMoveDown)
            ))

            // Enter - Select current
            commands.append(UIKeyCommand(
                input: "\r",  // Return key
                modifierFlags: [],
                action: #selector(handleSelectCurrent)
            ))

            // ESC - Close
            commands.append(UIKeyCommand(
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                action: #selector(handleEscape)
            ))
        }

        return commands
    }

    @objc private func handleQuickSwitcherToggle() {
        callbacks?.onQuickSwitcherToggle()
    }

    @objc private func handleQuickSelect(_ command: UIKeyCommand) {
        guard let input = command.input,
              let number = Int(input) else { return }
        callbacks?.onQuickSelect(number - 1)  // Convert to 0-indexed
    }

    @objc private func handleMoveUp() {
        callbacks?.onMoveUp()
    }

    @objc private func handleMoveDown() {
        callbacks?.onMoveDown()
    }

    @objc private func handleSelectCurrent() {
        callbacks?.onSelectCurrent()
    }

    @objc private func handleEscape() {
        callbacks?.onEscape()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        }
    }
}

// MARK: - View Extension

extension View {
    /// Add keyboard shortcut support for Quick Switcher
    func quickSwitcherKeyboardShortcuts(
        isVisible: Bool,
        onToggle: @escaping () -> Void,
        onQuickSelect: @escaping (Int) -> Void,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onSelectCurrent: @escaping () -> Void,
        onEscape: @escaping () -> Void
    ) -> some View {
        modifier(KeyboardShortcutModifier(
            isQuickSwitcherVisible: isVisible,
            onQuickSwitcherToggle: onToggle,
            onQuickSelect: onQuickSelect,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onSelectCurrent: onSelectCurrent,
            onEscape: onEscape
        ))
    }
}
