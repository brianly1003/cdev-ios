import Foundation

/// Represents a file or directory in the repository
struct FileEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String           // Relative path from repo root
    let type: EntryType
    let size: Int?             // File size in bytes (nil for directories)
    let modified: Date?
    let childrenCount: Int?    // Number of items (directories only) - legacy
    var gitStatus: GitFileStatus?  // Modified/Added/Deleted indicator
    let matchScore: Double?    // Search relevance score (0.0-1.0)

    // Enhanced directory metadata (from updated API)
    let folderCount: Int?          // Number of subdirectories (direct children)
    let fileCount: Int?            // Number of files (recursive)
    let totalSizeDisplay: String?  // Pre-formatted size like "38.8 KB"
    let modifiedDisplay: String?   // Pre-formatted like "2 hours ago"

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
        // Use .binary (1024 base) to match server calculation
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .binary)
    }

    var parentPath: String {
        guard !path.isEmpty else { return "" }
        let components = path.split(separator: "/")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    /// Formatted count summary for directories: "3 folders, 4 files • 2 days ago"
    /// Size is displayed separately on the right side of the row
    var directoryCountSummary: String? {
        guard isDirectory else { return nil }

        var parts: [String] = []

        // Folder count
        if let folders = folderCount, folders > 0 {
            parts.append("\(folders) folder\(folders == 1 ? "" : "s")")
        }

        // File count
        if let files = fileCount, files > 0 {
            parts.append("\(files) file\(files == 1 ? "" : "s")")
        }

        // Fallback to legacy childrenCount if new fields not available
        if parts.isEmpty, let count = childrenCount, count > 0 {
            parts.append("\(count) item\(count == 1 ? "" : "s")")
        }

        guard !parts.isEmpty else { return nil }

        var summary = parts.joined(separator: ", ")

        // Add modified time if available
        if let timeStr = modifiedDisplay {
            summary += " • \(timeStr)"
        }

        return summary
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
        matchScore: Double? = nil,
        folderCount: Int? = nil,
        fileCount: Int? = nil,
        totalSizeDisplay: String? = nil,
        modifiedDisplay: String? = nil
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
        self.folderCount = folderCount
        self.fileCount = fileCount
        self.totalSizeDisplay = totalSizeDisplay
        self.modifiedDisplay = modifiedDisplay
    }

    // MARK: - JSON-RPC Response Initializers

    /// Create from JSON-RPC RepositoryFileInfo (file)
    init(from info: RepositoryFileInfo) {
        self.id = info.path
        self.name = info.name
        self.path = info.path
        self.type = .file
        self.size = info.sizeBytes.map { Int($0) }
        self.modified = info.modifiedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.childrenCount = nil
        self.gitStatus = nil
        self.matchScore = nil
        self.folderCount = nil
        self.fileCount = nil
        self.totalSizeDisplay = nil
        self.modifiedDisplay = nil
    }

    /// Create from JSON-RPC RepositoryDirectoryInfo (directory)
    init(from info: RepositoryDirectoryInfo) {
        // Handle empty path for root directory
        let dirPath = info.path.isEmpty ? info.name : info.path
        self.id = dirPath.isEmpty ? info.name : dirPath
        self.name = info.name.isEmpty ? "." : info.name
        self.path = dirPath
        self.type = .directory
        self.size = info.totalSizeBytes.map { Int($0) }
        self.modified = info.lastModified.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.childrenCount = nil
        self.gitStatus = nil
        self.matchScore = nil
        // Enhanced directory metadata
        self.folderCount = info.folderCount
        self.fileCount = info.fileCount
        self.totalSizeDisplay = info.totalSizeDisplay
        self.modifiedDisplay = info.modifiedDisplay
    }

    /// Create from JSON-RPC RepositorySearchFile (search result)
    init(from file: RepositorySearchFile) {
        self.id = file.path
        self.name = file.name
        self.path = file.path
        self.type = .file
        self.size = file.sizeBytes.map { Int($0) }
        self.modified = file.modifiedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.childrenCount = nil
        self.gitStatus = nil
        self.matchScore = file.matchScore
        self.folderCount = nil
        self.fileCount = nil
        self.totalSizeDisplay = nil
        self.modifiedDisplay = nil
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
