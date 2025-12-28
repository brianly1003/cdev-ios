import SwiftUI
import UIKit

/// Reusable copy button with visual feedback
/// Shows checkmark icon briefly after successful copy
/// Automatically handles haptic feedback via centralized Haptics utility
struct CopyButton: View {
    /// Text to copy to clipboard
    let text: String

    /// Optional label (if nil, shows icon only)
    var label: String?

    /// Icon size (default 12pt)
    var iconSize: CGFloat = 12

    /// Style variant
    var style: CopyButtonStyle = .icon

    @State private var isCopied = false

    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            switch style {
            case .icon:
                iconOnlyLabel
            case .iconWithText:
                iconWithTextLabel
            case .compact:
                compactLabel
            }
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .opacity(text.isEmpty ? 0.5 : 1)
    }

    // MARK: - Label Styles

    private var iconOnlyLabel: some View {
        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            .font(.system(size: iconSize))
            .foregroundStyle(isCopied ? ColorSystem.success : ColorSystem.textTertiary)
            .contentTransition(.symbolEffect(.replace))
    }

    private var iconWithTextLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: iconSize))
            Text(isCopied ? "Copied" : (label ?? "Copy"))
                .font(.system(size: iconSize, weight: .medium))
        }
        .foregroundStyle(isCopied ? ColorSystem.success : ColorSystem.textTertiary)
        .contentTransition(.symbolEffect(.replace))
    }

    private var compactLabel: some View {
        HStack(spacing: 2) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: iconSize - 2))
            if let label = label {
                Text(isCopied ? "Copied" : label)
                    .font(.system(size: iconSize - 2, weight: .medium))
            }
        }
        .foregroundStyle(isCopied ? ColorSystem.success : ColorSystem.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(Capsule())
        .contentTransition(.symbolEffect(.replace))
    }

    // MARK: - Copy Action

    private func copyToClipboard() {
        guard !text.isEmpty else { return }

        UIPasteboard.general.string = text
        Haptics.selection()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isCopied = true
        }

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isCopied = false
            }
        }
    }
}

// MARK: - Style Enum

enum CopyButtonStyle {
    /// Icon only (default)
    case icon
    /// Icon with text label
    case iconWithText
    /// Compact pill style with background
    case compact
}

// MARK: - Floating Copied Toast

/// Floating toast notification for copy feedback
/// Use this for context menus or when you need a floating indicator
struct CopiedToast: View {
    var message: String = "Copied to clipboard"

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ColorSystem.success)
            Text(message)
                .font(Typography.bannerBody)
        }
        .foregroundStyle(ColorSystem.textPrimary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(ColorSystem.terminalBgElevated)
        .overlay(
            Capsule()
                .stroke(ColorSystem.primary.opacity(0.3), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
        .shadow(color: ColorSystem.primary.opacity(0.2), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview("Copy Button Styles") {
    VStack(spacing: 20) {
        // Icon only
        HStack {
            Text("Icon only:")
            Spacer()
            CopyButton(text: "Hello World")
        }

        // Icon with text
        HStack {
            Text("With text:")
            Spacer()
            CopyButton(text: "Hello World", style: .iconWithText)
        }

        // Compact
        HStack {
            Text("Compact:")
            Spacer()
            CopyButton(text: "Hello World", label: "Copy", style: .compact)
        }

        // Custom label
        HStack {
            Text("Custom label:")
            Spacer()
            CopyButton(text: "curl -X GET ...", label: "cURL", style: .iconWithText)
        }

        Divider()

        // Toast
        CopiedToast()
    }
    .padding()
    .background(ColorSystem.terminalBg)
}
