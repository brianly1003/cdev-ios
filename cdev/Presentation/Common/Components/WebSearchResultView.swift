import SwiftUI

// MARK: - Web Search Link Model

/// Represents a single link from web search results
struct WebSearchLink: Identifiable, Equatable {
    let id: String
    let title: String
    let url: String

    /// Extract domain from URL for display
    var domain: String {
        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return url
        }
        // Remove www. prefix
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Favicon URL using Google's favicon service
    var faviconURL: URL? {
        guard let urlObj = URL(string: url),
              let scheme = urlObj.scheme,
              let host = urlObj.host else {
            return nil
        }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(scheme)://\(host)&sz=32")
    }
}

// MARK: - Parsed Web Search Result

/// Parsed web search result containing query, links, and summary
struct ParsedWebSearchResult: Equatable {
    let query: String
    let links: [WebSearchLink]
    let summary: String

    /// Check if this is a valid web search result
    var isValid: Bool {
        !query.isEmpty || !links.isEmpty
    }
}

// MARK: - Web Search Parser

/// Utility to parse web search results from tool result content
enum WebSearchParser {
    /// Parse web search result from raw content string
    /// Format: "Web search results for query: "..."\n\nLinks: [{...}]\n\n[summary]"
    static func parse(_ content: String) -> ParsedWebSearchResult? {
        var query = ""
        var links: [WebSearchLink] = []
        var summary = ""

        // Extract query from "Web search results for query: "...""
        if let queryMatch = content.range(of: #"Web search results for query: "([^"]+)""#, options: .regularExpression) {
            let queryLine = String(content[queryMatch])
            if let startQuote = queryLine.firstIndex(of: "\""),
               let endQuote = queryLine.lastIndex(of: "\""),
               startQuote < endQuote {
                query = String(queryLine[queryLine.index(after: startQuote)..<endQuote])
            }
        }

        // Extract Links JSON array
        if let linksStart = content.range(of: "Links: ["),
           let linksEnd = content.range(of: "]", range: linksStart.upperBound..<content.endIndex) {
            let jsonString = "[" + String(content[linksStart.upperBound..<linksEnd.upperBound])
            if let jsonData = jsonString.data(using: .utf8),
               let parsedLinks = try? JSONDecoder().decode([LinkDTO].self, from: jsonData) {
                links = parsedLinks.enumerated().map { index, dto in
                    WebSearchLink(id: "\(index)-\(dto.url)", title: dto.title, url: dto.url)
                }
            }

            // Extract summary (everything after the Links array)
            let afterLinks = String(content[linksEnd.upperBound...])
            summary = afterLinks.trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove the REMINDER line if present
            if let reminderRange = summary.range(of: "REMINDER:", options: .caseInsensitive) {
                summary = String(summary[..<reminderRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !query.isEmpty || !links.isEmpty else {
            return nil
        }

        return ParsedWebSearchResult(query: query, links: links, summary: summary)
    }

    /// DTO for decoding links from JSON
    private struct LinkDTO: Decodable {
        let title: String
        let url: String
    }
}

// MARK: - Web Search Result View

/// Sophisticated view for displaying web search results
/// Shows query, links grid, and expandable summary
struct WebSearchResultView: View {
    let result: ParsedWebSearchResult
    var searchText: String = ""
    @State private var isExpanded = false
    @State private var showAllLinks = false

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// How many links to show in collapsed state
    private let collapsedLinkCount = 4

    /// Links to display based on expansion state
    private var displayedLinks: [WebSearchLink] {
        showAllLinks ? result.links : Array(result.links.prefix(collapsedLinkCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header with search icon and query
            headerView

            // Links section
            if !result.links.isEmpty {
                linksSection
            }

            // Summary section (expandable)
            if !result.summary.isEmpty {
                summarySection
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            // Tree connector
            Text("⎿")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textQuaternary)

            // Search icon with query
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ColorSystem.primary)

                if searchText.isEmpty {
                    Text("Web search: \"\(result.query)\"")
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textSecondary)
                        .lineLimit(2)
                } else {
                    HighlightedText("Web search: \"\(result.query)\"", highlighting: searchText)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            // Link count badge
            Text("\(result.links.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(ColorSystem.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(ColorSystem.primary.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    // MARK: - Links Section

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Links in horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(displayedLinks) { link in
                        WebSearchLinkCard(link: link, searchText: searchText)
                    }

                    // "More" button if there are hidden links
                    if !showAllLinks && result.links.count > collapsedLinkCount {
                        moreLinksButton
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(.leading, Spacing.md)

            // "Show less" button when expanded
            if showAllLinks && result.links.count > collapsedLinkCount {
                Button {
                    withAnimation(Animations.stateChange) {
                        showAllLinks = false
                    }
                    Haptics.selection()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Show less")
                            .font(Typography.terminalSmall)
                    }
                    .foregroundStyle(ColorSystem.textTertiary)
                }
                .padding(.leading, Spacing.md)
            }
        }
    }

    private var moreLinksButton: some View {
        Button {
            withAnimation(Animations.stateChange) {
                showAllLinks = true
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 4) {
                Text("+\(result.links.count - collapsedLinkCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorSystem.primary)

                Text("more")
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .stroke(ColorSystem.primary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Toggle for summary
            Button {
                withAnimation(Animations.stateChange) {
                    isExpanded.toggle()
                }
                Haptics.selection()
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(ColorSystem.textQuaternary)

                    Text(isExpanded ? "Hide summary" : "Show summary")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                }
                .padding(.leading, Spacing.md)
            }
            .buttonStyle(.plain)

            // Expanded summary
            if isExpanded {
                summaryContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchText.isEmpty {
                Text(result.summary)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HighlightedText(result.summary, highlighting: searchText)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.sm)
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        .padding(.leading, Spacing.md)
    }
}

// MARK: - Web Search Link Card

/// Individual link card with favicon, title, and domain
struct WebSearchLinkCard: View {
    let link: WebSearchLink
    var searchText: String = ""

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: link.url) {
                openURL(url)
                Haptics.light()
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                // Favicon
                faviconView
                    .padding(.top, 2)

                // Title and domain
                VStack(alignment: .leading, spacing: 3) {
                    // Title (single line for compact display)
                    if searchText.isEmpty {
                        Text(link.title)
                            .font(Typography.terminalSmall)
                            .fontWeight(.medium)
                            .foregroundStyle(ColorSystem.textPrimary)
                            .lineLimit(1)
                    } else {
                        HighlightedText(link.title, highlighting: searchText)
                            .font(Typography.terminalSmall)
                            .fontWeight(.medium)
                            .foregroundStyle(ColorSystem.textPrimary)
                            .lineLimit(1)
                    }

                    // Domain with link icon
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 8))
                        Text(link.domain)
                            .font(Typography.badge)
                            .lineLimit(1)
                    }
                    .foregroundStyle(ColorSystem.primary.opacity(0.8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 160, alignment: .topLeading)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .stroke(ColorSystem.textQuaternary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURL = link.faviconURL {
            AsyncImage(url: faviconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                case .failure, .empty:
                    fallbackIcon
                @unknown default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "globe")
            .font(.system(size: 12))
            .foregroundStyle(ColorSystem.textTertiary)
            .frame(width: 16, height: 16)
    }
}

// MARK: - Preview

#Preview {
    let sampleResult = ParsedWebSearchResult(
        query: "iOS streaming API results pagination infinite scroll best practices 2024",
        links: [
            WebSearchLink(id: "1", title: "Infinite Scroll vs. Pagination: Which Is the Better Option for UX in 2024?", url: "https://designerly.com/infinite-scroll/"),
            WebSearchLink(id: "2", title: "Pagination and Infinite Scrolling in iOS: Complete SwiftUI Guide", url: "https://ravi6997.medium.com/pagination-and-infinite-scrolling-in-ios"),
            WebSearchLink(id: "3", title: "Infinite scroll with InstantSearch iOS | Algolia", url: "https://www.algolia.com/doc/guides/building-search-ui/ui-and-ux-patterns/infinite-scroll/ios/"),
            WebSearchLink(id: "4", title: "Implementing Infinite Scroll Pagination with JavaScript", url: "https://blockchain.oodles.io/dev-blog/Infinite-Scroll-Pagination-With-JavaScript-and-a-REST-API/"),
            WebSearchLink(id: "5", title: "UITableView Infinite Scrolling Tutorial | Kodeco", url: "https://www.kodeco.com/5786-uitableview-infinite-scrolling-tutorial"),
            WebSearchLink(id: "6", title: "Infinite scroll Pattern | UX Patterns for Developers", url: "https://uxpatterns.dev/patterns/navigation/infinite-scroll")
        ],
        summary: "Here are the search results for iOS streaming API pagination and infinite scroll best practices:\n\n## iOS-Specific Resources\n\nA complete SwiftUI guide on iOS pagination covers building infinite scrolling feeds with real APIs, cursor-based pagination, and performance optimizations."
    )

    ScrollView {
        WebSearchResultView(result: sampleResult)
            .padding()
    }
    .background(ColorSystem.terminalBg)
}
