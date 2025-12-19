import Foundation
import Combine

/// ViewModel for file explorer functionality
@MainActor
final class ExplorerViewModel: ObservableObject {
    // MARK: - Navigation State

    @Published var currentPath: String = ""
    @Published private(set) var navigationStack: [String] = []  // Breadcrumb history

    // MARK: - Content State

    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var isLoading = false
    @Published var error: AppError?

    // MARK: - File Viewer State

    @Published var selectedFile: FileEntry?
    @Published private(set) var fileContent: String?
    @Published private(set) var isLoadingFile = false

    // MARK: - Search State

    @Published var searchQuery = ""
    @Published private(set) var searchResults: [FileEntry] = []
    @Published private(set) var isSearching = false
    @Published var searchError: AppError?

    /// Whether search mode is active (has query or results)
    var isSearchActive: Bool {
        !searchQuery.isEmpty || !searchResults.isEmpty
    }

    /// Minimum characters required before searching
    private let minSearchLength = 2

    // MARK: - Dependencies

    private let fileRepository: FileRepositoryProtocol
    private var gitStatusProvider: (() -> [GitFileEntry])?

    // MARK: - Task Management

    /// Current directory loading task - cancelled when starting a new load
    private var loadingTask: Task<Void, Never>?

    /// Search debounce task - cancelled when query changes
    private var searchDebounceTask: Task<Void, Never>?

    /// Current search task - cancelled when starting a new search
    private var currentSearchTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Current directory name for display
    var currentDirectoryName: String {
        if currentPath.isEmpty {
            return "Repository"
        }
        return currentPath.split(separator: "/").last.map(String.init) ?? currentPath
    }

    /// Whether we can navigate back
    var canNavigateBack: Bool {
        !currentPath.isEmpty
    }

    /// Breadcrumb path components for navigation
    var breadcrumbComponents: [(name: String, path: String)] {
        guard !currentPath.isEmpty else { return [] }

        var result: [(String, String)] = []
        var currentBuildPath = ""

        for component in currentPath.split(separator: "/") {
            currentBuildPath += (currentBuildPath.isEmpty ? "" : "/") + component
            result.append((String(component), currentBuildPath))
        }

        return result
    }

    // MARK: - Init

    init(
        fileRepository: FileRepositoryProtocol,
        gitStatusProvider: (() -> [GitFileEntry])? = nil
    ) {
        self.fileRepository = fileRepository
        self.gitStatusProvider = gitStatusProvider
    }

    // MARK: - Navigation

    /// Navigate into a directory
    func navigateTo(path: String) async {
        // Don't navigate to same path
        guard path != currentPath else { return }

        // Add current path to stack for back navigation
        if !currentPath.isEmpty || !path.isEmpty {
            navigationStack.append(currentPath)
        }

        currentPath = path
        await loadDirectory()

        Haptics.selection()
    }

    /// Navigate back to previous directory
    func navigateBack() async {
        guard let previousPath = navigationStack.popLast() else {
            // If no history, go to root
            if !currentPath.isEmpty {
                currentPath = ""
                await loadDirectory()
            }
            return
        }

        currentPath = previousPath
        await loadDirectory()

        Haptics.selection()
    }

    /// Navigate to root directory
    func navigateToRoot() async {
        guard !currentPath.isEmpty else { return }

        navigationStack.removeAll()
        currentPath = ""
        await loadDirectory()

        Haptics.selection()
    }

    /// Navigate to a specific path in breadcrumb
    func navigateToBreadcrumb(path: String) async {
        // Remove all paths after this one from the stack
        while let last = navigationStack.last, last != path {
            navigationStack.removeLast()
        }

        currentPath = path
        await loadDirectory()

        Haptics.selection()
    }

    // MARK: - Data Loading

    /// Load the current directory contents
    func loadDirectory() async {
        // Cancel any existing loading task
        loadingTask?.cancel()

        isLoading = true
        error = nil

        // Create a new task that we can track
        let path = currentPath
        loadingTask = Task {
            do {
                // Check for cancellation before making network request
                try Task.checkCancellation()

                var fetchedEntries = try await fileRepository.listDirectory(path: path)

                // Check for cancellation after network request
                try Task.checkCancellation()

                // Merge git status if available
                if let gitFiles = gitStatusProvider?() {
                    fetchedEntries = mergeGitStatus(entries: fetchedEntries, gitFiles: gitFiles)
                }

                // Only update if this is still the current path (not cancelled/navigated away)
                if self.currentPath == path {
                    entries = fetchedEntries
                    AppLogger.log("[ExplorerViewModel] Loaded \(entries.count) entries for '\(path)'")
                }
            } catch is CancellationError {
                // Task was cancelled - this is expected when navigating away quickly
                AppLogger.log("[ExplorerViewModel] Directory load cancelled for '\(path)'")
            } catch {
                // Check if this is a URL cancellation error (code -999)
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    // Request was cancelled - this is expected behavior
                    AppLogger.log("[ExplorerViewModel] HTTP request cancelled for '\(path)'")
                } else {
                    // Only set error if this is still the current path
                    if self.currentPath == path {
                        self.error = error as? AppError ?? .unknown(underlying: error)
                        AppLogger.error(error, context: "Loading directory '\(path)'")
                    }
                }
            }

            // Only update loading state if this is still the current path
            if self.currentPath == path {
                isLoading = false
            }
        }

        // Wait for the task to complete
        await loadingTask?.value
    }

    /// Refresh the current directory
    func refresh() async {
        // Invalidate cache for current path
        await fileRepository.invalidateCache(path: currentPath)
        await loadDirectory()
    }

    // MARK: - File Operations

    /// Current file loading task
    private var fileLoadingTask: Task<Void, Never>?

    /// Open a file for viewing
    func openFile(_ file: FileEntry) async {
        guard !file.isDirectory else { return }

        // If same file is already selected and has content, just re-trigger the sheet
        if selectedFile?.path == file.path {
            if fileContent != nil {
                AppLogger.log("[ExplorerViewModel] Re-opening same file: '\(file.name)'")
                // Force onChange to trigger by clearing and re-setting
                let savedFile = selectedFile
                let savedContent = fileContent
                selectedFile = nil
                // Small delay to ensure onChange detects the change
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
                selectedFile = savedFile
                fileContent = savedContent
                return
            }
            // If still loading, ignore additional taps
            if isLoadingFile {
                AppLogger.log("[ExplorerViewModel] File still loading: '\(file.name)'")
                return
            }
        }

        // Cancel any existing file loading task
        fileLoadingTask?.cancel()

        // Clear any existing error to prevent sheet conflict
        error = nil

        // Clear previous content before setting new file
        fileContent = nil
        isLoadingFile = true
        selectedFile = file

        AppLogger.log("[ExplorerViewModel] Opening file: '\(file.name)'")

        let filePath = file.path
        fileLoadingTask = Task {
            do {
                try Task.checkCancellation()
                let response = try await fileRepository.readFile(path: filePath)
                try Task.checkCancellation()

                // Only update if this file is still selected
                if self.selectedFile?.path == filePath {
                    fileContent = response.content
                    AppLogger.log("[ExplorerViewModel] Loaded file '\(filePath)' (\(response.size) bytes)")
                }
            } catch is CancellationError {
                AppLogger.log("[ExplorerViewModel] File load cancelled for '\(filePath)'")
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    AppLogger.log("[ExplorerViewModel] HTTP request cancelled for file '\(filePath)'")
                } else if self.selectedFile?.path == filePath {
                    self.error = error as? AppError ?? .unknown(underlying: error)
                    AppLogger.error(error, context: "Reading file '\(filePath)'")
                }
            }

            if self.selectedFile?.path == filePath {
                isLoadingFile = false
            }
        }

        await fileLoadingTask?.value
    }

    /// Close the file viewer
    func closeFile() {
        fileLoadingTask?.cancel()
        fileLoadingTask = nil
        selectedFile = nil
        fileContent = nil
    }

    /// Handle entry selection (file or directory)
    func selectEntry(_ entry: FileEntry) async {
        if entry.isDirectory {
            await navigateTo(path: entry.path)
        } else {
            await openFile(entry)
        }
    }

    // MARK: - Git Status Integration

    /// Merge git status information into file entries
    private func mergeGitStatus(entries: [FileEntry], gitFiles: [GitFileEntry]) -> [FileEntry] {
        // Create a lookup dictionary for git files
        let gitStatusByPath = Dictionary(
            gitFiles.map { ($0.path, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )

        return entries.map { entry in
            var modifiedEntry = entry
            // Check if this entry or any of its children have git status
            if let status = gitStatusByPath[entry.path] {
                modifiedEntry.gitStatus = status
            } else if entry.isDirectory {
                // Check if any git file is under this directory
                let pathPrefix = entry.path + "/"
                let hasModifiedChildren = gitFiles.contains { $0.path.hasPrefix(pathPrefix) }
                if hasModifiedChildren {
                    modifiedEntry.gitStatus = .modified  // Mark directory as having changes
                }
            }
            return modifiedEntry
        }
    }

    // MARK: - Search

    /// Update search query with debouncing
    /// Call this when the search text field changes
    func updateSearchQuery(_ query: String) {
        searchQuery = query
        searchError = nil

        // Cancel any pending debounce
        searchDebounceTask?.cancel()

        // If query is empty or too short, clear results immediately
        guard query.count >= minSearchLength else {
            clearSearchResults()
            return
        }

        // Debounce: wait 300ms before searching
        searchDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)  // 300ms
                guard !Task.isCancelled else { return }
                await self?.performSearch(query: query)
            } catch {
                // Task was cancelled - expected behavior
            }
        }
    }

    /// Perform the actual search request
    private func performSearch(query: String) async {
        // Cancel any in-flight search
        currentSearchTask?.cancel()

        let searchId = query  // Use query as identifier
        currentSearchTask = Task { [weak self] in
            guard let self = self else { return }

            self.isSearching = true

            do {
                try Task.checkCancellation()
                let results = try await self.fileRepository.searchFiles(query: query)
                try Task.checkCancellation()

                // Only update if query hasn't changed
                guard self.searchQuery == searchId else { return }
                self.searchResults = results
                self.searchError = nil
                AppLogger.log("[ExplorerViewModel] Search found \(results.count) results for '\(query)'")
            } catch is CancellationError {
                // Expected - user typed again
                AppLogger.log("[ExplorerViewModel] Search cancelled for '\(query)'")
            } catch {
                // Only show error if this is still the current query
                if self.searchQuery == searchId {
                    self.searchError = error as? AppError ?? .unknown(underlying: error)
                    self.searchResults = []
                    AppLogger.error(error, context: "Search for '\(query)'")
                }
            }

            // Only update loading state if this is still the current query
            if self.searchQuery == searchId {
                self.isSearching = false
            }
        }

        await currentSearchTask?.value
    }

    /// Clear search results (but keep query for UI)
    private func clearSearchResults() {
        currentSearchTask?.cancel()
        searchResults = []
        isSearching = false
        searchError = nil
    }

    /// Clear search completely and exit search mode
    func clearSearch() {
        searchDebounceTask?.cancel()
        currentSearchTask?.cancel()
        searchQuery = ""
        searchResults = []
        isSearching = false
        searchError = nil
    }

    /// Retry search after an error
    func retrySearch() {
        guard !searchQuery.isEmpty else { return }
        searchError = nil
        updateSearchQuery(searchQuery)
    }

    // MARK: - Cleanup

    /// Cancel all tasks - call when view disappears or on deinit
    func cancelAllTasks() {
        loadingTask?.cancel()
        fileLoadingTask?.cancel()
        searchDebounceTask?.cancel()
        currentSearchTask?.cancel()
    }
}
