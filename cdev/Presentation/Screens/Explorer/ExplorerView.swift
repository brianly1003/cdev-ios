import SwiftUI

/// Main file explorer view - 3rd tab in dashboard
/// Allows browsing repository files with navigation and file viewing
struct ExplorerView: View {
    @ObservedObject var viewModel: ExplorerViewModel

    // Sheet presentation state - use isPresented instead of item to avoid race conditions
    @State private var isShowingFileViewer = false
    @State private var isDismissing = false

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb navigation bar
            BreadcrumbBar(
                path: viewModel.currentPath,
                onNavigate: { path in
                    Task { await viewModel.navigateToBreadcrumb(path: path) }
                },
                onRoot: {
                    Task { await viewModel.navigateToRoot() }
                }
            )

            // Content area
            contentView
        }
        .background(ColorSystem.terminalBg)
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $isShowingFileViewer, onDismiss: {
            // Called when sheet is fully dismissed
            isDismissing = false
            viewModel.closeFile()
        }) {
            if let file = viewModel.selectedFile {
                FileViewerView(
                    file: file,
                    content: viewModel.fileContent,
                    isLoading: viewModel.isLoadingFile,
                    onDismiss: {
                        isDismissing = true
                        isShowingFileViewer = false
                    }
                )
            }
        }
        .onChange(of: viewModel.selectedFile) { _, newFile in
            // Only show sheet if file selected and not currently dismissing
            if newFile != nil && !isDismissing && !isShowingFileViewer {
                isShowingFileViewer = true
            }
        }
        .errorAlert($viewModel.error)
        .task {
            // Load initial directory if empty
            if viewModel.entries.isEmpty {
                await viewModel.loadDirectory()
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading && viewModel.entries.isEmpty {
            // Loading skeleton
            DirectoryLoadingView()
        } else if viewModel.entries.isEmpty {
            // Empty state
            EmptyDirectoryView(isRoot: viewModel.currentPath.isEmpty)
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
                }
            )
        }
    }
}


// MARK: - Preview

#Preview {
    // Create mock repository and view model for preview
    let cache = FileCache()
    let httpService = HTTPService()
    let repository = FileRepository(
        httpService: httpService,
        cache: cache,
        useMockData: true
    )
    let viewModel = ExplorerViewModel(fileRepository: repository)

    return ExplorerView(viewModel: viewModel)
}
