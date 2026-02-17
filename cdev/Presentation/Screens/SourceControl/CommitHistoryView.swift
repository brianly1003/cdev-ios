import SwiftUI

private struct GraphLayoutMetrics {
    let columns: Int
    let gutterWidth: CGFloat
    let laneSpacing: CGFloat
    let laneInset: CGFloat
    let rowHeight: CGFloat
    let nodeSize: CGFloat
}

private enum GraphPalette {
    static let laneColors: [Color] = [
        Color(hex: "#49C6E5"), // Aegean blue
        Color(hex: "#6DD3A0"), // olive green
        Color(hex: "#F4C06A"), // antique gold
        Color(hex: "#F08A6A"), // terracotta
        Color(hex: "#87C9FF"), // ionian sky
        Color(hex: "#9AD1D4"), // marble aqua
        Color(hex: "#E6B8A2"), // sand
        Color(hex: "#6FB3B8")  // sea glass
    ]

    static func color(for lane: Int) -> Color {
        guard !laneColors.isEmpty else { return ColorSystem.primary }
        return laneColors[abs(lane) % laneColors.count]
    }
}

// MARK: - Commit History View

/// Compact terminal-style commit history with optional git graph visualization
/// Designed for mobile with touch-friendly rows and responsive layout
struct CommitHistoryView: View {
    @StateObject private var viewModel: CommitHistoryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    @State private var selectedCommit: GitCommitNode?
    @State private var searchText = ""
    @State private var showGraph = true
    @State private var compactMode = true
    @FocusState private var isSearchFocused: Bool

    init(workspaceId: String) {
        _viewModel = StateObject(wrappedValue: CommitHistoryViewModel(workspaceId: workspaceId))
    }

    /// Local filtering to avoid AttributeGraph cycles
    private var filteredCommits: [GitCommitNode] {
        guard !searchText.isEmpty else { return viewModel.commits }
        let query = searchText.lowercased()
        return viewModel.commits.filter { commit in
            commit.subject.lowercased().contains(query) ||
            commit.author.lowercased().contains(query) ||
            commit.shortSha?.lowercased().contains(query) == true ||
            commit.sha.lowercased().contains(query)
        }
    }

    private var indexedFilteredCommits: [(offset: Int, commit: GitCommitNode)] {
        Array(filteredCommits.enumerated()).map { item in
            (offset: item.offset, commit: item.element)
        }
    }

    private var graphColumns: Int {
        max(1, viewModel.maxColumns)
    }

    private var graphLayout: GraphLayoutMetrics {
        let laneInset: CGFloat = compactMode ? 8 : 10
        let preferredLaneSpacing: CGFloat = compactMode
            ? (layout.isCompact ? 9 : 10)
            : (layout.isCompact ? 10 : 12)
        let minimumLaneSpacing: CGFloat = compactMode ? 5.5 : 7
        let targetGutterWidth: CGFloat = compactMode
            ? (layout.isCompact ? 112 : 148)
            : (layout.isCompact ? 124 : 176)
        let availableWidth = max(0, targetGutterWidth - laneInset * 2)
        let fittedLaneSpacing = max(
            minimumLaneSpacing,
            min(preferredLaneSpacing, availableWidth / CGFloat(max(1, graphColumns)))
        )
        let gutterWidth = laneInset * 2 + fittedLaneSpacing * CGFloat(graphColumns)

        return GraphLayoutMetrics(
            columns: graphColumns,
            gutterWidth: gutterWidth,
            laneSpacing: fittedLaneSpacing,
            laneInset: laneInset,
            rowHeight: compactMode ? (layout.isCompact ? 44 : 46) : (layout.isCompact ? 52 : 56),
            nodeSize: compactMode ? 7 : 9
        )
    }

    private var toolbarButtonSize: CGFloat {
        layout.isCompact ? 42 : 44
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                filterBar

                // Content
                if viewModel.isLoading && viewModel.commits.isEmpty {
                    loadingView
                } else if viewModel.commits.isEmpty {
                    emptyView
                } else {
                    commitList
                }
            }
            .background(ColorSystem.terminalBg)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(ColorSystem.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: layout.contentSpacing) {
                        Button {
                            compactMode.toggle()
                            Haptics.selection()
                        } label: {
                            Image(systemName: compactMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                .font(.system(size: layout.iconMedium))
                                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                                .background(ColorSystem.terminalBgElevated.opacity(0.95))
                                .overlay(
                                    Circle()
                                        .stroke(ColorSystem.terminalBgHighlight.opacity(0.7), lineWidth: 0.8)
                                )
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }

                        Button {
                            showGraph.toggle()
                            Haptics.selection()
                        } label: {
                            Image(systemName: showGraph ? "point.3.filled.connected.trianglepath.dotted" : "list.bullet")
                                .font(.system(size: layout.iconMedium))
                                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                                .background(ColorSystem.terminalBgElevated.opacity(0.95))
                                .overlay(
                                    Circle()
                                        .stroke(ColorSystem.terminalBgHighlight.opacity(0.7), lineWidth: 0.8)
                                )
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                    }
                }
            }
            .task {
                await viewModel.loadCommits()
            }
            .sheet(item: $selectedCommit) { commit in
                CommitDetailSheet(commit: commit)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: layout.contentSpacing) {
            // Search
            HStack(spacing: layout.tightSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("Search commits...", text: $searchText)
                    .font(Typography.terminal)
                    .focused($isSearchFocused)
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: layout.iconSmall))
                            .foregroundStyle(ColorSystem.textTertiary)
                    }
                }
            }
            .padding(.horizontal, layout.smallPadding)
            .padding(.vertical, layout.tightSpacing)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Commit count
            if viewModel.totalCount > 0 {
                Text("\(viewModel.totalCount)")
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ColorSystem.textSecondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, layout.smallPadding)
        .background(ColorSystem.terminalBgElevated)
    }

    private var commitTableHeader: some View {
        HStack(spacing: layout.tightSpacing) {
            if showGraph {
                Text("Graph")
                    .frame(width: graphLayout.gutterWidth, alignment: .leading)
            }
            Text("Description")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Commit")
                .frame(width: 78, alignment: .leading)
            Text("Author")
                .frame(width: 132, alignment: .leading)
            Text("Date")
                .frame(width: 94, alignment: .trailing)
        }
        .font(Typography.badge)
        .foregroundStyle(ColorSystem.textTertiary)
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, 6)
        .background(ColorSystem.terminalBgElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ColorSystem.terminalBgHighlight.opacity(0.6))
                .frame(height: 0.7)
        }
    }

    // MARK: - Commit List

    private var commitList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !layout.isCompact {
                    commitTableHeader
                }

                ForEach(indexedFilteredCommits, id: \.offset) { item in
                    let commit = item.commit
                    GitGraphRow(
                        commit: commit,
                        showGraph: showGraph,
                        isSelected: selectedCommit?.id == commit.id,
                        layout: layout,
                        compactMode: compactMode,
                        graphLayout: graphLayout,
                        rowIndex: item.offset
                    )
                    .onTapGesture {
                        selectedCommit = commit
                        Haptics.selection()
                    }
                }

                // Load more indicator
                if viewModel.hasMore {
                    loadMoreRow
                }

                // Bottom padding
                Color.clear.frame(height: Spacing.xl)
            }
        }
        .refreshable {
            await viewModel.loadCommits()
        }
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            if viewModel.isLoadingMore {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    Text("Load more...")
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.primary)
                }
            }
            Spacer()
        }
        .padding(.vertical, layout.standardPadding)
        .onAppear {
            Task { await viewModel.loadMore() }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading history...")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)
            Spacer()
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(ColorSystem.textTertiary)

            Text(searchText.isEmpty ? "No commits yet" : "No matching commits")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    viewModel.filterText = ""
                } label: {
                    Text("Clear search")
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.primary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Commit History ViewModel

@MainActor
final class CommitHistoryViewModel: ObservableObject {
    @Published private(set) var commits: [GitCommitNode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var totalCount = 0
    @Published private(set) var maxColumns = 1
    @Published private(set) var error: String?
    @Published var filterText = ""

    private let workspaceId: String
    private var currentOffset = 0
    private let pageSize = 50

    init(workspaceId: String) {
        self.workspaceId = workspaceId
    }

    var filteredCommits: [GitCommitNode] {
        guard !filterText.isEmpty else { return commits }
        let search = filterText.lowercased()
        return commits.filter { commit in
            commit.subject.lowercased().contains(search) ||
            commit.author.lowercased().contains(search) ||
            commit.displaySha.lowercased().contains(search)
        }
    }

    func loadCommits() async {
        isLoading = true
        error = nil
        currentOffset = 0

        do {
            let result = try await WorkspaceManagerService.shared.gitLog(
                workspaceId: workspaceId,
                limit: pageSize,
                offset: 0,
                graph: true
            )
            commits = result.safeCommits
            totalCount = result.totalCount ?? commits.count
            hasMore = result.hasMore ?? false
            maxColumns = result.maxColumns ?? 1
            currentOffset = commits.count
        } catch {
            self.error = error.localizedDescription
            AppLogger.log("[CommitHistory] Failed to load commits: \(error)", type: .error)
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }
        isLoadingMore = true

        do {
            let result = try await WorkspaceManagerService.shared.gitLog(
                workspaceId: workspaceId,
                limit: pageSize,
                offset: currentOffset,
                graph: true
            )
            commits.append(contentsOf: result.safeCommits)
            hasMore = result.hasMore ?? false
            currentOffset = commits.count
        } catch {
            AppLogger.log("[CommitHistory] Failed to load more: \(error)", type: .error)
        }

        isLoadingMore = false
    }
}

// MARK: - Git Graph Row

/// SourceTree-like row: stable graph gutter + table-like metadata columns
private struct GitGraphRow: View {
    let commit: GitCommitNode
    let showGraph: Bool
    let isSelected: Bool
    let layout: ResponsiveLayout
    let compactMode: Bool
    let graphLayout: GraphLayoutMetrics
    let rowIndex: Int

    private var graphColumns: Int { max(1, graphLayout.columns) }
    private var laneSpacing: CGFloat { graphLayout.laneSpacing }
    private var laneInsetX: CGFloat { graphLayout.laneInset }
    private var rowHeight: CGFloat { graphLayout.rowHeight }
    private var nodeSize: CGFloat { commit.isMergeCommit ? graphLayout.nodeSize + 1 : graphLayout.nodeSize }
    private var currentColumn: Int { commit.graphPosition?.column ?? 0 }
    private var primaryInlineRefs: [GitCommitRef] {
        Array((commit.refs ?? []).prefix(compactMode ? 1 : 2))
    }
    private var hiddenInlineRefCount: Int {
        max(0, (commit.refs?.count ?? 0) - primaryInlineRefs.count)
    }
    private var inlineRefOffsetX: CGFloat {
        let proposed = xPosition(for: currentColumn) + nodeSize / 2 + 4
        let reservedWidth: CGFloat = compactMode ? 34 : 56
        return min(max(0, proposed), max(0, graphLayout.gutterWidth - reservedWidth))
    }

    var body: some View {
        HStack(alignment: .center, spacing: layout.tightSpacing) {
            if showGraph {
                graphView
            }

            if layout.isCompact {
                compactDetails
            } else {
                regularDetails
            }
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, layout.ultraTightSpacing + 2)
        .frame(minHeight: rowHeight + 8)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ColorSystem.terminalBgHighlight.opacity(0.45))
                .frame(height: 0.7)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Layouts

    private var compactDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.subject)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textPrimary)
                .lineLimit(compactMode ? 1 : 2)
                .truncationMode(.tail)

            HStack(spacing: 4) {
                Text(commit.displaySha)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#84D7EF"))
                Text("•")
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.textQuaternary)
                Text(commit.author)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(commit.displayRelativeDate)
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var regularDetails: some View {
        HStack(spacing: layout.contentSpacing) {
            Text(commit.subject)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textPrimary)
                .lineLimit(compactMode ? 1 : 2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(commit.displaySha)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: "#84D7EF"))
                .frame(width: 78, alignment: .leading)

            Text(commit.author)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 132, alignment: .leading)

            Text(commit.displayRelativeDate)
                .font(Typography.badge)
                .foregroundStyle(ColorSystem.textQuaternary)
                .frame(width: 94, alignment: .trailing)
        }
    }

    // MARK: - Graph View

    private var graphView: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(ColorSystem.terminalBgElevated.opacity(0.38))

            Canvas { context, size in
                let centerY = size.height / 2

                drawLaneGuides(context: context, size: size)

                if let lines = commit.graphPosition?.lines, !lines.isEmpty {
                    for line in lines {
                        drawLine(context: context, line: line, centerY: centerY, rowHeight: size.height)
                    }
                } else {
                    drawStem(context: context, column: currentColumn, rowHeight: size.height)
                }

                let nodeX = xPosition(for: currentColumn)
                let nodeRect = CGRect(
                    x: nodeX - nodeSize / 2,
                    y: centerY - nodeSize / 2,
                    width: nodeSize,
                    height: nodeSize
                )
                let nodeColor = branchColor(for: currentColumn)

                if commit.isMergeCommit {
                    context.stroke(
                        Circle().path(in: nodeRect),
                        with: .color(nodeColor),
                        lineWidth: 1.8
                    )
                    context.fill(
                        Circle().path(in: nodeRect.insetBy(dx: 1.8, dy: 1.8)),
                        with: .color(Color(hex: "#EDE5D6"))
                    )
                } else {
                    context.fill(Circle().path(in: nodeRect), with: .color(nodeColor))
                    context.stroke(
                        Circle().path(in: nodeRect),
                        with: .color(Color(hex: "#EDE5D6").opacity(0.85)),
                        lineWidth: 0.7
                    )
                }
            }

            if !primaryInlineRefs.isEmpty {
                HStack(spacing: 2) {
                    ForEach(primaryInlineRefs) { ref in
                        InlineNodeRefBadge(ref: ref, compact: compactMode)
                    }
                    if hiddenInlineRefCount > 0 {
                        Text("+\(hiddenInlineRefCount)")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(ColorSystem.textTertiary)
                    }
                }
                .offset(x: inlineRefOffsetX, y: 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: graphLayout.gutterWidth, height: rowHeight)
        .clipped()
    }

    private func drawLaneGuides(context: GraphicsContext, size: CGSize) {
        for lane in 0..<graphColumns {
            let x = xPosition(for: lane)
            var guide = Path()
            guide.move(to: CGPoint(x: x, y: 0))
            guide.addLine(to: CGPoint(x: x, y: size.height))

            let isCurrent = lane == currentColumn
            let color = isCurrent
                ? Color(hex: "#9ED4F1").opacity(0.24)
                : Color(hex: "#7994A8").opacity(0.18)
            context.stroke(guide, with: .color(color), lineWidth: isCurrent ? 1.0 : 0.7)
        }
    }

    private func drawStem(context: GraphicsContext, column: Int, rowHeight: CGFloat) {
        var path = Path()
        let x = xPosition(for: column)
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: rowHeight))
        context.stroke(path, with: .color(branchColor(for: column)), lineWidth: compactMode ? 1.8 : 2.1)
    }

    private func drawLine(context: GraphicsContext, line: GitGraphLine, centerY: CGFloat, rowHeight: CGFloat) {
        let fromX = xPosition(for: line.fromColumn)
        let toX = xPosition(for: line.toColumn)

        var path = Path()

        switch line.lineType {
        case .straight:
            path.move(to: CGPoint(x: fromX, y: 0))
            if fromX == toX {
                path.addLine(to: CGPoint(x: toX, y: rowHeight))
            } else {
                let controlY = rowHeight * 0.5
                path.addCurve(
                    to: CGPoint(x: toX, y: rowHeight),
                    control1: CGPoint(x: fromX, y: controlY * 0.7),
                    control2: CGPoint(x: toX, y: controlY * 1.3)
                )
            }
        case .mergeLeft, .mergeRight:
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addCurve(
                to: CGPoint(x: toX, y: centerY),
                control1: CGPoint(x: fromX, y: rowHeight * 0.45),
                control2: CGPoint(x: toX, y: rowHeight * 0.75)
            )
        case .branchLeft, .branchRight:
            path.move(to: CGPoint(x: fromX, y: centerY))
            path.addCurve(
                to: CGPoint(x: toX, y: rowHeight),
                control1: CGPoint(x: fromX, y: rowHeight * 0.65),
                control2: CGPoint(x: toX, y: rowHeight * 0.35)
            )
        case .horizontal:
            path.move(to: CGPoint(x: fromX, y: centerY))
            path.addLine(to: CGPoint(x: toX, y: centerY))
        case .cross:
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addLine(to: CGPoint(x: fromX, y: rowHeight))
            path.move(to: CGPoint(x: fromX, y: centerY))
            path.addLine(to: CGPoint(x: toX, y: centerY))
        }

        context.stroke(
            path,
            with: .color(branchColor(for: line.fromColumn)),
            lineWidth: compactMode ? 1.8 : 2.1
        )
    }

    private func xPosition(for column: Int) -> CGFloat {
        CGFloat(column) * laneSpacing + laneSpacing / 2 + laneInsetX
    }

    private func branchColor(for column: Int) -> Color {
        GraphPalette.color(for: column)
    }

    private var rowBackground: some View {
        let zebra = rowIndex.isMultiple(of: 2)
            ? ColorSystem.terminalBg.opacity(0.84)
            : ColorSystem.terminalBgElevated.opacity(0.44)
        return Rectangle()
            .fill(isSelected ? ColorSystem.primary.opacity(0.16) : zebra)
    }
}

private struct InlineNodeRefBadge: View {
    let ref: GitCommitRef
    let compact: Bool

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: iconName)
                .font(.system(size: compact ? 5 : 6))
            Text(displayName)
                .font(.system(size: compact ? 7 : 8, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(refColor)
        .padding(.horizontal, compact ? 3 : 4)
        .padding(.vertical, 1)
        .background(refColor.opacity(0.14))
        .clipShape(Capsule())
    }

    private var displayName: String {
        let trimmed: String
        switch ref.refType {
        case .head:
            trimmed = "HEAD"
        case .remoteBranch where ref.name.hasPrefix("origin/"):
            trimmed = String(ref.name.dropFirst(7))
        default:
            trimmed = ref.name
        }
        let maxLen = compact ? 8 : 12
        return trimmed.count > maxLen ? String(trimmed.prefix(maxLen - 1)) + "…" : trimmed
    }

    private var iconName: String {
        switch ref.refType {
        case .head: return "arrow.right"
        case .localBranch: return "arrow.triangle.branch"
        case .remoteBranch: return "cloud"
        case .tag: return "tag"
        }
    }

    private var refColor: Color {
        switch ref.refType {
        case .head: return .orange
        case .localBranch: return ColorSystem.success
        case .remoteBranch: return ColorSystem.info
        case .tag: return .yellow
        }
    }
}

// MARK: - Ref Badge Compact

/// Ultra-compact ref badge for commit list
struct RefBadgeCompact: View {
    let ref: GitCommitRef

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: iconName)
                .font(.system(size: 6))
            Text(displayName)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundStyle(refColor)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(refColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch ref.refType {
        case .head: return "arrow.right"
        case .localBranch: return "arrow.triangle.branch"
        case .remoteBranch: return "cloud"
        case .tag: return "tag"
        }
    }

    private var displayName: String {
        switch ref.refType {
        case .head: return "HEAD"
        case .remoteBranch:
            if ref.name.hasPrefix("origin/") {
                return String(ref.name.dropFirst(7))
            }
            return ref.name
        default:
            // Truncate long branch names
            if ref.name.count > 12 {
                return String(ref.name.prefix(10)) + "…"
            }
            return ref.name
        }
    }

    private var refColor: Color {
        switch ref.refType {
        case .head: return .orange
        case .localBranch: return ColorSystem.success
        case .remoteBranch: return ColorSystem.info
        case .tag: return .yellow
        }
    }
}

// MARK: - Commit Detail Sheet

/// Detailed view of a single commit
struct CommitDetailSheet: View {
    let commit: GitCommitNode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    // Commit message
                    messageSection

                    Divider()
                        .background(ColorSystem.terminalBgHighlight)

                    // Metadata
                    metadataSection

                    // Refs
                    if let refs = commit.refs, !refs.isEmpty {
                        Divider()
                            .background(ColorSystem.terminalBgHighlight)
                        refsSection(refs: refs)
                    }

                    // Parents
                    if let parents = commit.parentShas, !parents.isEmpty {
                        Divider()
                            .background(ColorSystem.terminalBgHighlight)
                        parentsSection(parents: parents)
                    }
                }
                .padding(layout.standardPadding)
            }
            .background(ColorSystem.terminalBg)
            .navigationTitle("Commit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(ColorSystem.primary)
                }
            }
        }
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            // Subject (first line)
            Text(commit.subject)
                .font(Typography.bodyBold)
                .foregroundStyle(ColorSystem.textPrimary)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            // SHA
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "number")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(width: 20)

                Text(commit.sha)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ColorSystem.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button {
                    UIPasteboard.general.string = commit.sha
                    Haptics.light()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: layout.iconSmall))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
            }

            // Author
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "person")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(commit.author)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textPrimary)
                    Text(commit.authorEmail)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                }
            }

            // Date
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "calendar")
                    .font(.system(size: layout.iconSmall))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(width: 20)

                if let date = commit.parsedDate {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textSecondary)
                } else {
                    Text(commit.date)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textSecondary)
                }
            }
        }
    }

    private func refsSection(refs: [GitCommitRef]) -> some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            Text("References")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)

            FlowLayout(spacing: layout.tightSpacing) {
                ForEach(refs) { ref in
                    RefBadgeCompact(ref: ref)
                }
            }
        }
    }

    private func parentsSection(parents: [String]) -> some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            Text("Parents")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)

            ForEach(parents, id: \.self) { parent in
                Text(String(parent.prefix(7)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ColorSystem.primary)
            }
        }
    }
}

// MARK: - Flow Layout

/// Simple flow layout for wrapping badges
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - Date Extension

extension Date {
    /// Format date as relative time (e.g., "2h", "3d", "1w")
    var relativeFormatted: String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day, .weekOfYear], from: self, to: now)

        if let weeks = components.weekOfYear, weeks >= 1 {
            return "\(weeks)w"
        } else if let days = components.day, days >= 1 {
            return "\(days)d"
        } else if let hours = components.hour, hours >= 1 {
            return "\(hours)h"
        } else if let minutes = components.minute, minutes >= 1 {
            return "\(minutes)m"
        } else {
            return "now"
        }
    }
}

// MARK: - Preview

#Preview {
    CommitHistoryView(workspaceId: "test")
}
