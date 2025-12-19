import SwiftUI

/// Compact search bar for file explorer
/// Always visible, with loading indicator and clear button
struct ExplorerSearchBar: View {
    @Binding var query: String
    let isSearching: Bool
    let onQueryChange: (String) -> Void
    let onClear: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Search icon or loading indicator
            Group {
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(ColorSystem.textTertiary)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(isFocused ? ColorSystem.primary : ColorSystem.textTertiary)
                }
            }
            .frame(width: 20)

            // Text field
            TextField(placeholder, text: $query)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textPrimary)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: query) { _, newValue in
                    onQueryChange(newValue)
                }

            // Clear button (only when there's text)
            if !query.isEmpty {
                Button {
                    onClear()
                    Haptics.light()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
                .transition(.opacity.combined(with: .scale))
            }

            // Keyboard shortcut hint (iPad only)
            if !isCompact && !isFocused && query.isEmpty {
                Text("K")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(ColorSystem.textQuaternary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? ColorSystem.primary.opacity(0.5) : .clear, lineWidth: 1)
        )
        .animation(Animations.stateChange, value: query.isEmpty)
        .animation(Animations.stateChange, value: isFocused)
    }

    private var placeholder: String {
        isCompact ? "Search..." : "Search files..."
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Spacing.md) {
        // Idle state
        ExplorerSearchBar(
            query: .constant(""),
            isSearching: false,
            onQueryChange: { _ in },
            onClear: {}
        )

        // With query
        ExplorerSearchBar(
            query: .constant("ViewModel"),
            isSearching: false,
            onQueryChange: { _ in },
            onClear: {}
        )

        // Searching
        ExplorerSearchBar(
            query: .constant("Dashboard"),
            isSearching: true,
            onQueryChange: { _ in },
            onClear: {}
        )
    }
    .padding()
    .background(ColorSystem.terminalBg)
}
