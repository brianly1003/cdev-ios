import Foundation

/// Repository for file system operations
/// Uses JSON-RPC over WebSocket for API calls with caching support
final class FileRepository: FileRepositoryProtocol {
    // MARK: - Dependencies

    private let webSocketService: WebSocketServiceProtocol
    private let httpService: HTTPServiceProtocol  // Fallback for file content
    private let cache: FileCache
    private let useMockData: Bool

    // MARK: - Mock Data

    private lazy var mockFileSystem = FileEntry.mockFileSystem()

    // MARK: - Init

    init(
        webSocketService: WebSocketServiceProtocol,
        httpService: HTTPServiceProtocol,
        cache: FileCache,
        useMockData: Bool = false
    ) {
        self.webSocketService = webSocketService
        self.httpService = httpService
        self.cache = cache
        self.useMockData = useMockData
    }

    // MARK: - JSON-RPC Client

    /// Get the JSON-RPC client from WebSocketService
    private var rpcClient: JSONRPCClient? {
        guard let wsService = webSocketService as? WebSocketService else {
            return nil
        }
        return wsService.getJSONRPCClient()
    }

    /// Check if WebSocket is connected
    private var isConnected: Bool {
        webSocketService.isConnected
    }

    /// Get current workspace ID from WorkspaceStore
    @MainActor
    private var currentWorkspaceId: String? {
        WorkspaceStore.shared.activeWorkspace?.remoteWorkspaceId
    }

    // MARK: - FileRepositoryProtocol

    func listDirectory(path: String) async throws -> [FileEntry] {
        // Check cache first
        if let cached = await cache.getDirectory(path: path) {
            return cached
        }

        // Fetch entries
        let entries: [FileEntry]
        if useMockData {
            entries = try await fetchMockDirectory(path: path)
        } else {
            entries = try await fetchRemoteDirectory(path: path)
        }

        // Sort: directories first, then alphabetically
        let sortedEntries = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        // Cache and return
        await cache.cacheDirectory(path: path, entries: sortedEntries)
        return sortedEntries
    }

    func readFile(path: String) async throws -> FileContentResponse {
        // Binary files (images, etc.) are never cached — the cache stores plain String content
        // and would lose the imageData, causing the raw base64 string to be shown as text.
        let isBinary = Self.isBinaryPath(path)

        // Check cache first (text files only)
        if !isBinary, let cachedContent = await cache.getContent(path: path) {
            return FileContentResponse(path: path, content: cachedContent)
        }

        // Fetch content
        let response: FileContentResponse
        if useMockData {
            response = try await fetchMockContent(path: path)
        } else {
            response = try await fetchRemoteContent(path: path)
        }

        // Cache only text files that aren't truncated
        if !isBinary && !response.truncated {
            await cache.cacheContent(path: path, content: response.content)
        }

        return response
    }

    /// Returns true for file extensions the server returns as base64-encoded binary.
    private static func isBinaryPath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "gif", "bmp", "ico", "tiff",
                "pdf", "zip", "tar", "gz", "rar", "7z",
                "ttf", "otf", "woff", "woff2"].contains(ext)
    }

    func searchFiles(query: String) async throws -> [FileEntry] {
        if useMockData {
            // Search in mock data
            let lowercasedQuery = query.lowercased()
            var results: [FileEntry] = []

            for (_, entries) in mockFileSystem {
                for entry in entries where entry.name.lowercased().contains(lowercasedQuery) {
                    results.append(entry)
                }
            }

            return results.sorted { $0.name < $1.name }
        } else {
            // Use real API
            return try await fetchRemoteSearch(query: query)
        }
    }

    func invalidateCache(path: String) async {
        await cache.invalidateDirectory(path: path)
        await cache.invalidateContent(path: path)
    }

    func clearCache() async {
        await cache.clear()
    }

    // MARK: - Repository Indexer Operations

    func getIndexStatus() async throws -> RepositoryIndexStatusResult {
        guard let rpcClient = rpcClient else {
            throw AppError.webSocketDisconnected
        }

        let params = RepositoryIndexStatusParams()
        return try await rpcClient.request(
            method: JSONRPCMethod.repositoryIndexStatus,
            params: params,
            timeout: nil
        )
    }

    func getFileTree(path: String?, depth: Int?) async throws -> RepositoryFilesTreeResult {
        guard let rpcClient = rpcClient else {
            throw AppError.webSocketDisconnected
        }

        let params = RepositoryFilesTreeParams(
            workspaceId: nil,
            path: path,
            depth: depth ?? 3
        )

        return try await rpcClient.request(
            method: JSONRPCMethod.repositoryFilesTree,
            params: params,
            timeout: nil
        )
    }

    func getStats() async throws -> RepositoryStatsResult {
        guard let rpcClient = rpcClient else {
            throw AppError.webSocketDisconnected
        }

        let params = RepositoryStatsParams()
        return try await rpcClient.request(
            method: JSONRPCMethod.repositoryStats,
            params: params,
            timeout: nil
        )
    }

    func rebuildIndex(force: Bool) async throws -> RepositoryIndexRebuildResult {
        guard let rpcClient = rpcClient else {
            throw AppError.webSocketDisconnected
        }

        let params = RepositoryIndexRebuildParams(
            workspaceId: nil,
            force: force
        )

        return try await rpcClient.request(
            method: JSONRPCMethod.repositoryIndexRebuild,
            params: params,
            timeout: nil
        )
    }

    // MARK: - Mock Data Fetching

    private func fetchMockDirectory(path: String) async throws -> [FileEntry] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms

        guard let entries = mockFileSystem[path] else {
            // Return empty array for unknown paths
            AppLogger.log("[FileRepository] Mock: No entries for path '\(path)', returning empty")
            return []
        }

        AppLogger.log("[FileRepository] Mock: Loaded \(entries.count) entries for '\(path)'")
        return entries
    }

    private func fetchMockContent(path: String) async throws -> FileContentResponse {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 150_000_000)  // 150ms

        let content = FileEntry.mockFileContent(for: path)
        AppLogger.log("[FileRepository] Mock: Loaded content for '\(path)' (\(content.utf8.count) bytes)")

        return FileContentResponse(
            path: path,
            content: content,
            encoding: "utf-8",
            size: content.utf8.count,
            truncated: false
        )
    }

    // MARK: - Remote API Fetching (JSON-RPC)

    private func fetchRemoteDirectory(path: String) async throws -> [FileEntry] {
        guard let rpcClient = rpcClient else {
            throw AppError.webSocketDisconnected
        }

        // Get workspace ID from active workspace
        let workspaceId = await MainActor.run { self.currentWorkspaceId }
        guard let wsId = workspaceId else {
            AppLogger.log("[FileRepository] No workspace ID available for file listing", type: .warning)
            throw AppError.commandFailed(reason: "No workspace selected")
        }

        // Build params for workspace/files/list
        let params = WorkspaceFilesListParams(
            workspaceId: wsId,
            directory: path.isEmpty ? nil : path,
            limit: 500
        )

        let response: RepositoryFilesListResult = try await rpcClient.request(
            method: JSONRPCMethod.workspaceFilesList,
            params: params,
            timeout: nil
        )

        // Combine directories and files into FileEntry array
        var entries: [FileEntry] = []

        // Add directories first (using safe accessor)
        for dirInfo in response.safeDirectories {
            entries.append(FileEntry(from: dirInfo))
        }

        // Add files (using safe accessor)
        for fileInfo in response.safeFiles {
            entries.append(FileEntry(from: fileInfo))
        }

        AppLogger.log("[FileRepository] Loaded \(response.safeDirectories.count) dirs, \(response.safeFiles.count) files for '\(path)'")
        return entries
    }

    private func fetchRemoteContent(path: String) async throws -> FileContentResponse {
        guard let rpcClient = rpcClient else {
            throw AppError.webSocketDisconnected
        }

        // Get workspace ID from active workspace
        let workspaceId = await MainActor.run { self.currentWorkspaceId }
        guard let wsId = workspaceId else {
            AppLogger.log("[FileRepository] No workspace ID available for file content", type: .warning)
            throw AppError.commandFailed(reason: "No workspace selected")
        }

        let params = WorkspaceFileGetParams(workspaceId: wsId, path: path)
        let result: FileGetResult = try await rpcClient.request(
            method: JSONRPCMethod.workspaceFileGet,
            params: params,
            timeout: nil
        )

        // Decode base64-encoded binary content (images, PDFs, etc.)
        var imageData: Data? = nil
        if result.encoding == "base64", let b64 = result.content {
            imageData = Data(base64Encoded: b64)
        }

        return FileContentResponse(
            path: result.path ?? path,
            content: result.content ?? "",
            encoding: result.encoding ?? "utf-8",
            size: result.size,
            truncated: result.truncated ?? false,
            imageData: imageData
        )
    }

    // MARK: - Remote Search (JSON-RPC)

    private func fetchRemoteSearch(query: String) async throws -> [FileEntry] {
        guard let rpcClient = rpcClient else {
            throw AppError.webSocketDisconnected
        }

        let params = RepositorySearchParams(
            query: query,
            workspaceId: nil,  // Uses current workspace context
            mode: "fuzzy",
            limit: 50,
            excludeBinaries: true
        )

        let response: RepositorySearchResult = try await rpcClient.request(
            method: JSONRPCMethod.repositorySearch,
            params: params,
            timeout: nil
        )

        return (response.results ?? []).map { FileEntry(from: $0) }
    }
}

// MARK: - AppError Extension

extension AppError {
    static var notImplemented: AppError {
        .commandFailed(reason: "Feature not yet implemented")
    }
}
