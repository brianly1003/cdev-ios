import SwiftUI

// MARK: - Workspace Switcher Sheet

/// Sophisticated workspace switcher for 100+ repositories
/// Features: Search, compact rows, responsive iPad/iPhone, keyboard shortcuts
struct WorkspaceSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var workspaceStore: WorkspaceStore

    let currentWorkspace: Workspace?
    let isConnected: Bool
    let claudeState: ClaudeState
    let onSwitch: (Workspace) -> Void
    let onAddNew: () -> Void
    let onDisconnect: () -> Void

    @State private var searchText = ""
    @State private var showDisconnectConfirm = false
    @FocusState private var isSearchFocused: Bool

    private var isCompact: Bool { sizeClass == .compact }

    // Filtered workspaces based on search
    private var filteredWorkspaces: [Workspace] {
        let others = workspaceStore.otherWorkspaces
        guard !searchText.isEmpty else { return others }

        let query = searchText.lowercased()
        return others.filter { workspace in
            workspace.name.lowercased().contains(query) ||
            workspace.hostDisplay.lowercased().contains(query) ||
            (workspace.branch?.lowercased().contains(query) ?? false)
        }
    }

    // Group workspaces by host for better organization
    private var groupedWorkspaces: [(host: String, workspaces: [Workspace])] {
        let grouped = Dictionary(grouping: filteredWorkspaces) { $0.hostDisplay }
        return grouped.map { (host: $0.key, workspaces: $0.value) }
            .sorted { $0.workspaces.first?.lastConnected ?? .distantPast >
                      $1.workspaces.first?.lastConnected ?? .distantPast }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorSystem.terminalBg
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    WorkspaceSearchBar(
                        text: $searchText,
                        placeholder: "Search \(workspaceStore.workspaces.count) workspaces...",
                        isFocused: $isSearchFocused
                    )
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, Spacing.xs)

                    // Content
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            // Current workspace (compact card)
                            if let current = currentWorkspace, searchText.isEmpty {
                                CurrentWorkspaceCompact(
                                    workspace: current,
                                    isConnected: isConnected,
                                    claudeState: claudeState,
                                    onDisconnect: { showDisconnectConfirm = true }
                                )
                                .padding(.horizontal, Spacing.sm)
                                .padding(.bottom, Spacing.sm)
                            }

                            // Workspaces list
                            if filteredWorkspaces.isEmpty && !searchText.isEmpty {
                                NoResultsView(query: searchText)
                                    .padding(.top, Spacing.xl)
                            } else if groupedWorkspaces.count == 1 {
                                // Single host - no grouping needed
                                ForEach(filteredWorkspaces) { workspace in
                                    CompactWorkspaceRow(
                                        workspace: workspace,
                                        showHost: false,
                                        onTap: {
                                            onSwitch(workspace)
                                            dismiss()
                                        },
                                        onDelete: {
                                            workspaceStore.removeWorkspace(workspace)
                                        }
                                    )
                                }
                                .padding(.horizontal, Spacing.sm)
                            } else {
                                // Multiple hosts - group by host
                                ForEach(groupedWorkspaces, id: \.host) { group in
                                    Section {
                                        ForEach(group.workspaces) { workspace in
                                            CompactWorkspaceRow(
                                                workspace: workspace,
                                                showHost: false,
                                                onTap: {
                                                    onSwitch(workspace)
                                                    dismiss()
                                                },
                                                onDelete: {
                                                    workspaceStore.removeWorkspace(workspace)
                                                }
                                            )
                                        }
                                    } header: {
                                        HostSectionHeader(host: group.host, count: group.workspaces.count)
                                            .padding(.horizontal, Spacing.sm)
                                    }
                                }
                            }

                            // Empty state
                            if currentWorkspace == nil && workspaceStore.workspaces.isEmpty {
                                EmptyWorkspacesView()
                                    .padding(.top, Spacing.xl)
                            }

                            // Add new workspace button
                            if searchText.isEmpty {
                                AddWorkspaceCompact(onTap: {
                                    onAddNew()
                                    dismiss()
                                })
                                .padding(.horizontal, Spacing.sm)
                                .padding(.top, Spacing.sm)
                                .padding(.bottom, Spacing.lg)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Workspaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(workspaceStore.workspaces.count)")
                        .font(Typography.caption1)
                        .foregroundStyle(ColorSystem.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ColorSystem.terminalBgHighlight)
                        .clipShape(Capsule())
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(ColorSystem.terminalBgElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                "Disconnect from workspace?",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    onDisconnect()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to scan the QR code again to reconnect.")
            }
        }
        .onAppear {
            // Auto-focus search on iPad for keyboard users
            if !isCompact {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isSearchFocused = true
                }
            }
        }
    }
}

// MARK: - Search Bar

private struct WorkspaceSearchBar: View {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.textTertiary)

            TextField(placeholder, text: $text)
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)
                .focused(isFocused)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                    Haptics.light()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(ColorSystem.terminalBgHighlight, lineWidth: 1)
        )
    }
}

// MARK: - Current Workspace Compact

private struct CurrentWorkspaceCompact: View {
    let workspace: Workspace
    let isConnected: Bool
    let claudeState: ClaudeState
    let onDisconnect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            // Folder icon
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(ColorSystem.primary)
                .padding(.top, 2)

            // Name and info
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.displayName)
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    // Status badges
                    StatusPill(
                        color: isConnected ? ColorSystem.success : ColorSystem.error,
                        text: isConnected ? "ON" : "OFF"
                    )

                    StatusPill(
                        color: ColorSystem.Status.color(for: claudeState),
                        text: String(claudeState.rawValue.prefix(3)).uppercased()
                    )

                    // Host
                    Text(workspace.hostDisplay)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textQuaternary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Disconnect
            Button {
                onDisconnect()
                Haptics.warning()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ColorSystem.error)
                    .padding(6)
                    .background(ColorSystem.error.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(ColorSystem.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .stroke(ColorSystem.primary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Status Pill

private struct StatusPill: View {
    let color: Color
    let text: String

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

// MARK: - Compact Workspace Row

private struct CompactWorkspaceRow: View {
    let workspace: Workspace
    let showHost: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        Button {
            onTap()
            Haptics.selection()
        } label: {
            HStack(alignment: .top, spacing: Spacing.xs) {
                // Folder icon
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(width: 16)
                    .padding(.top, 2)

                // Name and details
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.displayName)
                        .font(Typography.body)
                        .foregroundStyle(ColorSystem.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: Spacing.xs) {
                        // Branch (if available)
                        if let branch = workspace.branch {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8))
                                Text(branch)
                                    .lineLimit(1)
                            }
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textQuaternary)
                        }

                        // Host (if showing)
                        if showHost {
                            Text(workspace.hostDisplay)
                                .font(Typography.terminalSmall)
                                .foregroundStyle(ColorSystem.textQuaternary)
                        }

                        // Time
                        Text(workspace.timeSinceConnected)
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textQuaternary)
                    }
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textQuaternary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(ColorSystem.terminalBgElevated)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Remove", systemImage: "trash")
            }

            Button {
                UIPasteboard.general.string = workspace.webSocketURL.absoluteString
                Haptics.success()
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
        }
        .confirmationDialog(
            "Remove workspace?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \(workspace.displayName) from your workspaces.")
        }
    }
}

// MARK: - Host Section Header

private struct HostSectionHeader: View {
    let host: String
    let count: Int

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "server.rack")
                .font(.system(size: 9))
            Text(host)
                .font(Typography.terminalSmall)
            Text("(\(count))")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textQuaternary)
            Spacer()
        }
        .foregroundStyle(ColorSystem.textTertiary)
        .padding(.vertical, Spacing.xxs)
        .padding(.horizontal, Spacing.sm)
        .background(ColorSystem.terminalBg)
    }
}

// MARK: - Add Workspace Compact

private struct AddWorkspaceCompact: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
            Haptics.light()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.primary)

                Text("Add Workspace")
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.primary)

                Spacer()

                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 12))
                    .foregroundStyle(ColorSystem.textTertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
                    .foregroundStyle(ColorSystem.primary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - No Results View

private struct NoResultsView: View {
    let query: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(ColorSystem.textQuaternary)

            Text("No workspaces matching \"\(query)\"")
                .font(Typography.caption1)
                .foregroundStyle(ColorSystem.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
    }
}

// MARK: - Empty State

private struct EmptyWorkspacesView: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(ColorSystem.textQuaternary)

            VStack(spacing: Spacing.xxs) {
                Text("No Workspaces")
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textSecondary)

                Text("Scan a QR code to connect")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
    }
}

// MARK: - Tappable Workspace Badge

/// Compact badge for status bar - tap to open switcher
struct WorkspaceBadge: View {
    let workspace: Workspace?
    let isConnected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
            Haptics.selection()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9))

                if let workspace = workspace {
                    Text(workspace.displayName)
                        .font(Typography.statusLabel)
                        .lineLimit(1)
                } else {
                    Text("No Workspace")
                        .font(Typography.statusLabel)
                }

                // Chevron indicator
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(isConnected ? ColorSystem.textSecondary : ColorSystem.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
