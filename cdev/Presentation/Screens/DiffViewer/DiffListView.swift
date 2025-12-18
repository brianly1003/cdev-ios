import SwiftUI

/// Pulse Terminal Diff List - file changes view
struct DiffListView: View {
    let diffs: [DiffEntry]
    let onClear: () -> Void
    let onRefresh: () async -> Void

    @State private var selectedDiff: DiffEntry?

    var body: some View {
        Group {
            if diffs.isEmpty {
                // Empty state with pull-to-refresh
                ScrollView {
                    EmptyStateView(
                        icon: Icons.changes,
                        title: "No Changes",
                        subtitle: "Pull to refresh"
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
                .refreshable {
                    await onRefresh()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(diffs) { diff in
                            DiffEntryRow(diff: diff)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedDiff = diff
                                    Haptics.selection()
                                }
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                .refreshable {
                    await onRefresh()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorSystem.terminalBg)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !diffs.isEmpty {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: Icons.clear)
                            .font(.system(size: 12))
                            .foregroundStyle(ColorSystem.textSecondary)
                    }
                }
            }
        }
        .sheet(item: $selectedDiff) { diff in
            DiffDetailView(diff: diff)
        }
    }
}

// MARK: - Pulse Terminal Diff Entry Row

struct DiffEntryRow: View {
    let diff: DiffEntry

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Change type gutter indicator
            Rectangle()
                .fill(changeTypeColor)
                .frame(width: 3)

            // File icon
            Image(systemName: fileIcon)
                .font(.system(size: 14))
                .foregroundStyle(changeTypeColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                // File name
                Text(diff.fileName)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .lineLimit(1)

                // Path
                Text(diff.filePath)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Stats or change type badge
            if diff.isFileChangeOnly {
                // Change type badge
                Text(diff.summaryText)
                    .font(Typography.badge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(changeTypeColor.opacity(0.2))
                    .foregroundStyle(changeTypeColor)
                    .clipShape(Capsule())
            } else {
                // Diff stats
                HStack(spacing: 6) {
                    if diff.additions > 0 {
                        Text("+\(diff.additions)")
                            .font(Typography.terminalTimestamp)
                            .foregroundStyle(ColorSystem.Diff.addedText)
                    }
                    if diff.deletions > 0 {
                        Text("-\(diff.deletions)")
                            .font(Typography.terminalTimestamp)
                            .foregroundStyle(ColorSystem.Diff.removedText)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ColorSystem.textQuaternary)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(ColorSystem.terminalBgElevated)
    }

    private var fileIcon: String {
        // Show change type icon for file changes
        if let changeType = diff.changeType {
            return Icons.fileChange(for: changeType)
        }
        return Icons.fileType(for: diff.fileExtension)
    }

    private var changeTypeColor: Color {
        ColorSystem.FileChange.color(for: diff.changeType)
    }
}

// MARK: - Pulse Terminal Diff Detail View

struct DiffDetailView: View {
    let diff: DiffEntry
    @Environment(\.dismiss) private var dismiss
    @State private var diffContent: String?
    @State private var isLoading = false
    @State private var error: String?

    // Zoom state - persisted across sessions
    @AppStorage(Constants.UserDefaults.diffZoomScale) private var zoomScale: Double = 1.0
    @State private var showZoomIndicator = false
    @State private var lastZoomScale: CGFloat = 1.0

    private var currentScale: CGFloat {
        CGFloat(zoomScale)
    }

    private var parsedDiff: ParsedDiff {
        ParsedDiff.parse(diffContent ?? diff.diff)
    }

    private var stats: (additions: Int, deletions: Int) {
        if diffContent != nil || !diff.diff.isEmpty {
            var adds = 0
            var dels = 0
            for line in parsedDiff.lines {
                if line.type == .addition { adds += 1 }
                if line.type == .deletion { dels += 1 }
            }
            return (adds, dels)
        }
        return (diff.additions, diff.deletions)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if isLoading {
                        // Loading state
                        VStack(spacing: Spacing.md) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(ColorSystem.primary)
                            Text("Loading diff...")
                                .font(Typography.terminal)
                                .foregroundStyle(ColorSystem.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ColorSystem.terminalBg)
                    } else if let error = error {
                        // Error state
                        VStack(spacing: Spacing.md) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundStyle(ColorSystem.warning)
                            Text("Failed to load diff")
                                .font(Typography.bannerTitle)
                                .foregroundStyle(ColorSystem.textPrimary)
                            Text(error)
                                .font(Typography.terminalSmall)
                                .foregroundStyle(ColorSystem.textTertiary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await fetchDiff() }
                            }
                            .font(Typography.buttonLabel)
                            .foregroundStyle(ColorSystem.primary)
                        }
                        .padding(Spacing.lg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ColorSystem.terminalBg)
                    } else if parsedDiff.lines.isEmpty && diff.isFileChangeOnly {
                        // File change without diff content
                        VStack(spacing: Spacing.lg) {
                            Image(systemName: Icons.fileChange(for: diff.changeType))
                                .font(.system(size: 48))
                                .foregroundStyle(ColorSystem.FileChange.color(for: diff.changeType))

                            Text("File \(diff.summaryText)")
                                .font(Typography.bannerTitle)
                                .foregroundStyle(ColorSystem.textPrimary)

                            Text(diff.filePath)
                                .font(Typography.terminalSmall)
                                .foregroundStyle(ColorSystem.textTertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ColorSystem.terminalBg)
                    } else {
                        // Diff content view with zoom support
                        zoomableDiffContent
                    }
                }

                // Floating zoom indicator
                VStack {
                    Spacer()
                    ZoomIndicatorView(scale: currentScale, isVisible: $showZoomIndicator)
                        .padding(.bottom, Spacing.lg)
                }
            }
            .navigationTitle(diff.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ColorSystem.terminalBgElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Typography.buttonLabel)
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(diff.fileName)
                            .font(Typography.terminal)
                            .foregroundStyle(ColorSystem.textPrimary)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 6) {
                        if stats.additions > 0 {
                            Text("+\(stats.additions)")
                                .foregroundStyle(ColorSystem.Diff.addedText)
                        }
                        if stats.deletions > 0 {
                            Text("-\(stats.deletions)")
                                .foregroundStyle(ColorSystem.Diff.removedText)
                        }
                    }
                    .font(Typography.terminalTimestamp)
                }
            }
            // Bottom toolbar with zoom controls
            .safeAreaInset(edge: .bottom) {
                if !parsedDiff.lines.isEmpty || !diff.isFileChangeOnly {
                    ZoomToolbar(
                        scale: Binding(
                            get: { currentScale },
                            set: { newValue in
                                zoomScale = Double(newValue)
                                showZoomIndicator = true
                            }
                        ),
                        onReset: resetZoom
                    )
                }
            }
        }
        .task {
            // Fetch diff if not already loaded
            if diff.diff.isEmpty {
                await fetchDiff()
            }
        }
    }

    // MARK: - Zoomable Diff Content

    @ViewBuilder
    private var zoomableDiffContent: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // File header
                DiffFileHeader(filePath: diff.filePath, changeType: diff.changeType, scale: currentScale)

                // Diff lines with zoom
                ForEach(parsedDiff.lines) { line in
                    EnhancedDiffLineRow(line: line, scale: currentScale)
                }
            }
            .padding(.bottom, Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(ColorSystem.terminalBg)
        // Use simultaneousGesture to allow pinch alongside scroll
        .simultaneousGesture(magnificationGesture)
        .onTapGesture(count: 2) {
            // Double-tap to toggle between default and 150%
            withAnimation(Animations.stateChange) {
                if abs(currentScale - Constants.Zoom.defaultScale) < 0.1 {
                    zoomScale = 1.5
                } else {
                    zoomScale = Double(Constants.Zoom.defaultScale)
                }
            }
            showZoomIndicator = true
            Haptics.light()
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let delta = value / lastZoomScale
                lastZoomScale = value
                let newScale = currentScale * delta
                zoomScale = Double(min(max(newScale, Constants.Zoom.minScale), Constants.Zoom.maxScale))
                showZoomIndicator = true
            }
            .onEnded { _ in
                lastZoomScale = 1.0
                Haptics.light()
            }
    }

    private func resetZoom() {
        withAnimation(Animations.stateChange) {
            zoomScale = Double(Constants.Zoom.defaultScale)
        }
        showZoomIndicator = true
        Haptics.light()
    }

    private func fetchDiff() async {
        isLoading = true
        error = nil

        do {
            // Get repository from DI container
            let container = DependencyContainer.shared
            let repository = container.agentRepository
            let diffs = try await repository.getGitDiff(file: diff.filePath)

            if let fetchedDiff = diffs.first {
                diffContent = fetchedDiff.diff
            } else {
                error = "No diff available for this file"
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Zoom Toolbar

struct ZoomToolbar: View {
    @Binding var scale: CGFloat
    let onReset: () -> Void

    var body: some View {
        HStack {
            Spacer()

            ZoomControlView(scale: $scale, onReset: onReset)

            Spacer()
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Diff File Header

struct DiffFileHeader: View {
    let filePath: String
    let changeType: FileChangeType?
    var scale: CGFloat = 1.0

    private var scaledFontSize: CGFloat { 8 * scale }
    private var scaledIconSize: CGFloat { 10 * scale }

    var body: some View {
        HStack(spacing: Spacing.xs * scale) {
            // Change type indicator
            Rectangle()
                .fill(ColorSystem.FileChange.color(for: changeType))
                .frame(width: 4)

            // File icon
            Image(systemName: Icons.fileType(for: (filePath as NSString).pathExtension))
                .font(.system(size: scaledIconSize))
                .foregroundStyle(ColorSystem.textSecondary)

            // File path - truncate to fit
            Text(filePath)
                .font(.system(size: scaledFontSize, design: .monospaced))
                .foregroundStyle(ColorSystem.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Change type badge - aligned to right edge
            if let changeType = changeType {
                Text(changeType.rawValue.capitalized)
                    .font(.system(size: 9 * scale, weight: .medium))
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(ColorSystem.FileChange.color(for: changeType).opacity(0.2))
                    .foregroundStyle(ColorSystem.FileChange.color(for: changeType))
                    .clipShape(Capsule())
                    .fixedSize()
            }
        }
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, Spacing.xs * scale)
        .frame(width: UIScreen.main.bounds.width)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Enhanced Diff Line Row

struct EnhancedDiffLineRow: View {
    let line: DiffLine
    var scale: CGFloat = 1.0

    // Scaled dimensions - reduced base sizes (100% = what was 80%)
    private var lineNumberWidth: CGFloat { 30 * scale }
    private var indicatorWidth: CGFloat { 12 * scale }
    private var minContentWidth: CGFloat { 500 * scale }
    private var terminalFontSize: CGFloat { 10 * scale }
    private var lineNumberFontSize: CGFloat { 8 * scale }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Gutter indicator
            Rectangle()
                .fill(gutterColor)
                .frame(width: 4)

            // Old line number
            Text(line.oldLineNumber.map { "\($0)" } ?? "")
                .font(.system(size: lineNumberFontSize, weight: .light, design: .monospaced))
                .foregroundStyle(ColorSystem.textQuaternary)
                .frame(width: lineNumberWidth, alignment: .trailing)
                .padding(.trailing, 4 * scale)

            // New line number
            Text(line.newLineNumber.map { "\($0)" } ?? "")
                .font(.system(size: lineNumberFontSize, weight: .light, design: .monospaced))
                .foregroundStyle(ColorSystem.textQuaternary)
                .frame(width: lineNumberWidth, alignment: .trailing)
                .padding(.trailing, Spacing.xs * scale)

            // Change indicator (+/-/space)
            Text(changeIndicator)
                .font(.system(size: terminalFontSize, design: .monospaced))
                .foregroundStyle(indicatorColor)
                .frame(width: indicatorWidth)

            // Content (without the leading +/- character for additions/deletions)
            Text(displayContent)
                .font(.system(size: terminalFontSize, design: .monospaced))
                .foregroundStyle(lineColor)
                .textSelection(.enabled)
        }
        .frame(minWidth: minContentWidth, alignment: .leading)
        .padding(.vertical, 1 * scale)
        .background(lineBackground)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = line.content
                Haptics.selection()
            } label: {
                Label("Copy Line", systemImage: Icons.copy)
            }
        }
    }

    private var changeIndicator: String {
        switch line.type {
        case .addition: return "+"
        case .deletion: return "-"
        case .hunkHeader: return ""
        default: return " "
        }
    }

    private var indicatorColor: Color {
        switch line.type {
        case .addition: return ColorSystem.Diff.addedText
        case .deletion: return ColorSystem.Diff.removedText
        default: return .clear
        }
    }

    private var displayContent: String {
        // Remove the leading +/- character for display
        switch line.type {
        case .addition, .deletion:
            return String(line.content.dropFirst())
        default:
            return line.content
        }
    }

    private var gutterColor: Color {
        switch line.type {
        case .addition: return ColorSystem.Diff.addedGutter
        case .deletion: return ColorSystem.Diff.removedGutter
        case .hunkHeader: return ColorSystem.Diff.headerText.opacity(0.5)
        default: return .clear
        }
    }

    private var lineColor: Color {
        switch line.type {
        case .addition: return ColorSystem.Diff.addedText
        case .deletion: return ColorSystem.Diff.removedText
        case .header: return ColorSystem.Diff.headerText
        case .hunkHeader: return ColorSystem.Diff.headerText
        case .context: return ColorSystem.Diff.contextText
        }
    }

    private var lineBackground: Color {
        switch line.type {
        case .addition: return ColorSystem.Diff.addedBg
        case .deletion: return ColorSystem.Diff.removedBg
        case .header, .hunkHeader: return ColorSystem.Diff.headerBg
        case .context: return .clear
        }
    }
}

// MARK: - Zoom Control View

/// Sophisticated zoom control for diff viewer
struct ZoomControlView: View {
    @Binding var scale: CGFloat
    let onReset: () -> Void

    @State private var showPresets = false

    private var zoomPercentage: Int {
        Int(scale * 100)
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Zoom out button
            Button {
                adjustZoom(by: -Constants.Zoom.stepSize)
                Haptics.selection()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(scale > Constants.Zoom.minScale ? ColorSystem.textPrimary : ColorSystem.textQuaternary)
                    .frame(width: 28, height: 28)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(Circle())
            }
            .disabled(scale <= Constants.Zoom.minScale)

            // Zoom level indicator (tap for presets)
            Button {
                showPresets.toggle()
                Haptics.light()
            } label: {
                Text("\(zoomPercentage)%")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .frame(minWidth: 44)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 4)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(Capsule())
            }
            .popover(isPresented: $showPresets, attachmentAnchor: .point(.top)) {
                ZoomPresetsView(
                    currentScale: scale,
                    onSelect: { preset in
                        showPresets = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(Animations.stateChange) {
                                scale = preset
                            }
                            Haptics.selection()
                        }
                    },
                    onReset: {
                        showPresets = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onReset()
                        }
                    }
                )
                .presentationCompactAdaptation(.none)
            }

            // Zoom in button
            Button {
                adjustZoom(by: Constants.Zoom.stepSize)
                Haptics.selection()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(scale < Constants.Zoom.maxScale ? ColorSystem.textPrimary : ColorSystem.textQuaternary)
                    .frame(width: 28, height: 28)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(Circle())
            }
            .disabled(scale >= Constants.Zoom.maxScale)
        }
    }

    private func adjustZoom(by delta: CGFloat) {
        withAnimation(Animations.stateChange) {
            scale = min(max(scale + delta, Constants.Zoom.minScale), Constants.Zoom.maxScale)
        }
    }
}

// MARK: - Zoom Presets Popover

struct ZoomPresetsView: View {
    let currentScale: CGFloat
    let onSelect: (CGFloat) -> Void
    let onReset: () -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Header with reset
            HStack {
                Text("Zoom")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)

                Spacer()

                Button {
                    onReset()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("Reset")
                            .font(Typography.terminalSmall)
                    }
                    .foregroundStyle(ColorSystem.primary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)

            // Grid of zoom presets
            LazyVGrid(columns: columns, spacing: Spacing.xs) {
                ForEach(Constants.Zoom.presets, id: \.self) { preset in
                    ZoomPresetChip(
                        percentage: Int(preset * 100),
                        isSelected: abs(currentScale - preset) < 0.05,
                        action: { onSelect(preset) }
                    )
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.sm)
        }
        .frame(width: 200)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Zoom Preset Chip

struct ZoomPresetChip: View {
    let percentage: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(percentage)%")
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isSelected ? ColorSystem.primary : ColorSystem.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? ColorSystem.primary.opacity(0.15) : ColorSystem.terminalBgHighlight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? ColorSystem.primary.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Zoom Indicator Toast

/// Floating zoom indicator that appears during zoom changes
struct ZoomIndicatorView: View {
    let scale: CGFloat
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                Text("\(Int(scale * 100))%")
                    .font(Typography.terminal)
            }
            .foregroundStyle(ColorSystem.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8)
            .transition(.opacity.combined(with: .scale))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
    }
}
