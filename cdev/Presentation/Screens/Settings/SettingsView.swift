import SwiftUI

/// Settings view - Compact design for mobile developers
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Display settings
    @AppStorage(Constants.UserDefaults.showTimestamps) private var showTimestamps = true
    @AppStorage(Constants.UserDefaults.syntaxHighlighting) private var syntaxHighlighting = true
    @AppStorage(Constants.UserDefaults.showSessionId) private var showSessionId = false

    // Behavior settings
    @AppStorage(Constants.UserDefaults.hapticFeedback) private var hapticFeedback = true
    @AppStorage(Constants.UserDefaults.autoReconnect) private var autoReconnect = true

    var onDisconnect: (() -> Void)?
    @State private var showDisconnectConfirm = false
    @State private var showClearDataConfirm = false
    @State private var showWorkspaceManager = false

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorSystem.terminalBg
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.sm) {
                        // Branded Header
                        BrandedHeader()

                        // Appearance Section (Themes coming soon)
                        SettingsSection(title: "Appearance", icon: "paintpalette") {
                            SettingsToggleRow(
                                icon: "clock",
                                title: "Timestamps",
                                isOn: $showTimestamps
                            )

                            SettingsToggleRow(
                                icon: "paintbrush",
                                title: "Syntax Highlighting",
                                isOn: $syntaxHighlighting
                            )

                            SettingsToggleRow(
                                icon: "number",
                                title: "Session ID",
                                isOn: $showSessionId
                            )

                            SettingsNavRow(
                                icon: "moon.stars",
                                title: "Theme",
                                value: "Dark",
                                disabled: true
                            )
                        }

                        // Behavior Section
                        SettingsSection(title: "Behavior", icon: "slider.horizontal.3") {
                            SettingsToggleRow(
                                icon: "iphone.radiowaves.left.and.right",
                                title: "Haptic Feedback",
                                isOn: $hapticFeedback
                            )

                            SettingsToggleRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Auto-Reconnect",
                                isOn: $autoReconnect
                            )
                        }

                        // Toolkit Section (Coming soon)
                        SettingsSection(title: "Toolkit", icon: "wrench.and.screwdriver") {
                            SettingsNavRow(
                                icon: "square.grid.2x2",
                                title: "Configure Tools",
                                value: "5 active",
                                disabled: true
                            )
                        }

                        // Connection Section
                        SettingsSection(title: "Connection", icon: "wifi") {
                            SettingsButtonRow(
                                icon: "laptopcomputer.and.iphone",
                                title: "Remote Workspaces",
                                style: .normal
                            ) {
                                showWorkspaceManager = true
                            }

                            SettingsButtonRow(
                                icon: "xmark.circle",
                                title: "Disconnect",
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
                                title: "Clear Workspaces",
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
                                url: URL(string: "https://github.com/brianly1003/cdev-ios")!
                            )

                            SettingsLinkRow(
                                icon: "ladybug",
                                title: "Report Issue",
                                url: URL(string: "https://github.com/brianly1003/cdev/issues")!
                            )
                        }

                    }
                    .padding(.horizontal, Spacing.xs)
                    .padding(.top, Spacing.xs)
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
                    // Call disconnect - RootView will handle navigation
                    // Don't call dismiss() here - the view hierarchy change will dismiss this sheet
                    onDisconnect?()
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
            .sheet(isPresented: $showWorkspaceManager) {
                WorkspaceManagerView(
                    onDisconnect: onDisconnect != nil ? {
                        onDisconnect?()
                    } : nil
                )
                    .responsiveSheet()
            }
        }
    }
}

// MARK: - Settings Section (Compact)

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Section Header
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title.uppercased())
                    .font(Typography.badge)
            }
            .foregroundStyle(ColorSystem.textTertiary)
            .padding(.horizontal, Spacing.xs)

            // Section Content
            VStack(spacing: 0.5) {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
    }
}

// MARK: - Settings Toggle Row (Compact)

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.primary)
                .frame(width: 20)

            Text(title)
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ColorSystem.primary)
                .scaleEffect(0.85)
                .onChange(of: isOn) { _, _ in
                    Haptics.selection()
                }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Settings Nav Row (Coming Soon placeholder)

private struct SettingsNavRow: View {
    let icon: String
    let title: String
    let value: String
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(disabled ? ColorSystem.textQuaternary : ColorSystem.primary)
                .frame(width: 20)

            Text(title)
                .font(Typography.body)
                .foregroundStyle(disabled ? ColorSystem.textTertiary : ColorSystem.textPrimary)

            Spacer()

            Text(value)
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textQuaternary)

            if disabled {
                Text("Soon")
                    .font(Typography.badge)
                    .foregroundStyle(ColorSystem.textQuaternary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(ColorSystem.terminalBgHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Settings Button Row (Compact)

private struct SettingsButtonRow: View {
    let icon: String
    let title: String
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
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(textColor)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(ColorSystem.terminalBgElevated)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Settings Info Row (Compact)

private struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.primary)
                .frame(width: 20)

            Text(title)
                .font(Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)

            Spacer()

            Text(value)
                .font(Typography.terminal)
                .foregroundStyle(ColorSystem.textTertiary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ColorSystem.terminalBgElevated)
    }
}

// MARK: - Settings Link Row (Compact)

private struct SettingsLinkRow: View {
    let icon: String
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.primary)
                    .frame(width: 20)

                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(ColorSystem.terminalBgElevated)
        }
    }
}

// MARK: - Branded Header

private struct BrandedHeader: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            // App Icon
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            // App Name & Tagline
            VStack(spacing: 2) {
                Text("Cdev")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("Mobile companion for Claude Code")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            // Credits - compact inline
            HStack(spacing: Spacing.xxs) {
                Text("Made with")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textQuaternary)

                Image(systemName: "heart.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.21)) // Brand orange

                Text("by Brian Ly")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .padding(.bottom, Spacing.xs)
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
