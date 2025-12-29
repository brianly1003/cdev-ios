import SwiftUI

/// ⌘K Quick Switcher - Spotlight-style workspace switcher
/// Keyboard-first design for rapid workspace switching
/// Supports fuzzy search, keyboard navigation, and quick shortcuts
struct QuickSwitcherView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var viewModel: QuickSwitcherViewModel
    @ObservedObject var workspaceStore: WorkspaceStore

    let currentWorkspace: Workspace?
    let workspaceStates: [UUID: WorkspaceState]  // Live workspace states
    let onSwitch: (Workspace) -> Void
    let onDismiss: () -> Void

    @FocusState private var isSearchFocused: Bool

    private var layout: ResponsiveLayout {
        ResponsiveLayout.current(for: sizeClass)
    }

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Switcher card
            VStack(spacing: 0) {
                // Header
                header

                // Search bar
                searchBar
                    .padding(.horizontal, layout.standardPadding)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, Spacing.xs)

                // Results
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.filteredWorkspaces.enumerated()), id: \.element.id) { index, workspace in
                                WorkspaceResultRow(
                                    workspace: workspace,
                                    state: workspaceStates[workspace.id],
                                    isSelected: index == viewModel.selectedIndex,
                                    isCurrent: workspace.id == currentWorkspace?.id,
                                    shortcutNumber: index < 9 ? index + 1 : nil,
                                    onTap: {
                                        selectWorkspace(workspace)
                                    }
                                )
                                .id(index)
                            }

                            if viewModel.filteredWorkspaces.isEmpty {
                                noResultsView
                            }
                        }
                    }
                    .frame(maxHeight: isCompact ? 400 : 500)
                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                // Footer hints
                if !isCompact {
                    footer
                }
            }
            .frame(maxWidth: isCompact ? .infinity : 600)
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? 0 : CornerRadius.large))
            .shadow(color: .black.opacity(0.5), radius: 20)
            .padding(.horizontal, isCompact ? 0 : layout.standardPadding)
        }
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            // Title
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "command")
                    .font(.system(size: layout.iconMedium, weight: .semibold))
                    .foregroundStyle(ColorSystem.primary)

                Text("K")
                    .font(.system(size: layout.iconMedium, weight: .bold, design: .monospaced))
                    .foregroundStyle(ColorSystem.primary)

                Text("Quick Switch")
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textPrimary)
            }

            Spacer()

            // Count badge
            Text("\(viewModel.resultCount)")
                .font(Typography.caption1)
                .foregroundStyle(ColorSystem.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(Capsule())

            // Close button
            Button {
                dismiss()
            } label: {
                Text("ESC")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, Spacing.sm)
        .background(ColorSystem.terminalBg)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: layout.iconMedium))
                .foregroundStyle(ColorSystem.textTertiary)

            TextField("Type to search...", text: $viewModel.searchText)
                .font(Typography.inputField)
                .foregroundStyle(ColorSystem.textPrimary)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onChange(of: viewModel.searchText) {
                    viewModel.resetSelection()
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    Haptics.light()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: layout.iconMedium))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgHighlight)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: layout.contentSpacing) {
            KeyHint(key: "↑↓", description: "Navigate")
            KeyHint(key: "↵", description: "Select")
            KeyHint(key: "⌘↵", description: "Select & Run")
            Spacer()
            KeyHint(key: "⌘1-9", description: "Quick select")
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBg)
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(ColorSystem.textQuaternary)

            Text("No workspaces matching \"\(viewModel.searchText)\"")
                .font(Typography.caption1)
                .foregroundStyle(ColorSystem.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - Actions

    private func selectWorkspace(_ workspace: Workspace) {
        onSwitch(workspace)
        dismiss()
        Haptics.selection()
    }

    private func dismiss() {
        viewModel.hide()
        onDismiss()
        Haptics.light()
    }
}

// MARK: - Workspace Result Row

private struct WorkspaceResultRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    let workspace: Workspace
    let state: WorkspaceState?
    let isSelected: Bool
    let isCurrent: Bool
    let shortcutNumber: Int?
    let onTap: () -> Void

    private var layout: ResponsiveLayout {
        ResponsiveLayout.current(for: sizeClass)
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: Spacing.xs) {
                // Folder icon
                Image(systemName: isCurrent ? "folder.fill" : "folder")
                    .font(.system(size: layout.iconMedium))
                    .foregroundStyle(isCurrent ? ColorSystem.primary : ColorSystem.textTertiary)
                    .frame(width: 20)

                // Workspace info
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.displayName)
                        .font(Typography.body)
                        .foregroundStyle(ColorSystem.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        // Status badges
                        if let state = state {
                            StatusBadge(
                                text: state.isConnected ? "RUNNING" : "STOPPED",
                                color: state.isConnected ? ColorSystem.success : ColorSystem.Status.stopped
                            )

                            StatusBadge(
                                text: String(state.claudeState.rawValue.prefix(4).uppercased()),
                                color: ColorSystem.Status.color(for: state.claudeState)
                            )
                        }

                        // Host and time
                        Group {
                            Text(workspace.hostDisplay)
                            Text("•")
                            if let branch = workspace.branch {
                                Text(branch)
                                Text("•")
                            }
                            Text(workspace.timeSinceConnected)
                        }
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textQuaternary)
                        .lineLimit(1)
                    }
                }

                Spacer()

                // Shortcut number
                if let number = shortcutNumber {
                    Text("⌘\(number)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ColorSystem.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ColorSystem.terminalBgHighlight)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .fill(isSelected ? ColorSystem.terminalBgSelected : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Key Hint

private struct KeyHint: View {
    let key: String
    let description: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(ColorSystem.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(description)
                .font(Typography.caption1)
                .foregroundStyle(ColorSystem.textTertiary)
        }
    }
}
