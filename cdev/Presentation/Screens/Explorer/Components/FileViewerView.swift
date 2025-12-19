import SwiftUI

/// Sheet view for displaying file contents with IDE-style code editor appearance
/// Designed for future theme customization (VSCode-style)
struct FileViewerView: View {
    let file: FileEntry
    let content: String?
    let isLoading: Bool
    let onDismiss: () -> Void

    @State private var showCopiedPath = false
    @State private var showCopiedContent = false
    @State private var wordWrap = false
    @State private var showLineNumbers = true
    @State private var activeLineIndex: Int? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                ColorSystem.Editor.background
                    .ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if let content = content {
                    codeEditorView(content: content)
                } else {
                    errorView
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ColorSystem.terminalBgElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(Typography.buttonLabel)
                            .foregroundStyle(ColorSystem.primary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    editorToolbar
                }
            }
            .safeAreaInset(edge: .bottom) {
                editorStatusBar
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorSystem.Editor.background)
    }

    // MARK: - Editor Toolbar

    private var editorToolbar: some View {
        HStack(spacing: Spacing.sm) {
            // Word wrap toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    wordWrap.toggle()
                }
                Haptics.selection()
            } label: {
                Image(systemName: wordWrap ? "text.alignleft" : "arrow.left.and.right.text.vertical")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(wordWrap ? ColorSystem.primary : ColorSystem.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(wordWrap ? ColorSystem.primaryGlow : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Line numbers toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLineNumbers.toggle()
                }
                Haptics.selection()
            } label: {
                Image(systemName: showLineNumbers ? "number" : "number.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(showLineNumbers ? ColorSystem.primary : ColorSystem.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(showLineNumbers ? ColorSystem.primaryGlow : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // More options menu
            Menu {
                Section("Display") {
                    Button {
                        wordWrap.toggle()
                        Haptics.selection()
                    } label: {
                        Label(
                            wordWrap ? "Disable Word Wrap" : "Enable Word Wrap",
                            systemImage: wordWrap ? "arrow.left.and.right.text.vertical" : "text.alignleft"
                        )
                    }

                    Button {
                        showLineNumbers.toggle()
                        Haptics.selection()
                    } label: {
                        Label(
                            showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers",
                            systemImage: showLineNumbers ? "eye.slash" : "eye"
                        )
                    }
                }

                Divider()

                Section("Copy") {
                    Button {
                        UIPasteboard.general.string = file.path
                        showCopiedPath = true
                        Haptics.light()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedPath = false
                        }
                    } label: {
                        Label(
                            showCopiedPath ? "Copied!" : "Copy Path",
                            systemImage: showCopiedPath ? "checkmark" : "link"
                        )
                    }

                    if let content = content {
                        Button {
                            UIPasteboard.general.string = content
                            showCopiedContent = true
                            Haptics.light()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopiedContent = false
                            }
                        } label: {
                            Label(
                                showCopiedContent ? "Copied!" : "Copy Content",
                                systemImage: showCopiedContent ? "checkmark" : "doc.on.clipboard"
                            )
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ColorSystem.textSecondary)
                    .frame(width: 28, height: 28)
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            // Skeleton loading animation
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(0..<8, id: \.self) { index in
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ColorSystem.terminalBgHighlight)
                            .frame(width: 24, height: 12)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(ColorSystem.terminalBgHighlight)
                            .frame(width: CGFloat.random(in: 80...200), height: 12)
                    }
                    .opacity(0.3 + Double(index) * 0.08)
                }
            }
            .padding(Spacing.md)

            Text("Loading...")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
        }
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isLoading)
    }

    private var errorView: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(ColorSystem.error.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(ColorSystem.error)
            }

            VStack(spacing: Spacing.xs) {
                Text("Unable to load file")
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text(file.path)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onDismiss()
            } label: {
                Text("Dismiss")
                    .font(Typography.buttonLabel)
                    .foregroundStyle(ColorSystem.primary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(ColorSystem.primaryGlow)
                    .clipShape(Capsule())
            }
        }
        .padding(Spacing.xl)
    }

    private func codeEditorView(content: String) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            CodeEditorContentView(
                content: content,
                fileExtension: file.fileExtension,
                wordWrap: wordWrap,
                showLineNumbers: showLineNumbers,
                activeLineIndex: activeLineIndex,
                onLineTap: { index in
                    withAnimation(.easeOut(duration: 0.15)) {
                        activeLineIndex = (activeLineIndex == index) ? nil : index
                    }
                    Haptics.selection()
                }
            )
        }
    }

    // MARK: - Editor Status Bar

    private var editorStatusBar: some View {
        HStack(spacing: 0) {
            // Language indicator (file extension)
            if let ext = file.fileExtension, !ext.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(languageColor(for: ext))
                        .frame(width: 8, height: 8)

                    Text(ext.uppercased())
                        .font(Typography.badge)
                        .foregroundStyle(ColorSystem.textSecondary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Spacer()

            // File info
            HStack(spacing: Spacing.md) {
                // Line count
                if let content = content {
                    let lineCount = content.components(separatedBy: "\n").count
                    HStack(spacing: 3) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9))
                        Text("\(lineCount) lines")
                    }
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                }

                // File size
                if let size = file.formattedSize {
                    HStack(spacing: 3) {
                        Image(systemName: "doc")
                            .font(.system(size: 9))
                        Text(size)
                    }
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                }

                // Encoding indicator
                Text("UTF-8")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
        .overlay(
            Rectangle()
                .fill(ColorSystem.Editor.gutterBorder)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Helpers

    private func languageColor(for ext: String) -> Color {
        switch ext.lowercased() {
        case "swift": return Color(hex: "#F05138")
        case "js", "jsx", "ts", "tsx": return Color(hex: "#F7DF1E")
        case "py": return Color(hex: "#3776AB")
        case "rb": return Color(hex: "#CC342D")
        case "go": return Color(hex: "#00ADD8")
        case "rs": return Color(hex: "#DEA584")
        case "java", "kt": return Color(hex: "#B07219")
        case "cpp", "c", "h": return Color(hex: "#F34B7D")
        case "css", "scss": return Color(hex: "#563D7C")
        case "html": return Color(hex: "#E34C26")
        case "json": return Color(hex: "#A5D6FF")
        case "md": return Color(hex: "#083FA1")
        case "yml", "yaml": return Color(hex: "#CB171E")
        case "sh", "bash", "zsh": return Color(hex: "#89E051")
        case "sql": return Color(hex: "#E38C00")
        default: return ColorSystem.textTertiary
        }
    }
}

// MARK: - Code Editor Content View

/// IDE-style code content with gutter, line numbers, and active line highlighting
struct CodeEditorContentView: View {
    let content: String
    let fileExtension: String?
    var wordWrap: Bool = false
    var showLineNumbers: Bool = true
    var activeLineIndex: Int? = nil
    var onLineTap: ((Int) -> Void)? = nil

    private var lines: [String] {
        content.components(separatedBy: "\n")
    }

    private var lineNumberWidth: CGFloat {
        let maxLineNumber = lines.count
        let digitCount = String(maxLineNumber).count
        return CGFloat(max(digitCount * 8 + 16, 36))
    }

    var body: some View {
        if wordWrap {
            wordWrapLayout
        } else {
            horizontalScrollLayout
        }
    }

    // MARK: - Word Wrap Layout

    private var wordWrapLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                lineRow(index: index, line: line, isWrapped: true)
            }
        }
    }

    // MARK: - Horizontal Scroll Layout

    private var horizontalScrollLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Fixed gutter with line numbers
            if showLineNumbers {
                gutterColumn
            }

            // Scrollable code content
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        codeLineContent(index: index, line: line)
                    }
                }
                .padding(.trailing, Spacing.xl)
            }
        }
    }

    // MARK: - Components

    private var gutterColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                let isActive = activeLineIndex == index

                Text("\(index + 1)")
                    .font(Typography.codeLineNumber)
                    .foregroundStyle(isActive ? ColorSystem.Editor.lineNumberActive : ColorSystem.Editor.lineNumber)
                    .frame(width: lineNumberWidth - 12, height: 20, alignment: .trailing)
                    .background(isActive ? ColorSystem.Editor.activeLineBg : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onLineTap?(index)
                    }
            }
        }
        .frame(width: lineNumberWidth)
        .background(ColorSystem.Editor.gutterBg)
        .overlay(
            Rectangle()
                .fill(ColorSystem.Editor.gutterBorder)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private func lineRow(index: Int, line: String, isWrapped: Bool) -> some View {
        let isActive = activeLineIndex == index

        return HStack(alignment: .top, spacing: 0) {
            // Line number
            if showLineNumbers {
                Text("\(index + 1)")
                    .font(Typography.codeLineNumber)
                    .foregroundStyle(isActive ? ColorSystem.Editor.lineNumberActive : ColorSystem.Editor.lineNumber)
                    .frame(width: lineNumberWidth - 12, alignment: .trailing)
                    .padding(.trailing, 8)
                    .background(ColorSystem.Editor.gutterBg)
            }

            // Separator
            if showLineNumbers {
                Rectangle()
                    .fill(ColorSystem.Editor.gutterBorder)
                    .frame(width: 1)
            }

            // Code line
            Text(line.isEmpty ? " " : line)
                .font(Typography.codeContent)
                .foregroundStyle(ColorSystem.Syntax.plain)
                .textSelection(.enabled)
                .padding(.leading, Spacing.sm)
                .padding(.trailing, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 20)
        .background(isActive ? ColorSystem.Editor.activeLineBg : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onLineTap?(index)
        }
    }

    private func codeLineContent(index: Int, line: String) -> some View {
        let isActive = activeLineIndex == index

        return Text(line.isEmpty ? " " : line)
            .font(Typography.codeContent)
            .foregroundStyle(ColorSystem.Syntax.plain)
            .frame(height: 20, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Spacing.sm)
            .textSelection(.enabled)
            .background(isActive ? ColorSystem.Editor.activeLineBg : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                onLineTap?(index)
            }
    }
}

// MARK: - Preview

#Preview("File Viewer - Swift") {
    FileViewerView(
        file: FileEntry(
            name: "AppState.swift",
            path: "cdev/App/AppState.swift",
            type: .file,
            size: 5280,
            gitStatus: .modified
        ),
        content: """
        import Foundation
        import Combine

        /// Global app state - manages connection and creates view models
        @MainActor
        final class AppState: ObservableObject {
            // MARK: - Published State

            @Published var connectionState: ConnectionState = .disconnected
            @Published var claudeState: ClaudeState = .idle
            @Published var lastError: AppError?

            // MARK: - Dependencies

            private let dependencyContainer: DependencyContainer

            // MARK: - Init

            init(container: DependencyContainer = .shared) {
                self.dependencyContainer = container
                startListening()
            }

            private func startListening() {
                // Subscribe to WebSocket connection state
                Task {
                    for await state in dependencyContainer.webSocketService.connectionStateStream {
                        self.connectionState = state
                    }
                }
            }

            func connect(to info: ConnectionInfo) async throws {
                try await dependencyContainer.webSocketService.connect(to: info)
            }

            func disconnect() {
                dependencyContainer.webSocketService.disconnect()
            }
        }
        """,
        isLoading: false,
        onDismiss: {}
    )
}

#Preview("File Viewer - Loading") {
    FileViewerView(
        file: FileEntry(
            name: "Loading.swift",
            path: "cdev/App/Loading.swift",
            type: .file,
            size: nil,
            gitStatus: nil
        ),
        content: nil,
        isLoading: true,
        onDismiss: {}
    )
}

#Preview("File Viewer - Error") {
    FileViewerView(
        file: FileEntry(
            name: "Error.swift",
            path: "cdev/App/Error.swift",
            type: .file,
            size: nil,
            gitStatus: nil
        ),
        content: nil,
        isLoading: false,
        onDismiss: {}
    )
}
