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
                    repoName: viewModel.agentStatus.repoName
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
                    logsCount: viewModel.logs.count,
                    diffsCount: viewModel.diffs.count
                )

                // Content - tap to dismiss keyboard
                TabView(selection: $viewModel.selectedTab) {
                    LogListView(
                        logs: viewModel.logs,
                        onClear: { Task { await viewModel.clearLogs() } }
                    )
                    .tag(DashboardTab.logs)

                    DiffListView(
                        diffs: viewModel.diffs,
                        onClear: { Task { await viewModel.clearDiffs() } }
                    )
                    .tag(DashboardTab.diffs)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .dismissKeyboardOnTap()

                // Bottom action bar
                ActionBarView(
                    claudeState: viewModel.claudeState,
                    promptText: $viewModel.promptText,
                    isLoading: viewModel.isLoading,
                    onSend: { Task { await viewModel.sendPrompt() } },
                    onStop: { Task { await viewModel.stopClaude() } }
                )
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .errorAlert($viewModel.error)
        .task {
            await viewModel.refreshStatus()
        }
    }
}

// MARK: - Compact Status Bar

struct StatusBarView: View {
    let connectionState: ConnectionState
    let claudeState: ClaudeState
    let repoName: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Connection status - compact
            HStack(spacing: 3) {
                Circle()
                    .fill(connectionState.isConnected ? Color.accentGreen : Color.errorRed)
                    .frame(width: 6, height: 6)

                Text(connectionState.isConnected ? "Online" : "Offline")
                    .font(Typography.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 10)

            // Claude status - compact
            HStack(spacing: 3) {
                Circle()
                    .fill(claudeStateColor)
                    .frame(width: 6, height: 6)

                Text(claudeState.rawValue.capitalized)
                    .font(Typography.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Repo name - compact
            if let repoName = repoName {
                HStack(spacing: 2) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text(repoName)
                        .font(Typography.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
    }

    private var claudeStateColor: Color {
        switch claudeState {
        case .running: return .statusRunning
        case .idle: return .statusIdle
        case .waiting: return .statusWaiting
        case .error: return .statusError
        case .stopped: return .secondary
        }
    }
}

// MARK: - Compact Tab Selector

struct CompactTabSelector: View {
    @Binding var selectedTab: DashboardTab
    let logsCount: Int
    let diffsCount: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                    Haptics.selection()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10))

                        Text(tab.rawValue)
                            .font(Typography.caption2)

                        // Badge - compact
                        let count = tab == .logs ? logsCount : diffsCount
                        if count > 0 {
                            Text("\(min(count, 99))\(count > 99 ? "+" : "")")
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    selectedTab == tab
                                        ? Color.primaryBlue.opacity(0.2)
                                        : Color.secondary.opacity(0.2)
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? Color.primaryBlue : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            // Selection indicator
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.primaryBlue)
                    .frame(width: geo.size.width / 2, height: 2)
                    .offset(x: selectedTab == .logs ? 0 : geo.size.width / 2)
            }
            .frame(height: 2)
        }
    }
}

// MARK: - Compact Action Bar

struct ActionBarView: View {
    let claudeState: ClaudeState
    @Binding var promptText: String
    let isLoading: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: Spacing.xs) {
                // Stop button (when running) - compact
                if claudeState == .running || claudeState == .waiting {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.errorRed)
                            .clipShape(Circle())
                    }
                    .pressEffect()
                }

                // Prompt input - compact
                HStack(spacing: 6) {
                    TextField("Ask Claude...", text: $promptText, axis: .vertical)
                        .font(Typography.footnote)
                        .lineLimit(1...3)
                        .focused($isFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            if !promptText.isBlank {
                                onSend()
                            }
                        }

                    // Send button - compact
                    Button(action: onSend) {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 22))
                            }
                        }
                        .foregroundStyle(promptText.isBlank ? .secondary : Color.primaryBlue)
                    }
                    .disabled(promptText.isBlank || isLoading)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
        }
    }
}
