import SwiftUI

/// Pulse Terminal Typography System
/// Optimized for terminal-first developer experience
enum Typography {
    // MARK: - Headings

    static let largeTitle: Font = .largeTitle.bold()
    static let title1: Font = .title.bold()
    static let title2: Font = .title2.bold()
    static let title3: Font = .title3.weight(.semibold)

    // MARK: - Body

    static let body: Font = .body
    static let bodyBold: Font = .body.weight(.semibold)
    static let callout: Font = .callout

    // MARK: - Small Text

    static let subheadline: Font = .subheadline
    static let footnote: Font = .footnote
    static let caption1: Font = .caption
    static let caption2: Font = .caption2

    // MARK: - Terminal Typography (Core to Pulse Terminal identity)

    /// Large terminal - expanded/detail views
    static let terminalLarge: Font = .system(size: 14, weight: .regular, design: .monospaced)

    /// Standard terminal - main log display
    static let terminal: Font = .system(size: 12, weight: .regular, design: .monospaced)

    /// Small terminal - compact views
    static let terminalSmall: Font = .system(size: 10, weight: .regular, design: .monospaced)

    /// Micro terminal - timestamps, line numbers
    static let terminalTimestamp: Font = .system(size: 9, weight: .regular, design: .monospaced)

    /// Line numbers - lighter weight for visual hierarchy
    static let lineNumber: Font = .system(size: 10, weight: .light, design: .monospaced)

    /// Diff headers
    static let diffHeader: Font = .system(size: 11, weight: .medium, design: .monospaced)

    // MARK: - Code Typography

    static let code: Font = .system(.body, design: .monospaced)
    static let codeSmall: Font = .system(.caption, design: .monospaced)
    static let codeLarge: Font = .system(.title3, design: .monospaced)

    // MARK: - UI Typography

    /// Status labels - compact, readable
    static let statusLabel: Font = .system(size: 10, weight: .semibold, design: .rounded)

    /// Badges - bold, small
    static let badge: Font = .system(size: 9, weight: .bold, design: .rounded)

    /// Tab labels
    static let tabLabel: Font = .system(size: 11, weight: .medium)

    // MARK: - Interaction Typography

    /// Banner titles
    static let bannerTitle: Font = .system(size: 13, weight: .semibold)

    /// Banner body text
    static let bannerBody: Font = .system(size: 12, weight: .regular)

    /// Button labels
    static let buttonLabel: Font = .system(size: 12, weight: .semibold)

    /// Input fields
    static let inputField: Font = .system(size: 13, weight: .regular)

    // MARK: - Rounded (for numbers/stats)

    static let statLarge: Font = .system(.largeTitle, design: .rounded).bold()
    static let statMedium: Font = .system(.title2, design: .rounded).bold()
    static let statSmall: Font = .system(.headline, design: .rounded).bold()
}

// MARK: - View Extension

extension View {
    func typography(_ font: Font) -> some View {
        self.font(font)
    }
}
