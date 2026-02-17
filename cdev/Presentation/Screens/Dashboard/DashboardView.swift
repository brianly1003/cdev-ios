import SwiftUI

/// Main dashboard view - compact, developer-focused UI
/// Hero: Terminal output, quick actions, minimal chrome
struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    @StateObject private var workspaceStore = WorkspaceStore.shared
    @StateObject private var workspaceStateManager = WorkspaceStateManager.shared
    @StateObject private var quickSwitcherViewModel: QuickSwitcherViewModel

    // Voice input (beta feature)
    @StateObject private var voiceInputViewModel = VoiceInputViewModel()
    @StateObject private var voiceInputSettings = VoiceInputSettingsStore.shared

    // Observe explorerViewModel directly for file content updates (nested ObservableObject workaround)
    @ObservedObject private var explorerViewModel: ExplorerViewModel
    @State private var showSettings = false
    @State private var showDebugLogs = false
    @State private var showWorkspaceSwitcher = false
    @State private var showReconnectedToast = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showCameraPermissionAlert = false
    @State private var previousConnectionState: ConnectionState?
    @FocusState private var isInputFocused: Bool
    @State private var isTextFieldEditing: Bool = false  // Tracks actual editing state from UITextView
    @State private var actionBarHeight: CGFloat = 60  // Tracks input bar height for keyboard button positioning

    // File viewer presentation (hoisted from ExplorerView to avoid TabView recreation issues)
    @State private var fileToDisplay: FileEntry?
    @State private var isFileDismissing = false

    // Diff viewer presentation (hoisted from SourceControlView to avoid TabView recreation issues)
    @State private var diffFileToDisplay: GitFileEntry?

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _quickSwitcherViewModel = StateObject(wrappedValue: QuickSwitcherViewModel(workspaceStore: WorkspaceStore.shared))
        // Initialize ObservedObject for nested explorerViewModel to observe its @Published properties
        _explorerViewModel = ObservedObject(wrappedValue: viewModel.explorerViewModel)
    }

    /// Toolkit items - Easy to extend! Just add more .add() calls
    /// See PredefinedTool enum for available tools, or use .addCustom() for new ones
    private var toolkitItems: [ToolkitItem] {
        var builder = ToolkitBuilder()
            .add(.settings { showSettings = true })
            .add(.refresh { Task { await viewModel.refreshStatus() } })
            .add(.clearLogs { Task { await viewModel.clearLogs() } })
            .add(.debugLogs { showDebugLogs = true })

        // Add reconnect button when disconnected/failed
        if !viewModel.connectionState.isConnected {
            builder = builder.add(.reconnect {
                Task { await viewModel.retryConnection() }
            })
        }

        return builder.build()
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    // Compact status bar with workspace switcher
                    // Hide session ID when pending temp session (waiting for session_id_resolved)
                    StatusBarView(
                        connectionState: viewModel.connectionState,
                        claudeState: viewModel.claudeState,
                        repoName: viewModel.agentStatus.repoName,
                        sessionId: viewModel.isPendingTempSession ? nil : viewModel.agentStatus.sessionId,
                        isWatchingSession: viewModel.isWatchingSession,
                        onWorkspaceTap: { showWorkspaceSwitcher = true },
                        externalSessionManager: viewModel.externalSessionManager
                    )

                    // Connection status banner (non-blocking)
                    // Shows when disconnected/connecting/reconnecting/failed
                    ConnectionBanner(
                        connectionState: viewModel.connectionState,
                        onRetry: {
                            Task { await viewModel.retryConnection() }
                        },
                        onCancel: {
                            viewModel.cancelConnection()
                        }
                    )

                    // Pending interaction banner (if any) - NOT for PTY permissions
                    // PTY permissions are shown at the bottom via PTYPermissionPanel
                    if let interaction = viewModel.pendingInteraction,
                       !interaction.isPTYMode {
                        InteractionBanner(
                            interaction: interaction,
                            onApprove: { Task { await viewModel.approvePermission() } },
                            onDeny: { Task { await viewModel.denyPermission() } },
                            onAnswer: { response in Task { await viewModel.answerQuestion(response) } },
                            onPTYResponse: { key in Task { await viewModel.respondToPTYPermission(key: key) } }
                        )
                    }

                    // Search header (only visible when search is active)
                    if viewModel.terminalSearchState.isActive && viewModel.selectedTab == .logs {
                        TerminalSearchHeader(state: viewModel.terminalSearchState)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onChange(of: viewModel.terminalSearchState.searchText) { _, _ in
                                viewModel.performSearch()
                            }
                            .onChange(of: viewModel.terminalSearchState.activeFilters) { _, _ in
                                viewModel.performSearch()
                            }
                    }

                    // Tab selector
                    CompactTabSelector(
                        selectedTab: $viewModel.selectedTab,
                        logsCount: viewModel.logsCountForBadge,
                        diffsCount: viewModel.sourceControlViewModel.state.totalCount,
                        showSearchButton: viewModel.selectedTab == .logs,
                        isSearchActive: viewModel.terminalSearchState.isActive,
                        onSearchTap: {
                            withAnimation(Animations.stateChange) {
                                viewModel.terminalSearchState.isActive.toggle()
                            }
                        }
                    )

                    // Content - tap to dismiss keyboard
                    TabView(selection: $viewModel.selectedTab) {
                        // Extract search values here so SwiftUI tracks them as dependencies
                        // This ensures LogListView re-renders when search state changes
                        let searchText = viewModel.terminalSearchState.searchText
                        let matchingIds = viewModel.terminalSearchState.matchingElementIds
                        let matchIndex = viewModel.terminalSearchState.currentMatchIndex

                        LogListView(
                            logs: viewModel.logs,
                            elements: viewModel.chatElements,  // NEW: Elements API UI
                            onClear: { Task { await viewModel.clearLogs() } },
                            isVisible: viewModel.selectedTab == .logs,
                            isInputFocused: isTextFieldEditing,
                            isStreaming: viewModel.isStreaming,
                            spinnerMessage: viewModel.spinnerMessage,
                            hasMoreMessages: viewModel.messagesHasMore,
                            isLoadingMore: viewModel.isLoadingMoreMessages,
                            onLoadMore: { await viewModel.loadMoreMessages() },
                            searchText: searchText,
                            matchingElementIds: matchingIds,
                            currentMatchIndex: matchIndex,
                            scrollRequest: viewModel.scrollRequest
                        )
                        // Extra bottom inset when attachment strip is visible (uses safeAreaInset for transparent overlay)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if !viewModel.attachedImages.isEmpty {
                                Color.clear.frame(height: 80)  // Invisible spacer for scroll content
                            }
                        }
                        .tag(DashboardTab.logs)

                        // Source Control (Mini Repo Management)
                        SourceControlView(
                            viewModel: viewModel.sourceControlViewModel,
                            onRefresh: {
                                await viewModel.sourceControlViewModel.refresh()
                            },
                            scrollRequest: viewModel.scrollRequest,
                            onPresentDiff: { file in
                                // Present diff viewer (hoisted here to avoid TabView recreation issues)
                                AppLogger.log("[DashboardView] Presenting diff viewer for '\(file.path)'")
                                diffFileToDisplay = file
                            }
                        )
                        .tag(DashboardTab.diffs)

                        // File Explorer
                        ExplorerView(
                            viewModel: viewModel.explorerViewModel,
                            scrollRequest: viewModel.scrollRequest,
                            onPresentFile: { file in
                                // Present file viewer (hoisted here to avoid TabView recreation issues)
                                guard !isFileDismissing && fileToDisplay == nil else {
                                    AppLogger.log("[DashboardView] Skipping file presentation - dismissing or already showing")
                                    return
                                }
                                AppLogger.log("[DashboardView] Presenting file viewer for '\(file.path)'")
                                fileToDisplay = file
                            }
                        )
                        .tag(DashboardTab.explorer)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .dismissKeyboardOnTap()
                    .background(ColorSystem.terminalBg)
                    // Tap-outside-to-dismiss backdrop for attachment menu
                    .overlay {
                        if viewModel.showAttachmentMenu {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.showAttachmentMenu = false
                                }
                        }
                    }

                    // Action bar - only show on logs tab
                    // Uses manual keyboard handling, so ignore SwiftUI's automatic keyboard avoidance
                    if viewModel.selectedTab == .logs {
                        VStack(spacing: 0) {
                            // PTY Permission Panel - shown above input for PTY mode permissions
                            // Positioned here for easy access while typing
                            if let interaction = viewModel.pendingInteraction,
                               interaction.isPTYMode {
                                PTYPermissionPanel(
                                    interaction: interaction,
                                    onResponse: { key in
                                        Task { await viewModel.respondToPTYPermission(key: key) }
                                    },
                                    onDismiss: {
                                        viewModel.dismissPendingInteraction()
                                    }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            ActionBarView(
                                claudeState: viewModel.claudeState,
                                promptText: $viewModel.promptText,
                                isBashMode: $viewModel.isBashMode,
                                isLoading: viewModel.isLoading,
                                isFocused: $isInputFocused,
                                isEditing: $isTextFieldEditing,  // Actual editing state from UITextView
                                hasPTYPermission: viewModel.pendingInteraction?.isPTYMode ?? false,
                                onSend: { Task { await viewModel.sendPrompt() } },
                                onStop: { Task { await viewModel.stopClaude() } },
                                onToggleBashMode: { viewModel.toggleBashMode() },
                                onFocusChange: nil,
                                // Agent selector - switch between Claude/Codex/etc.
                                selectedRuntime: $viewModel.selectedSessionRuntime,
                                // Runtime switch orchestration is handled in DashboardViewModel.selectedSessionRuntime didSet.
                                onAgentChanged: nil,
                                // Voice input (beta feature - only passed when enabled)
                                voiceInputViewModel: voiceInputSettings.isEnabled ? voiceInputViewModel : nil,
                                // Image attachments
                                attachedImages: $viewModel.attachedImages,
                                showAttachmentMenu: $viewModel.showAttachmentMenu,
                                onAttachImage: { viewModel.showAttachmentMenu = true },
                                onRemoveImage: { id in viewModel.removeAttachedImage(id) },
                                onRetryUpload: { id in Task { await viewModel.retryUpload(id) } },
                                onCameraCapture: {
                                    AppLogger.log("[Dashboard] Camera capture requested")
                                    Task { await handleCameraRequest() }
                                },
                                onPhotoLibrary: {
                                    AppLogger.log("[Dashboard] Photo library requested")
                                    showPhotoPicker = true
                                },
                                onScreenshotCapture: {
                                    AppLogger.log("[Dashboard] Screenshot capture requested")
                                    captureScreenshot()
                                },
                                canAttachMoreImages: viewModel.canAttachMoreImages
                            )
                            // Track action bar height for keyboard dismiss button positioning
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ActionBarHeightKey.self,
                                        value: geo.size.height
                                    )
                                }
                            )
                            .onPreferenceChange(ActionBarHeightKey.self) { height in
                                actionBarHeight = height
                            }

                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // Use UITextView editing state (more reliable than FocusState for UIViewRepresentable)
                .ignoresSafeArea(.keyboard, edges: isTextFieldEditing ? .bottom : [])
                .background(ColorSystem.terminalBg)
                // Floating keyboard dismiss button - tracks keyboard and positions itself
                // Only add action bar height offset on logs tab (which has the action bar)
                // Note: actionBarHeight already includes agent selector bar height (measured via GeometryReader)
                .overlay(alignment: .trailing) {
                    FloatingKeyboardDismissButton(
                        inputBarHeight: viewModel.selectedTab == .logs ? actionBarHeight : 0,
                        promptText: viewModel.selectedTab == .logs ? viewModel.promptText : ""
                        // isBashMode no longer needed - bash indicator is part of agent selector bar
                    )
                    .padding(.trailing, Spacing.md)
                }
                .animation(Animations.stateChange, value: viewModel.selectedTab)
                // Dismiss keyboard and reset search when switching tabs
                .onChange(of: viewModel.selectedTab) { oldTab, newTab in
                    // Dismiss keyboard globally
                    hideKeyboard()
                    isInputFocused = false
                    isTextFieldEditing = false

                    // Reset Terminal search when leaving logs tab
                    if oldTab == .logs && viewModel.terminalSearchState.isActive {
                        viewModel.terminalSearchState.dismiss()
                    }

                    // Reset Explorer search when leaving explorer tab
                    if oldTab == .explorer {
                        viewModel.explorerViewModel.clearSearch()
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(Constants.Brand.appName)
                            .font(Typography.title3)
                            .fontWeight(.bold)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showDebugLogs) {
                    AdminToolsView()
                        .responsiveSheet()
                }
                .fullScreenCover(isPresented: $showSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $viewModel.showSessionPicker) {
                    SessionPickerView(
                        sessions: viewModel.sessions,
                        currentSessionId: viewModel.agentStatus.sessionId,
                        workspaceId: viewModel.currentWorkspaceId,
                        hasMore: viewModel.sessionsHasMore,
                        isLoadingMore: viewModel.isLoadingMoreSessions,
                        agentRepository: viewModel.agentRepository,
                        selectedRuntime: $viewModel.selectedSessionRuntime,
                        onSelect: { sessionId in
                            Task { await viewModel.resumeSession(sessionId) }
                        },
                        onDelete: { sessionId in
                            Task { await viewModel.deleteSession(sessionId) }
                        },
                        onDeleteAll: {
                            Task { await viewModel.deleteAllSessions() }
                        },
                        onLoadMore: {
                            Task { await viewModel.loadMoreSessions() }
                        },
                        onDismiss: { viewModel.showSessionPicker = false }
                    )
                }
                // Photo Library Picker
                .sheet(isPresented: $showPhotoPicker) {
                    PhotoLibraryPicker(
                        maxSelections: max(0, AttachedImageState.Constants.maxImages - viewModel.attachedImages.count),
                        onImagesSelected: { images in
                            showPhotoPicker = false
                            for image in images {
                                Task { await viewModel.attachImage(image, source: .photoLibrary) }
                            }
                        },
                        onDismiss: { showPhotoPicker = false }
                    )
                }
                // Camera Capture
                .fullScreenCover(isPresented: $showCamera) {
                    CameraImagePicker(
                        onImageCaptured: { image in
                            showCamera = false
                            Task { await viewModel.attachImage(image, source: .camera) }
                        },
                        onDismiss: { showCamera = false }
                    )
                }
                // Camera Permission Alert
                .alert("Camera Access Required", isPresented: $showCameraPermissionAlert) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Please allow camera access in Settings to take photos.")
                }
                .fullScreenCover(isPresented: $showWorkspaceSwitcher) {
                    WorkspaceManagerView(
                        onConnectToWorkspace: { workspace, host in
                            AppLogger.log("[DashboardView] onConnectToWorkspace called: workspace=\(workspace.name), host=\(host)")
                            AppLogger.log("[DashboardView] onConnectToWorkspace: hasActiveSession=\(workspace.hasActiveSession)")
                            let result = await viewModel.connectToRemoteWorkspace(workspace, host: host)
                            AppLogger.log("[DashboardView] onConnectToWorkspace: connectToRemoteWorkspace returned \(result)")
                            return result
                        },
                        onDisconnect: {
                            await viewModel.disconnect()
                        },
                        showDismissButton: true
                    )
                }
                // File Viewer (hoisted from ExplorerView to avoid TabView recreation issues)
                .sheet(item: $fileToDisplay, onDismiss: {
                    AppLogger.log("[DashboardView] FileViewer onDismiss called")
                    isFileDismissing = false
                    explorerViewModel.closeFile()
                }) { file in
                    FileViewerView(
                        file: file,
                        content: explorerViewModel.fileContent,
                        isLoading: explorerViewModel.isLoadingFile,
                        onDismiss: {
                            AppLogger.log("[DashboardView] FileViewerView onDismiss - dismissing cover")
                            isFileDismissing = true
                            fileToDisplay = nil
                        }
                    )
                }
                // Diff Viewer (hoisted from SourceControlView to avoid TabView recreation issues)
                .sheet(item: $diffFileToDisplay) { file in
                    DiffDetailSheet(file: file)
                }
            }

            // Floating toolkit button (AssistiveTouch-style)
            FloatingToolkitButton(items: toolkitItems) { direction in
                // Request scroll to top or bottom
                viewModel.requestScroll(direction: direction)
            }

            // Floating keyboard dismiss button is now inside ActionBarView for proper positioning

            // Reconnection toast (shown when connection is restored)
            VStack {
                ReconnectedToast(
                    isPresented: $showReconnectedToast,
                    message: "Connection restored"
                )
                .padding(.top, 60) // Below safe area
                Spacer()
            }

            // Session awareness toast (join/leave notifications) - bottom position for visibility
            VStack {
                Spacer()
                SessionAwarenessToast()
                    .padding(.bottom, 80) // Above action bar
            }

            // Copy feedback toast - bottom position
            VStack {
                Spacer()
                CopyToast()
                    .padding(.bottom, 140) // Above session toast
            }

            // ⌘K Quick Switcher overlay
            if quickSwitcherViewModel.isVisible {
                QuickSwitcherView(
                    viewModel: quickSwitcherViewModel,
                    workspaceStore: workspaceStore,
                    currentWorkspace: workspaceStore.activeWorkspace,
                    workspaceStates: workspaceStateManager.workspaceStates,
                    onSwitch: { workspace in
                        Task { await viewModel.switchWorkspace(workspace) }
                    },
                    onDismiss: {
                        quickSwitcherViewModel.hide()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(1000)  // Above everything else
            }

            // Voice input overlay (beta feature)
            if voiceInputViewModel.showOverlay {
                VoiceInputOverlay(
                    viewModel: voiceInputViewModel,
                    onDismiss: {
                        voiceInputViewModel.dismissOverlay()
                    }
                )
                .transition(.opacity)
                .zIndex(2000)  // Above quick switcher
            }
        }
        .animation(Animations.stateChange, value: voiceInputViewModel.showOverlay)
        .errorAlert($viewModel.error)
        .onAppear {
            AppLogger.log("[DashboardView] onAppear - UI should be interactive now")
            previousConnectionState = viewModel.connectionState

            // Connect voice input completion to prompt text
            voiceInputViewModel.onTranscriptionComplete = { transcription in
                if viewModel.promptText.isEmpty {
                    viewModel.promptText = transcription
                } else {
                    viewModel.promptText += " " + transcription
                }
            }
        }
        // Track connection state changes for reconnection toast
        .onChange(of: viewModel.connectionState) { oldState, newState in
            // Show toast when transitioning from disconnected/reconnecting to connected
            let wasDisconnected = !oldState.isConnected
            let isNowConnected = newState.isConnected

            if wasDisconnected && isNowConnected {
                withAnimation(Animations.bannerTransition) {
                    showReconnectedToast = true
                }
                Haptics.success()
            }
        }
        // Navigate to workspace list when session fails (e.g., user declined trust_folder)
        .onChange(of: viewModel.shouldShowWorkspaceList) { _, shouldShow in
            if shouldShow {
                // Reset the flag immediately to prevent re-triggering
                viewModel.shouldShowWorkspaceList = false
                // Show the workspace switcher
                showWorkspaceSwitcher = true
            }
        }
        .task(priority: .utility) {
            AppLogger.log("[DashboardView] .task started - waiting 500ms before refreshStatus")
            // Delay to let UI become fully interactive first
            // This prevents hang when user tries to tap during initial load
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            AppLogger.log("[DashboardView] .task - calling refreshStatus")
            await viewModel.refreshStatus()
            AppLogger.log("[DashboardView] .task completed")
        }
        // iPad keyboard shortcuts (⌘F to search, Escape to dismiss)
        .focusable()
        .onKeyPress(phases: .down) { keyPress in
            // ⌘F to activate search when on Terminal tab
            if keyPress.key.character == "f" && keyPress.modifiers.contains(.command) && viewModel.selectedTab == .logs {
                withAnimation(Animations.stateChange) {
                    viewModel.terminalSearchState.isActive = true
                }
                return .handled
            }
            // Escape to dismiss search
            if keyPress.key == .escape && viewModel.terminalSearchState.isActive {
                withAnimation(Animations.stateChange) {
                    viewModel.terminalSearchState.dismiss()
                }
                return .handled
            }
            return .ignored
        }
        // Quick Switcher keyboard shortcuts (⌘K, ⌘1-9, arrows)
        .quickSwitcherKeyboardShortcuts(
            isVisible: quickSwitcherViewModel.isVisible,
            onToggle: {
                withAnimation(Animations.stateChange) {
                    if quickSwitcherViewModel.isVisible {
                        quickSwitcherViewModel.hide()
                    } else {
                        quickSwitcherViewModel.show()
                    }
                }
                Haptics.selection()
            },
            onQuickSelect: { index in
                if let workspace = quickSwitcherViewModel.selectByShortcut(index: index) {
                    Task { await viewModel.switchWorkspace(workspace) }
                    quickSwitcherViewModel.hide()
                    Haptics.success()
                }
            },
            onMoveUp: {
                quickSwitcherViewModel.moveSelectionUp()
            },
            onMoveDown: {
                quickSwitcherViewModel.moveSelectionDown()
            },
            onSelectCurrent: {
                if let workspace = quickSwitcherViewModel.selectedWorkspace {
                    Task { await viewModel.switchWorkspace(workspace) }
                    quickSwitcherViewModel.hide()
                    Haptics.selection()
                }
            },
            onEscape: {
                quickSwitcherViewModel.hide()
                Haptics.light()
            }
        )
        // Update workspace state manager when connection or Claude state changes
        .onChange(of: viewModel.connectionState) { _, newState in
            if let activeId = workspaceStore.activeWorkspaceId {
                workspaceStateManager.updateConnection(
                    workspaceId: activeId,
                    isConnected: newState.isConnected
                )
            }
        }
        .onChange(of: viewModel.claudeState) { _, newState in
            if let activeId = workspaceStore.activeWorkspaceId {
                workspaceStateManager.updateClaudeState(
                    workspaceId: activeId,
                    claudeState: newState
                )
            }
        }
    }

    // MARK: - Image Attachment Helpers

    /// Handle camera request with permission check
    private func handleCameraRequest() async {
        // Check if camera is available
        guard CameraImagePicker.isAvailable else {
            AppLogger.log("[Dashboard] Camera not available on this device")
            return
        }

        // Check permission status
        let status = CameraImagePicker.authorizationStatus
        switch status {
        case .authorized:
            await MainActor.run {
                showCamera = true
            }
        case .notDetermined:
            let granted = await CameraImagePicker.requestPermission()
            if granted {
                await MainActor.run {
                    showCamera = true
                }
            }
        case .denied, .restricted:
            await MainActor.run {
                showCameraPermissionAlert = true
            }
        @unknown default:
            break
        }
    }

    /// Capture a screenshot of the current screen
    private func captureScreenshot() {
        // Get the key window
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            AppLogger.log("[Dashboard] Could not get window for screenshot")
            return
        }

        // Render the window to an image
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let screenshot = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }

        AppLogger.log("[Dashboard] Screenshot captured: \(screenshot.size)")
        Haptics.success()

        // Attach the screenshot
        Task {
            await viewModel.attachImage(screenshot, source: .screenshot)
        }
    }
}

// MARK: - Pulse Terminal Status Bar

struct StatusBarView: View {
    let connectionState: ConnectionState
    let claudeState: ClaudeState
    let repoName: String?
    let sessionId: String?
    var isWatchingSession: Bool = false
    var onWorkspaceTap: (() -> Void)?
    var externalSessionManager: ExternalSessionManager?

    @StateObject private var sessionAwareness = SessionAwarenessManager.shared
    @State private var isPulsing = false
    @State private var showCopiedToast = false
    @State private var watchingPulse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                // Connection indicator with sophisticated animations
                ConnectionStatusIndicator(state: connectionState)

                Divider()
                    .frame(height: 12)
                    .background(ColorSystem.terminalBgHighlight)

                // Claude state with pulse animation
                HStack(spacing: 4) {
                    Circle()
                        .fill(ColorSystem.Status.color(for: claudeState))
                        .frame(width: 6, height: 6)
                        .shadow(
                            color: ColorSystem.Status.glow(for: claudeState),
                            radius: (isPulsing && claudeState == .running) ? 2.0 : 1.0
                        )
                        .scaleEffect(isPulsing && claudeState == .running ? 1.2 : 1.0)

                    Text(claudeState.rawValue.capitalized)
                        .font(Typography.statusLabel)
                        .foregroundStyle(ColorSystem.Status.color(for: claudeState))
                }

                // Live indicator when watching session (only when connected)
                if isWatchingSession && connectionState.isConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ColorSystem.error)
                            .frame(width: 6, height: 6)
                            .scaleEffect(watchingPulse ? 1.3 : 1.0)
                            .opacity(watchingPulse ? 0.7 : 1.0)

                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(ColorSystem.error)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(ColorSystem.error.opacity(0.15))
                    .clipShape(Capsule())

                    // Multi-device viewer count badge
                    if sessionAwareness.hasOtherViewers {
                        ViewerCountBadge(viewerCount: sessionAwareness.viewerCount)
                    }
                }

                // External sessions badge (when hook events detected)
                if let manager = externalSessionManager, manager.activeSessionCount > 0 {
                    ExternalSessionsBadge(manager: manager)
                }

                Spacer()

                // Enhanced workspace badge - shows workspace count + ⌘K hint
                EnhancedWorkspaceBadge(
                    repoName: repoName,
                    isConnected: connectionState.isConnected,
                    onTap: {
                        onWorkspaceTap?()
                        Haptics.selection()
                    }
                )
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)

            // Session ID row (always visible when connected)
            if connectionState.isConnected, let fullId = sessionId, !fullId.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .font(.system(size: 8))
                    Text(fullId)
                        .font(Typography.terminalSmall)
                        .lineLimit(1)

                    // Copy button - right after session ID
                    Button {
                        UIPasteboard.general.string = fullId
                        Haptics.light()
                        withAnimation {
                            showCopiedToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                showCopiedToast = false
                            }
                        }
                    } label: {
                        if showCopiedToast {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ColorSystem.success)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(ColorSystem.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .foregroundStyle(ColorSystem.textQuaternary)
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xxs)
            }
        }
        .background(ColorSystem.terminalBgElevated)
        .onAppear {
            isPulsing = claudeState == .running
        }
        .onChange(of: claudeState) { _, newState in
            withAnimation(newState == .running ? Animations.pulse : .none) {
                isPulsing = newState == .running
            }
        }
        .onChange(of: isWatchingSession) { _, watching in
            // Reset pulse state when watching status changes
            // This ensures animation is properly tied to current state
            watchingPulse = watching
        }
        .animation(
            isWatchingSession
                ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                : .default,
            value: watchingPulse
        )
    }
}

// MARK: - Pulse Terminal Tab Selector

struct CompactTabSelector: View {
    @Binding var selectedTab: DashboardTab
    let logsCount: Int
    let diffsCount: Int
    var showSearchButton: Bool = false
    var isSearchActive: Bool = false
    var onSearchTap: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }

    private var tabCount: CGFloat {
        CGFloat(DashboardTab.allCases.count)
    }

    private var selectedIndex: CGFloat {
        CGFloat(DashboardTab.allCases.firstIndex(of: selectedTab) ?? 0)
    }

    private func badgeCount(for tab: DashboardTab) -> Int {
        switch tab {
        case .logs: return logsCount
        case .diffs: return diffsCount
        case .explorer: return 0  // No badge for explorer
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Search button (only for Terminal tab)
            if showSearchButton {
                Button {
                    onSearchTap?()
                    Haptics.selection()
                } label: {
                    Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSearchActive ? ColorSystem.primary : ColorSystem.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            // Tab buttons
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(Animations.tabSlide) {
                        selectedTab = tab
                    }
                    Haptics.selection()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))

                        Text(tab.rawValue)
                            .font(Typography.tabLabel)

                        // Badge with glow when selected
                        let count = badgeCount(for: tab)
                        if count > 0 {
                            Text("\(min(count, 99))\(count > 99 ? "+" : "")")
                                .font(Typography.badge)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    selectedTab == tab
                                        ? ColorSystem.primary.opacity(0.2)
                                        : ColorSystem.terminalBgHighlight
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)  // Fill container height
                    .foregroundStyle(selectedTab == tab ? ColorSystem.primary : ColorSystem.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // iPad keyboard hint
            if !isCompact && showSearchButton && !isSearchActive {
                Text("⌘F")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ColorSystem.textQuaternary)
                    .padding(.trailing, Spacing.xs)
            }
        }
        .frame(height: 32)  // Fixed height for consistent tab bar sizing
        .background(ColorSystem.terminalBgElevated)
        .overlay(alignment: .bottom) {
            // Animated selection indicator with glow
            GeometryReader { geo in
                // Guard against invalid geometry during layout transitions
                if geo.size.width > 50 {
                    // Adjust for search button width
                    let searchButtonWidth: CGFloat = showSearchButton ? 32 : 0
                    let availableWidth = max(1, geo.size.width - searchButtonWidth - (isCompact ? 0 : 30))
                    let tabWidth = availableWidth / tabCount
                    Rectangle()
                        .fill(ColorSystem.primary)
                        .frame(width: tabWidth, height: 2)
                        .shadow(color: ColorSystem.primaryGlow, radius: 4, y: 0)
                        .offset(x: searchButtonWidth + selectedIndex * tabWidth)
                        .animation(Animations.tabSlide, value: selectedTab)
                }
            }
            .frame(height: 2)
        }
    }
}

// MARK: - Built-in Commands

struct BuiltInCommand: Identifiable {
    let id: String
    let command: String
    let description: String
    let icon: String

    static let all: [BuiltInCommand] = [
        BuiltInCommand(id: "resume", command: "/resume", description: "Resume a previous session", icon: "arrow.uturn.backward"),
        BuiltInCommand(id: "new", command: "/new", description: "Start a new session", icon: "plus.circle"),
        BuiltInCommand(id: "clear", command: "/clear", description: "Clear terminal output", icon: "trash"),
        BuiltInCommand(id: "help", command: "/help", description: "Show available commands", icon: "questionmark.circle"),
    ]

    /// Filter commands based on input
    static func matching(_ input: String) -> [BuiltInCommand] {
        guard input.hasPrefix("/") else { return [] }
        let query = input.lowercased()
        if query == "/" {
            return all
        }
        return all.filter { $0.command.lowercased().hasPrefix(query) }
    }
}

// MARK: - Command Suggestions View

struct CommandSuggestionsView: View {
    let commands: [BuiltInCommand]
    let onSelect: (String) -> Void

    /// Height per row (content + padding + divider)
    private let rowHeight: CGFloat = 50
    /// Maximum visible items before scrolling
    private let maxVisibleItems: Int = 4

    /// Calculate the view height based on command count
    private var viewHeight: CGFloat {
        let itemCount = min(commands.count, maxVisibleItems)
        return CGFloat(itemCount) * rowHeight
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(commands) { cmd in
                    Button {
                        onSelect(cmd.command)
                        Haptics.selection()
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: cmd.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(ColorSystem.primary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cmd.command)
                                    .font(Typography.terminal)
                                    .foregroundStyle(ColorSystem.textPrimary)

                                Text(cmd.description)
                                    .font(Typography.caption1)
                                    .foregroundStyle(ColorSystem.textTertiary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if cmd.id != commands.last?.id {
                        Divider()
                            .background(ColorSystem.terminalBgHighlight)
                    }
                }
            }
        }
        .frame(height: viewHeight)
        .scrollIndicators(commands.count > maxVisibleItems ? .visible : .hidden)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorSystem.terminalBgElevated)
                .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ColorSystem.terminalBgHighlight, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Pulse Terminal Action Bar

struct ActionBarView: View {
    let claudeState: ClaudeState
    @Binding var promptText: String
    @Binding var isBashMode: Bool
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    @Binding var isEditing: Bool  // Actual editing state from UITextView (more reliable than FocusState)
    var hasPTYPermission: Bool = false  // Hide stop button when PTY permission panel is showing
    let onSend: () -> Void
    let onStop: () -> Void
    let onToggleBashMode: () -> Void
    var onFocusChange: ((Bool) -> Void)?  // Callback to update focus state (workaround for FocusState limitation)

    // Agent selector - switch between Claude/Codex/etc.
    @Binding var selectedRuntime: AgentRuntime
    var onAgentChanged: ((AgentRuntime) -> Void)?

    // Voice input (optional - beta feature)
    var voiceInputViewModel: VoiceInputViewModel?

    // Image attachments (optional - beta feature)
    @Binding var attachedImages: [AttachedImageState]
    var showAttachmentMenu: Binding<Bool>?
    var onAttachImage: (() -> Void)?
    var onRemoveImage: ((UUID) -> Void)?
    var onRetryUpload: ((UUID) -> Void)?
    // Individual image source callbacks
    var onCameraCapture: (() -> Void)?
    var onPhotoLibrary: (() -> Void)?
    var onScreenshotCapture: (() -> Void)?
    var canAttachMoreImages: Bool = true

    // Keyboard height tracking for proper positioning
    @State private var keyboardHeight: CGFloat = 0

    // Messenger-style action buttons collapse when focused
    // When focused: show only chevron button, hide action buttons
    // When user taps chevron: expand to show action buttons temporarily
    @State private var areActionsExpanded: Bool = false
    // Auto-show buttons after 5 seconds when text is empty and still focused
    @State private var shouldAutoShowButtons: Bool = false
    @State private var autoShowTask: Task<Void, Never>?

    // Responsive layout for iPhone/iPad
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    // MARK: - Responsive Sizing (Using ResponsiveLayout constants)

    /// Spacing between elements in the main HStack
    private var elementSpacing: CGFloat { layout.tightSpacing }

    /// Horizontal padding for the action bar container
    private var containerPadding: CGFloat { layout.smallPadding }

    /// Bash toggle button size
    private var bashButtonSize: CGFloat { layout.indicatorSize }

    /// Bash toggle icon size
    private var bashIconSize: CGFloat { layout.iconAction }

    /// Input field internal spacing
    private var inputSpacing: CGFloat { layout.tightSpacing }

    /// Input field horizontal padding
    private var inputHorizontalPadding: CGFloat { layout.smallPadding }

    /// Input field vertical padding
    private var inputVerticalPadding: CGFloat { layout.smallPadding }

    /// Clear button size
    private var clearButtonSize: CGFloat { layout.isCompact ? 24 : 28 }

    /// Send button icon size
    private var sendIconSize: CGFloat { layout.iconXLarge }

    /// Filtered commands based on current input
    private var suggestedCommands: [BuiltInCommand] {
        BuiltInCommand.matching(promptText)
    }

    /// Whether to show command suggestions
    private var showSuggestions: Bool {
        // Slash commands only activate when "/" is the first character.
        !suggestedCommands.isEmpty && promptText.hasPrefix("/")
    }

    /// Whether sending is disabled (Claude is running or waiting)
    private var isSendDisabled: Bool {
        promptText.isBlank || isLoading || claudeState == .running
    }

    /// Show stop indicator when Claude is running/waiting (replaces send button)
    private var shouldShowStopIndicator: Bool {
        (claudeState == .running || claudeState == .waiting) && !hasPTYPermission
    }

    /// Placeholder text based on Claude state and bash mode
    private var placeholderText: String {
        if claudeState == .running {
            return "\(selectedRuntime.displayName) is running..."
        }
        return isBashMode ? "Run bash command..." : "Ask \(selectedRuntime.displayName)..."
    }

    /// Whether any images are being uploaded
    private var isUploadingImages: Bool {
        attachedImages.contains { $0.isUploading }
    }

    /// Whether any uploads have failed
    private var hasFailedUploads: Bool {
        attachedImages.contains { $0.canRetry }
    }

    /// Messenger-style: Show action buttons when:
    /// - NOT focused (default state)
    /// - Manually expanded via chevron tap
    /// - Empty text AND 5-second timer has elapsed (auto-show)
    private var shouldShowActionButtons: Bool {
        !isEditing || areActionsExpanded || (promptText.isEmpty && shouldAutoShowButtons)
    }

    /// Show expand chevron when focused and actions are collapsed
    /// Hide chevron when buttons are visible (manually expanded or auto-shown)
    private var shouldShowExpandChevron: Bool {
        isEditing && !areActionsExpanded && !(promptText.isEmpty && shouldAutoShowButtons)
    }

    /// Dynamic offset for floating popups - accounts for agent selector bar height
    private var popupOffset: CGFloat {
        let baseOffset: CGFloat = -64  // Input row height (~56pt) + gap (~8pt)
        let agentSelectorHeight: CGFloat = -28  // Agent selector bar always visible (~24pt + padding)
        return baseOffset + agentSelectorHeight
    }

    // MARK: - Timer Helpers

    /// Start 5-second timer to auto-show buttons when text is empty
    private func startAutoShowTimer() {
        cancelAutoShowTimer()
        autoShowTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(Animations.stateChange) {
                    shouldAutoShowButtons = true
                }
            }
        }
    }

    /// Cancel the auto-show timer
    private func cancelAutoShowTimer() {
        autoShowTask?.cancel()
        autoShowTask = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: elementSpacing) {
                // Messenger-style: Expand chevron when focused (shows ">" to expand action buttons)
                if shouldShowExpandChevron {
                    Button {
                        withAnimation(Animations.stateChange) {
                            areActionsExpanded = true
                            // Close attachment menu when expanding (reset to default state)
                            showAttachmentMenu?.wrappedValue = false
                        }
                        Haptics.light()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: bashIconSize, weight: .semibold))
                            .foregroundStyle(ColorSystem.primary)
                            .frame(width: bashButtonSize, height: bashButtonSize)
                            .background(ColorSystem.terminalBgHighlight)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Action buttons group - hidden when focused (Messenger-style)
                if shouldShowActionButtons {
                    // Image attach button (shown when onAttachImage is provided)
                    if let menuBinding = showAttachmentMenu {
                        ImageAttachButton(
                            attachedCount: attachedImages.count,
                            isUploading: isUploadingImages,
                            hasError: hasFailedUploads,
                            isMenuOpen: menuBinding,
                            onTap: {
                                // Toggle the menu
                                menuBinding.wrappedValue.toggle()
                            },
                            onLongPress: { onAttachImage?() }
                        )
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Voice input button (beta feature - only shown when enabled)
                    if let voiceVM = voiceInputViewModel {
                        VoiceInputButton(viewModel: voiceVM)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Bash mode toggle button - compact on iPhone
                    Button {
                        onToggleBashMode()
                    } label: {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: bashIconSize, weight: .semibold))
                            .foregroundStyle(isBashMode ? ColorSystem.success : ColorSystem.textTertiary)
                            .frame(width: bashButtonSize, height: bashButtonSize)
                            .background(isBashMode ? ColorSystem.success.opacity(0.15) : ColorSystem.terminalBgHighlight)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isBashMode ? ColorSystem.success.opacity(0.3) : .clear,
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: isBashMode ? ColorSystem.success.opacity(0.3) : .clear, radius: 4)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                // Prompt input with Pulse Terminal styling + rainbow "ultrathink" detection
                HStack(spacing: inputSpacing) {
                    RainbowTextField(
                        placeholder: placeholderText,
                        text: $promptText,
                        font: Typography.inputField,
                        axis: .vertical,
                        lineLimit: 1...3,
                        maxHeight: 120,  // ~6 lines max, then scroll
                        isDisabled: claudeState == .running,
                        onSubmit: {
                            if !isSendDisabled {
                                onSend()
                            }
                        }
                    )
                    .focused(isFocused, onFocusChange: { focused in
                        isEditing = focused
                        onFocusChange?(focused)
                    })
                    .autocorrectionDisabled(isBashMode)  // Disable autocorrection in bash mode
                    .padding(.vertical, inputVerticalPadding)
                    .padding(.leading, inputHorizontalPadding)
                    .padding(.trailing, 2)

                    // Clear button - compact, only when text is not empty
                    if !promptText.isEmpty {
                        Button {
                            promptText = ""
                            Haptics.light()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: clearButtonSize * 0.7))
                                .foregroundStyle(ColorSystem.textTertiary)
                                .frame(width: clearButtonSize, height: clearButtonSize)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Send button or stop indicator (replace when active)
                    if shouldShowStopIndicator {
                        StopButtonWithAnimation(onStop: onStop)
                            .padding(.trailing, inputHorizontalPadding)
                            .padding(.vertical, layout.tightSpacing)
                            .transition(Animations.fadeScale)
                    } else {
                        Button(action: onSend) {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .tint(ColorSystem.primary)
                                } else {
                                    Image(systemName: Icons.send)
                                        .font(.system(size: sendIconSize))
                                }
                            }
                            .foregroundStyle(isSendDisabled ? ColorSystem.textQuaternary : ColorSystem.primary)
                            .shadow(
                                color: isSendDisabled ? .clear : ColorSystem.primaryGlow,
                                radius: 4
                            )
                        }
                        .disabled(isSendDisabled)
                        .padding(.trailing, inputHorizontalPadding)
                        .padding(.vertical, layout.tightSpacing)
                        .transition(Animations.fadeScale)
                    }
                }
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(RoundedRectangle(cornerRadius: layout.indicatorSize / 2))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.indicatorSize / 2)
                        .stroke(
                            isBashMode
                                ? ColorSystem.success.opacity(isFocused.wrappedValue ? 0.6 : 0.3)
                                : (isFocused.wrappedValue ? ColorSystem.primary.opacity(0.5) : .clear),
                            lineWidth: isBashMode ? layout.borderWidthThick : layout.borderWidth
                        )
                )
            }
            .padding(.horizontal, containerPadding)
            .padding(.vertical, layout.smallPadding)

            // Cursor-style compact selector bar (always visible)
            // Shows: Agent selector | bash mode indicator (same line)
            AgentSelectorBar(
                selectedRuntime: $selectedRuntime,
                isBashMode: isBashMode,
                onAgentChanged: onAgentChanged
            )
            .padding(.horizontal, containerPadding)
            .padding(.bottom, Spacing.xs)
        }
        .background(ColorSystem.terminalBgElevated)
        // Command suggestions floating above (hidden when attachment menu is open)
        .overlay(alignment: .bottom) {
            let isAttachmentMenuOpen = showAttachmentMenu?.wrappedValue ?? false
            // Only show suggestions when attachment menu is NOT open
            if showSuggestions && !isAttachmentMenuOpen {
                CommandSuggestionsView(commands: suggestedCommands) { command in
                    promptText = command
                }
                .padding(.horizontal, containerPadding)
                .padding(.trailing, 58)  // Space for floating toolkit
                // Position just above ActionBar (dynamic - accounts for bash mode indicator)
                .offset(y: popupOffset)
                // Slide up from just below final position (feels like emerging from ActionBar top)
                .transition(.offset(y: 20).combined(with: .opacity))
                // Prevent tap-through during exit animation
                .allowsHitTesting(showSuggestions && !isAttachmentMenuOpen)
            }
        }
        // Image attachment strip floating above ActionBar (semi-transparent like popup)
        .overlay(alignment: .bottom) {
            if !attachedImages.isEmpty {
                ImageAttachmentStrip(
                    attachedImages: $attachedImages,
                    onRemove: { id in onRemoveImage?(id) },
                    onAddMore: { onAttachImage?() },
                    onRetry: { id in onRetryUpload?(id) },
                    canAddMore: canAttachMoreImages
                )
                .padding(.horizontal, containerPadding)  // Match other popup padding
                // Position just above ActionBar (same offset as other popups)
                .offset(y: popupOffset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Animations.stateChange, value: attachedImages.count)  // Animate strip appearance
        // Attachment menu popup floating above (takes priority - shows when open AND buttons visible)
        .overlay(alignment: .bottomLeading) {
            if let menuBinding = showAttachmentMenu, menuBinding.wrappedValue && shouldShowActionButtons {
                AttachmentMenuPopup(
                    onCamera: {
                        menuBinding.wrappedValue = false
                        onCameraCapture?()
                    },
                    onPhotoLibrary: {
                        menuBinding.wrappedValue = false
                        onPhotoLibrary?()
                    },
                    onScreenshot: {
                        menuBinding.wrappedValue = false
                        onScreenshotCapture?()
                    }
                )
                .padding(.leading, containerPadding)
                // Position just above ActionBar (dynamic - accounts for bash mode indicator)
                .offset(y: popupOffset)
                // Slide up from just below final position (consistent with Command suggestions)
                .transition(.offset(y: 20).combined(with: .opacity))
            }
        }
        // Only add keyboard padding when the UITextView is actively editing.
        // Keep this after popup overlays so overlays are anchored to the input bar, not the padded region.
        .padding(.bottom, isEditing ? keyboardHeight : 0)
        // Background for keyboard padding area (prevents black gap)
        .background(ColorSystem.terminalBg)
        .animation(Animations.stateChange, value: claudeState)
        .animation(Animations.stateChange, value: showSuggestions)
        .animation(Animations.stateChange, value: showAttachmentMenu?.wrappedValue)
        .animation(Animations.stateChange, value: areActionsExpanded)  // Animate manual expand/collapse
        .animation(Animations.stateChange, value: shouldAutoShowButtons)  // Animate auto-show after 5s
        .animation(Animations.stateChange, value: isEditing)  // Animate when focus changes
        .animation(Animations.stateChange, value: isBashMode)  // Animate bash mode indicator
        .animation(Animations.stateChange, value: popupOffset)  // Animate popup position when bash mode changes
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        // Dismiss keyboard when Claude starts running - don't auto-focus when done
        .onChange(of: claudeState) { _, newState in
            if newState == .running {
                isFocused.wrappedValue = false
            }
        }
        // Messenger-style: Collapse action buttons when input gains focus
        .onChange(of: isEditing) { oldValue, newValue in
            AppLogger.log("[ActionBar] isEditing changed: \(oldValue) -> \(newValue)")
            // Reset keyboard offset when editing ends.
            if !newValue {
                keyboardHeight = 0
            }
            if newValue {
                // Focus gained - collapse action buttons (show chevron)
                // Close attachment menu immediately when chevron appears
                withAnimation(Animations.stateChange) {
                    areActionsExpanded = false
                    shouldAutoShowButtons = false
                    showAttachmentMenu?.wrappedValue = false
                }
                AppLogger.log("[ActionBar] Focus gained - reset states, promptText.isEmpty=\(promptText.isEmpty)")
                // Start timer if text is already empty
                if promptText.isEmpty {
                    startAutoShowTimer()
                    AppLogger.log("[ActionBar] Started 5-second timer")
                }
            } else {
                // Focus lost - cancel timer and reset states
                cancelAutoShowTimer()
                shouldAutoShowButtons = false
                // Also close menu when focus is lost
                showAttachmentMenu?.wrappedValue = false
                AppLogger.log("[ActionBar] Focus lost - reset states")
            }
        }
        // Messenger-style: Start/cancel 5-second timer based on text content
        .onChange(of: promptText) { oldValue, newValue in
            guard isEditing else { return }

            if newValue.isEmpty && !oldValue.isEmpty {
                // Text became empty - start 5-second timer to show buttons
                startAutoShowTimer()
            } else if !newValue.isEmpty {
                // Text has content - cancel timer and hide buttons
                cancelAutoShowTimer()
                shouldAutoShowButtons = false
                areActionsExpanded = false
            }
        }
        // Track keyboard height for positioning above keyboard
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            // Only track keyboard when this input is actively editing
            guard isEditing else { return }
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // Subtract safe area bottom since we're inside the safe area
            let safeAreaBottom = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first?.safeAreaInsets.bottom ?? 0
            keyboardHeight = keyboardFrame.height - safeAreaBottom
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }
}

// MARK: - Enhanced Workspace Badge

/// Enhanced workspace badge with workspace count and ⌘K hint
/// Shows total workspaces and makes it obvious the badge is tappable
private struct EnhancedWorkspaceBadge: View {
    let repoName: String?
    let isConnected: Bool
    let onTap: () -> Void

    @StateObject private var workspaceStore = WorkspaceStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                // Folder icon with subtle glow when connected
                Image(systemName: "folder.fill")
                    .font(.system(size: layout.iconMedium))
                    .foregroundStyle(isConnected ? ColorSystem.primary : ColorSystem.textTertiary)
                    .shadow(color: isConnected ? ColorSystem.primaryGlow : .clear, radius: 2)

                // Workspace name
                if let repoName = repoName, !repoName.isEmpty {
                    Text(repoName)
                        .font(Typography.statusLabel)
                        .lineLimit(1)
                } else {
                    Text("No Workspace")
                        .font(Typography.statusLabel)
                }

                // Workspace count badge (if more than 1 workspace)
                if workspaceStore.workspaces.count > 1 {
                    Text("\(workspaceStore.workspaces.count)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(ColorSystem.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(ColorSystem.primary.opacity(0.15))
                        .clipShape(Circle())
                }

                // Chevron + keyboard hint (iPad only)
                if !isCompact {
                    HStack(spacing: 2) {
                        Text("⌘K")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ColorSystem.textQuaternary)
                    }
                } else {
                    // Chevron only on iPhone
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                }
            }
            .foregroundStyle(isConnected ? ColorSystem.textSecondary : ColorSystem.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ColorSystem.terminalBgHighlight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isConnected ? ColorSystem.primary.opacity(0.2) : .clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cursor-Style Agent Selector Bar

/// Cursor IDE-inspired compact agent selector bar
/// Ultra-minimal text-based design that sits below the input field
/// Shows: [icon] Agent Name ▼  |  [icon] bash mode enabled
struct AgentSelectorBar: View {
    @Binding var selectedRuntime: AgentRuntime
    var isBashMode: Bool = false
    var onAgentChanged: ((AgentRuntime) -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Agent color from design system
    private var agentColor: Color {
        ColorSystem.Agent.color(for: selectedRuntime)
    }

    private var sortedRuntimes: [AgentRuntime] {
        AgentRuntime.allCases.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Agent selector dropdown
            Menu {
                ForEach(sortedRuntimes) { runtime in
                    Button {
                        if selectedRuntime != runtime {
                            withAnimation(Animations.stateChange) {
                                selectedRuntime = runtime
                            }
                            onAgentChanged?(runtime)
                            Haptics.selection()
                        }
                    } label: {
                        Label {
                            Text(runtime.displayName)
                        } icon: {
                            Image(systemName: runtime.iconName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    // Agent icon with brand color
                    Image(systemName: selectedRuntime.iconName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(agentColor)

                    // Agent name
                    Text(selectedRuntime.displayName)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textSecondary)

                    // Dropdown chevron
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(ColorSystem.textTertiary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ColorSystem.terminalBgHighlight.opacity(0.6))
                )
            }
            .menuStyle(.borderlessButton)

            // Bash mode indicator (same line, right side)
            if isBashMode {
                HStack(spacing: 4) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("bash")
                        .font(Typography.terminalSmall)
                }
                .foregroundStyle(ColorSystem.success)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ColorSystem.success.opacity(0.12))
                )
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Future: Add more selectors here (model, session mode, etc.)
            // Example: "Sonnet 4.5 ▼" | "Continue ▼"
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Animations.stateChange, value: isBashMode)
    }
}

// MARK: - Stop Button with Loading Animation

/// Stop button with rotating ring animation
/// Sized to match the send button visual weight
private struct StopButtonWithAnimation: View {
    let onStop: () -> Void
    @State private var rotation: Double = 0

    var body: some View {
        Button(action: onStop) {
            ZStack {
                // Rotating ring animation
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                ColorSystem.error.opacity(0),
                                ColorSystem.error.opacity(0.3),
                                ColorSystem.error.opacity(0.6),
                                ColorSystem.error
                            ]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(rotation))

                // Stop button - smaller to fit inside ring
                Image(systemName: Icons.stop)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(ColorSystem.error)
                    .clipShape(Circle())
            }
            .shadow(color: ColorSystem.errorGlow, radius: 3)
        }
        .pressEffect()
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Viewer Count Badge (Multi-Device Awareness)

/// Badge showing number of devices viewing the same session
struct ViewerCountBadge: View {
    let viewerCount: Int
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        HStack(spacing: layout.ultraTightSpacing) {
            Image(systemName: "person.2.fill")
                .font(.system(size: layout.iconSmall - 1))

            Text("\(viewerCount)")
                .font(.system(size: layout.iconSmall - 1, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(ColorSystem.primary)
        .padding(.horizontal, layout.tightSpacing + 1)
        .padding(.vertical, layout.ultraTightSpacing)
        .background(ColorSystem.primary.opacity(0.15))
        .clipShape(Capsule())
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewerCount)
    }
}

// MARK: - Session Awareness Toast (Join/Leave Notifications)

/// Toast notification for session join/leave events
struct SessionAwarenessToast: View {
    @StateObject private var sessionAwareness = SessionAwarenessManager.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        if let notification = sessionAwareness.recentNotification {
            HStack(spacing: layout.contentSpacing) {
                // Compact icon with colored background
                Image(systemName: notification.isJoin ? "person.badge.plus" : "person.badge.minus")
                    .font(.system(size: layout.iconSmall, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: layout.indicatorSizeSmall + 4, height: layout.indicatorSizeSmall + 4)
                    .background(notification.isJoin ? ColorSystem.success : ColorSystem.warning)
                    .clipShape(Circle())

                Text(notification.message)
                    .font(layout.captionFont)
                    .foregroundStyle(ColorSystem.textSecondary)
            }
            .padding(.horizontal, layout.standardPadding)
            .padding(.vertical, layout.smallPadding)
            .background(ColorSystem.terminalBgElevated)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: layout.shadowRadius, y: 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: notification)
        }
    }
}

// MARK: - Preference Keys

/// Preference key for tracking ActionBarView height
private struct ActionBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 60
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
