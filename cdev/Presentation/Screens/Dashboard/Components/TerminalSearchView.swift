import SwiftUI

// MARK: - Search Filter Types

/// Quick filter options for Terminal search
enum TerminalSearchFilter: String, CaseIterable, Identifiable {
    case user = "User"
    case claude = "Claude"
    case tools = "Tools"
    case errors = "Errors"
    case code = "Code"

    var id: String { rawValue }

    /// Icon for the filter chip
    var icon: String {
        switch self {
        case .user: return "person"
        case .claude: return "sparkles"
        case .tools: return "wrench.and.screwdriver"
        case .errors: return "exclamationmark.triangle"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Check if an element matches this filter
    func matches(_ element: ChatElement) -> Bool {
        switch self {
        case .user:
            return element.type == .userInput
        case .claude:
            return element.type == .assistantText || element.type == .thinking
        case .tools:
            return element.type == .toolCall || element.type == .toolResult
        case .errors:
            if case .toolResult(let content) = element.content {
                return content.isError
            }
            return false
        case .code:
            // Check if content contains code blocks
            return element.searchableText.contains("```")
        }
    }
}

// MARK: - Search State

/// Observable search state for Terminal
@MainActor
final class TerminalSearchState: ObservableObject {
    @Published var isActive: Bool = false
    @Published var searchText: String = ""
    @Published var activeFilters: Set<TerminalSearchFilter> = []
    @Published var currentMatchIndex: Int = 0
    @Published var matchingElementIds: [String] = []

    /// Total match count
    var matchCount: Int { matchingElementIds.count }

    /// Whether there are any matches
    var hasMatches: Bool { !matchingElementIds.isEmpty }

    /// Current match display (e.g., "3/15" or "3 of 15")
    func matchDisplay(compact: Bool) -> String {
        guard hasMatches else { return "" }
        let current = currentMatchIndex + 1
        return compact ? "\(current)/\(matchCount)" : "\(current) of \(matchCount)"
    }

    /// Current highlighted element ID
    var currentMatchId: String? {
        guard hasMatches, currentMatchIndex < matchingElementIds.count else { return nil }
        return matchingElementIds[currentMatchIndex]
    }

    /// Navigate to next match
    func nextMatch() {
        guard hasMatches else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchCount
        Haptics.selection()
    }

    /// Navigate to previous match
    func previousMatch() {
        guard hasMatches else { return }
        currentMatchIndex = currentMatchIndex > 0 ? currentMatchIndex - 1 : matchCount - 1
        Haptics.selection()
    }

    /// Toggle a filter
    func toggleFilter(_ filter: TerminalSearchFilter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
        Haptics.selection()
    }

    /// Clear search state
    func clear() {
        searchText = ""
        activeFilters.removeAll()
        currentMatchIndex = 0
        matchingElementIds.removeAll()
    }

    /// Dismiss search
    func dismiss() {
        isActive = false
        clear()
    }
}

// MARK: - Search Bar View

/// Compact search bar with navigation controls
struct TerminalSearchBar: View {
    @ObservedObject var state: TerminalSearchState
    @FocusState private var isFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.textTertiary)

            // Text field
            TextField("Search messages...", text: $state.searchText)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textPrimary)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            // Match count and navigation (only when has text)
            if !state.searchText.isEmpty {
                HStack(spacing: 4) {
                    // Match count
                    Text(state.matchDisplay(compact: isCompact))
                        .font(Typography.badge)
                        .foregroundStyle(state.hasMatches ? ColorSystem.textSecondary : ColorSystem.textQuaternary)
                        .fixedSize()

                    // Navigation arrows
                    if state.hasMatches {
                        Button { state.previousMatch() } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ColorSystem.textSecondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)

                        Button { state.nextMatch() } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ColorSystem.textSecondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Clear button
                Button {
                    state.searchText = ""
                    Haptics.light()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // Cancel button
            Button {
                state.dismiss()
                Haptics.light()
            } label: {
                Text("Cancel")
                    .font(Typography.buttonLabel)
                    .foregroundStyle(ColorSystem.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Filter Chips View

/// Horizontal scrolling filter chips
struct TerminalFilterChips: View {
    @ObservedObject var state: TerminalSearchState
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(TerminalSearchFilter.allCases) { filter in
                    FilterChip(
                        filter: filter,
                        isSelected: state.activeFilters.contains(filter),
                        compact: isCompact
                    ) {
                        state.toggleFilter(filter)
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
        }
        .background(ColorSystem.terminalBgElevated)
    }
}

/// Individual filter chip button
private struct FilterChip: View {
    let filter: TerminalSearchFilter
    let isSelected: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: compact ? 10 : 11))

                Text(filter.rawValue)
                    .font(compact ? Typography.badge : Typography.terminalSmall)
            }
            .foregroundStyle(isSelected ? ColorSystem.terminalBg : ColorSystem.textSecondary)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 5)
            .background(isSelected ? ColorSystem.primary : ColorSystem.terminalBgHighlight)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Combined Search Header

/// Combined search bar and filters
struct TerminalSearchHeader: View {
    @ObservedObject var state: TerminalSearchState

    var body: some View {
        VStack(spacing: 0) {
            TerminalSearchBar(state: state)

            Divider()
                .background(ColorSystem.terminalBgHighlight)

            TerminalFilterChips(state: state)
        }
    }
}

// MARK: - Search Button (for tab bar)

/// Compact search button to activate search mode
struct TerminalSearchButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(isActive ? ColorSystem.primary : ColorSystem.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ChatElement Search Extension

extension ChatElement {
    /// Searchable text content for this element
    var searchableText: String {
        switch content {
        case .userInput(let c):
            return c.text
        case .assistantText(let c):
            return c.text
        case .toolCall(let c):
            return "\(c.tool) \(c.display) \(c.params.values.joined(separator: " "))"
        case .toolResult(let c):
            return "\(c.toolName) \(c.summary) \(c.fullContent)"
        case .diff(let c):
            return c.filePath
        case .thinking(let c):
            return c.text
        case .interrupted(let c):
            return c.message
        case .contextCompaction(let c):
            return c.summary
        }
    }

    /// Check if element matches search criteria
    func matches(searchText: String, filters: Set<TerminalSearchFilter>) -> Bool {
        // If no search text and no filters, don't match
        if searchText.isEmpty && filters.isEmpty {
            return false
        }

        // Check filters first (if any active)
        if !filters.isEmpty {
            let matchesAnyFilter = filters.contains { $0.matches(self) }
            if !matchesAnyFilter {
                return false
            }
        }

        // If no search text but passed filter check, it's a match
        if searchText.isEmpty {
            return true
        }

        // Case-insensitive text search
        return searchableText.localizedCaseInsensitiveContains(searchText)
    }
}

// MARK: - Text Highlighting

/// Highlight matching text in a string
struct HighlightedText: View {
    let text: String
    let searchText: String
    let highlightColor: Color

    init(_ text: String, highlighting searchText: String, color: Color = ColorSystem.warning) {
        self.text = text
        self.searchText = searchText
        self.highlightColor = color
    }

    var body: some View {
        if searchText.isEmpty {
            Text(text)
        } else {
            Text(attributedText)
        }
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(text)
        var searchStart = text.startIndex

        while let range = text[searchStart...].range(of: searchText, options: .caseInsensitive) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = highlightColor.opacity(0.3)
                attributed[attrRange].foregroundColor = highlightColor
            }
            searchStart = range.upperBound
        }

        return attributed
    }
}
