import Foundation

/// Represents a file or directory in the repository
struct FileEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String           // Relative path from repo root
    let type: EntryType
    let size: Int?             // File size in bytes (nil for directories)
    let modified: Date?
    let childrenCount: Int?    // Number of items (directories only)
    var gitStatus: GitFileStatus?  // Modified/Added/Deleted indicator
    let matchScore: Double?    // Search relevance score (0.0-1.0)

    enum EntryType: String, Codable {
        case file
        case directory
    }

    // MARK: - Computed Properties

    var isDirectory: Bool { type == .directory }

    var fileExtension: String? {
        guard !isDirectory else { return nil }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? nil : ext.lowercased()
    }

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        return Icons.fileType(for: fileExtension ?? "")
    }

    var formattedSize: String? {
        guard let size = size else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var parentPath: String {
        guard !path.isEmpty else { return "" }
        let components = path.split(separator: "/")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    // MARK: - Init

    init(
        id: String = UUID().uuidString,
        name: String,
        path: String,
        type: EntryType,
        size: Int? = nil,
        modified: Date? = nil,
        childrenCount: Int? = nil,
        gitStatus: GitFileStatus? = nil,
        matchScore: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.type = type
        self.size = size
        self.modified = modified
        self.childrenCount = childrenCount
        self.gitStatus = gitStatus
        self.matchScore = matchScore
    }

    /// Create from API DTO (legacy)
    init(from dto: FileEntryDTO, parentPath: String) {
        let fullPath = parentPath.isEmpty ? dto.name : "\(parentPath)/\(dto.name)"
        self.id = fullPath
        self.name = dto.name
        self.path = fullPath
        self.type = dto.type == "directory" ? .directory : .file
        self.size = dto.size
        self.modified = dto.modified.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.childrenCount = dto.childrenCount
        self.gitStatus = nil
        self.matchScore = nil
    }

    /// Create from cdev-agent FileInfo DTO (file)
    init(from dto: FileInfoDTO) {
        self.id = dto.path
        self.name = dto.name
        self.path = dto.path
        self.type = .file
        self.size = dto.sizeBytes.map { Int($0) }
        self.modified = dto.modifiedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.childrenCount = nil
        self.gitStatus = nil
        self.matchScore = dto.matchScore
    }

    /// Create from cdev-agent DirectoryInfo DTO (directory)
    init(from dto: DirectoryInfoDTO) {
        // Handle empty path for root directory
        let dirPath = dto.path.isEmpty ? dto.name : dto.path
        self.id = dirPath.isEmpty ? dto.name : dirPath
        self.name = dto.name.isEmpty ? "." : dto.name
        self.path = dirPath
        self.type = .directory
        self.size = nil
        self.modified = dto.lastModified.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.childrenCount = dto.fileCount
        self.gitStatus = nil
        self.matchScore = nil
    }
}

// MARK: - API Response Types (Matches cdev-agent /api/repository/files/list)

/// API response for directory listing from cdev-agent
struct RepositoryFileListResponse: Codable {
    let directory: String?
    let files: [FileInfoDTO]?
    let directories: [DirectoryInfoDTO]?
    let totalFiles: Int?
    let totalDirectories: Int?
    let pagination: PaginationDTO?

    enum CodingKeys: String, CodingKey {
        case directory, files, directories, pagination
        case totalFiles = "total_files"
        case totalDirectories = "total_directories"
    }

    // Convenience accessors with defaults
    var safeFiles: [FileInfoDTO] { files ?? [] }
    var safeDirectories: [DirectoryInfoDTO] { directories ?? [] }
}

/// Pagination info from API
struct PaginationDTO: Codable {
    let limit: Int
    let offset: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case limit, offset
        case hasMore = "has_more"
    }
}

/// DTO for file info from cdev-agent API
struct FileInfoDTO: Codable {
    let path: String
    let name: String
    let directory: String?
    let ext: String?
    let sizeBytes: Int64?
    let modifiedAt: String?
    let isBinary: Bool?
    let isSensitive: Bool?
    let gitTracked: Bool?
    let gitIgnored: Bool?
    let isSymlink: Bool?
    let lineCount: Int?
    let indexedAt: String?
    let matchScore: Double?  // For search results

    enum CodingKeys: String, CodingKey {
        case path, name, directory
        case ext = "extension"
        case sizeBytes = "size_bytes"
        case modifiedAt = "modified_at"
        case isBinary = "is_binary"
        case isSensitive = "is_sensitive"
        case gitTracked = "git_tracked"
        case gitIgnored = "git_ignored"
        case isSymlink = "is_symlink"
        case lineCount = "line_count"
        case indexedAt = "indexed_at"
        case matchScore = "match_score"
    }
}

/// DTO for directory info from cdev-agent API
struct DirectoryInfoDTO: Codable {
    let path: String
    let name: String
    let fileCount: Int?
    let totalSizeBytes: Int64?
    let lastModified: String?

    enum CodingKeys: String, CodingKey {
        case path, name
        case fileCount = "file_count"
        case totalSizeBytes = "total_size_bytes"
        case lastModified = "last_modified"
    }
}

// MARK: - Search Response (Matches cdev-agent /api/repository/search)

/// API response for file search from cdev-agent
struct RepositorySearchResponse: Codable {
    let query: String
    let mode: String
    let results: [FileInfoDTO]
    let total: Int
    let elapsedMs: Int64

    enum CodingKeys: String, CodingKey {
        case query, mode, results, total
        case elapsedMs = "elapsed_ms"
    }
}

// MARK: - Legacy DTO (for backwards compatibility)

/// Legacy directory listing response
struct DirectoryListingResponse: Codable {
    let path: String
    let entries: [FileEntryDTO]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case path, entries
        case totalCount = "total_count"
    }
}

/// Legacy file entry DTO
struct FileEntryDTO: Codable {
    let name: String
    let type: String
    let size: Int?
    let modified: String?
    let childrenCount: Int?

    enum CodingKeys: String, CodingKey {
        case name, type, size, modified
        case childrenCount = "children_count"
    }
}

// MARK: - Mock Data Extension

extension FileEntry {
    /// Generate mock file system structure for testing
    static func mockFileSystem() -> [String: [FileEntry]] {
        var fileSystem: [String: [FileEntry]] = [:]

        // Root level
        fileSystem[""] = [
            FileEntry(name: "cdev", path: "cdev", type: .directory, childrenCount: 5),
            FileEntry(name: "cdev.xcodeproj", path: "cdev.xcodeproj", type: .directory, childrenCount: 2),
            FileEntry(name: "CLAUDE.md", path: "CLAUDE.md", type: .file, size: 4520, gitStatus: .modified),
            FileEntry(name: "README.md", path: "README.md", type: .file, size: 2340),
            FileEntry(name: ".gitignore", path: ".gitignore", type: .file, size: 156),
        ]

        // cdev directory
        fileSystem["cdev"] = [
            FileEntry(name: "App", path: "cdev/App", type: .directory, childrenCount: 3),
            FileEntry(name: "Core", path: "cdev/Core", type: .directory, childrenCount: 4),
            FileEntry(name: "Data", path: "cdev/Data", type: .directory, childrenCount: 3),
            FileEntry(name: "Domain", path: "cdev/Domain", type: .directory, childrenCount: 3),
            FileEntry(name: "Presentation", path: "cdev/Presentation", type: .directory, childrenCount: 3),
        ]

        // cdev/App
        fileSystem["cdev/App"] = [
            FileEntry(name: "AppState.swift", path: "cdev/App/AppState.swift", type: .file, size: 5280, gitStatus: .modified),
            FileEntry(name: "cdevApp.swift", path: "cdev/App/cdevApp.swift", type: .file, size: 1420),
            FileEntry(name: "DependencyContainer.swift", path: "cdev/App/DependencyContainer.swift", type: .file, size: 3890),
        ]

        // cdev/Core
        fileSystem["cdev/Core"] = [
            FileEntry(name: "Design", path: "cdev/Core/Design", type: .directory, childrenCount: 5),
            FileEntry(name: "Extensions", path: "cdev/Core/Extensions", type: .directory, childrenCount: 4),
            FileEntry(name: "Utilities", path: "cdev/Core/Utilities", type: .directory, childrenCount: 6),
            FileEntry(name: "Errors", path: "cdev/Core/Errors", type: .directory, childrenCount: 1),
        ]

        // cdev/Core/Design
        fileSystem["cdev/Core/Design"] = [
            FileEntry(name: "ColorSystem.swift", path: "cdev/Core/Design/ColorSystem.swift", type: .file, size: 8920),
            FileEntry(name: "Typography.swift", path: "cdev/Core/Design/Typography.swift", type: .file, size: 3450),
            FileEntry(name: "Icons.swift", path: "cdev/Core/Design/Icons.swift", type: .file, size: 4120),
            FileEntry(name: "Animations.swift", path: "cdev/Core/Design/Animations.swift", type: .file, size: 2890),
            FileEntry(name: "Gradients.swift", path: "cdev/Core/Design/Gradients.swift", type: .file, size: 1560),
        ]

        // cdev/Domain/Models
        fileSystem["cdev/Domain"] = [
            FileEntry(name: "Models", path: "cdev/Domain/Models", type: .directory, childrenCount: 8),
            FileEntry(name: "Interfaces", path: "cdev/Domain/Interfaces", type: .directory, childrenCount: 3),
            FileEntry(name: "UseCases", path: "cdev/Domain/UseCases", type: .directory, childrenCount: 4),
        ]

        fileSystem["cdev/Domain/Models"] = [
            FileEntry(name: "AgentEvent.swift", path: "cdev/Domain/Models/AgentEvent.swift", type: .file, size: 12450),
            FileEntry(name: "AgentCommand.swift", path: "cdev/Domain/Models/AgentCommand.swift", type: .file, size: 4230, gitStatus: .modified),
            FileEntry(name: "ConnectionInfo.swift", path: "cdev/Domain/Models/ConnectionInfo.swift", type: .file, size: 1890),
            FileEntry(name: "DiffEntry.swift", path: "cdev/Domain/Models/DiffEntry.swift", type: .file, size: 5670),
            FileEntry(name: "FileEntry.swift", path: "cdev/Domain/Models/FileEntry.swift", type: .file, size: 3200, gitStatus: .added),
            FileEntry(name: "LogEntry.swift", path: "cdev/Domain/Models/LogEntry.swift", type: .file, size: 7890),
            FileEntry(name: "Workspace.swift", path: "cdev/Domain/Models/Workspace.swift", type: .file, size: 2340),
            FileEntry(name: "ChatElement.swift", path: "cdev/Domain/Models/ChatElement.swift", type: .file, size: 6780),
        ]

        // cdev/Presentation
        fileSystem["cdev/Presentation"] = [
            FileEntry(name: "Common", path: "cdev/Presentation/Common", type: .directory, childrenCount: 1),
            FileEntry(name: "Navigation", path: "cdev/Presentation/Navigation", type: .directory, childrenCount: 1),
            FileEntry(name: "Screens", path: "cdev/Presentation/Screens", type: .directory, childrenCount: 6),
        ]

        fileSystem["cdev/Presentation/Screens"] = [
            FileEntry(name: "Dashboard", path: "cdev/Presentation/Screens/Dashboard", type: .directory, childrenCount: 2),
            FileEntry(name: "Explorer", path: "cdev/Presentation/Screens/Explorer", type: .directory, childrenCount: 4, gitStatus: .untracked),
            FileEntry(name: "LogViewer", path: "cdev/Presentation/Screens/LogViewer", type: .directory, childrenCount: 2),
            FileEntry(name: "Pairing", path: "cdev/Presentation/Screens/Pairing", type: .directory, childrenCount: 2),
            FileEntry(name: "Settings", path: "cdev/Presentation/Screens/Settings", type: .directory, childrenCount: 1),
            FileEntry(name: "SourceControl", path: "cdev/Presentation/Screens/SourceControl", type: .directory, childrenCount: 2),
        ]

        return fileSystem
    }

    /// Mock file content for testing
    static func mockFileContent(for path: String) -> String {
        switch path {
        case "CLAUDE.md":
            return """
            # CLAUDE.md

            This file provides guidance to Claude Code when working with code in this repository.

            ## Build & Development

            Open `cdev.xcodeproj` in Xcode 15+ and build for iOS 17.0+.

            ```bash
            # Open project
            open cdev.xcodeproj
            ```

            ## Architecture

            cdev-ios is an iOS client for cdev-agent following **Clean Architecture + MVVM** pattern.
            """

        case _ where path.hasSuffix(".swift"):
            return """
            import Foundation

            /// Sample Swift file content
            struct Sample {
                let id: String
                let name: String

                init(id: String, name: String) {
                    self.id = id
                    self.name = name
                }

                func process() async throws {
                    // Implementation
                }
            }
            """

        default:
            return "// File content for: \(path)"
        }
    }
}
