import SwiftUI

/// Typography system following CleanerApp design guidelines
/// Uses SF Pro with Dynamic Type support
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

    // MARK: - Monospace (for code/logs)

    static let code: Font = .system(.body, design: .monospaced)
    static let codeSmall: Font = .system(.caption, design: .monospaced)
    static let codeLarge: Font = .system(.title3, design: .monospaced)

    // Terminal-optimized (compact)
    static let terminal: Font = .system(size: 12, weight: .regular, design: .monospaced)
    static let terminalSmall: Font = .system(size: 10, weight: .regular, design: .monospaced)
    static let terminalTimestamp: Font = .system(size: 9, weight: .regular, design: .monospaced)

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
