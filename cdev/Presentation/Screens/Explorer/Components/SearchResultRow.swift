import SwiftUI

/// Single search result row with fuzzy match highlighting
struct SearchResultRow: View {
    let entry: FileEntry
    let query: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                // File/folder icon
                Image(systemName: entry.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                // File info
                VStack(alignment: .leading, spacing: 2) {
                    // Filename with highlighted matches
                    Text(highlightedName)
                        .font(Typography.terminal)
                        .lineLimit(1)

                    // Parent path
                    if !entry.parentPath.isEmpty {
                        Text(entry.parentPath)
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textQuaternary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Match score badge (if available)
                if let score = entry.matchScore {
                    Text("\(Int(score * 100))%")
                        .font(Typography.badge)
                        .foregroundStyle(scoreColor(for: score))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(scoreColor(for: score).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Chevron for directories
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorSystem.textQuaternary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: 40)
            .background(ColorSystem.terminalBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Properties

    private var iconColor: Color {
        if entry.isDirectory {
            return ColorSystem.warning  // Folder icon color
        }
        return ColorSystem.textSecondary
    }

    /// Highlight matching characters in the filename
    private var highlightedName: AttributedString {
        highlightMatches(in: entry.name, query: query)
    }

    /// Get color based on score (higher = greener)
    private func scoreColor(for score: Double) -> Color {
        if score >= 0.8 {
            return ColorSystem.success
        } else if score >= 0.5 {
            return ColorSystem.primary
        } else {
            return ColorSystem.textTertiary
        }
    }

    /// Highlight matching characters in text using fuzzy matching
    private func highlightMatches(in text: String, query: String) -> AttributedString {
        var result = AttributedString(text)

        // Set default color
        result.foregroundColor = ColorSystem.textPrimary

        guard !query.isEmpty else { return result }

        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        // Find matching character positions (fuzzy match)
        var textIndex = lowercasedText.startIndex
        var matchPositions: [Int] = []

        for queryChar in lowercasedQuery {
            // Find next occurrence of this character
            while textIndex < lowercasedText.endIndex {
                let currentIndex = lowercasedText.distance(from: lowercasedText.startIndex, to: textIndex)
                if lowercasedText[textIndex] == queryChar {
                    matchPositions.append(currentIndex)
                    textIndex = lowercasedText.index(after: textIndex)
                    break
                }
                textIndex = lowercasedText.index(after: textIndex)
            }
        }

        // Apply highlight to matched positions
        for position in matchPositions {
            guard position < text.count else { continue }
            let start = result.index(result.startIndex, offsetByCharacters: position)
            let end = result.index(start, offsetByCharacters: 1)
            result[start..<end].foregroundColor = ColorSystem.primary
            // Use a slightly bolder weight for highlighted characters
            result[start..<end].font = Typography.terminal.bold()
        }

        return result
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        SearchResultRow(
            entry: FileEntry(
                name: "DashboardViewModel.swift",
                path: "cdev/Presentation/Screens/Dashboard/DashboardViewModel.swift",
                type: .file,
                matchScore: 0.95
            ),
            query: "dashvm",
            onTap: {}
        )

        Divider().background(ColorSystem.terminalBgHighlight)

        SearchResultRow(
            entry: FileEntry(
                name: "Explorer",
                path: "cdev/Presentation/Screens/Explorer",
                type: .directory,
                matchScore: 0.72
            ),
            query: "exp",
            onTap: {}
        )

        Divider().background(ColorSystem.terminalBgHighlight)

        SearchResultRow(
            entry: FileEntry(
                name: "ColorSystem.swift",
                path: "cdev/Core/Design/ColorSystem.swift",
                type: .file,
                matchScore: 0.45
            ),
            query: "color",
            onTap: {}
        )
    }
    .background(ColorSystem.terminalBg)
}
