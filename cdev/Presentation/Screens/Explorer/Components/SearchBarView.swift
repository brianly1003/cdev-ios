import SwiftUI

/// Compact search bar for file explorer
/// Style matches TerminalSearchBar for consistency
/// Uses ResponsiveLayout for iPhone/iPad adaptation
struct ExplorerSearchBar: View {
    @Binding var query: String
    let isSearching: Bool
    let onQueryChange: (String) -> Void
    let onClear: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Search icon or loading indicator
            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(ColorSystem.textTertiary)
                    .frame(width: 20)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.textTertiary)
            }

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
                .buttonStyle(.plain)
            }

            // Cancel button (always visible)
            Button {
                onClear()
                isFocused = false
                Haptics.light()
            } label: {
                Text("Cancel")
                    .font(Typography.buttonLabel)
                    .foregroundStyle(ColorSystem.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, layout.standardPadding)
        .frame(height: layout.buttonHeight)  // Fixed height for consistent sizing
        .background(ColorSystem.terminalBgElevated)
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
