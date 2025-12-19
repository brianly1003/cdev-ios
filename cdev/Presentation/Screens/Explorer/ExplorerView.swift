import SwiftUI

/// Main file explorer view - 3rd tab in dashboard
/// Allows browsing repository files with navigation and file viewing
struct ExplorerView: View {
    @ObservedObject var viewModel: ExplorerViewModel

    // Local state for controlled sheet presentation (prevents conflicts)
    @State private var presentedFile: FileEntry?
    @State private var isPresentingSheet = false

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
        .sheet(item: $presentedFile) { file in
            FileViewerView(
                file: file,
                content: viewModel.fileContent,
                isLoading: viewModel.isLoadingFile,
                onDismiss: {
                    presentedFile = nil
                    viewModel.closeFile()
                }
            )
        }
        .onChange(of: viewModel.selectedFile) { _, newFile in
            // Controlled presentation: only present if not already presenting
            if let file = newFile {
                if !isPresentingSheet {
                    isPresentingSheet = true
                    // Small delay to avoid presentation conflicts
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        presentedFile = file
                    }
                }
            } else {
                // File was deselected
                isPresentingSheet = false
                presentedFile = nil
            }
        }
        .onChange(of: presentedFile) { _, newValue in
            // Track presentation state
            if newValue == nil {
                isPresentingSheet = false
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
