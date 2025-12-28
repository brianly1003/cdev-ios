import SwiftUI

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
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showGraph.toggle()
                        Haptics.selection()
                    } label: {
                        Image(systemName: showGraph ? "chart.bar.xaxis" : "list.bullet")
                            .font(.system(size: layout.iconMedium))
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

    // MARK: - Commit List

    private var commitList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredCommits) { commit in
                    GitGraphRow(
                        commit: commit,
                        maxColumns: viewModel.maxColumns,
                        showGraph: showGraph,
                        isSelected: selectedCommit?.id == commit.id,
                        layout: layout
                    )
                    .onTapGesture {
                        selectedCommit = commit
                        Haptics.selection()
                    }

                    // Divider
                    if commit.id != filteredCommits.last?.id {
                        Divider()
                            .background(ColorSystem.terminalBgHighlight)
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

/// Compact row with git graph visualization and commit info
struct GitGraphRow: View {
    let commit: GitCommitNode
    let maxColumns: Int
    let showGraph: Bool
    let isSelected: Bool
    let layout: ResponsiveLayout

    private let columnWidth: CGFloat = 16
    private let nodeSize: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            // Graph visualization (optional)
            if showGraph {
                graphView
                    .frame(width: CGFloat(max(1, maxColumns)) * columnWidth + 8)
            }

            // Commit info
            commitInfo
                .padding(.leading, showGraph ? 0 : layout.smallPadding)

            Spacer(minLength: layout.tightSpacing)

            // Refs (tags, branches) and date
            HStack(spacing: layout.tightSpacing) {
                refsView
                dateView
            }
        }
        .padding(.horizontal, layout.smallPadding)
        .padding(.vertical, layout.tightSpacing)
        .background(isSelected ? ColorSystem.primary.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Graph View

    private var graphView: some View {
        Canvas { context, size in
            let rowHeight = size.height
            let midY = rowHeight / 2
            let column = commit.graphPosition?.column ?? 0

            // Draw lines from graph position
            if let lines = commit.graphPosition?.lines {
                for line in lines {
                    drawLine(context: context, line: line, midY: midY, rowHeight: rowHeight)
                }
            } else {
                // Default: draw straight line through commit
                var path = Path()
                let x = CGFloat(column) * columnWidth + columnWidth / 2
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: rowHeight))
                context.stroke(path, with: .color(branchColor(for: column)), lineWidth: 1.5)
            }

            // Draw node (commit dot)
            let nodeX = CGFloat(column) * columnWidth + columnWidth / 2
            let nodeRect = CGRect(
                x: nodeX - nodeSize / 2,
                y: midY - nodeSize / 2,
                width: nodeSize,
                height: nodeSize
            )

            // Merge commit = hollow circle, regular = filled
            if commit.isMergeCommit {
                context.stroke(
                    Circle().path(in: nodeRect),
                    with: .color(branchColor(for: column)),
                    lineWidth: 2
                )
            } else {
                context.fill(
                    Circle().path(in: nodeRect),
                    with: .color(branchColor(for: column))
                )
            }
        }
    }

    private func drawLine(context: GraphicsContext, line: GitGraphLine, midY: CGFloat, rowHeight: CGFloat) {
        let fromX = CGFloat(line.fromColumn) * columnWidth + columnWidth / 2
        let toX = CGFloat(line.toColumn) * columnWidth + columnWidth / 2

        var path = Path()

        switch line.lineType {
        case .straight:
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addLine(to: CGPoint(x: toX, y: rowHeight))

        case .mergeLeft, .mergeRight:
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: toX, y: midY),
                control: CGPoint(x: fromX, y: midY)
            )

        case .branchLeft, .branchRight:
            path.move(to: CGPoint(x: fromX, y: midY))
            path.addQuadCurve(
                to: CGPoint(x: toX, y: rowHeight),
                control: CGPoint(x: toX, y: midY)
            )

        case .horizontal:
            path.move(to: CGPoint(x: fromX, y: midY))
            path.addLine(to: CGPoint(x: toX, y: midY))

        case .cross:
            // Vertical line
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addLine(to: CGPoint(x: fromX, y: rowHeight))
        }

        context.stroke(path, with: .color(branchColor(for: line.fromColumn)), lineWidth: 1.5)
    }

    private func branchColor(for column: Int) -> Color {
        let colors: [Color] = [
            ColorSystem.primary,     // Column 0 - main branch
            ColorSystem.success,     // Column 1
            ColorSystem.info,        // Column 2
            ColorSystem.warning,     // Column 3
            .purple,                 // Column 4+
            .pink
        ]
        return colors[column % colors.count]
    }

    // MARK: - Commit Info

    private var commitInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            // SHA + Message
            HStack(spacing: layout.tightSpacing) {
                Text(commit.displaySha)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ColorSystem.primary)

                Text(commit.subject)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .lineLimit(1)
            }

            // Author
            Text(commit.author)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Refs View

    private var refsView: some View {
        HStack(spacing: 2) {
            if let refs = commit.refs?.prefix(2) {
                ForEach(Array(refs)) { ref in
                    RefBadgeCompact(ref: ref)
                }

                if (commit.refs?.count ?? 0) > 2 {
                    Text("+\((commit.refs?.count ?? 0) - 2)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
            }
        }
    }

    // MARK: - Date View

    private var dateView: some View {
        Text(commit.displayRelativeDate)
            .font(Typography.terminalSmall)
            .foregroundStyle(ColorSystem.textQuaternary)
            .frame(minWidth: 32, alignment: .trailing)
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
                    Button("Done") { dismiss() }
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
