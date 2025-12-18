import SwiftUI

/// Pulse Terminal Icon System
/// Consistent icon vocabulary for the cdev app
enum Icons {
    // MARK: - Status Icons

    static let pulse = "circle.fill"
    static let running = "play.circle.fill"
    static let waiting = "pause.circle.fill"
    static let stopped = "stop.circle.fill"
    static let error = "exclamationmark.circle.fill"
    static let idle = "moon.circle.fill"

    // MARK: - Connection Icons

    static let connected = "wifi"
    static let disconnected = "wifi.slash"
    static let connecting = "wifi.exclamationmark"

    // MARK: - Tab Icons

    static let terminal = "terminal.fill"
    static let changes = "doc.badge.plus"
    static let files = "folder.fill"
    static let search = "magnifyingglass"

    // MARK: - Action Icons

    static let send = "arrow.up.circle.fill"
    static let stop = "stop.fill"
    static let approve = "checkmark.circle.fill"
    static let deny = "xmark.circle.fill"
    static let expand = "arrow.up.left.and.arrow.down.right"
    static let collapse = "arrow.down.right.and.arrow.up.left"
    static let copy = "doc.on.doc"
    static let share = "square.and.arrow.up"
    static let refresh = "arrow.clockwise"
    static let clear = "trash"
    static let settings = "gearshape"

    // MARK: - File Change Icons

    static let fileCreated = "plus.circle.fill"
    static let fileModified = "pencil.circle.fill"
    static let fileDeleted = "minus.circle.fill"
    static let fileRenamed = "arrow.right.circle.fill"

    /// Get icon for file change type
    static func fileChange(for type: FileChangeType?) -> String {
        guard let type = type else { return "doc" }
        switch type {
        case .created: return fileCreated
        case .modified: return fileModified
        case .deleted: return fileDeleted
        case .renamed: return fileRenamed
        }
    }

    // MARK: - File Type Icons

    /// Get icon for file extension
    static func fileType(for ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "t.square"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "rs": return "r.circle"
        case "md": return "doc.plaintext"
        case "json": return "curlybraces.square"
        case "yaml", "yml": return "list.bullet"
        case "css", "scss": return "paintbrush"
        case "html": return "globe"
        case "rb": return "diamond"
        case "java", "kt": return "cup.and.saucer"
        case "c", "cpp", "h", "hpp": return "c.circle"
        case "sh", "bash", "zsh": return "terminal"
        case "sql": return "cylinder"
        case "xml": return "angle.brackets"
        default: return "doc"
        }
    }

    // MARK: - Claude State Icons

    static func claudeState(for state: ClaudeState) -> String {
        switch state {
        case .running: return running
        case .idle: return idle
        case .waiting: return waiting
        case .error: return error
        case .stopped: return stopped
        }
    }
}
