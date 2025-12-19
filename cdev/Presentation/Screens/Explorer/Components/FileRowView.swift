import SwiftUI

/// Single row in file explorer list
/// Shows file/folder with icon, name, size, and git status
struct FileRowView: View {
    let entry: FileEntry

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Git status indicator bar (left edge)
            if let status = entry.gitStatus {
                Rectangle()
                    .fill(ColorSystem.FileChange.color(for: status))
                    .frame(width: 3)
            } else {
                // Spacer for alignment when no status
                Color.clear
                    .frame(width: 3)
            }

            // File/folder icon
            Image(systemName: entry.icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            // Name and metadata
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .lineLimit(1)

                // Subtitle: children count for directories, nothing for files
                if entry.isDirectory, let count = entry.childrenCount {
                    Text("\(count) item\(count == 1 ? "" : "s")")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                }
            }

            Spacer()

            // Git status badge (optional, for clearer indication)
            if let status = entry.gitStatus {
                Text(status.code)
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.FileChange.color(for: status))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(ColorSystem.FileChange.color(for: status).opacity(0.15))
                    .clipShape(Capsule())
            }

            // File size (files only)
            if let size = entry.formattedSize {
                Text(size)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(minWidth: 50, alignment: .trailing)
            }

            // Navigation chevron for directories
            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
        }
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 36)
        .background(ColorSystem.terminalBg)
        .contentShape(Rectangle())
    }

    // MARK: - Computed Properties

    private var iconColor: Color {
        if entry.isDirectory {
            return ColorSystem.primary
        }

        // Color based on file extension
        switch entry.fileExtension {
        case "swift":
            return .orange
        case "js", "ts", "jsx", "tsx":
            return .yellow
        case "py":
            return .blue
        case "go":
            return .cyan
        case "md", "txt":
            return ColorSystem.textSecondary
        case "json", "yaml", "yml":
            return .green
        case "css", "scss":
            return .pink
        case "html":
            return .red
        default:
            return ColorSystem.textSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        FileRowView(entry: FileEntry(
            name: "Components",
            path: "src/Components",
            type: .directory,
            childrenCount: 12
        ))

        FileRowView(entry: FileEntry(
            name: "AppState.swift",
            path: "cdev/App/AppState.swift",
            type: .file,
            size: 5280,
            gitStatus: .modified
        ))

        FileRowView(entry: FileEntry(
            name: "README.md",
            path: "README.md",
            type: .file,
            size: 2340
        ))

        FileRowView(entry: FileEntry(
            name: "NewFile.swift",
            path: "src/NewFile.swift",
            type: .file,
            size: 890,
            gitStatus: .added
        ))
    }
    .background(ColorSystem.terminalBg)
}
