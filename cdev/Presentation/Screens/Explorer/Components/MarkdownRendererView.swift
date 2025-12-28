import SwiftUI

/// Renders markdown content with proper formatting
/// Supports headings, code blocks, lists, bold, italic, links, blockquotes, and horizontal rules
struct MarkdownRendererView: View {
    let content: String

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                    renderBlock(block)
                }
            }
            .padding(layout.standardPadding)
        }
        .background(ColorSystem.Editor.background)
    }

    // MARK: - Block Types

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case codeBlock(language: String?, code: String)
        case unorderedList(items: [String])
        case orderedList(items: [String])
        case blockquote(text: String)
        case horizontalRule
        case table(headers: [String], rows: [[String]])
    }

    // MARK: - Parser

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line - skip
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Horizontal rule
            if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) && trimmed.count >= 3 {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // Heading
            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            // Code block
            if trimmed.hasPrefix("```") {
                let (codeBlock, newIndex) = parseCodeBlock(lines: lines, startIndex: index)
                blocks.append(codeBlock)
                index = newIndex
                continue
            }

            // Table
            if trimmed.hasPrefix("|") && index + 1 < lines.count {
                let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if nextLine.contains("---") && nextLine.hasPrefix("|") {
                    let (table, newIndex) = parseTable(lines: lines, startIndex: index)
                    if let table = table {
                        blocks.append(table)
                        index = newIndex
                        continue
                    }
                }
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                let (quote, newIndex) = parseBlockquote(lines: lines, startIndex: index)
                blocks.append(quote)
                index = newIndex
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                let (list, newIndex) = parseUnorderedList(lines: lines, startIndex: index)
                blocks.append(list)
                index = newIndex
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                let (list, newIndex) = parseOrderedList(lines: lines, startIndex: index)
                blocks.append(list)
                index = newIndex
                continue
            }

            // Default: paragraph
            let (paragraph, newIndex) = parseParagraph(lines: lines, startIndex: index)
            blocks.append(paragraph)
            index = newIndex
        }

        return blocks
    }

    private func parseHeading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        let hashCount = line.prefix(while: { $0 == "#" }).count
        guard hashCount <= 6 else { return nil }
        let text = String(line.dropFirst(hashCount)).trimmingCharacters(in: .whitespaces)
        return .heading(level: hashCount, text: text)
    }

    private func parseCodeBlock(lines: [String], startIndex: Int) -> (MarkdownBlock, Int) {
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let language = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)

        var code: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                break
            }
            code.append(line)
            index += 1
        }

        return (.codeBlock(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n")), index)
    }

    private func parseBlockquote(lines: [String], startIndex: Int) -> (MarkdownBlock, Int) {
        var quoteLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") {
                let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                quoteLines.append(content)
                index += 1
            } else if line.isEmpty && index + 1 < lines.count && lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                index += 1
            } else {
                break
            }
        }

        return (.blockquote(text: quoteLines.joined(separator: " ")), index)
    }

    private func isUnorderedListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
    }

    private func isOrderedListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let firstDot = trimmed.firstIndex(of: ".") else { return false }
        let prefix = trimmed[..<firstDot]
        return prefix.allSatisfy { $0.isNumber }
    }

    private func parseUnorderedList(lines: [String], startIndex: Int) -> (MarkdownBlock, Int) {
        var items: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isUnorderedListItem(trimmed) {
                let content = String(trimmed.dropFirst(2))
                items.append(content)
                index += 1
            } else if trimmed.isEmpty {
                index += 1
            } else {
                break
            }
        }

        return (.unorderedList(items: items), index)
    }

    private func parseOrderedList(lines: [String], startIndex: Int) -> (MarkdownBlock, Int) {
        var items: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isOrderedListItem(trimmed) {
                if let dotIndex = trimmed.firstIndex(of: ".") {
                    let content = String(trimmed[trimmed.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                    items.append(content)
                }
                index += 1
            } else if trimmed.isEmpty {
                index += 1
            } else {
                break
            }
        }

        return (.orderedList(items: items), index)
    }

    private func parseParagraph(lines: [String], startIndex: Int) -> (MarkdownBlock, Int) {
        var paragraphLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Stop at empty line or start of new block
            if trimmed.isEmpty ||
               trimmed.hasPrefix("#") ||
               trimmed.hasPrefix("```") ||
               trimmed.hasPrefix(">") ||
               isUnorderedListItem(trimmed) ||
               isOrderedListItem(trimmed) ||
               (trimmed.hasPrefix("|") && trimmed.contains("|")) {
                break
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        return (.paragraph(text: paragraphLines.joined(separator: " ")), index)
    }

    private func parseTable(lines: [String], startIndex: Int) -> (MarkdownBlock?, Int) {
        var index = startIndex

        // Parse header row
        let headerLine = lines[index].trimmingCharacters(in: .whitespaces)
        let headers = parseTableRow(headerLine)
        index += 1

        // Skip separator row
        if index < lines.count {
            index += 1
        }

        // Parse data rows
        var rows: [[String]] = []
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") && line.contains("|") {
                rows.append(parseTableRow(line))
                index += 1
            } else {
                break
            }
        }

        guard !headers.isEmpty else { return (nil, startIndex + 1) }
        return (.table(headers: headers, rows: rows), index)
    }

    private func parseTableRow(_ line: String) -> [String] {
        line.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Renderers

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            renderHeading(level: level, text: text)

        case .paragraph(let text):
            renderInlineText(text)
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)

        case .codeBlock(let language, let code):
            renderCodeBlock(language: language, code: code)

        case .unorderedList(let items):
            renderUnorderedList(items)

        case .orderedList(let items):
            renderOrderedList(items)

        case .blockquote(let text):
            renderBlockquote(text)

        case .horizontalRule:
            Rectangle()
                .fill(ColorSystem.Editor.gutterBorder)
                .frame(height: 1)
                .padding(.vertical, Spacing.sm)

        case .table(let headers, let rows):
            renderTable(headers: headers, rows: rows)
        }
    }

    @ViewBuilder
    private func renderHeading(level: Int, text: String) -> some View {
        let styling = headingStyling(for: level)

        VStack(alignment: .leading, spacing: 0) {
            renderInlineText(text)
                .font(styling.font)
                .foregroundStyle(ColorSystem.textPrimary)

            if level <= 2 {
                Rectangle()
                    .fill(ColorSystem.Editor.gutterBorder)
                    .frame(height: 1)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.bottom, styling.bottomPadding)
    }

    private func headingStyling(for level: Int) -> (font: Font, bottomPadding: CGFloat) {
        switch level {
        case 1: return (.system(size: 28, weight: .bold), Spacing.sm)
        case 2: return (.system(size: 24, weight: .bold), Spacing.xs)
        case 3: return (.system(size: 20, weight: .semibold), Spacing.xs)
        case 4: return (.system(size: 18, weight: .semibold), Spacing.xxs)
        case 5: return (.system(size: 16, weight: .semibold), Spacing.xxs)
        default: return (.system(size: 14, weight: .semibold), Spacing.xxs)
        }
    }

    @ViewBuilder
    private func renderCodeBlock(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language badge
            if let lang = language, !lang.isEmpty {
                Text(lang.uppercased())
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.bottom, Spacing.xs)
            }

            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                let highlightedCode = highlightCode(code, language: language)
                Text(highlightedCode)
                    .font(Typography.terminal)
                    .textSelection(.enabled)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorSystem.terminalBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ColorSystem.Editor.gutterBorder, lineWidth: 1)
            )
        }
    }

    private func highlightCode(_ code: String, language: String?) -> AttributedString {
        let lang = SyntaxHighlighter.detectLanguage(from: language)
        var result = AttributedString()

        for (index, line) in code.components(separatedBy: "\n").enumerated() {
            if index > 0 {
                result.append(AttributedString("\n"))
            }
            result.append(SyntaxHighlighter.highlight(line: line, language: lang))
        }

        return result
    }

    @ViewBuilder
    private func renderUnorderedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text("•")
                        .font(Typography.body)
                        .foregroundStyle(ColorSystem.primary)

                    renderInlineText(item)
                        .font(Typography.body)
                        .foregroundStyle(ColorSystem.textPrimary)
                }
            }
        }
        .padding(.leading, Spacing.sm)
    }

    @ViewBuilder
    private func renderOrderedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text("\(index + 1).")
                        .font(Typography.body)
                        .foregroundStyle(ColorSystem.primary)
                        .frame(minWidth: 20, alignment: .trailing)

                    renderInlineText(item)
                        .font(Typography.body)
                        .foregroundStyle(ColorSystem.textPrimary)
                }
            }
        }
        .padding(.leading, Spacing.sm)
    }

    @ViewBuilder
    private func renderBlockquote(_ text: String) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(ColorSystem.primary)
                .frame(width: 4)

            renderInlineText(text)
                .font(Typography.body)
                .italic()
                .foregroundStyle(ColorSystem.textSecondary)
                .padding(.leading, Spacing.sm)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private func renderTable(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                    Text(header)
                        .font(Typography.bodyBold)
                        .foregroundStyle(ColorSystem.textPrimary)
                        .padding(Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ColorSystem.terminalBgHighlight)

                    if index < headers.count - 1 {
                        Rectangle()
                            .fill(ColorSystem.Editor.gutterBorder)
                            .frame(width: 1)
                    }
                }
            }

            Rectangle()
                .fill(ColorSystem.Editor.gutterBorder)
                .frame(height: 1)

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                        Text(cell)
                            .font(Typography.body)
                            .foregroundStyle(ColorSystem.textPrimary)
                            .padding(Spacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if colIndex < row.count - 1 {
                            Rectangle()
                                .fill(ColorSystem.Editor.gutterBorder)
                                .frame(width: 1)
                        }
                    }
                }

                if rowIndex < rows.count - 1 {
                    Rectangle()
                        .fill(ColorSystem.Editor.gutterBorder)
                        .frame(height: 1)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ColorSystem.Editor.gutterBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Inline Text Rendering

    /// Render inline markdown: **bold**, *italic*, `code`, [links](url)
    private func renderInlineText(_ text: String) -> Text {
        var result = Text("")
        var remaining = text[...]

        while !remaining.isEmpty {
            // Check for inline code (use distinct color, no background as it breaks Text concatenation)
            if remaining.hasPrefix("`") {
                if let endIndex = remaining.dropFirst().firstIndex(of: "`") {
                    let code = String(remaining[remaining.index(after: remaining.startIndex)..<endIndex])
                    result = result + Text(code)
                        .font(Typography.terminal)
                        .foregroundColor(ColorSystem.primary)
                    remaining = remaining[remaining.index(after: endIndex)...]
                    continue
                }
            }

            // Check for bold (**text**)
            if remaining.hasPrefix("**") {
                let afterStars = remaining.dropFirst(2)
                if let endIndex = afterStars.range(of: "**")?.lowerBound {
                    let boldText = String(afterStars[..<endIndex])
                    result = result + Text(boldText).bold()
                    remaining = afterStars[afterStars.index(endIndex, offsetBy: 2)...]
                    continue
                }
            }

            // Check for italic (*text* or _text_)
            if remaining.hasPrefix("*") && !remaining.hasPrefix("**") {
                let afterStar = remaining.dropFirst()
                if let endIndex = afterStar.firstIndex(of: "*") {
                    let italicText = String(afterStar[..<endIndex])
                    result = result + Text(italicText).italic()
                    remaining = afterStar[afterStar.index(after: endIndex)...]
                    continue
                }
            }

            // Check for links [text](url)
            if remaining.hasPrefix("[") {
                if let closeBracket = remaining.firstIndex(of: "]"),
                   remaining.index(after: closeBracket) < remaining.endIndex,
                   remaining[remaining.index(after: closeBracket)] == "(" {
                    let linkText = String(remaining[remaining.index(after: remaining.startIndex)..<closeBracket])
                    let afterBracket = remaining[remaining.index(closeBracket, offsetBy: 2)...]
                    if let closeParen = afterBracket.firstIndex(of: ")") {
                        result = result + Text(linkText)
                            .foregroundColor(ColorSystem.primary)
                            .underline()
                        remaining = afterBracket[afterBracket.index(after: closeParen)...]
                        continue
                    }
                }
            }

            // Regular character
            result = result + Text(String(remaining.first!))
            remaining = remaining.dropFirst()
        }

        return result
    }
}

// MARK: - Preview

#Preview("Markdown Renderer") {
    MarkdownRendererView(content: """
    # JavaScript Best Practices

    ## Variables

    - Use `const` by default, `let` when reassignment is needed
    - Avoid `var` to prevent hoisting issues
    - Use descriptive, meaningful variable names

    ## Functions

    - Keep functions small and focused on a single task
    - Use arrow functions for callbacks
    - Use default parameters instead of short-circuiting

    ```javascript
    // Good
    function greet(name = 'Guest') {
        return `Hello, ${name}`;
    }

    // Avoid
    function greet(name) {
        name = name || 'Guest';
        return 'Hello, ' + name;
    }
    ```

    ## Error Handling

    - Always handle promises with `.catch()` or try/catch with async/await
    - Throw meaningful error messages
    - Don't swallow errors silently

    > This is a blockquote with important information.

    ## Code Style

    - Use consistent indentation (2 or 4 spaces)

    | Feature | Status | Notes |
    |---------|--------|-------|
    | Variables | Done | Use const/let |
    | Functions | Done | Keep small |
    | Errors | WIP | Add handling |

    ---

    *Italic text* and **bold text** and `inline code`.
    """)
}
