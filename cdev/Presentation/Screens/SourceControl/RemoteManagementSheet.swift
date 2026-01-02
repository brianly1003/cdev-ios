import SwiftUI

// MARK: - Remote Management Sheet

/// Compact sheet for viewing and managing git remotes
/// Follows terminal-first design with responsive layout
struct RemoteManagementSheet: View {
    let workspaceId: String
    @Binding var isPresented: Bool
    var onRemoteChanged: (() -> Void)?

    @StateObject private var viewModel: RemoteManagementViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    @State private var showAddRemote = false
    @State private var remoteToDelete: WorkspaceGitRemoteInfo?
    @State private var showDeleteAlert = false

    init(workspaceId: String, isPresented: Binding<Bool>, onRemoteChanged: (() -> Void)? = nil) {
        self.workspaceId = workspaceId
        self._isPresented = isPresented
        self.onRemoteChanged = onRemoteChanged
        self._viewModel = StateObject(wrappedValue: RemoteManagementViewModel(workspaceId: workspaceId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.remotes.isEmpty {
                    loadingView
                } else if viewModel.remotes.isEmpty {
                    emptyView
                } else {
                    remoteList
                }
            }
            .background(ColorSystem.terminalBg)
            .navigationTitle("Remotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                        .foregroundStyle(ColorSystem.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddRemote = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: layout.iconMedium))
                    }
                }
            }
            .task {
                await viewModel.loadRemotes()
            }
            .sheet(isPresented: $showAddRemote) {
                AddRemoteSheet(
                    workspaceId: workspaceId,
                    isPresented: $showAddRemote,
                    onSuccess: {
                        Task { await viewModel.loadRemotes() }
                        onRemoteChanged?()
                    }
                )
            }
            .alert("Remove Remote?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    if let remote = remoteToDelete {
                        Task { await viewModel.removeRemote(name: remote.name) }
                        onRemoteChanged?()
                    }
                }
            } message: {
                if let remote = remoteToDelete {
                    Text("Remove '\(remote.name)' remote? This will not delete the remote repository.")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Remote List

    private var remoteList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.remotes) { remote in
                    RemoteRow(
                        remote: remote,
                        layout: layout,
                        onDelete: {
                            remoteToDelete = remote
                            showDeleteAlert = true
                        }
                    )

                    if remote.id != viewModel.remotes.last?.id {
                        Divider()
                            .background(ColorSystem.terminalBgHighlight)
                    }
                }
            }
            .padding(.top, layout.smallPadding)
        }
        .refreshable {
            await viewModel.loadRemotes()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading remotes...")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)
            Spacer()
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "link.circle")
                .font(.system(size: 40))
                .foregroundStyle(ColorSystem.textTertiary)

            Text("No remotes configured")
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textSecondary)

            Text("Add a remote to sync with GitHub, GitLab, or another git server.")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            Button {
                showAddRemote = true
            } label: {
                Label("Add Remote", systemImage: "plus")
                    .font(Typography.buttonLabel)
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorSystem.primary)
            .padding(.top, Spacing.sm)

            Spacer()
        }
    }
}

// MARK: - Remote Row

/// Compact row showing remote info with delete action
struct RemoteRow: View {
    let remote: WorkspaceGitRemoteInfo
    let layout: ResponsiveLayout
    let onDelete: () -> Void

    @State private var showCopied = false

    var body: some View {
        HStack(spacing: layout.contentSpacing) {
            // Provider icon
            providerIcon

            // Remote info
            VStack(alignment: .leading, spacing: 2) {
                // Name
                HStack(spacing: layout.tightSpacing) {
                    Text(remote.name)
                        .font(Typography.terminal)
                        .foregroundStyle(ColorSystem.textPrimary)

                    if remote.name == "origin" {
                        Text("default")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(ColorSystem.primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(ColorSystem.primary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                // URL with copy button
                HStack(spacing: layout.tightSpacing) {
                    if let parsed = remote.parsedURL {
                        Text(parsed.displayName)
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textSecondary)
                            .lineLimit(1)

                        // Protocol badge
                        Text(parsed.protocolText)
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(ColorSystem.textTertiary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(ColorSystem.textTertiary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    } else if let url = remote.fetchUrl {
                        Text(url)
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: layout.tightSpacing)

            // Actions
            HStack(spacing: layout.tightSpacing) {
                // Copy URL button
                Button {
                    if let url = remote.fetchUrl {
                        UIPasteboard.general.string = url
                        showCopied = true
                        Haptics.light()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopied = false
                        }
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: layout.iconSmall))
                        .foregroundStyle(showCopied ? ColorSystem.success : ColorSystem.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(ColorSystem.terminalBgHighlight)
                        .clipShape(Circle())
                }

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: layout.iconSmall))
                        .foregroundStyle(ColorSystem.error)
                        .frame(width: 28, height: 28)
                        .background(ColorSystem.error.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, layout.smallPadding)
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    private var providerIcon: some View {
        Group {
            if let parsed = remote.parsedURL {
                Image(systemName: parsed.provider.icon)
                    .font(.system(size: layout.iconLarge))
                    .foregroundStyle(parsed.provider.color)
            } else {
                Image(systemName: "server.rack")
                    .font(.system(size: layout.iconLarge))
                    .foregroundStyle(ColorSystem.textTertiary)
            }
        }
        .frame(width: 32, height: 32)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Add Remote Sheet

/// Compact sheet for adding a new remote
struct AddRemoteSheet: View {
    let workspaceId: String
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)?

    @State private var remoteURL: String = ""
    @State private var remoteName: String = "origin"
    @State private var parsedURL: GitRemoteURL?
    @State private var isLoading: Bool = false
    @State private var error: String?
    @FocusState private var isURLFocused: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }
    private let workspaceManager = WorkspaceManagerService.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                // URL input
                VStack(alignment: .leading, spacing: layout.tightSpacing) {
                    Text("Repository URL")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)

                    TextField("git@github.com:user/repo.git", text: $remoteURL, axis: .vertical)
                        .font(Typography.terminal)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...2)
                        .focused($isURLFocused)
                        .padding(layout.smallPadding)
                        .background(ColorSystem.terminalBgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(parsedURL != nil ? ColorSystem.success.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                        .onChange(of: remoteURL) { _, newValue in
                            parsedURL = GitRemoteURL.parse(newValue)
                        }
                }

                // Parsed URL preview
                if let parsed = parsedURL {
                    HStack(spacing: layout.contentSpacing) {
                        Image(systemName: parsed.provider.icon)
                            .font(.system(size: layout.iconMedium))
                            .foregroundStyle(parsed.provider.color)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(parsed.displayName)
                                .font(Typography.terminal)
                                .foregroundStyle(ColorSystem.textPrimary)
                            Text(parsed.provider.displayName)
                                .font(Typography.terminalSmall)
                                .foregroundStyle(ColorSystem.textTertiary)
                        }

                        Spacer()

                        Text(parsed.protocolText)
                            .font(Typography.badge)
                            .foregroundStyle(ColorSystem.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ColorSystem.terminalBgHighlight)
                            .clipShape(Capsule())
                    }
                    .padding(layout.smallPadding)
                    .background(ColorSystem.success.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Remote name
                VStack(alignment: .leading, spacing: layout.tightSpacing) {
                    Text("Remote Name")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)

                    TextField("origin", text: $remoteName)
                        .font(Typography.terminal)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(layout.smallPadding)
                        .background(ColorSystem.terminalBgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Error message
                if let error = error {
                    HStack(spacing: layout.tightSpacing) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: layout.iconSmall))
                        Text(error)
                            .font(Typography.terminalSmall)
                    }
                    .foregroundStyle(ColorSystem.error)
                }

                Spacer()
            }
            .padding(layout.standardPadding)
            .background(ColorSystem.terminalBg)
            .navigationTitle("Add Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await addRemote() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(parsedURL == nil || isLoading)
                }
            }
            .onAppear {
                isURLFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func addRemote() async {
        guard let url = parsedURL else { return }

        isLoading = true
        error = nil

        do {
            let result = try await workspaceManager.gitRemoteAdd(
                workspaceId: workspaceId,
                name: remoteName.isEmpty ? "origin" : remoteName,
                url: url.fullURL
            )

            if result.isSuccess {
                Haptics.success()
                onSuccess?()
                isPresented = false
            } else {
                error = result.error ?? result.message ?? "Failed to add remote"
                Haptics.error()
            }
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }

        isLoading = false
    }
}

// MARK: - Remote Management ViewModel

@MainActor
final class RemoteManagementViewModel: ObservableObject {
    @Published private(set) var remotes: [WorkspaceGitRemoteInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let workspaceId: String
    private let workspaceManager = WorkspaceManagerService.shared

    init(workspaceId: String) {
        self.workspaceId = workspaceId
    }

    func loadRemotes() async {
        isLoading = true
        error = nil

        do {
            let result = try await workspaceManager.getRemotes(workspaceId: workspaceId)
            remotes = result.safeRemotes
        } catch {
            self.error = error.localizedDescription
            AppLogger.log("[RemoteManagement] Failed to load remotes: \(error)", type: .error)
        }

        isLoading = false
    }

    func removeRemote(name: String) async {
        do {
            let result = try await workspaceManager.gitRemoteRemove(workspaceId: workspaceId, name: name)
            if result.isSuccess {
                remotes.removeAll { $0.name == name }
                Haptics.success()
            } else {
                error = result.error ?? "Failed to remove remote"
                Haptics.error()
            }
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}

// MARK: - Preview

#Preview {
    RemoteManagementSheet(
        workspaceId: "test",
        isPresented: .constant(true)
    )
}
