import SwiftUI

// MARK: - Repository Discovery View

/// Discover Git repositories on the host machine for adding as workspaces
struct RepositoryDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var viewModel = RepositoryDiscoveryViewModel()

    /// Callback when user wants to connect to an added workspace
    /// Returns true if connection succeeded (dismisses view), false otherwise (stays on page)
    var onConnectToWorkspace: ((RemoteWorkspace, String) async -> Bool)?

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorSystem.terminalBg
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search paths input
                    searchPathsSection
                        .padding(.horizontal, layout.standardPadding)
                        .padding(.vertical, layout.smallPadding)

                    // Search bar (only show when we have results)
                    if !viewModel.repositories.isEmpty {
                        searchBar
                            .padding(.horizontal, layout.standardPadding)
                            .padding(.bottom, layout.smallPadding)
                    }

                    Divider()
                        .background(ColorSystem.terminalBgHighlight)

                    // Results
                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.repositories.isEmpty {
                        emptyStateView
                    } else if viewModel.filteredRepositories.isEmpty {
                        noSearchResultsView
                    } else {
                        repositoryList
                    }
                }
            }
            .navigationTitle("Discover Repos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(ColorSystem.textSecondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.discover() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: layout.iconAction))
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .task {
                // Auto-discover on appear
                await viewModel.discover()
            }
        }
    }

    // MARK: - Search Paths Section

    private var searchPathsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Search Paths")
                .font(Typography.caption1)
                .foregroundStyle(ColorSystem.textSecondary)

            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("~/Projects, ~/Code", text: $viewModel.searchPathsInput)
                    .font(Typography.inputField)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.discover() }
                    }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

            Text("Leave empty to search default locations")
                .font(Typography.caption2)
                .foregroundStyle(ColorSystem.textTertiary)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.textTertiary)

            TextField("Search repositories...", text: $viewModel.searchText)
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)
                .autocorrectionDisabled()

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    // MARK: - Repository List

    private var repositoryList: some View {
        List {
            ForEach(viewModel.filteredRepositories) { repo in
                RepositoryRowView(
                    repository: repo,
                    isLoading: viewModel.loadingRepoId == repo.id
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !repo.isConfigured {
                        // Add & Connect (full swipe)
                        Button {
                            Task {
                                if let (workspace, host) = await viewModel.addAndStartWorkspace(repo) {
                                    // Await connection result - only dismiss on success
                                    let success = await onConnectToWorkspace?(workspace, host) ?? false
                                    if success {
                                        dismiss()
                                    }
                                }
                            }
                        } label: {
                            Label("Add & Connect", systemImage: "arrow.right.circle.fill")
                        }
                        .tint(ColorSystem.primary)

                        // Add only
                        Button {
                            Task { await viewModel.addWorkspace(repo) }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .tint(ColorSystem.success)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if repo.isConfigured {
                        // Connect to already-added workspace
                        Button {
                            Task {
                                if let (workspace, host) = await viewModel.startAndConnect(repo) {
                                    // Await connection result - only dismiss on success
                                    let success = await onConnectToWorkspace?(workspace, host) ?? false
                                    if success {
                                        dismiss()
                                    }
                                }
                            }
                        } label: {
                            Label("Connect", systemImage: "arrow.right.circle.fill")
                        }
                        .tint(ColorSystem.primary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Scanning for repositories...")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(ColorSystem.textTertiary)

            Text("No Repositories Found")
                .font(Typography.title3)
                .foregroundStyle(ColorSystem.textPrimary)

            Text("No Git repositories found in the specified paths.")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Button {
                Task { await viewModel.discover() }
            } label: {
                Label("Search Again", systemImage: "arrow.clockwise")
                    .font(Typography.buttonLabel)
                    .foregroundStyle(ColorSystem.primary)
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - No Search Results

    private var noSearchResultsView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(ColorSystem.textTertiary)

            Text("No Results")
                .font(Typography.title3)
                .foregroundStyle(ColorSystem.textPrimary)

            Text("No repositories match \"\(viewModel.searchText)\"")
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.searchText = ""
            } label: {
                Text("Clear Search")
                    .font(Typography.buttonLabel)
                    .foregroundStyle(ColorSystem.primary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Repository Row View

struct RepositoryRowView: View {
    let repository: DiscoveredRepository
    var isLoading: Bool = false

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        HStack(spacing: layout.contentSpacing) {
            // Folder icon
            Image(systemName: "folder.fill")
                .font(.system(size: layout.iconLarge))
                .foregroundStyle(ColorSystem.warning)

            // Repo info
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .lineLimit(1)

                Text(repository.path)
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let remote = repository.repoName {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text(remote)
                            .font(Typography.caption2)
                    }
                    .foregroundStyle(ColorSystem.textQuaternary)
                }
            }

            Spacer(minLength: 0)

            // Loading indicator or status badge
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: layout.indicatorSize, height: layout.indicatorSize)
            } else if repository.isConfigured {
                // Swipe hint for configured repos
                HStack(spacing: 4) {
                    Text("Added")
                        .font(Typography.badge)
                        .foregroundStyle(ColorSystem.success)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8))
                        .foregroundStyle(ColorSystem.textQuaternary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ColorSystem.success.opacity(0.12))
                .clipShape(Capsule())
            } else {
                // Swipe hint for unconfigured repos
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(ColorSystem.textQuaternary)
                    Text("Swipe")
                        .font(Typography.badge)
                        .foregroundStyle(ColorSystem.textTertiary)
                }
            }
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, layout.smallPadding)
        .contentShape(Rectangle())
    }
}

// MARK: - Repository Discovery ViewModel

@MainActor
final class RepositoryDiscoveryViewModel: ObservableObject {
    @Published var repositories: [DiscoveredRepository] = []
    @Published var searchPathsInput: String = ""
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    /// Track which repo is currently being added/started
    @Published var loadingRepoId: String?

    private let managerService = WorkspaceManagerService.shared

    /// Parse search paths from input
    private var searchPaths: [String]? {
        let paths = searchPathsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return paths.isEmpty ? nil : paths
    }

    /// Filtered repositories based on search text
    var filteredRepositories: [DiscoveredRepository] {
        guard !searchText.isEmpty else { return repositories }
        let query = searchText.lowercased()
        return repositories.filter { repo in
            repo.name.lowercased().contains(query) ||
            repo.path.lowercased().contains(query) ||
            (repo.repoName?.lowercased().contains(query) ?? false)
        }
    }

    /// Discover repositories
    func discover() async {
        guard managerService.isConnected else {
            errorMessage = "Not connected to workspace manager"
            showError = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            repositories = try await managerService.discoverRepositories(paths: searchPaths)
        } catch let error as WorkspaceManagerError {
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Add a discovered repository as a workspace (just marks it, doesn't connect)
    func addWorkspace(_ repo: DiscoveredRepository) async {
        guard !repo.isConfigured else {
            // Already configured
            return
        }

        loadingRepoId = repo.id
        defer { loadingRepoId = nil }

        do {
            // Call workspace manager API to add workspace
            _ = try await managerService.addWorkspace(path: repo.path, name: repo.name)

            // Mark as configured in local state
            if let index = repositories.firstIndex(where: { $0.id == repo.id }) {
                let updated = DiscoveredRepository(
                    name: repo.name,
                    path: repo.path,
                    remoteUrl: repo.remoteUrl,
                    lastModified: repo.lastModified,
                    isConfigured: true
                )
                repositories[index] = updated
            }
            Haptics.success()
        } catch {
            errorMessage = "Failed to add workspace: \(error.localizedDescription)"
            showError = true
            Haptics.error()
        }
    }

    /// Add a workspace, start it, and return it for connection
    func addAndStartWorkspace(_ repo: DiscoveredRepository) async -> (RemoteWorkspace, String)? {
        loadingRepoId = repo.id
        defer { loadingRepoId = nil }

        do {
            // Add the workspace
            let workspace = try await managerService.addWorkspace(path: repo.path, name: repo.name)

            // Mark as configured in local state
            if let index = repositories.firstIndex(where: { $0.id == repo.id }) {
                let updated = DiscoveredRepository(
                    name: repo.name,
                    path: repo.path,
                    remoteUrl: repo.remoteUrl,
                    lastModified: repo.lastModified,
                    isConfigured: true
                )
                repositories[index] = updated
            }

            // Start a session for the workspace if none active
            if !workspace.hasActiveSession {
                _ = try await managerService.startSession(workspaceId: workspace.id)
            }

            // Refresh workspace to get updated sessions
            let updatedWorkspaces = try await managerService.listWorkspaces()
            let runningWorkspace = updatedWorkspaces.first(where: { $0.id == workspace.id }) ?? workspace

            // Get the host from the manager service
            guard let host = managerService.currentHost else {
                errorMessage = "Manager host not available"
                showError = true
                Haptics.error()
                return nil
            }

            Haptics.success()
            return (runningWorkspace, host)
        } catch {
            errorMessage = "Failed to add workspace: \(error.localizedDescription)"
            showError = true
            Haptics.error()
            return nil
        }
    }

    /// Start and connect to an already-configured workspace
    func startAndConnect(_ repo: DiscoveredRepository) async -> (RemoteWorkspace, String)? {
        guard repo.isConfigured else {
            errorMessage = "Repository is not configured as a workspace"
            showError = true
            return nil
        }

        loadingRepoId = repo.id
        defer { loadingRepoId = nil }

        do {
            // Find the workspace by path
            let workspaces = try await managerService.listWorkspaces()
            guard let workspace = workspaces.first(where: { $0.path == repo.path }) else {
                errorMessage = "Workspace not found. It may have been removed."
                showError = true
                Haptics.error()
                return nil
            }

            // Start a session for the workspace if none active
            if !workspace.hasActiveSession {
                _ = try await managerService.startSession(workspaceId: workspace.id)
            }

            // Refresh workspace to get updated sessions
            let updatedWorkspaces = try await managerService.listWorkspaces()
            let runningWorkspace = updatedWorkspaces.first(where: { $0.id == workspace.id }) ?? workspace

            // Get the host from the manager service
            guard let host = managerService.currentHost else {
                errorMessage = "Manager host not available"
                showError = true
                Haptics.error()
                return nil
            }

            Haptics.success()
            return (runningWorkspace, host)
        } catch {
            errorMessage = "Failed to connect: \(error.localizedDescription)"
            showError = true
            Haptics.error()
            return nil
        }
    }
}

// MARK: - Preview

#Preview {
    RepositoryDiscoveryView()
}
