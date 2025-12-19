import SwiftUI

/// Navigation breadcrumb bar for file explorer
/// Shows current path with tappable segments for quick navigation
struct BreadcrumbBar: View {
    let path: String
    let onNavigate: (String) -> Void
    let onRoot: () -> Void

    private var pathComponents: [(name: String, path: String)] {
        guard !path.isEmpty else { return [] }

        var result: [(String, String)] = []
        var currentPath = ""

        for component in path.split(separator: "/") {
            currentPath += (currentPath.isEmpty ? "" : "/") + component
            result.append((String(component), currentPath))
        }

        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: Spacing.xxs) {
                    // Root button
                    Button {
                        onRoot()
                    } label: {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(path.isEmpty ? ColorSystem.primary : ColorSystem.textSecondary)
                    }
                    .buttonStyle(.plain)

                    // Path segments
                    ForEach(Array(pathComponents.enumerated()), id: \.element.path) { index, component in
                        HStack(spacing: Spacing.xxs) {
                            // Separator chevron
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(ColorSystem.textQuaternary)

                            // Path segment button
                            Button {
                                onNavigate(component.path)
                            } label: {
                                Text(component.name)
                                    .font(Typography.terminalSmall)
                                    .foregroundStyle(
                                        component.path == path
                                            ? ColorSystem.textPrimary
                                            : ColorSystem.textSecondary
                                    )
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .id(component.path)
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .onChange(of: path) { _, newPath in
                    // Auto-scroll to show current path segment
                    withAnimation {
                        proxy.scrollTo(newPath, anchor: .trailing)
                    }
                }
            }
        }
        .frame(height: 28)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        BreadcrumbBar(
            path: "",
            onNavigate: { _ in },
            onRoot: {}
        )

        BreadcrumbBar(
            path: "cdev/Presentation/Screens/Explorer",
            onNavigate: { path in print("Navigate to: \(path)") },
            onRoot: { print("Go to root") }
        )

        Spacer()
    }
    .background(ColorSystem.terminalBg)
}
