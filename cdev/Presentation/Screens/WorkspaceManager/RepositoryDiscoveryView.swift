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

    /// Show debug logs sheet (for FloatingToolkit)
    @State private var showDebugLogs: Bool = false

    /// Show settings sheet (for FloatingToolkit)
    @State private var showSettings: Bool = false

    /// Scroll request (from floating toolkit force touch)
    @State private var scrollRequest: ScrollDirection?

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Toolkit items - only Debug Logs button
    private var toolkitItems: [ToolkitItem] {
        ToolkitBuilder()
            .add(.settings { showSettings = true })
            .add(.debugLogs { showDebugLogs = true })
            .build()
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    ColorSystem.terminalBg
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        // Search paths input
                        searchPathsSection
                            .padding(.horizontal, layout.standardPadding)
                            .padding(.top, layout.smallPadding)

                        // Cache status bar (only show when we have results)
                        if !viewModel.repositories.isEmpty || viewModel.lastDiscoveryResponse != nil {
                            cacheStatusBar
                                .padding(.horizontal, layout.standardPadding)
                                .padding(.vertical, Spacing.xs)
                        }

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
                    .dismissKeyboardOnTap()
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
                .sheet(isPresented: $showDebugLogs) {
                    AdminToolsView()
                        .responsiveSheet()
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .responsiveSheet()
                }
                .task {
                    // Auto-discover on appear
                    await viewModel.discover()
                }
                .onDisappear {
                    // Cancel any pending discovery when sheet is dismissed
                    viewModel.cancelDiscovery()
                }
            } // End NavigationStack

            // Floating toolkit button with Debug Logs only
            FloatingToolkitButton(items: toolkitItems) { direction in
                requestScroll(direction: direction)
            }
        } // End outer ZStack
    }

    // MARK: - Search Paths Section

    private var searchPathsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Header row with label, cache status, and Fresh Scan button
            HStack {
                Text("Search Paths")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textSecondary)

                Spacer()

                // Cache age label (left of Fresh Scan)
                if let response = viewModel.lastDiscoveryResponse, response.isCached {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                        if let age = response.cacheAgeDescription {
                            Text("Cached \(age)")
                        } else {
                            Text("Cached")
                        }
                    }
                    .font(Typography.badge)
                    .foregroundStyle(response.isCacheStale ? ColorSystem.warning : ColorSystem.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(Capsule())
                }

                // Fresh scan button
                Button {
                    Task { await viewModel.discoverFresh() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Fresh Scan")
                            .font(Typography.badge)
                    }
                    .foregroundStyle(ColorSystem.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ColorSystem.primary.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }

            // Unified text field style
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.textTertiary)
                    .frame(width: 24)

                TextField("~/Projects, ~/Code", text: $viewModel.searchPathsInput)
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.discover() }
                    }
            }
            .frame(height: layout.buttonHeight)
            .padding(.horizontal, Spacing.sm)
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

            Text("Leave empty to search default locations")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textQuaternary)
        }
    }

    // MARK: - Cache Status Bar

    private var cacheStatusBar: some View {
        HStack(spacing: Spacing.xs) {
            if let response = viewModel.lastDiscoveryResponse {
                // Background refresh indicator
                if response.isRefreshing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Updating...")
                            .font(Typography.badge)
                    }
                    .foregroundStyle(ColorSystem.primary)
                }

                Spacer()

                // Result count
                Text("\(response.count) repos")
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.textTertiary)
                .frame(width: 24)

            TextField("Search repositories...", text: $viewModel.searchText)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textPrimary)
                .autocorrectionDisabled()

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: layout.buttonHeight)
        .padding(.horizontal, Spacing.sm)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    // MARK: - Repository List

    private var repositoryList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.filteredRepositories) { repo in
                    RepositoryRowView(
                        repository: repo,
                        isLoading: viewModel.loadingRepoId == repo.id,
                        onAdd: {
                            Task { await viewModel.addWorkspace(repo) }
                        }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .id(repo.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .onChange(of: scrollRequest) { _, direction in
                guard let direction = direction else { return }
                handleScrollRequest(direction: direction, proxy: proxy)
            }
        }
    }

    // MARK: - Scroll Request Handler

    /// Request scroll to top or bottom (triggered by floating toolkit force touch)
    private func requestScroll(direction: ScrollDirection) {
        scrollRequest = direction
        // Auto-reset after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            scrollRequest = nil
        }
    }

    private func handleScrollRequest(direction: ScrollDirection, proxy: ScrollViewProxy) {
        guard !viewModel.filteredRepositories.isEmpty else { return }
        switch direction {
        case .top:
            if let firstId = viewModel.filteredRepositories.first?.id {
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(firstId, anchor: .top)
                }
            }
        case .bottom:
            if let lastId = viewModel.filteredRepositories.last?.id {
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
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
    var onAdd: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Folder icon - compact
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.warning)
                .frame(width: 20)

            // Repo info - compact
            VStack(alignment: .leading, spacing: 1) {
                Text(repository.name)
                    .font(Typography.terminal)
                    .fontWeight(.medium)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .lineLimit(1)

                Text(repository.path)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let remote = repository.repoName {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 8))
                        Text(remote)
                            .font(Typography.badge)
                    }
                    .foregroundStyle(ColorSystem.textQuaternary)
                }
            }

            Spacer(minLength: 0)

            // Loading indicator, status badge, or add button
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 28, height: 28)
            } else if repository.isConfigured {
                // Already added badge
                Text("Added")
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ColorSystem.success.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                // Add button for unconfigured repos
                Button {
                    onAdd?()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(ColorSystem.success)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, layout.standardPadding)
        .padding(.vertical, Spacing.xs)
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

    /// Last discovery response with cache metadata (observed from service)
    var lastDiscoveryResponse: DiscoveryResponse? {
        managerService.lastDiscoveryResponse
    }

    private let managerService = WorkspaceManagerService.shared
    private var refreshPollTask: Task<Void, Never>?

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

    /// Discover repositories (uses cache if available)
    /// Uses shared service state to prevent duplicate concurrent requests
    func discover() async {
        await performDiscovery(fresh: false)
    }

    /// Discover repositories with fresh scan (ignores cache)
    func discoverFresh() async {
        await performDiscovery(fresh: true)
    }

    /// Internal discovery implementation
    private func performDiscovery(fresh: Bool) async {
        guard managerService.isConnected else {
            errorMessage = "Not connected to workspace manager"
            showError = true
            return
        }

        // Cancel any existing poll task
        refreshPollTask?.cancel()
        refreshPollTask = nil

        isLoading = true

        do {
            let results = try await managerService.discoverRepositories(paths: searchPaths, fresh: fresh)
            repositories = results

            // If background refresh is in progress, start polling for updates
            if lastDiscoveryResponse?.isRefreshing == true {
                startRefreshPolling()
            }
        } catch is CancellationError {
            // Task was cancelled (e.g., sheet dismissed) - ignore silently
            AppLogger.log("[Discovery] Repository discovery cancelled")
        } catch let error as WorkspaceManagerError {
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    /// Poll for background refresh completion
    private func startRefreshPolling() {
        refreshPollTask?.cancel()
        refreshPollTask = Task {
            // Poll every 2 seconds while refresh is in progress
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

                guard !Task.isCancelled else { break }

                do {
                    let results = try await managerService.discoverRepositories(paths: searchPaths, fresh: false)
                    repositories = results

                    // Stop polling when refresh completes
                    if lastDiscoveryResponse?.isRefreshing != true {
                        AppLogger.log("[Discovery] Background refresh completed")
                        break
                    }
                } catch {
                    // Stop polling on error
                    break
                }
            }
        }
    }

    /// Cancel any pending discovery request (called when view disappears)
    func cancelDiscovery() {
        refreshPollTask?.cancel()
        refreshPollTask = nil
        managerService.cancelDiscovery()
        isLoading = false
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
