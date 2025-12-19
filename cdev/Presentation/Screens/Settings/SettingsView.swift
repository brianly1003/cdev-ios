import SwiftUI

/// Settings view - Pulse Terminal design system
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Constants.UserDefaults.showTimestamps) private var showTimestamps = true
    @AppStorage(Constants.UserDefaults.syntaxHighlighting) private var syntaxHighlighting = true
    @AppStorage(Constants.UserDefaults.showSessionId) private var showSessionId = false
    @AppStorage(Constants.UserDefaults.hapticFeedback) private var hapticFeedback = true
    @AppStorage(Constants.UserDefaults.autoReconnect) private var autoReconnect = true

    var onDisconnect: (() -> Void)?
    @State private var showDisconnectConfirm = false
    @State private var showClearDataConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                ColorSystem.terminalBg
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.md) {
                        // Display Section
                        SettingsSection(title: "Display", icon: "eye") {
                            SettingsToggleRow(
                                icon: "clock",
                                title: "Show Timestamps",
                                subtitle: "Display time for each log entry",
                                isOn: $showTimestamps
                            )

                            SettingsToggleRow(
                                icon: "paintbrush",
                                title: "Syntax Highlighting",
                                subtitle: "Colorize code in terminal output",
                                isOn: $syntaxHighlighting
                            )

                            SettingsToggleRow(
                                icon: "number",
                                title: "Show Session ID",
                                subtitle: "Display session identifier in status bar",
                                isOn: $showSessionId
                            )
                        }

                        // Behavior Section
                        SettingsSection(title: "Behavior", icon: "gearshape") {
                            SettingsToggleRow(
                                icon: "iphone.radiowaves.left.and.right",
                                title: "Haptic Feedback",
                                subtitle: "Vibration on interactions",
                                isOn: $hapticFeedback
                            )

                            SettingsToggleRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Auto-Reconnect",
                                subtitle: "Reconnect to last workspace on launch",
                                isOn: $autoReconnect
                            )
                        }

                        // Connection Section
                        SettingsSection(title: "Connection", icon: "wifi") {
                            SettingsButtonRow(
                                icon: "xmark.circle",
                                title: "Disconnect",
                                subtitle: "Disconnect from current workspace",
                                style: .destructive,
                                disabled: onDisconnect == nil
                            ) {
                                showDisconnectConfirm = true
                            }
                        }

                        // Data Section
                        SettingsSection(title: "Data", icon: "externaldrive") {
                            SettingsButtonRow(
                                icon: "trash",
                                title: "Clear Saved Workspaces",
                                subtitle: "Remove all saved connection history",
                                style: .destructive
                            ) {
                                showClearDataConfirm = true
                            }
                        }

                        // About Section
                        SettingsSection(title: "About", icon: "info.circle") {
                            SettingsInfoRow(
                                icon: "tag",
                                title: "Version",
                                value: Bundle.main.appVersion
                            )

                            SettingsLinkRow(
                                icon: "chevron.left.forwardslash.chevron.right",
                                title: "Source Code",
                                subtitle: "GitHub Repository",
                                url: URL(string: "https://github.com/brianly1003/cdev-ios")!
                            )

                            SettingsLinkRow(
                                icon: "ladybug",
                                title: "Report Issue",
                                subtitle: "Submit bug reports",
                                url: URL(string: "https://github.com/brianly1003/cdev-ios/issues")!
                            )
                        }

                        // Footer
                        VStack(spacing: Spacing.xxs) {
                            Text("cdev")
                                .font(Typography.bodyBold)
                                .foregroundStyle(ColorSystem.textSecondary)

                            Text("Mobile companion for Claude Code")
                                .font(Typography.caption1)
                                .foregroundStyle(ColorSystem.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.xl)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.sm)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ColorSystem.terminalBgElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Disconnect from workspace?",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    onDisconnect?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to scan the QR code again to reconnect.")
            }
            .confirmationDialog(
                "Clear all saved workspaces?",
                isPresented: $showClearDataConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    WorkspaceStore.shared.clearAll()
                    Haptics.warning()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all saved workspace connections. You'll need to scan QR codes again.")
            }
        }
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Section Header
            HStack(spacing: Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title.uppercased())
                    .font(Typography.badge)
            }
            .foregroundStyle(ColorSystem.textTertiary)
            .padding(.horizontal, Spacing.sm)

            // Section Content
            VStack(spacing: 1) {
                content
            }
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
    }
}

// MARK: - Settings Toggle Row

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.primary)
                .frame(width: 24)

            // Text
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text(subtitle)
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            Spacer()

            // Toggle
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ColorSystem.primary)
                .onChange(of: isOn) { _, _ in
                    Haptics.selection()
                }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Settings Button Row

private struct SettingsButtonRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var style: ButtonStyle = .normal
    var disabled: Bool = false
    let action: () -> Void

    enum ButtonStyle {
        case normal, destructive
    }

    private var iconColor: Color {
        disabled ? ColorSystem.textQuaternary :
            (style == .destructive ? ColorSystem.error : ColorSystem.primary)
    }

    private var textColor: Color {
        disabled ? ColorSystem.textQuaternary :
            (style == .destructive ? ColorSystem.error : ColorSystem.textPrimary)
    }

    var body: some View {
        Button {
            action()
            Haptics.light()
        } label: {
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                // Text
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(textColor)

                    Text(subtitle)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(ColorSystem.terminalBgElevated)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Settings Info Row

private struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.primary)
                .frame(width: 24)

            // Title
            Text(title)
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)

            Spacer()

            // Value
            Text(value)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textTertiary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Settings Link Row

private struct SettingsLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.primary)
                    .frame(width: 24)

                // Text
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(ColorSystem.textPrimary)

                    Text(subtitle)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textTertiary)
                }

                Spacer()

                // External link indicator
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(ColorSystem.terminalBgElevated)
        }
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
