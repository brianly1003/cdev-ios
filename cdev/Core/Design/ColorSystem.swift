import SwiftUI

/// Pulse Terminal Design System - Unique color palette for cdev
/// A distinctive, developer-focused color system that cannot be easily mimicked
/// Brand colors derived from cdev logo (coral orange identity)
enum ColorSystem {
    // MARK: - Brand Colors (Matching Logo)

    /// Coral Orange - Primary brand color from logo
    static let brand = Color(hex: "#FF8C5A")
    static let brandDim = Color(hex: "#E67A4A")
    static let brandGlow = Color(hex: "#FF8C5A").opacity(0.4)

    // MARK: - Primary Palette (Unique to cdev)

    /// Electric Cyan - Accent color for actions, selection, links
    static let primary = Color(hex: "#00E5FF")
    static let primaryDim = Color(hex: "#00B8D4")
    static let primaryGlow = Color(hex: "#00E5FF").opacity(0.3)

    /// Phosphor Green - Success states, running, additions
    static let success = Color(hex: "#00FF88")
    static let successDim = Color(hex: "#00CC6A")
    static let successGlow = Color(hex: "#00FF88").opacity(0.3)

    /// Amber Alert - Warning, waiting, attention
    static let warning = Color(hex: "#FFB300")
    static let warningDim = Color(hex: "#FF8F00")
    static let warningGlow = Color(hex: "#FFB300").opacity(0.3)

    /// Crimson Error - Error states, destructive, deletions
    static let error = Color(hex: "#FF1744")
    static let errorDim = Color(hex: "#D50000")
    static let errorGlow = Color(hex: "#FF1744").opacity(0.3)

    /// Violet Accent - Secondary accent for special elements
    static let accent = Color(hex: "#7C4DFF")
    static let accentDim = Color(hex: "#651FFF")
    static let accentGlow = Color(hex: "#7C4DFF").opacity(0.3)

    /// Info Blue - Informational messages, neutral status
    static let info = Color(hex: "#58A6FF")
    static let infoDim = Color(hex: "#388BFD")
    static let infoGlow = Color(hex: "#58A6FF").opacity(0.3)

    // MARK: - Terminal Background Palette

    /// Deep dark - Primary terminal background
    static let terminalBg = Color(hex: "#0D1117")

    /// Elevated surfaces - Headers, status bars
    static let terminalBgElevated = Color(hex: "#161B22")

    /// Highlight - Hover states
    static let terminalBgHighlight = Color(hex: "#21262D")

    /// Selected - Active/selected items
    static let terminalBgSelected = Color(hex: "#30363D")

    // MARK: - Text Colors

    static let textPrimary = Color(hex: "#E6EDF3")
    static let textSecondary = Color(hex: "#8B949E")
    static let textTertiary = Color(hex: "#6E7681")
    static let textQuaternary = Color(hex: "#484F58")

    // MARK: - Semantic Status Colors

    enum Status {
        static let running = ColorSystem.success
        static let idle = Color(hex: "#6E7681")
        static let waiting = ColorSystem.warning
        static let error = ColorSystem.error
        static let stopped = Color(hex: "#484F58")

        /// Get glow color for a Claude state
        static func glow(for state: ClaudeState) -> Color {
            switch state {
            case .running: return ColorSystem.successGlow
            case .waiting: return ColorSystem.warningGlow
            case .error: return ColorSystem.errorGlow
            default: return .clear
            }
        }

        /// Get color for a Claude state
        static func color(for state: ClaudeState) -> Color {
            switch state {
            case .running: return running
            case .idle: return idle
            case .waiting: return waiting
            case .error: return error
            case .stopped: return stopped
            }
        }
    }

    // MARK: - Diff Colors (GitHub-inspired but enhanced)

    enum Diff {
        static let addedBg = Color(hex: "#0D4429")
        static let addedText = Color(hex: "#7EE787")
        static let addedGutter = Color(hex: "#238636")
        static let added = addedText  // Convenience alias

        static let removedBg = Color(hex: "#4C1D16")
        static let removedText = Color(hex: "#FF7B72")
        static let removedGutter = Color(hex: "#DA3633")
        static let removed = removedText  // Convenience alias

        static let contextText = Color(hex: "#8B949E")
        static let headerBg = Color(hex: "#161B22")
        static let headerText = Color(hex: "#58A6FF")
    }

    // MARK: - Tool Colors (for tool call UI)

    enum Tool {
        /// Tool name highlighting
        static let name = ColorSystem.primary
        /// Running tool indicator
        static let running = ColorSystem.info
        /// Completed tool indicator
        static let completed = ColorSystem.primary
        /// Error tool indicator
        static let error = ColorSystem.error
        /// Interrupted tool indicator
        static let interrupted = ColorSystem.warning
        /// Tool result text
        static let result = ColorSystem.textSecondary
        /// Tool result error
        static let resultError = ColorSystem.error
    }

    // MARK: - Log Stream Colors

    enum Log {
        static let stdout = Color(hex: "#E6EDF3")
        static let stderr = ColorSystem.error
        static let system = ColorSystem.primary
        static let user = ColorSystem.brand  // User's messages in brand color
        static let timestamp = Color(hex: "#484F58")
        static let json = ColorSystem.accent
    }

    // MARK: - Bash Command Colors (Claude Code CLI style)

    enum Bash {
        /// "!" prompt indicator - bright green like terminal prompt
        static let prompt = Color(hex: "#00FF88")
        /// Command text - bright white for visibility
        static let command = Color(hex: "#E6EDF3")
        /// Output text - slightly dimmed for distinction
        static let output = Color(hex: "#A8B2BC")
        /// Error output - red for stderr
        static let error = ColorSystem.error
    }

    // MARK: - Code Editor Colors (IDE-style theming)

    enum Editor {
        /// Editor backgrounds
        static let background = ColorSystem.terminalBg
        static let gutterBg = Color(hex: "#0A0E13")
        static let activeLineBg = Color(hex: "#1C2128")
        static let selectionBg = Color(hex: "#264F78").opacity(0.5)

        /// Line numbers
        static let lineNumber = ColorSystem.textQuaternary
        static let lineNumberActive = ColorSystem.textSecondary
        static let gutterBorder = Color(hex: "#21262D")

        /// Cursor and selection
        static let cursor = ColorSystem.primary
        static let matchHighlight = ColorSystem.primaryGlow

        /// Minimap (future)
        static let minimapBg = Color(hex: "#0A0E13")
        static let minimapSlider = Color(hex: "#30363D").opacity(0.6)

        /// Scroll decoration
        static let scrollbarBg = Color(hex: "#161B22")
        static let scrollbarThumb = Color(hex: "#484F58").opacity(0.5)
    }

    // MARK: - Syntax Highlighting (VSCode-inspired, theme-ready)

    enum Syntax {
        /// Keywords: if, else, func, class, struct, enum, import, return, etc.
        static let keyword = Color(hex: "#FF7B72")

        /// Types: String, Int, Bool, custom types
        static let type = Color(hex: "#79C0FF")

        /// Functions/methods
        static let function = Color(hex: "#D2A8FF")

        /// Variables and parameters
        static let variable = Color(hex: "#FFA657")

        /// String literals
        static let string = Color(hex: "#A5D6FF")

        /// Number literals
        static let number = Color(hex: "#79C0FF")

        /// Comments
        static let comment = Color(hex: "#8B949E")

        /// Operators: +, -, =, ==, etc.
        static let `operator` = Color(hex: "#FF7B72")

        /// Punctuation: (), {}, [], etc.
        static let punctuation = ColorSystem.textSecondary

        /// Preprocessor/directives: #import, @property
        static let preprocessor = Color(hex: "#FF7B72")

        /// Constants and enums
        static let constant = Color(hex: "#79C0FF")

        /// Property names
        static let property = Color(hex: "#7EE787")

        /// Decorators/attributes: @MainActor, @Published
        static let decorator = Color(hex: "#D2A8FF")

        /// Regular text (plain code)
        static let plain = ColorSystem.textPrimary

        /// Error squiggles
        static let errorUnderline = ColorSystem.error

        /// Warning squiggles
        static let warningUnderline = ColorSystem.warning
    }

    // MARK: - File Change Type Colors

    enum FileChange {
        static let created = ColorSystem.success
        static let modified = ColorSystem.warning
        static let deleted = ColorSystem.error
        static let renamed = ColorSystem.primary
        static let untracked = ColorSystem.success  // Same as created (green)
        static let added = ColorSystem.success      // Staged new file
        static let conflict = ColorSystem.error     // Merge conflicts

        static func color(for type: FileChangeType?) -> Color {
            guard let type = type else { return ColorSystem.textSecondary }
            switch type {
            case .created: return created
            case .modified: return modified
            case .deleted: return deleted
            case .renamed: return renamed
            }
        }

        /// Color for GitFileStatus
        static func color(for status: GitFileStatus) -> Color {
            switch status {
            case .modified: return modified
            case .added: return added
            case .deleted: return deleted
            case .renamed: return renamed
            case .untracked: return untracked
            case .unmerged: return conflict
            case .copied: return ColorSystem.info
            case .ignored: return ColorSystem.textQuaternary
            case .typeChanged: return modified
            }
        }
    }
}

// MARK: - Convenience Extensions

extension Color {
    /// Apply glow effect to a color
    func glow(radius: CGFloat = 4) -> some View {
        shadow(color: self.opacity(0.5), radius: radius)
    }
}
