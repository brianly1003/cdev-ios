import SwiftUI

/// Compact diff list - file changes view
struct DiffListView: View {
    let diffs: [DiffEntry]
    let onClear: () -> Void

    @State private var selectedDiff: DiffEntry?

    var body: some View {
        Group {
            if diffs.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Changes",
                    subtitle: "File changes will appear here"
                )
            } else {
                List(diffs) { diff in
                    DiffEntryRow(diff: diff)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedDiff = diff
                            Haptics.selection()
                        }
                        .listRowInsets(EdgeInsets(
                            top: Spacing.xs,
                            leading: Spacing.sm,
                            bottom: Spacing.xs,
                            trailing: Spacing.sm
                        ))
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !diffs.isEmpty {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                }
            }
        }
        .sheet(item: $selectedDiff) { diff in
            DiffDetailView(diff: diff)
        }
    }
}

// MARK: - Diff Entry Row

struct DiffEntryRow: View {
    let diff: DiffEntry

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // File icon based on extension
            Image(systemName: fileIcon)
                .font(.body)
                .foregroundStyle(fileColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                // File name
                Text(diff.fileName)
                    .font(Typography.bodyBold)
                    .lineLimit(1)

                // Path
                Text(diff.filePath)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Stats
            HStack(spacing: Spacing.xs) {
                if diff.additions > 0 {
                    Text("+\(diff.additions)")
                        .font(Typography.codeSmall)
                        .foregroundStyle(Color.diffAdded)
                }
                if diff.deletions > 0 {
                    Text("-\(diff.deletions)")
                        .font(Typography.codeSmall)
                        .foregroundStyle(Color.diffRemoved)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var fileIcon: String {
        switch diff.fileExtension.lowercased() {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "md": return "doc.text"
        case "json", "yaml", "yml": return "doc.badge.gearshape"
        case "css", "scss": return "paintbrush"
        case "html": return "globe"
        default: return "doc"
        }
    }

    private var fileColor: Color {
        if diff.isNewFile {
            return .accentGreen
        }
        switch diff.fileExtension.lowercased() {
        case "swift": return .orange
        case "js", "ts", "jsx", "tsx": return .yellow
        case "py": return .blue
        case "go": return .cyan
        default: return .secondary
        }
    }
}

// MARK: - Diff Detail View

struct DiffDetailView: View {
    let diff: DiffEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diff.lines) { line in
                        DiffLineRow(line: line)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .background(Color.black)
            .navigationTitle(diff.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Text(diff.summaryText)
                        .font(Typography.codeSmall)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Diff Line Row

struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number
            Text("\(line.lineNumber)")
                .font(Typography.codeSmall)
                .foregroundStyle(.gray)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, Spacing.xs)

            // Content
            Text(line.content)
                .font(Typography.code)
                .foregroundStyle(lineColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 1)
        .background(lineBackground)
    }

    private var lineColor: Color {
        switch line.type {
        case .addition: return .white
        case .deletion: return .white
        case .header: return .cyan
        case .context: return .gray
        }
    }

    private var lineBackground: Color {
        switch line.type {
        case .addition: return Color.diffAdded.opacity(0.3)
        case .deletion: return Color.diffRemoved.opacity(0.3)
        case .header: return Color.blue.opacity(0.1)
        case .context: return .clear
        }
    }
}
