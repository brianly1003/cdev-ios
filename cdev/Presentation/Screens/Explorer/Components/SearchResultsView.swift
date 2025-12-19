import SwiftUI

/// Search results list with loading, empty, and error states
struct SearchResultsView: View {
    let results: [FileEntry]
    let query: String
    let isSearching: Bool
    let error: AppError?
    let onSelect: (FileEntry) -> Void
    let onRetry: () -> Void

    var body: some View {
        Group {
            if isSearching && results.isEmpty {
                searchingView
            } else if let error = error {
                errorView(error)
            } else if results.isEmpty && !query.isEmpty && query.count >= 2 {
                emptyView
            } else if results.isEmpty {
                hintView
            } else {
                resultsList
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Results header
                HStack {
                    Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)

                // Result rows
                ForEach(results) { entry in
                    SearchResultRow(
                        entry: entry,
                        query: query,
                        onTap: {
                            onSelect(entry)
                            Haptics.selection()
                        }
                    )

                    if entry.id != results.last?.id {
                        Divider()
                            .background(ColorSystem.terminalBgHighlight)
                            .padding(.leading, Spacing.sm + 20 + Spacing.xs)
                    }
                }
            }
        }
        .background(ColorSystem.terminalBg)
    }

    // MARK: - Searching State

    private var searchingView: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                SearchSkeletonRow()
            }
            Spacer()
        }
        .background(ColorSystem.terminalBg)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(ColorSystem.textQuaternary)

            Text("No files matching")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)

            Text("'\(query)'")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textTertiary)
                .lineLimit(1)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(ColorSystem.terminalBg)
    }

    // MARK: - Hint State (query too short)

    private var hintView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(ColorSystem.textQuaternary)

            Text("Type to search files")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)

            Text("Minimum 2 characters")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(ColorSystem.terminalBg)
    }

    // MARK: - Error State

    private func errorView(_ error: AppError) -> some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(ColorSystem.error)

            Text("Search failed")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)

            Text(error.localizedDescription)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, Spacing.lg)

            Button {
                onRetry()
                Haptics.light()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                    Text("Retry")
                        .font(Typography.buttonLabel)
                }
                .foregroundStyle(ColorSystem.primary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(ColorSystem.primary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(ColorSystem.terminalBg)
    }
}

// MARK: - Skeleton Row

/// Loading skeleton for search results
private struct SearchSkeletonRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Icon placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(ColorSystem.terminalBgHighlight)
                .frame(width: 20, height: 20)

            // Text placeholders
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ColorSystem.terminalBgHighlight)
                    .frame(width: CGFloat.random(in: 100...180), height: 12)

                RoundedRectangle(cornerRadius: 2)
                    .fill(ColorSystem.terminalBgHighlight)
                    .frame(width: CGFloat.random(in: 60...120), height: 10)
            }

            Spacer()

            // Score placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(ColorSystem.terminalBgHighlight)
                .frame(width: 32, height: 16)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 40)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear { isAnimating = true }
    }
}

// MARK: - Preview

#Preview("Results") {
    SearchResultsView(
        results: [
            FileEntry(name: "DashboardViewModel.swift", path: "cdev/Presentation/DashboardViewModel.swift", type: .file, matchScore: 0.95),
            FileEntry(name: "Dashboard", path: "cdev/Presentation/Screens/Dashboard", type: .directory, matchScore: 0.72),
            FileEntry(name: "DashboardView.swift", path: "cdev/Presentation/DashboardView.swift", type: .file, matchScore: 0.68),
        ],
        query: "dash",
        isSearching: false,
        error: nil,
        onSelect: { _ in },
        onRetry: {}
    )
}

#Preview("Searching") {
    SearchResultsView(
        results: [],
        query: "test",
        isSearching: true,
        error: nil,
        onSelect: { _ in },
        onRetry: {}
    )
}

#Preview("Empty") {
    SearchResultsView(
        results: [],
        query: "xyznotfound",
        isSearching: false,
        error: nil,
        onSelect: { _ in },
        onRetry: {}
    )
}

#Preview("Error") {
    SearchResultsView(
        results: [],
        query: "test",
        isSearching: false,
        error: .connectionTimeout,
        onSelect: { _ in },
        onRetry: {}
    )
}
