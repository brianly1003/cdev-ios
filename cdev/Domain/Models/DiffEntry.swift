import Foundation

/// Git diff entry or file change
struct DiffEntry: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let filePath: String
    let diff: String
    let additions: Int
    let deletions: Int
    let isNewFile: Bool
    let changeType: FileChangeType?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        filePath: String,
        diff: String,
        additions: Int = 0,
        deletions: Int = 0,
        isNewFile: Bool = false,
        changeType: FileChangeType? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.filePath = filePath
        self.diff = diff
        self.additions = additions
        self.deletions = deletions
        self.isNewFile = isNewFile
        self.changeType = changeType
    }

    /// Create from git_diff event
    static func from(event: AgentEvent) -> DiffEntry? {
        guard case .gitDiff(let payload) = event.payload,
              let filePath = payload.file,
              let diff = payload.diff else {
            return nil
        }

        return DiffEntry(
            id: event.id,
            timestamp: event.timestamp,
            filePath: filePath,
            diff: diff,
            additions: payload.additions ?? 0,
            deletions: payload.deletions ?? 0,
            isNewFile: payload.isNew ?? false
        )
    }

    /// Create from file_changed event
    static func fromFileChanged(event: AgentEvent) -> DiffEntry? {
        guard case .fileChanged(let payload) = event.payload,
              let path = payload.path else {
            return nil
        }

        let change = payload.change ?? .modified

        return DiffEntry(
            id: event.id,
            timestamp: event.timestamp,
            filePath: path,
            diff: "",
            additions: 0,
            deletions: 0,
            isNewFile: change == .created,
            changeType: change
        )
    }

    /// Create from git status file entry
    static func from(gitFile: GitStatusResponse.GitFileStatus) -> DiffEntry {
        DiffEntry(
            id: gitFile.path,
            timestamp: Date(),
            filePath: gitFile.path,
            diff: "",
            additions: 0,
            deletions: 0,
            isNewFile: gitFile.isUntracked,
            changeType: gitFile.changeType
        )
    }

    /// File name without path
    var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    /// File extension
    var fileExtension: String {
        (filePath as NSString).pathExtension
    }

    /// Summary text (e.g., "+10 -5" or "Created")
    var summaryText: String {
        // If we have a change type but no diff, show the change type
        if let changeType = changeType, diff.isEmpty {
            return changeType.rawValue.capitalized
        }

        var parts: [String] = []
        if additions > 0 {
            parts.append("+\(additions)")
        }
        if deletions > 0 {
            parts.append("-\(deletions)")
        }
        return parts.isEmpty ? (changeType?.rawValue.capitalized ?? "No changes") : parts.joined(separator: " ")
    }

    /// Whether this is a file change without diff content
    var isFileChangeOnly: Bool {
        changeType != nil && diff.isEmpty
    }

    /// Parsed diff lines
    var lines: [DiffLine] {
        diff.components(separatedBy: .newlines).enumerated().map { index, line in
            DiffLine(lineNumber: index + 1, content: line)
        }
    }
}

/// Single line in a diff with proper line number tracking
struct DiffLine: Identifiable {
    let id = UUID()
    let oldLineNumber: Int?  // Line number in original file (nil for additions)
    let newLineNumber: Int?  // Line number in new file (nil for deletions)
    let content: String
    let type: DiffLineType

    init(oldLineNumber: Int?, newLineNumber: Int?, content: String, type: DiffLineType) {
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.content = content
        self.type = type
    }

    /// Legacy initializer for simple line numbering
    init(lineNumber: Int, content: String) {
        self.oldLineNumber = lineNumber
        self.newLineNumber = lineNumber
        self.content = content
        if content.isDiffAddition {
            self.type = .addition
        } else if content.isDiffDeletion {
            self.type = .deletion
        } else if content.isDiffHeader {
            self.type = .header
        } else {
            self.type = .context
        }
    }
}

enum DiffLineType {
    case addition
    case deletion
    case context
    case header
    case hunkHeader  // @@ -1,3 +1,4 @@ lines
}

/// Parsed diff with proper line numbers
struct ParsedDiff {
    let hunks: [DiffHunk]
    let lines: [DiffLine]

    /// Parse a unified diff string into structured data
    static func parse(_ diffString: String) -> ParsedDiff {
        var hunks: [DiffHunk] = []
        var allLines: [DiffLine] = []

        let rawLines = diffString.components(separatedBy: .newlines)
        var currentHunk: DiffHunk?
        var oldLine = 0
        var newLine = 0

        for line in rawLines {
            // Check for hunk header: @@ -oldStart,oldCount +newStart,newCount @@
            if line.hasPrefix("@@") {
                // Parse hunk header
                if let hunk = DiffHunk.parse(line) {
                    if let current = currentHunk {
                        hunks.append(current)
                    }
                    currentHunk = hunk
                    oldLine = hunk.oldStart
                    newLine = hunk.newStart

                    allLines.append(DiffLine(
                        oldLineNumber: nil,
                        newLineNumber: nil,
                        content: line,
                        type: .hunkHeader
                    ))
                }
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") ||
                      line.hasPrefix("---") || line.hasPrefix("+++") {
                // File header lines
                allLines.append(DiffLine(
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    content: line,
                    type: .header
                ))
            } else if line.hasPrefix("+") {
                // Addition
                allLines.append(DiffLine(
                    oldLineNumber: nil,
                    newLineNumber: newLine,
                    content: line,
                    type: .addition
                ))
                newLine += 1
            } else if line.hasPrefix("-") {
                // Deletion
                allLines.append(DiffLine(
                    oldLineNumber: oldLine,
                    newLineNumber: nil,
                    content: line,
                    type: .deletion
                ))
                oldLine += 1
            } else if line.hasPrefix(" ") || (!line.isEmpty && currentHunk != nil) {
                // Context line
                allLines.append(DiffLine(
                    oldLineNumber: oldLine,
                    newLineNumber: newLine,
                    content: line,
                    type: .context
                ))
                oldLine += 1
                newLine += 1
            } else if !line.isEmpty {
                // Other content (treat as context)
                allLines.append(DiffLine(
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    content: line,
                    type: .context
                ))
            }
        }

        if let current = currentHunk {
            hunks.append(current)
        }

        return ParsedDiff(hunks: hunks, lines: allLines)
    }
}

/// A hunk in a diff (a block of changes)
struct DiffHunk: Identifiable {
    let id = UUID()
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let header: String

    /// Parse @@ -oldStart,oldCount +newStart,newCount @@ header
    static func parse(_ line: String) -> DiffHunk? {
        // Pattern: @@ -1,3 +1,4 @@ optional context
        let pattern = #"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        func extractInt(_ range: NSRange) -> Int? {
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: line) else { return nil }
            return Int(line[swiftRange])
        }

        let oldStart = extractInt(match.range(at: 1)) ?? 1
        let oldCount = extractInt(match.range(at: 2)) ?? 1
        let newStart = extractInt(match.range(at: 3)) ?? 1
        let newCount = extractInt(match.range(at: 4)) ?? 1

        return DiffHunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            header: line
        )
    }
}
