import SwiftUI

/// Detail view for inspecting a single debug log entry
/// Shows full request/response data, payloads, and metadata
struct DebugLogDetailView: View {
    let entry: DebugLogEntry

    @State private var showCopiedToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header section
                HeaderSection(entry: entry)

                // Content based on log type
                switch entry.details {
                case .http(let details):
                    HTTPDetailSection(details: details, onCopy: copyToClipboard)
                case .websocket(let details):
                    WebSocketDetailSection(details: details, entry: entry, onCopy: copyToClipboard)
                case .text(let text):
                    TextDetailSection(text: text, onCopy: copyToClipboard)
                case .none:
                    if let subtitle = entry.subtitle {
                        TextDetailSection(text: subtitle, onCopy: copyToClipboard)
                    }
                }

                // Raw entry info (for debugging)
                MetadataSection(entry: entry)
            }
            .padding(Spacing.sm)
        }
        .background(ColorSystem.terminalBg)
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                CopiedToast()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Animations.stateChange, value: showCopiedToast)
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        Haptics.success()

        withAnimation {
            showCopiedToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
}

// MARK: - Header Section

private struct HeaderSection: View {
    let entry: DebugLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Category and level badge
            HStack(spacing: Spacing.xs) {
                // Category pill
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: entry.category.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(entry.category.rawValue)
                        .font(Typography.badge)
                }
                .foregroundStyle(entry.category.color)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxxs)
                .background(entry.category.color.opacity(0.15))
                .clipShape(Capsule())

                // Level indicator
                if entry.level != .info {
                    HStack(spacing: 2) {
                        Image(systemName: entry.level == .error ? "xmark.circle.fill" : entry.level == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 9))
                        Text(entry.level.rawValue.uppercased())
                            .font(Typography.badge)
                    }
                    .foregroundStyle(entry.level.color)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxxs)
                    .background(entry.level.color.opacity(0.15))
                    .clipShape(Capsule())
                }

                Spacer()

                // Full timestamp
                Text(entry.fullTimeString)
                    .font(Typography.terminalTimestamp)
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            // Title
            Text(entry.title)
                .font(Typography.terminalLarge)
                .foregroundStyle(ColorSystem.textPrimary)
                .textSelection(.enabled)

            // Subtitle
            if let subtitle = entry.subtitle {
                Text(subtitle)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .padding(Spacing.sm)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

// MARK: - HTTP Detail Section

private struct HTTPDetailSection: View {
    let details: HTTPLogDetails
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Request info
            HStack {
                SectionHeader(title: "Request", icon: "arrow.up.circle")

                Spacer()

                // Copy cURL button
                if details.curlCommand != nil {
                    CopyCurlButton(details: details, onCopy: onCopy)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Method and path
                HStack(spacing: Spacing.xs) {
                    MethodBadge(method: details.method)
                    Text(details.path)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textPrimary)
                        .textSelection(.enabled)
                }

                // Full URL (if available)
                if let fullURL = details.fullURL {
                    DetailRow(label: "URL", value: fullURL)
                }

                // Query params
                if let params = details.queryParams, !params.isEmpty {
                    DetailRow(label: "Params", value: params)
                }

                // Request body
                if let body = details.requestBody, !body.isEmpty {
                    let formattedBody = formatJSON(body)
                    CollapsibleCodeBlock(
                        title: "Request Body",
                        content: formattedBody,
                        onCopy: { onCopy(formattedBody) }
                    )
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

            // Response info (if available)
            if details.responseStatus != nil || details.responseBody != nil {
                SectionHeader(title: "Response", icon: "arrow.down.circle")

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Status and duration
                    HStack(spacing: Spacing.sm) {
                        if let status = details.responseStatus {
                            StatusCodeBadge(status: status)
                        }

                        if let duration = details.durationString {
                            HStack(spacing: 2) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                Text(duration)
                                    .font(Typography.terminalSmall)
                            }
                            .foregroundStyle(ColorSystem.textTertiary)
                        }
                    }

                    // Response body
                    if let body = details.responseBody, !body.isEmpty {
                        let formattedBody = formatJSON(body)
                        CollapsibleCodeBlock(
                            title: "Response Body",
                            content: formattedBody,
                            onCopy: { onCopy(formattedBody) }
                        )
                    }
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }

            // Error (if any)
            if let error = details.error {
                SectionHeader(title: "Error", icon: "exclamationmark.triangle")

                Text(error)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.error)
                    .textSelection(.enabled)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ColorSystem.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
        }
    }
}

// MARK: - WebSocket Detail Section

private struct WebSocketDetailSection: View {
    let details: WebSocketLogDetails
    let entry: DebugLogEntry
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: directionTitle,
                icon: directionIcon
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Event type
                if let eventType = details.eventType {
                    DetailRow(label: "Event Type", value: eventType)
                }

                // Direction
                DetailRow(label: "Direction", value: directionDescription)

                // Payload
                if let payload = details.payload, !payload.isEmpty {
                    let formattedPayload = formatJSON(payload)
                    CollapsibleCodeBlock(
                        title: "Payload",
                        content: formattedPayload,
                        onCopy: { onCopy(formattedPayload) }
                    )
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
    }

    private var directionTitle: String {
        switch details.direction {
        case .incoming: return "Incoming Event"
        case .outgoing: return "Outgoing Command"
        case .status: return "Connection Status"
        }
    }

    private var directionIcon: String {
        switch details.direction {
        case .incoming: return "arrow.down.circle"
        case .outgoing: return "arrow.up.circle"
        case .status: return "circle.dotted"
        }
    }

    private var directionDescription: String {
        switch details.direction {
        case .incoming: return "Server → App"
        case .outgoing: return "App → Server"
        case .status: return "Status Change"
        }
    }
}

// MARK: - Text Detail Section

private struct TextDetailSection: View {
    let text: String
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Details", icon: "text.alignleft")

            CollapsibleCodeBlock(
                title: "Content",
                content: text,
                onCopy: { onCopy(text) }
            )
        }
    }
}

// MARK: - Metadata Section

private struct MetadataSection: View {
    let entry: DebugLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Metadata", icon: "info.circle")

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                DetailRow(label: "ID", value: entry.id.uuidString)
                DetailRow(label: "Timestamp", value: entry.fullTimeString)
                DetailRow(label: "Category", value: entry.category.rawValue)
                DetailRow(label: "Level", value: entry.level.rawValue)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
    }
}

// MARK: - Reusable Components

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(Typography.bannerTitle)
        }
        .foregroundStyle(ColorSystem.textSecondary)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(label)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textSecondary)
                .textSelection(.enabled)
        }
    }
}

private struct MethodBadge: View {
    let method: String

    var body: some View {
        Text(method)
            .font(Typography.badge)
            .foregroundStyle(methodColor)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(methodColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var methodColor: Color {
        switch method.uppercased() {
        case "GET": return ColorSystem.primary
        case "POST": return ColorSystem.success
        case "PUT", "PATCH": return ColorSystem.warning
        case "DELETE": return ColorSystem.error
        default: return ColorSystem.textSecondary
        }
    }
}

private struct StatusCodeBadge: View {
    let status: Int

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text("\(status)")
                .font(Typography.terminalSmall)

            Text(statusText)
                .font(Typography.terminalSmall)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        if (200...299).contains(status) { return ColorSystem.success }
        if (400...499).contains(status) { return ColorSystem.warning }
        return ColorSystem.error
    }

    private var statusText: String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 500: return "Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Unavailable"
        case 504: return "Gateway Timeout"
        default: return ""
        }
    }
}

private struct CollapsibleCodeBlock: View {
    let title: String
    let content: String
    let onCopy: () -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Header
            Button {
                withAnimation(Animations.stateChange) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorSystem.textTertiary)

                    Text(title)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)

                    Spacer()

                    // Copy button
                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(ColorSystem.primary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Content - vertical scroll only, with word wrap
            if isExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(content)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.accent)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)  // Enable word wrap
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 400) // Limit height to prevent infinite expansion
                .padding(Spacing.xs)
                .background(ColorSystem.terminalBg)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
    }
}

private struct CopiedToast: View {
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ColorSystem.success)
            Text("Copied to clipboard")
                .font(Typography.bannerBody)
        }
        .foregroundStyle(ColorSystem.textPrimary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(ColorSystem.terminalBgElevated)
        .overlay(
            Capsule()
                .stroke(ColorSystem.primary.opacity(0.3), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
        .shadow(color: ColorSystem.primary.opacity(0.2), radius: 8, x: 0, y: 2)
        .padding(.bottom, Spacing.md)
    }
}

/// Copy cURL button with menu for different formats
private struct CopyCurlButton: View {
    let details: HTTPLogDetails
    let onCopy: (String) -> Void

    var body: some View {
        Menu {
            // Copy formatted cURL (multiline, readable)
            if let curl = details.curlCommand {
                Button {
                    onCopy(curl)
                } label: {
                    Label("Copy cURL (Formatted)", systemImage: "terminal")
                }
            }

            // Copy compact cURL (single line)
            if let curlCompact = details.curlCommandCompact {
                Button {
                    onCopy(curlCompact)
                } label: {
                    Label("Copy cURL (Compact)", systemImage: "text.alignleft")
                }
            }

            Divider()

            // Copy just the URL
            if let url = details.fullURL {
                Button {
                    onCopy(url)
                } label: {
                    Label("Copy URL", systemImage: "link")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .semibold))
                Text("cURL")
                    .font(Typography.badge)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(ColorSystem.primary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 4)
            .background(ColorSystem.primary.opacity(0.15))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Helpers

/// Format JSON string for display
private func formatJSON(_ string: String) -> String {
    guard let data = string.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data),
          let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
          let result = String(data: formatted, encoding: .utf8) else {
        return string
    }
    return result
}

// MARK: - Identifiable Conformance

extension DebugLogEntry: Hashable {
    static func == (lhs: DebugLogEntry, rhs: DebugLogEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DebugLogDetailView(entry: DebugLogEntry(
            timestamp: Date(),
            category: .http,
            level: .success,
            title: "POST /api/claude/run",
            subtitle: "← 200 (350ms)",
            details: .http(HTTPLogDetails(
                method: "POST",
                path: "/api/claude/run",
                queryParams: nil,
                requestBody: "{\"prompt\":\"Hello world\",\"mode\":\"new\"}",
                responseStatus: 200,
                responseBody: "{\"status\":\"started\",\"session_id\":\"abc123\"}",
                duration: 0.350,
                error: nil,
                fullURL: "http://localhost:8080/api/claude/run",
                requestHeaders: ["Content-Type": "application/json", "Accept": "application/json"]
            ))
        ))
        .navigationTitle("Log Detail")
    }
}
