import Foundation

/// Protocol for file system operations
protocol FileRepositoryProtocol: AnyObject {
    /// List contents of a directory
    /// - Parameter path: Relative path from repository root (empty string for root)
    /// - Returns: Array of file entries sorted by type and name
    func listDirectory(path: String) async throws -> [FileEntry]

    /// Read file content
    /// - Parameter path: Relative path to the file
    /// - Returns: File content response with content and metadata
    func readFile(path: String) async throws -> FileContentResponse

    /// Search for files matching a query (future)
    /// - Parameter query: Search query string
    /// - Returns: Array of matching file entries
    func searchFiles(query: String) async throws -> [FileEntry]

    /// Invalidate cached data for a path
    func invalidateCache(path: String) async

    /// Clear all cached data
    func clearCache() async
}

/// Response for file content read operation
struct FileContentResponse: Codable {
    let path: String
    let content: String
    let encoding: String
    let size: Int
    let truncated: Bool

    init(
        path: String,
        content: String,
        encoding: String = "utf-8",
        size: Int? = nil,
        truncated: Bool = false
    ) {
        self.path = path
        self.content = content
        self.encoding = encoding
        self.size = size ?? content.utf8.count
        self.truncated = truncated
    }
}
