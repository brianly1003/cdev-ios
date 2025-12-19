import SwiftUI

/// Scrollable list of file entries with lazy loading
/// Supports pull-to-refresh and empty states
struct DirectoryListView: View {
    let entries: [FileEntry]
    let currentPath: String
    let onSelect: (FileEntry) -> Void
    let onBack: () -> Void

    // Scroll request (from floating toolkit long-press)
    var scrollRequest: ScrollDirection?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Top anchor for scroll to top
                    Color.clear
                        .frame(height: 1)
                        .id("explorerTop")

                    // Parent directory row (if not at root)
                    if !currentPath.isEmpty {
                        ParentDirectoryRow(onTap: onBack)
                    }

                    // File entries
                    ForEach(entries) { entry in
                        Button {
                            Haptics.selection()
                            onSelect(entry)
                        } label: {
                            FileRowView(entry: entry)
                        }
                        .buttonStyle(.plain)

                        // Subtle separator
                        if entry.id != entries.last?.id {
                            Divider()
                                .background(ColorSystem.terminalBgHighlight)
                                .padding(.leading, Spacing.sm + 3 + Spacing.xs + 20)  // Align with text
                        }
                    }

                    // Bottom anchor for scroll to bottom
                    Color.clear
                        .frame(height: 1)
                        .id("explorerBottom")
                }
            }
            .background(ColorSystem.terminalBg)
            .onChange(of: scrollRequest) { _, direction in
                guard let direction = direction else { return }
                handleScrollRequest(direction: direction, proxy: proxy)
            }
        }
    }

    private func handleScrollRequest(direction: ScrollDirection, proxy: ScrollViewProxy) {
        switch direction {
        case .top:
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo("explorerTop", anchor: .top)
            }
        case .bottom:
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo("explorerBottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - Parent Directory Row

/// Row for navigating to parent directory (..)
struct ParentDirectoryRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                // Spacer for git status alignment
                Color.clear
                    .frame(width: 3)

                // Folder up icon
                Image(systemName: "arrow.turn.up.left")
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.textSecondary)
                    .frame(width: 20)

                Text("..")
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textSecondary)

                Spacer()

                Text("Parent directory")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
            .padding(.trailing, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: 36)
            .background(ColorSystem.terminalBg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider()
            .background(ColorSystem.terminalBgHighlight)
            .padding(.leading, Spacing.sm + 3 + Spacing.xs + 20)
    }
}

// MARK: - Empty State

/// Empty directory state view
struct EmptyDirectoryView: View {
    let isRoot: Bool

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: isRoot ? "folder.badge.questionmark" : "folder")
                .font(.system(size: 48))
                .foregroundStyle(ColorSystem.textTertiary)

            Text(isRoot ? "No Repository Connected" : "Empty Directory")
                .font(Typography.bodyBold)
                .foregroundStyle(ColorSystem.textSecondary)

            Text(isRoot
                 ? "Connect to a workspace to browse files"
                 : "This directory contains no files")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }
}

// MARK: - Loading State

/// Loading skeleton for directory list
struct DirectoryLoadingView: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                SkeletonFileRow()
            }
        }
    }
}

/// Skeleton placeholder row
struct SkeletonFileRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Git status placeholder
            Color.clear
                .frame(width: 3)

            // Icon placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(ColorSystem.terminalBgHighlight)
                .frame(width: 20, height: 20)

            // Text placeholder
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ColorSystem.terminalBgHighlight)
                    .frame(width: CGFloat.random(in: 80...160), height: 12)

                RoundedRectangle(cornerRadius: 2)
                    .fill(ColorSystem.terminalBgHighlight)
                    .frame(width: 50, height: 10)
            }

            Spacer()
        }
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 36)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            Animation.easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview

#Preview {
    DirectoryListView(
        entries: [
            FileEntry(name: "Components", path: "src/Components", type: .directory, childrenCount: 12),
            FileEntry(name: "App.swift", path: "src/App.swift", type: .file, size: 3450, gitStatus: .modified),
            FileEntry(name: "Utils.swift", path: "src/Utils.swift", type: .file, size: 1280),
        ],
        currentPath: "src",
        onSelect: { _ in },
        onBack: {}
    )
    .background(ColorSystem.terminalBg)
}
