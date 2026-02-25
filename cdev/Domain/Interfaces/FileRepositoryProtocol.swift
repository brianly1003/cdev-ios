import Foundation

/// Protocol for file system operations
/// Supports both directory browsing and repository indexing via JSON-RPC
protocol FileRepositoryProtocol: AnyObject {
    // MARK: - Directory Operations

    /// List contents of a directory
    /// - Parameter path: Relative path from repository root (empty string for root)
    /// - Returns: Array of file entries sorted by type and name
    func listDirectory(path: String) async throws -> [FileEntry]

    /// Read file content
    /// - Parameter path: Relative path to the file
    /// - Returns: File content response with content and metadata
    func readFile(path: String) async throws -> FileContentResponse

    /// Search for files matching a query
    /// - Parameter query: Search query string (uses fuzzy matching)
    /// - Returns: Array of matching file entries with match scores
    func searchFiles(query: String) async throws -> [FileEntry]

    // MARK: - Repository Indexer

    /// Get repository index status
    /// - Returns: Index status including ready state, progress, and file counts
    func getIndexStatus() async throws -> RepositoryIndexStatusResult

    /// Get repository file tree
    /// - Parameters:
    ///   - path: Root path for tree (nil for repo root)
    ///   - depth: Maximum depth to traverse (default: 3)
    /// - Returns: Tree structure with nested directories and files
    func getFileTree(path: String?, depth: Int?) async throws -> RepositoryFilesTreeResult

    /// Get repository statistics
    /// - Returns: Statistics including file counts, sizes, and language breakdown
    func getStats() async throws -> RepositoryStatsResult

    /// Rebuild repository index
    /// - Parameter force: Force full rebuild even if index exists
    /// - Returns: Rebuild status (started, queued, or already indexing)
    func rebuildIndex(force: Bool) async throws -> RepositoryIndexRebuildResult

    // MARK: - Cache Management

    /// Invalidate cached data for a path
    func invalidateCache(path: String) async

    /// Clear all cached data
    func clearCache() async
}

/// Response for file content read operation
struct FileContentResponse {
    let path: String
    let content: String
    let encoding: String
    let size: Int
    let truncated: Bool
    /// Decoded binary data for base64-encoded files (images, PDFs, etc.)
    let imageData: Data?

    init(
        path: String,
        content: String,
        encoding: String = "utf-8",
        size: Int? = nil,
        truncated: Bool = false,
        imageData: Data? = nil
    ) {
        self.path = path
        self.content = content
        self.encoding = encoding
        self.size = size ?? content.utf8.count
        self.truncated = truncated
        self.imageData = imageData
    }
}
