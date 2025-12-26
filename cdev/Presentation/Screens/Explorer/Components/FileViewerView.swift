import SwiftUI

/// Sheet view for displaying file contents with IDE-style code editor appearance
/// Designed for future theme customization (VSCode-style)
struct FileViewerView: View {
    let file: FileEntry
    let content: String?
    let isLoading: Bool
    let onDismiss: () -> Void

    // Display options
    @State private var showCopiedPath = false
    @State private var showCopiedContent = false
    @State private var wordWrap = true
    @State private var showLineNumbers = true
    @State private var syntaxHighlighting = true
    @State private var activeLineIndex: Int? = nil

    // Beautify state
    @State private var isFormatted = false
    @State private var formattedContent: String?
    @State private var showFormatError = false
    @State private var formatErrorMessage = ""

    // Fullscreen state
    @State private var isFullscreen = false

    // Search state
    @State private var isSearchActive = false
    @State private var searchQuery = ""
    @State private var debouncedQuery = ""  // Debounced version for actual search
    @State private var searchMatches: [SearchMatch] = []
    @State private var currentMatchIndex = 0
    @State private var isCaseSensitive = false
    @State private var showNoResults = false
    @State private var isSearching = false  // Loading indicator
    @State private var searchTask: Task<Void, Never>?  // For cancellation
    @FocusState private var isSearchFocused: Bool

    // Pre-computed lines cache (computed once per content)
    @State private var cachedLines: [String]?

    // Environment for iPad detection
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Debounce interval in milliseconds
    private let searchDebounceMs: UInt64 = 150

    var body: some View {
        NavigationStack {
            ZStack {
                ColorSystem.Editor.background
                    .ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if let displayContent = displayContent {
                    codeEditorView(content: displayContent)
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
            .safeAreaInset(edge: .top) {
                if isSearchActive {
                    searchBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) {
                editorStatusBar
            }
        }
        .presentationBackground(ColorSystem.Editor.background)
        .presentationDetents(isFullscreen ? [.fraction(0.99)] : [.medium, .large])
        .presentationDragIndicator(isFullscreen ? .hidden : .visible)
        .interactiveDismissDisabled(isFullscreen)
        .onChange(of: searchQuery) { _, newValue in
            // Debounce search input to reduce CPU usage
            debouncedSearch(query: newValue)
        }
        .onChange(of: isCaseSensitive) { _, _ in
            // Immediate search on case toggle (no debounce needed)
            performSearch(query: searchQuery)
        }
        .onChange(of: content) { _, newContent in
            // Invalidate cache when content changes
            cachedLines = newContent?.components(separatedBy: "\n")
        }
        .onKeyPress(.escape) {
            if isSearchActive {
                closeSearch()
                return .handled
            }
            return .ignored
        }
        .onDisappear {
            // Cancel any pending search task to prevent memory leaks
            searchTask?.cancel()
            searchTask = nil
        }
        .task {
            // Pre-compute lines on appear
            if cachedLines == nil, let content = content {
                cachedLines = content.components(separatedBy: "\n")
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.xs) {
            // Search field
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("Search in file...", text: $searchQuery)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        if !searchMatches.isEmpty {
                            navigateToNextMatch()
                        }
                    }

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        Haptics.light()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorSystem.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        showNoResults && !searchQuery.isEmpty
                            ? ColorSystem.error.opacity(0.5)
                            : Color.clear,
                        lineWidth: 1
                    )
            )

            // Case sensitivity toggle
            Button {
                isCaseSensitive.toggle()
                Haptics.selection()
            } label: {
                Text("Aa")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isCaseSensitive ? ColorSystem.primary : ColorSystem.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(isCaseSensitive ? ColorSystem.primaryGlow : ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Match counter and navigation
            if isSearching {
                // Loading indicator while debouncing
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 28, height: 28)
            } else if !searchMatches.isEmpty {
                HStack(spacing: 2) {
                    Text("\(currentMatchIndex + 1)/\(searchMatches.count)")
                        .font(Typography.badge)
                        .foregroundStyle(ColorSystem.textSecondary)
                        .frame(minWidth: 36)

                    // Previous match
                    Button {
                        navigateToPreviousMatch()
                        Haptics.selection()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ColorSystem.textSecondary)
                            .frame(width: 24, height: 28)
                    }

                    // Next match
                    Button {
                        navigateToNextMatch()
                        Haptics.selection()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ColorSystem.textSecondary)
                            .frame(width: 24, height: 28)
                    }
                }
                .padding(.horizontal, 4)
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if !searchQuery.isEmpty {
                Text("0")
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.error)
                    .frame(width: 28, height: 28)
                    .background(ColorSystem.errorGlow)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Close search
            Button {
                closeSearch()
                Haptics.light()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ColorSystem.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
        .overlay(
            Rectangle()
                .fill(ColorSystem.Editor.gutterBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Search Logic

    /// Debounced search - cancels previous search task and waits before executing
    private func debouncedSearch(query: String) {
        // Cancel any pending search task
        searchTask?.cancel()

        // Clear results immediately if query is empty
        guard !query.isEmpty else {
            searchMatches = []
            currentMatchIndex = 0
            showNoResults = false
            debouncedQuery = ""
            isSearching = false
            return
        }

        // Show loading state
        isSearching = true

        // Create new debounced task
        searchTask = Task { @MainActor in
            // Wait for debounce interval
            do {
                try await Task.sleep(nanoseconds: searchDebounceMs * 1_000_000)
            } catch {
                // Task was cancelled, exit early
                return
            }

            // Check if task was cancelled during sleep
            guard !Task.isCancelled else { return }

            // Update debounced query and perform search
            debouncedQuery = query
            performSearch(query: query)
            isSearching = false
        }
    }

    /// Perform the actual search (called after debounce)
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchMatches = []
            currentMatchIndex = 0
            showNoResults = false
            return
        }

        // Use cached lines or compute them
        let lines: [String]
        if let cached = cachedLines {
            lines = cached
        } else if let content = content {
            lines = content.components(separatedBy: "\n")
            cachedLines = lines
        } else {
            searchMatches = []
            showNoResults = true
            return
        }

        // Pre-allocate array with estimated capacity for better performance
        var matches: [SearchMatch] = []
        matches.reserveCapacity(min(lines.count, 100))

        let options: String.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]

        // Optimized search loop
        for (lineIndex, line) in lines.enumerated() {
            // Skip empty lines for performance
            guard !line.isEmpty else { continue }

            var searchStart = line.startIndex

            while searchStart < line.endIndex,
                  let range = line.range(of: query, options: options, range: searchStart..<line.endIndex) {

                let startColumn = line.distance(from: line.startIndex, to: range.lowerBound)
                let endColumn = line.distance(from: line.startIndex, to: range.upperBound)

                matches.append(SearchMatch(
                    lineIndex: lineIndex,
                    startColumn: startColumn,
                    endColumn: endColumn,
                    text: String(line[range])
                ))

                // Move past current match to find next
                searchStart = range.upperBound

                // Limit matches to prevent performance issues on large files
                if matches.count >= 10000 {
                    AppLogger.log("[Search] Hit max matches limit (10000)")
                    break
                }
            }

            // Early exit if we hit the limit
            if matches.count >= 10000 { break }
        }

        searchMatches = matches
        currentMatchIndex = matches.isEmpty ? 0 : 0
        showNoResults = matches.isEmpty

        // Auto-scroll to first match
        if let firstMatch = matches.first {
            activeLineIndex = firstMatch.lineIndex
        }
    }

    private func navigateToNextMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
        activeLineIndex = searchMatches[currentMatchIndex].lineIndex
    }

    private func navigateToPreviousMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = currentMatchIndex > 0 ? currentMatchIndex - 1 : searchMatches.count - 1
        activeLineIndex = searchMatches[currentMatchIndex].lineIndex
    }

    private func openSearch() {
        withAnimation(.easeOut(duration: 0.2)) {
            isSearchActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSearchFocused = true
        }
    }

    private func closeSearch() {
        // Cancel any pending search task
        searchTask?.cancel()
        searchTask = nil

        isSearchFocused = false
        withAnimation(.easeOut(duration: 0.2)) {
            isSearchActive = false
            searchQuery = ""
            debouncedQuery = ""
            searchMatches = []
            currentMatchIndex = 0
            showNoResults = false
            isSearching = false
        }
    }

    // MARK: - Editor Toolbar

    /// Check if toolbar actions should be disabled (loading or no content)
    private var isToolbarDisabled: Bool {
        isLoading || content == nil
    }

    private var editorToolbar: some View {
        HStack(spacing: Spacing.sm) {
            // Search button
            Button {
                if isSearchActive {
                    closeSearch()
                } else {
                    openSearch()
                }
                Haptics.selection()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSearchActive ? ColorSystem.primary : isToolbarDisabled ? ColorSystem.textQuaternary : ColorSystem.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(isSearchActive ? ColorSystem.primaryGlow : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(isToolbarDisabled)

            // Word wrap toggle - icon shows current state
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    wordWrap.toggle()
                }
                Haptics.selection()
            } label: {
                Image(systemName: wordWrap ? "arrow.left.and.right.text.vertical" : "text.alignleft")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(wordWrap ? ColorSystem.primary : isToolbarDisabled ? ColorSystem.textQuaternary : ColorSystem.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(wordWrap ? ColorSystem.primaryGlow : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(isToolbarDisabled)

            // Fullscreen toggle (iPad only)
            if horizontalSizeClass == .regular {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isFullscreen.toggle()
                    }
                    Haptics.selection()
                } label: {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isFullscreen ? ColorSystem.primary : isToolbarDisabled ? ColorSystem.textQuaternary : ColorSystem.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(isFullscreen ? ColorSystem.primaryGlow : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .disabled(isToolbarDisabled)
            }

            // More options menu
            Menu {
                Section("Display") {
                    Button {
                        syntaxHighlighting.toggle()
                        Haptics.selection()
                    } label: {
                        Label(
                            syntaxHighlighting ? "Disable Syntax Colors" : "Enable Syntax Colors",
                            systemImage: syntaxHighlighting ? "paintbrush.fill" : "paintbrush"
                        )
                    }

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
                    .foregroundStyle(isToolbarDisabled ? ColorSystem.textQuaternary : ColorSystem.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .disabled(isToolbarDisabled)
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

    /// Pre-compute matches grouped by line for O(1) lookup
    private var matchesByLine: [Int: [SearchMatch]] {
        Dictionary(grouping: searchMatches, by: { $0.lineIndex })
    }

    /// Current match object for direct comparison
    private var currentMatch: SearchMatch? {
        guard currentMatchIndex < searchMatches.count else { return nil }
        return searchMatches[currentMatchIndex]
    }

    private func codeEditorView(content: String) -> some View {
        // Use cached lines or compute them
        let lines = cachedLines ?? content.components(separatedBy: "\n")

        return ScrollViewReader { proxy in
            // Word wrap ON: use vertical ScrollView with LazyVStack
            // Word wrap OFF: CodeEditorContentView has its own 2D ScrollView
            Group {
                if wordWrap {
                    ScrollView(.vertical, showsIndicators: true) {
                        CodeEditorContentView(
                            lines: lines,
                            fileExtension: file.fileExtension,
                            wordWrap: wordWrap,
                            showLineNumbers: showLineNumbers,
                            syntaxHighlighting: syntaxHighlighting,
                            activeLineIndex: activeLineIndex,
                            matchesByLine: matchesByLine,
                            currentMatch: currentMatch,
                            onLineTap: { index in
                                withAnimation(.easeOut(duration: 0.15)) {
                                    activeLineIndex = (activeLineIndex == index) ? nil : index
                                }
                                Haptics.selection()
                            }
                        )
                    }
                } else {
                    // No outer ScrollView - horizontalScrollLayout has 2D ScrollView
                    CodeEditorContentView(
                        lines: lines,
                        fileExtension: file.fileExtension,
                        wordWrap: wordWrap,
                        showLineNumbers: showLineNumbers,
                        syntaxHighlighting: syntaxHighlighting,
                        activeLineIndex: activeLineIndex,
                        matchesByLine: matchesByLine,
                        currentMatch: currentMatch,
                        onLineTap: { index in
                            withAnimation(.easeOut(duration: 0.15)) {
                                activeLineIndex = (activeLineIndex == index) ? nil : index
                            }
                            Haptics.selection()
                        }
                    )
                }
            }
            .onChange(of: currentMatchIndex) { _, newIndex in
                // Scroll to current match
                if !searchMatches.isEmpty && newIndex < searchMatches.count {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("line-\(searchMatches[newIndex].lineIndex)", anchor: .center)
                    }
                }
            }
            .onChange(of: searchMatches) { _, matches in
                // Scroll to first match when search results change
                if let first = matches.first {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("line-\(first.lineIndex)", anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Editor Status Bar

    private var editorStatusBar: some View {
        VStack(spacing: 0) {
            // Error banner (if any) - above status bar
            // WCAG AA compliant: White text on error red provides 5.5:1+ contrast ratio
            if showFormatError {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white)

                    Text(formatErrorMessage)
                        .font(Typography.terminalSmall)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Spacer()

                    // Dismiss button
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showFormatError = false
                        }
                        Haptics.light()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 5)
                .background(ColorSystem.error)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main status bar with inline beautify button
            HStack(spacing: Spacing.sm) {
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

                    // Beautify button (inline, only for JSON/Markdown)
                    if isBeautifiable && !isLoading {
                        // Separator
                        Rectangle()
                            .fill(ColorSystem.Editor.gutterBorder)
                            .frame(width: 1, height: 12)

                        Button {
                            toggleBeautify()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isFormatted ? "arrow.uturn.backward" : "sparkles")
                                    .font(.system(size: 9, weight: .semibold))

                                Text(isFormatted ? "Original" : "Beautify")
                                    .font(Typography.badge)
                            }
                            .foregroundStyle(isFormatted ? ColorSystem.textSecondary : ColorSystem.primary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 3)
                            .background(isFormatted ? ColorSystem.terminalBgHighlight : ColorSystem.primaryGlow)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
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
    }

    // MARK: - Helpers

    /// Check if file is JSON or Markdown (for beautify button)
    private var isBeautifiable: Bool {
        guard let ext = file.fileExtension?.lowercased() else { return false }
        return ext == "json" || ext == "md" || ext == "markdown"
    }

    /// Get display content (formatted or original)
    private var displayContent: String? {
        if isFormatted, let formatted = formattedContent {
            return formatted
        }
        return content
    }

    /// Toggle beautification
    private func toggleBeautify() {
        guard let ext = file.fileExtension?.lowercased() else { return }

        // If already formatted, restore original
        if isFormatted {
            withAnimation(.easeOut(duration: 0.2)) {
                isFormatted = false
                showFormatError = false
            }
            Haptics.light()
            return
        }

        // Format the content
        guard let content = content else { return }

        Task { @MainActor in
            do {
                let formatted: String
                if ext == "json" {
                    formatted = try beautifyJSON(content)
                } else if ext == "md" || ext == "markdown" {
                    formatted = beautifyMarkdown(content)
                } else {
                    return
                }

                withAnimation(.easeOut(duration: 0.2)) {
                    formattedContent = formatted
                    isFormatted = true
                    showFormatError = false
                }
                Haptics.success()
            } catch {
                // Show error
                formatErrorMessage = error.localizedDescription
                showFormatError = true
                Haptics.error()

                // Auto-dismiss error after 3 seconds
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.easeOut(duration: 0.2)) {
                        showFormatError = false
                    }
                }
            }
        }
    }

    /// Beautify JSON with proper indentation
    private func beautifyJSON(_ content: String) throws -> String {
        guard let data = content.data(using: .utf8) else {
            throw FormatError.invalidContent
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])

        guard let formatted = String(data: prettyData, encoding: .utf8) else {
            throw FormatError.invalidContent
        }

        return formatted
    }

    /// Beautify Markdown with normalized formatting
    private func beautifyMarkdown(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var formatted: [String] = []

        for line in lines {
            var processedLine = line

            // Normalize headers (ensure space after #)
            if processedLine.hasPrefix("#") {
                let hashCount = processedLine.prefix(while: { $0 == "#" }).count
                let remaining = processedLine.dropFirst(hashCount).trimmingCharacters(in: .whitespaces)
                processedLine = String(repeating: "#", count: hashCount) + " " + remaining
            }

            // Normalize list items (ensure space after bullet/number)
            if processedLine.trimmingCharacters(in: .whitespaces).hasPrefix("-") ||
               processedLine.trimmingCharacters(in: .whitespaces).hasPrefix("*") ||
               processedLine.trimmingCharacters(in: .whitespaces).hasPrefix("+") {
                let trimmed = processedLine.trimmingCharacters(in: .whitespaces)
                let bullet = String(trimmed.prefix(1))
                let remaining = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                processedLine = bullet + " " + remaining
            }

            formatted.append(processedLine)
        }

        return formatted.joined(separator: "\n")
    }

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

// MARK: - Format Error

enum FormatError: LocalizedError {
    case invalidContent

    var errorDescription: String? {
        switch self {
        case .invalidContent:
            return "Invalid JSON format"
        }
    }
}

// MARK: - Search Match Model

/// Represents a search match in the file content
struct SearchMatch: Identifiable, Equatable {
    let id = UUID()
    let lineIndex: Int
    let startColumn: Int
    let endColumn: Int
    let text: String

    static func == (lhs: SearchMatch, rhs: SearchMatch) -> Bool {
        lhs.lineIndex == rhs.lineIndex &&
        lhs.startColumn == rhs.startColumn &&
        lhs.endColumn == rhs.endColumn
    }
}

// MARK: - Code Editor Content View

/// IDE-style code content with gutter, line numbers, and active line highlighting
/// Performance optimized with LazyVStack and pre-computed match lookup
struct CodeEditorContentView: View {
    let lines: [String]  // Pre-computed lines from parent
    let fileExtension: String?
    var wordWrap: Bool = false
    var showLineNumbers: Bool = true
    var syntaxHighlighting: Bool = true
    var activeLineIndex: Int? = nil
    var matchesByLine: [Int: [SearchMatch]] = [:]  // Pre-computed O(1) lookup
    var currentMatch: SearchMatch? = nil
    var onLineTap: ((Int) -> Void)? = nil


    private var language: SyntaxHighlighter.Language {
        SyntaxHighlighter.detectLanguage(from: fileExtension)
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
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                LineRowView(
                    index: index,
                    line: line,
                    lineNumberWidth: lineNumberWidth,
                    showLineNumbers: showLineNumbers,
                    syntaxHighlighting: syntaxHighlighting,
                    language: language,
                    isActive: activeLineIndex == index,
                    lineMatches: matchesByLine[index] ?? [],
                    currentMatch: currentMatch,
                    onTap: onLineTap
                )
                .id("line-\(index)")
            }
        }
    }

    // MARK: - Horizontal Scroll Layout
    // Uses UIKit UICollectionView for true lazy loading with synchronized horizontal scroll

    private var horizontalScrollLayout: some View {
        VirtualizedCodeView(
            lines: lines,
            fileExtension: fileExtension,
            showLineNumbers: showLineNumbers,
            syntaxHighlighting: syntaxHighlighting,
            activeLineIndex: activeLineIndex,
            matchesByLine: matchesByLine,
            currentMatch: currentMatch,
            onLineTap: onLineTap
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - Extracted Line Views (for better performance)

/// Gutter line number view - extracted for lazy rendering
private struct GutterLineView: View {
    let index: Int
    let lineNumberWidth: CGFloat
    let isActive: Bool
    let lineMatches: [SearchMatch]
    let currentMatch: SearchMatch?
    let onTap: ((Int) -> Void)?

    private var hasMatch: Bool { !lineMatches.isEmpty }
    private var hasCurrentMatch: Bool {
        guard let current = currentMatch else { return false }
        return lineMatches.contains { $0 == current }
    }

    var body: some View {
        Text("\(index + 1)")
            .font(Typography.codeLineNumber)
            .foregroundStyle(
                hasCurrentMatch ? ColorSystem.primary :
                hasMatch ? ColorSystem.warning :
                isActive ? ColorSystem.Editor.lineNumberActive :
                ColorSystem.Editor.lineNumber
            )
            .frame(width: lineNumberWidth - 12, height: 20, alignment: .trailing)
            .background(isActive ? ColorSystem.Editor.activeLineBg : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { onTap?(index) }
    }
}

/// Code line view for horizontal scroll layout - extracted for lazy rendering
private struct CodeLineView: View {
    let index: Int
    let line: String
    let syntaxHighlighting: Bool
    let language: SyntaxHighlighter.Language
    let isActive: Bool
    let lineMatches: [SearchMatch]
    let currentMatch: SearchMatch?
    let onTap: ((Int) -> Void)?

    var body: some View {
        highlightedText
            .font(Typography.codeContent)
            .frame(height: 20, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)  // Allow horizontal expansion for scrolling
            .padding(.leading, Spacing.sm)
            .textSelection(.enabled)
            .background(isActive ? ColorSystem.Editor.activeLineBg : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { onTap?(index) }
    }

    private var highlightedText: Text {
        buildHighlightedText(
            line: line,
            lineMatches: lineMatches,
            currentMatch: currentMatch,
            syntaxHighlighting: syntaxHighlighting,
            language: language
        )
    }
}

/// Full line row view for word wrap layout - extracted for lazy rendering
private struct LineRowView: View {
    let index: Int
    let line: String
    let lineNumberWidth: CGFloat
    let showLineNumbers: Bool
    let syntaxHighlighting: Bool
    let language: SyntaxHighlighter.Language
    let isActive: Bool
    let lineMatches: [SearchMatch]
    let currentMatch: SearchMatch?
    let onTap: ((Int) -> Void)?

    private var hasMatch: Bool { !lineMatches.isEmpty }
    private var hasCurrentMatch: Bool {
        guard let current = currentMatch else { return false }
        return lineMatches.contains { $0 == current }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number
            if showLineNumbers {
                Text("\(index + 1)")
                    .font(Typography.codeLineNumber)
                    .foregroundStyle(
                        hasCurrentMatch ? ColorSystem.primary :
                        hasMatch ? ColorSystem.warning :
                        isActive ? ColorSystem.Editor.lineNumberActive :
                        ColorSystem.Editor.lineNumber
                    )
                    .frame(width: lineNumberWidth - 12, alignment: .trailing)
                    .padding(.trailing, 8)
                    .background(ColorSystem.Editor.gutterBg)

                Rectangle()
                    .fill(ColorSystem.Editor.gutterBorder)
                    .frame(width: 1)
            }

            // Code line
            highlightedText
                .font(Typography.codeContent)
                .textSelection(.enabled)
                .padding(.leading, Spacing.sm)
                .padding(.trailing, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 20)
        .background(isActive ? ColorSystem.Editor.activeLineBg : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap?(index) }
    }

    private var highlightedText: Text {
        buildHighlightedText(
            line: line,
            lineMatches: lineMatches,
            currentMatch: currentMatch,
            syntaxHighlighting: syntaxHighlighting,
            language: language
        )
    }
}

// MARK: - Shared Text Highlighting

/// Build highlighted text with search matches using AttributedString
private func buildHighlightedText(
    line: String,
    lineMatches: [SearchMatch],
    currentMatch: SearchMatch?,
    syntaxHighlighting: Bool,
    language: SyntaxHighlighter.Language
) -> Text {
    // If no matches, return normal text (with or without syntax highlighting)
    guard !lineMatches.isEmpty else {
        if syntaxHighlighting && language != .plainText {
            return Text(SyntaxHighlighter.highlight(line: line, language: language))
        } else {
            return Text(line.isEmpty ? " " : line)
                .foregroundColor(ColorSystem.Syntax.plain)
        }
    }

    // Build AttributedString with highlighted matches
    var attrString: AttributedString
    if syntaxHighlighting && language != .plainText {
        attrString = SyntaxHighlighter.highlight(line: line, language: language)
    } else {
        attrString = AttributedString(line.isEmpty ? " " : line)
        attrString.foregroundColor = ColorSystem.Syntax.plain
    }

    // Apply search match highlighting
    let sortedMatches = lineMatches.sorted { $0.startColumn < $1.startColumn }

    for match in sortedMatches {
        // Calculate range in AttributedString
        let startIndex = attrString.index(attrString.startIndex, offsetByCharacters: match.startColumn)
        let endIndex = attrString.index(attrString.startIndex, offsetByCharacters: min(match.endColumn, line.count))

        guard startIndex < endIndex else { continue }

        let range = startIndex..<endIndex
        let isCurrent = currentMatch == match

        // Apply highlight styling
        attrString[range].backgroundColor = isCurrent ? ColorSystem.primary : ColorSystem.warning
        attrString[range].foregroundColor = isCurrent ? ColorSystem.terminalBg : ColorSystem.textPrimary
    }

    return Text(attrString)
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
