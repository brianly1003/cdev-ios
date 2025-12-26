import SwiftUI

/// Main file explorer view - 3rd tab in dashboard
/// Allows browsing repository files with navigation and file viewing
struct ExplorerView: View {
    @ObservedObject var viewModel: ExplorerViewModel

    // Scroll request (from floating toolkit long-press)
    var scrollRequest: ScrollDirection?

    // Callback to present file viewer (hoisted to DashboardView to avoid TabView recreation issues)
    var onPresentFile: ((FileEntry) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar (always visible)
            ExplorerSearchBar(
                query: $viewModel.searchQuery,
                isSearching: viewModel.isSearching,
                onQueryChange: { query in
                    viewModel.updateSearchQuery(query)
                },
                onClear: {
                    viewModel.clearSearch()
                }
            )

            // Bottom border (matches Terminal search bar)
            Divider()
                .background(ColorSystem.terminalBgHighlight)

            // Breadcrumb navigation bar (hidden when searching)
            if !viewModel.isSearchActive {
                BreadcrumbBar(
                    path: viewModel.currentPath,
                    onNavigate: { path in
                        Task { await viewModel.navigateToBreadcrumb(path: path) }
                    },
                    onRoot: {
                        Task { await viewModel.navigateToRoot() }
                    }
                )
            }

            // Content area - switches between directory and search results
            contentView
        }
        .background(ColorSystem.terminalBg)
        .refreshable {
            await viewModel.refresh()
        }
        .errorAlert($viewModel.error)
        .task {
            // Load initial directory if empty
            if viewModel.entries.isEmpty {
                await viewModel.loadDirectory()
            }
        }
        .onDisappear {
            // Clean up tasks when view disappears
            viewModel.cancelAllTasks()
        }
        .onChange(of: viewModel.selectedFile) { _, newFile in
            // Notify parent to present file viewer
            if let file = newFile {
                onPresentFile?(file)
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isSearchActive {
            // Search results mode
            SearchResultsView(
                results: viewModel.searchResults,
                query: viewModel.searchQuery,
                isSearching: viewModel.isSearching,
                error: viewModel.searchError,
                onSelect: { entry in
                    Task {
                        // Clear search and navigate to the selected entry
                        viewModel.clearSearch()
                        await viewModel.selectEntry(entry)
                    }
                },
                onRetry: {
                    viewModel.retrySearch()
                },
                scrollRequest: scrollRequest
            )
        } else if viewModel.isLoading && viewModel.entries.isEmpty {
            // Loading skeleton
            DirectoryLoadingView()
        } else if viewModel.entries.isEmpty {
            // Empty state with parent navigation
            EmptyDirectoryView(
                isRoot: viewModel.currentPath.isEmpty,
                onBack: {
                    Task { await viewModel.navigateBack() }
                }
            )
        } else {
            // Directory list
            DirectoryListView(
                entries: viewModel.entries,
                currentPath: viewModel.currentPath,
                onSelect: { entry in
                    Task { await viewModel.selectEntry(entry) }
                },
                onBack: {
                    Task { await viewModel.navigateBack() }
                },
                scrollRequest: scrollRequest
            )
        }
    }
}


// MARK: - Preview

#Preview {
    // Create mock repository and view model for preview
    let cache = FileCache()
    let webSocketService = WebSocketService()
    let httpService = HTTPService()
    let repository = FileRepository(
        webSocketService: webSocketService,
        httpService: httpService,
        cache: cache,
        useMockData: true  // Use mock data for preview
    )
    let viewModel = ExplorerViewModel(fileRepository: repository)

    return ExplorerView(viewModel: viewModel)
}
