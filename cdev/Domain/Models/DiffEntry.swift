import Foundation

/// Git diff entry
struct DiffEntry: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let filePath: String
    let diff: String
    let additions: Int
    let deletions: Int
    let isNewFile: Bool

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        filePath: String,
        diff: String,
        additions: Int = 0,
        deletions: Int = 0,
        isNewFile: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.filePath = filePath
        self.diff = diff
        self.additions = additions
        self.deletions = deletions
        self.isNewFile = isNewFile
    }

    /// Create from agent event
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

    /// File name without path
    var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    /// File extension
    var fileExtension: String {
        (filePath as NSString).pathExtension
    }

    /// Summary text (e.g., "+10 -5")
    var summaryText: String {
        var parts: [String] = []
        if additions > 0 {
            parts.append("+\(additions)")
        }
        if deletions > 0 {
            parts.append("-\(deletions)")
        }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " ")
    }

    /// Parsed diff lines
    var lines: [DiffLine] {
        diff.components(separatedBy: .newlines).enumerated().map { index, line in
            DiffLine(lineNumber: index + 1, content: line)
        }
    }
}

/// Single line in a diff
struct DiffLine: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let content: String

    var type: DiffLineType {
        if content.isDiffAddition {
            return .addition
        } else if content.isDiffDeletion {
            return .deletion
        } else if content.isDiffHeader {
            return .header
        } else {
            return .context
        }
    }
}

enum DiffLineType {
    case addition
    case deletion
    case context
    case header
}
