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

                // Content
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

// MARK: - Status Bar

struct StatusBarView: View {
    let connectionState: ConnectionState
    let claudeState: ClaudeState
    let repoName: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Connection status
            HStack(spacing: Spacing.xxs) {
                Circle()
                    .fill(connectionState.isConnected ? Color.accentGreen : Color.errorRed)
                    .frame(width: 8, height: 8)

                Text(connectionState.isConnected ? "Connected" : "Offline")
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 12)

            // Claude status
            HStack(spacing: Spacing.xxs) {
                Circle()
                    .fill(claudeStateColor)
                    .frame(width: 8, height: 8)

                Text(claudeState.rawValue.capitalized)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Repo name
            if let repoName = repoName {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text(repoName)
                        .font(Typography.caption1)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                    Haptics.selection()
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: tab.icon)
                            .font(.caption)

                        Text(tab.rawValue)
                            .font(Typography.footnote)

                        // Badge
                        let count = tab == .logs ? logsCount : diffsCount
                        if count > 0 {
                            Text("\(min(count, 99))\(count > 99 ? "+" : "")")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    selectedTab == tab
                                        ? Color.primaryBlue.opacity(0.2)
                                        : Color.secondary.opacity(0.2)
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, Spacing.xs)
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

// MARK: - Action Bar

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

            HStack(spacing: Spacing.sm) {
                // Stop button (when running)
                if claudeState == .running || claudeState == .waiting {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.errorRed)
                            .clipShape(Circle())
                    }
                    .pressEffect()
                }

                // Prompt input
                HStack(spacing: Spacing.xs) {
                    TextField("Ask Claude...", text: $promptText, axis: .vertical)
                        .font(Typography.body)
                        .lineLimit(1...4)
                        .focused($isFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            if !promptText.isBlank {
                                onSend()
                            }
                        }

                    // Send button
                    Button(action: onSend) {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                            }
                        }
                        .foregroundStyle(promptText.isBlank ? .secondary : Color.primaryBlue)
                    }
                    .disabled(promptText.isBlank || isLoading)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color(.secondarySystemBackground))
        }
    }
}
