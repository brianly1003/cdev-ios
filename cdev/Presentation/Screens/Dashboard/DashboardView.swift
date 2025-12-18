import SwiftUI

/// Main dashboard view - compact, developer-focused UI
/// Hero: Terminal output, quick actions, minimal chrome
struct DashboardView: View {
    @StateObject var viewModel: DashboardViewModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Compact status bar
                StatusBarView(
                    connectionState: viewModel.connectionState,
                    claudeState: viewModel.claudeState,
                    repoName: viewModel.agentStatus.repoName,
                    sessionId: viewModel.agentStatus.sessionId
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

                // Tab selector
                CompactTabSelector(
                    selectedTab: $viewModel.selectedTab,
                    logsCount: viewModel.logsCountForBadge,
                    diffsCount: viewModel.diffs.count
                )

                // Content - tap to dismiss keyboard
                TabView(selection: $viewModel.selectedTab) {
                    LogListView(
                        logs: viewModel.logs,
                        onClear: { Task { await viewModel.clearLogs() } },
                        isVisible: viewModel.selectedTab == .logs
                    )
                    .tag(DashboardTab.logs)

                    DiffListView(
                        diffs: viewModel.diffs,
                        onClear: { Task { await viewModel.clearDiffs() } },
                        onRefresh: { await viewModel.refreshGitStatus() }
                    )
                    .tag(DashboardTab.diffs)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .dismissKeyboardOnTap()
                .background(ColorSystem.terminalBg)
                // Use safeAreaInset so ScrollView accounts for action bar height
                .safeAreaInset(edge: .bottom) {
                    if viewModel.selectedTab == .logs {
                        ActionBarView(
                            claudeState: viewModel.claudeState,
                            promptText: $viewModel.promptText,
                            isLoading: viewModel.isLoading,
                            onSend: { Task { await viewModel.sendPrompt() } },
                            onStop: { Task { await viewModel.stopClaude() } }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .background(ColorSystem.terminalBg)
            .animation(Animations.stateChange, value: viewModel.selectedTab)
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $viewModel.showSessionPicker) {
                SessionPickerView(
                    sessions: viewModel.sessions,
                    currentSessionId: viewModel.agentStatus.sessionId,
                    hasMore: viewModel.sessionsHasMore,
                    isLoadingMore: viewModel.isLoadingMoreSessions,
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
        }
        .errorAlert($viewModel.error)
        .task {
            await viewModel.refreshStatus()
        }
    }
}

// MARK: - Pulse Terminal Status Bar

struct StatusBarView: View {
    let connectionState: ConnectionState
    let claudeState: ClaudeState
    let repoName: String?
    let sessionId: String?

    @AppStorage(Constants.UserDefaults.showSessionId) private var showSessionId = true
    @State private var isPulsing = false
    @State private var showCopiedToast = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                // Connection indicator with glow
                HStack(spacing: 4) {
                    Circle()
                        .fill(connectionState.isConnected ? ColorSystem.success : ColorSystem.error)
                        .frame(width: 6, height: 6)
                        .shadow(
                            color: (connectionState.isConnected ? ColorSystem.success : ColorSystem.error).opacity(0.5),
                            radius: 2
                        )

                    Text(connectionState.isConnected ? "Online" : "Offline")
                        .font(Typography.statusLabel)
                        .foregroundStyle(ColorSystem.textSecondary)
                }

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

                Spacer()

                // Repo badge
                if let repoName = repoName {
                    HStack(spacing: 3) {
                        Image(systemName: Icons.files)
                            .font(.system(size: 9))
                        Text(repoName)
                            .font(Typography.statusLabel)
                            .lineLimit(1)
                    }
                    .foregroundStyle(ColorSystem.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(Capsule())
                }
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
    }
}

// MARK: - Pulse Terminal Tab Selector

struct CompactTabSelector: View {
    @Binding var selectedTab: DashboardTab
    let logsCount: Int
    let diffsCount: Int

    var body: some View {
        HStack(spacing: 0) {
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
                        let count = tab == .logs ? logsCount : diffsCount
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
                    .padding(.vertical, Spacing.xs)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? ColorSystem.primary : ColorSystem.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(ColorSystem.terminalBgElevated)
        .overlay(alignment: .bottom) {
            // Animated selection indicator with glow
            GeometryReader { geo in
                Rectangle()
                    .fill(ColorSystem.primary)
                    .frame(width: geo.size.width / 2, height: 2)
                    .shadow(color: ColorSystem.primaryGlow, radius: 4, y: 0)
                    .offset(x: selectedTab == .logs ? 0 : geo.size.width / 2)
                    .animation(Animations.tabSlide, value: selectedTab)
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
    let isLoading: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    /// Filtered commands based on current input
    private var suggestedCommands: [BuiltInCommand] {
        BuiltInCommand.matching(promptText)
    }

    /// Whether to show command suggestions
    private var showSuggestions: Bool {
        !suggestedCommands.isEmpty && isFocused
    }

    /// Whether sending is disabled (Claude is running or waiting)
    private var isSendDisabled: Bool {
        promptText.isBlank || isLoading || claudeState == .running
    }

    /// Placeholder text based on Claude state
    private var placeholderText: String {
        claudeState == .running ? "Claude is running..." : "Ask Claude..."
    }

    var body: some View {
        VStack(spacing: 0) {
            // Command suggestions (above the input)
            if showSuggestions {
                CommandSuggestionsView(commands: suggestedCommands) { command in
                    promptText = command
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: Spacing.xs) {
                // Stop button with glow when active
                if claudeState == .running || claudeState == .waiting {
                    Button(action: onStop) {
                        Image(systemName: Icons.stop)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(ColorSystem.error)
                            .clipShape(Circle())
                            .shadow(color: ColorSystem.errorGlow, radius: 4)
                    }
                    .pressEffect()
                    .transition(Animations.fadeScale)
                }

                // Prompt input with Pulse Terminal styling
                HStack(spacing: Spacing.xs) {
                    TextField(placeholderText, text: $promptText, axis: .vertical)
                        .font(Typography.inputField)
                        .foregroundStyle(ColorSystem.textPrimary)
                        .lineLimit(1...3)
                        .focused($isFocused)
                        .submitLabel(.send)
                        .disabled(claudeState == .running)
                        .padding(.vertical, Spacing.sm)
                        .padding(.leading, Spacing.sm)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isFocused = true
                        }
                        .onSubmit {
                            if !isSendDisabled {
                                onSend()
                            }
                        }

                    // Send button with glow
                    Button(action: onSend) {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(ColorSystem.primary)
                            } else {
                                Image(systemName: Icons.send)
                                    .font(.system(size: 24))
                            }
                        }
                        .foregroundStyle(isSendDisabled ? ColorSystem.textQuaternary : ColorSystem.primary)
                        .shadow(
                            color: isSendDisabled ? .clear : ColorSystem.primaryGlow,
                            radius: 4
                        )
                    }
                    .disabled(isSendDisabled)
                    .padding(.trailing, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                }
                .background(ColorSystem.terminalBgHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isFocused ? ColorSystem.primary.opacity(0.5) : .clear,
                            lineWidth: 1
                        )
                )
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(ColorSystem.terminalBgElevated)
        }
        .background(ColorSystem.terminalBg)
        .animation(Animations.stateChange, value: claudeState)
        .animation(Animations.stateChange, value: showSuggestions)
    }
}
