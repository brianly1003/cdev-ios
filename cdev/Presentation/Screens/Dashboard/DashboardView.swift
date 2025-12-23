import SwiftUI

/// Main dashboard view - compact, developer-focused UI
/// Hero: Terminal output, quick actions, minimal chrome
struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    @StateObject private var workspaceStore = WorkspaceStore.shared
    @StateObject private var workspaceStateManager = WorkspaceStateManager.shared
    @StateObject private var quickSwitcherViewModel: QuickSwitcherViewModel
    @State private var showSettings = false
    @State private var showDebugLogs = false
    @State private var showWorkspaceSwitcher = false
    @State private var showPairing = false
    @State private var showReconnectedToast = false
    @State private var previousConnectionState: ConnectionState?
    @FocusState private var isInputFocused: Bool

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _quickSwitcherViewModel = StateObject(wrappedValue: QuickSwitcherViewModel(workspaceStore: WorkspaceStore.shared))
    }

    /// Toolkit items - Easy to extend! Just add more .add() calls
    /// See PredefinedTool enum for available tools, or use .addCustom() for new ones
    private var toolkitItems: [ToolkitItem] {
        var builder = ToolkitBuilder()
            .add(.debugLogs { showDebugLogs = true })
            .add(.refresh { Task { await viewModel.refreshStatus() } })
            .add(.clearLogs { Task { await viewModel.clearLogs() } })
            .add(.settings { showSettings = true })

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
                    StatusBarView(
                        connectionState: viewModel.connectionState,
                        claudeState: viewModel.claudeState,
                        repoName: viewModel.agentStatus.repoName,
                        sessionId: viewModel.agentStatus.sessionId,
                        isWatchingSession: viewModel.isWatchingSession,
                        onWorkspaceTap: { showWorkspaceSwitcher = true }
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

                    // Pending interaction banner (if any)
                    if let interaction = viewModel.pendingInteraction {
                        InteractionBanner(
                            interaction: interaction,
                            onApprove: { Task { await viewModel.approvePermission() } },
                            onDeny: { Task { await viewModel.denyPermission() } },
                            onAnswer: { response in Task { await viewModel.answerQuestion(response) } }
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
                            isInputFocused: isInputFocused,
                            isStreaming: viewModel.isStreaming,
                            streamingStartTime: viewModel.streamingStartTime,
                            hasMoreMessages: viewModel.messagesHasMore,
                            isLoadingMore: viewModel.isLoadingMoreMessages,
                            onLoadMore: { await viewModel.loadMoreMessages() },
                            searchText: searchText,
                            matchingElementIds: matchingIds,
                            currentMatchIndex: matchIndex,
                            scrollRequest: viewModel.scrollRequest
                        )
                        .tag(DashboardTab.logs)

                        // Source Control (Mini Repo Management)
                        SourceControlView(
                            viewModel: viewModel.sourceControlViewModel,
                            onRefresh: {
                                await viewModel.sourceControlViewModel.refresh()
                            },
                            scrollRequest: viewModel.scrollRequest
                        )
                        .tag(DashboardTab.diffs)

                        // File Explorer
                        ExplorerView(
                            viewModel: viewModel.explorerViewModel,
                            scrollRequest: viewModel.scrollRequest
                        )
                        .tag(DashboardTab.explorer)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .dismissKeyboardOnTap()
                    .background(ColorSystem.terminalBg)

                    // Action bar - only show on logs tab
                    // Uses manual keyboard handling, so ignore SwiftUI's automatic keyboard avoidance
                    if viewModel.selectedTab == .logs {
                        ZStack(alignment: .topTrailing) {
                            ActionBarView(
                                claudeState: viewModel.claudeState,
                                promptText: $viewModel.promptText,
                                isBashMode: $viewModel.isBashMode,
                                isLoading: viewModel.isLoading,
                                isFocused: $isInputFocused,
                                onSend: { Task { await viewModel.sendPrompt() } },
                                onStop: { Task { await viewModel.stopClaude() } },
                                onToggleBashMode: { viewModel.toggleBashMode() }
                            )

                            // Keyboard dismiss button - positioned at top-right of ActionBarView
                            // This ensures it moves with the text field as it grows
                            FloatingKeyboardDismissButton()
                                .padding(.top, -52)  // Position above the ActionBarView
                                .padding(.trailing, Spacing.md)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // Only ignore keyboard safe area when chat input is focused (uses manual handling)
                // When search bar is focused, let SwiftUI handle keyboard avoidance normally
                .ignoresSafeArea(.keyboard, edges: isInputFocused ? .bottom : [])
                .background(ColorSystem.terminalBg)
                .animation(Animations.stateChange, value: viewModel.selectedTab)
                // Dismiss keyboard and reset search when switching tabs
                .onChange(of: viewModel.selectedTab) { oldTab, newTab in
                    // Dismiss keyboard globally
                    hideKeyboard()
                    isInputFocused = false

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
                        Text("cdev")
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
                .sheet(isPresented: $showSettings) {
                    SettingsView(onDisconnect: {
                        Task { await viewModel.disconnect() }
                    })
                    .responsiveSheet()
                }
                .sheet(isPresented: $viewModel.showSessionPicker) {
                    SessionPickerView(
                        sessions: viewModel.sessions,
                        currentSessionId: viewModel.agentStatus.sessionId,
                        hasMore: viewModel.sessionsHasMore,
                        isLoadingMore: viewModel.isLoadingMoreSessions,
                        agentRepository: viewModel.agentRepository,
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
                .sheet(isPresented: $showWorkspaceSwitcher) {
                    WorkspaceSwitcherSheet(
                        workspaceStore: workspaceStore,
                        currentWorkspace: workspaceStore.activeWorkspace,
                        isConnected: viewModel.connectionState.isConnected,
                        claudeState: viewModel.claudeState,
                        onSwitch: { workspace in
                            Task { await viewModel.switchWorkspace(workspace) }
                        },
                        onAddNew: { showPairing = true },
                        onDisconnect: {
                            Task { await viewModel.disconnect() }
                        }
                    )
                    .responsiveSheet()
                }
                .sheet(isPresented: $showPairing) {
                    if let pairingViewModel = viewModel.makePairingViewModel() {
                        PairingView(viewModel: pairingViewModel)
                    }
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
        }
        .errorAlert($viewModel.error)
        .onAppear {
            AppLogger.log("[DashboardView] onAppear - UI should be interactive now")
            previousConnectionState = viewModel.connectionState
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
}

// MARK: - Pulse Terminal Status Bar

struct StatusBarView: View {
    let connectionState: ConnectionState
    let claudeState: ClaudeState
    let repoName: String?
    let sessionId: String?
    var isWatchingSession: Bool = false
    var onWorkspaceTap: (() -> Void)?

    @AppStorage(Constants.UserDefaults.showSessionId) private var showSessionId = true
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
                            radius: isPulsing ? 4 : 1
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

            // Session ID row (when enabled)
            if showSessionId, let fullId = sessionId, !fullId.isEmpty {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ColorSystem.terminalBgHighlight, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: -4)
    }
}

// MARK: - Pulse Terminal Action Bar

struct ActionBarView: View {
    let claudeState: ClaudeState
    @Binding var promptText: String
    @Binding var isBashMode: Bool
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void
    let onToggleBashMode: () -> Void

    // Keyboard height tracking for proper positioning
    @State private var keyboardHeight: CGFloat = 0

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
        !suggestedCommands.isEmpty && isFocused.wrappedValue
    }

    /// Whether sending is disabled (Claude is running or waiting)
    private var isSendDisabled: Bool {
        promptText.isBlank || isLoading || claudeState == .running
    }

    /// Placeholder text based on Claude state and bash mode
    private var placeholderText: String {
        if claudeState == .running {
            return "Claude is running..."
        }
        return isBashMode ? "Run bash command..." : "Ask Claude..."
    }

    var body: some View {
        VStack(spacing: 0) {
            // Command suggestions (above the input)
            // Leave space on right for floating toolkit button
            if showSuggestions {
                CommandSuggestionsView(commands: suggestedCommands) { command in
                    promptText = command
                }
                .padding(.leading, containerPadding)
                .padding(.trailing, 70)  // Space for floating toolkit
                .padding(.bottom, Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: elementSpacing) {
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
                .transition(Animations.fadeScale)

                // Stop button with loading animation when active
                if claudeState == .running || claudeState == .waiting {
                    StopButtonWithAnimation(onStop: onStop)
                        .transition(Animations.fadeScale)
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
                    .focused(isFocused)
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

                    // Send button with glow - compact sizing
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
            .background(ColorSystem.terminalBgElevated)
        }
        // Only add keyboard padding when THIS input is focused (not search bar)
        .padding(.bottom, isFocused.wrappedValue ? keyboardHeight : 0)
        .background(ColorSystem.terminalBg)
        .animation(Animations.stateChange, value: claudeState)
        .animation(Animations.stateChange, value: showSuggestions)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        // Dismiss keyboard when Claude starts running - don't auto-focus when done
        .onChange(of: claudeState) { _, newState in
            if newState == .running {
                isFocused.wrappedValue = false
            }
        }
        .onChange(of: isFocused.wrappedValue) { oldValue, newValue in
            AppLogger.log("[ActionBarView] Focus changed: \(oldValue) -> \(newValue)")
            // Reset keyboard height when losing focus
            if !newValue {
                keyboardHeight = 0
            }
        }
        // Track keyboard height for positioning above keyboard
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            // Only track keyboard when this input is focused
            guard isFocused.wrappedValue else { return }
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
