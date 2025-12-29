import SwiftUI

/// Settings view - Compact design for mobile developers
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Display settings
    @AppStorage(Constants.UserDefaults.showTimestamps) private var showTimestamps = true
    @AppStorage("app.theme") private var selectedTheme: String = AppTheme.dark.rawValue

    // Behavior settings
    @AppStorage(Constants.UserDefaults.hapticFeedback) private var hapticFeedback = true
    @AppStorage(Constants.UserDefaults.autoReconnect) private var autoReconnect = true

    @State private var showClearDataConfirm = false
    @State private var showThemePicker = false

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    private var currentTheme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .dark
    }

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

                            SettingsThemeRow(
                                currentTheme: currentTheme,
                                onTap: { showThemePicker = true }
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

                        // Voice Input Section (Beta)
                        VoiceInputSettingsSection()

                        // Toolkit Section (Coming soon)
                        SettingsSection(title: "Toolkit", icon: "wrench.and.screwdriver") {
                            SettingsNavRow(
                                icon: "square.grid.2x2",
                                title: "Configure Tools",
                                value: "5 active",
                                disabled: true
                            )
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

                        // Debug Logs Section
                        DebugLogsSettingsSection()

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
            .sheet(isPresented: $showThemePicker) {
                ThemePickerView(
                    selectedTheme: currentTheme,
                    onSelect: { theme in
                        selectedTheme = theme.rawValue
                        showThemePicker = false
                        Haptics.selection()
                    }
                )
                .presentationDetents([.height(280)])
                .preferredColorScheme(currentTheme.colorScheme)
            }
            // Sheets need their own preferredColorScheme (don't inherit from parent)
            .preferredColorScheme(currentTheme.colorScheme)
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
//                Text("Made with")
//                    .font(Typography.terminalSmall)
//                    .foregroundStyle(ColorSystem.textQuaternary)
//
//                Image(systemName: "heart.fill")
//                    .font(.system(size: 8))
//                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.21)) // Brand orange

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

// MARK: - Settings Theme Row

private struct SettingsThemeRow: View {
    let currentTheme: AppTheme
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
            Haptics.selection()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: currentTheme.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.primary)
                    .frame(width: 20)

                Text("Color Mode")
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                Spacer()

                HStack(spacing: 4) {
                    Text(currentTheme.displayName)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorSystem.textQuaternary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(ColorSystem.terminalBgElevated)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Picker View

private struct ThemePickerView: View {
    let selectedTheme: AppTheme
    let onSelect: (AppTheme) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        onSelect(theme)
                    } label: {
                        HStack(spacing: layout.contentSpacing) {
                            // Theme icon with color
                            Image(systemName: theme.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(iconColor(for: theme))
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(theme.displayName)
                                    .font(layout.bodyFont)
                                    .foregroundStyle(ColorSystem.textPrimary)

                                Text(themeDescription(for: theme))
                                    .font(layout.captionFont)
                                    .foregroundStyle(ColorSystem.textTertiary)
                            }

                            Spacer()

                            if theme == selectedTheme {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(ColorSystem.primary)
                            } else {
                                Circle()
                                    .strokeBorder(ColorSystem.textQuaternary, lineWidth: 1.5)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(.horizontal, layout.standardPadding)
                        .padding(.vertical, layout.smallPadding + 4)
                        .contentShape(Rectangle())  // Make entire row tappable
                        .background(
                            theme == selectedTheme
                                ? ColorSystem.primary.opacity(0.08)
                                : Color.clear
                        )
                    }
                    .buttonStyle(.plain)

                    if theme != AppTheme.allCases.last {
                        Divider()
                            .background(ColorSystem.terminalBgHighlight)
                            .padding(.leading, 56)
                    }
                }
            }
            .background(ColorSystem.terminalBgElevated)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .padding(.horizontal, layout.standardPadding)
            .padding(.top, layout.standardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ColorSystem.terminalBg)
            .navigationTitle("Color Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func iconColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system: return ColorSystem.primary
        case .light: return Color.orange
        case .dark: return Color.indigo
        }
    }

    private func themeDescription(for theme: AppTheme) -> String {
        switch theme {
        case .system: return "Follow iOS system setting"
        case .light: return "Always use light appearance"
        case .dark: return "Always use dark appearance"
        }
    }
}

// MARK: - Voice Input Settings Section

private struct VoiceInputSettingsSection: View {
    @StateObject private var settings = VoiceInputSettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Section Header with Beta badge
            HStack(spacing: 4) {
                Image(systemName: "mic")
                    .font(.system(size: 10))
                Text("VOICE INPUT")
                    .font(Typography.badge)

                // Beta badge
                Text("BETA")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(ColorSystem.warning)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(ColorSystem.warning.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .foregroundStyle(ColorSystem.textTertiary)
            .padding(.horizontal, Spacing.xs)

            // Section Content
            VStack(spacing: 0.5) {
                // Enable Voice Input
                VoiceInputToggleRow(
                    icon: "mic.fill",
                    title: "Enable Voice Input",
                    subtitle: "Add microphone button to chat",
                    isOn: Binding(
                        get: { settings.isEnabled },
                        set: { settings.isEnabled = $0 }
                    )
                )

                // Auto-send on Silence (only visible when enabled)
                if settings.isEnabled {
                    VoiceInputToggleRow(
                        icon: "bolt.fill",
                        title: "Auto-send on Silence",
                        subtitle: "Send message after 1.5s pause",
                        isOn: Binding(
                            get: { settings.autoSendOnSilence },
                            set: { settings.autoSendOnSilence = $0 }
                        )
                    )

                    // Language selector
                    VoiceInputLanguageRow(
                        currentLanguage: settings.selectedLanguage
                    ) { language in
                        settings.selectedLanguage = language
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
        .animation(.easeInOut(duration: 0.2), value: settings.isEnabled)
    }
}

// MARK: - Voice Input Toggle Row

private struct VoiceInputToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(ColorSystem.primary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text(subtitle)
                    .font(Typography.caption2)
                    .foregroundStyle(ColorSystem.textTertiary)
            }

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

// MARK: - Voice Input Language Row

private struct VoiceInputLanguageRow: View {
    let currentLanguage: VoiceInputLanguage
    let onSelect: (VoiceInputLanguage) -> Void

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
            Haptics.selection()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(ColorSystem.primary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Language")
                        .font(Typography.body)
                        .foregroundStyle(ColorSystem.textPrimary)

                    Text("Speech recognition language")
                        .font(Typography.caption2)
                        .foregroundStyle(ColorSystem.textTertiary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(currentLanguage.flag)
                        .font(.system(size: 16))

                    Text(currentLanguage.name)
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorSystem.textQuaternary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(ColorSystem.terminalBgElevated)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            VoiceLanguagePickerView(
                selectedLanguage: currentLanguage,
                onSelect: { language in
                    onSelect(language)
                    showPicker = false
                }
            )
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Voice Language Picker View

private struct VoiceLanguagePickerView: View {
    let selectedLanguage: VoiceInputLanguage
    let onSelect: (VoiceInputLanguage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        NavigationStack {
            List(VoiceInputLanguage.all) { language in
                Button {
                    onSelect(language)
                    Haptics.selection()
                } label: {
                    HStack(spacing: layout.contentSpacing) {
                        Text(language.flag)
                            .font(.system(size: 24))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.name)
                                .font(layout.bodyFont)
                                .foregroundStyle(ColorSystem.textPrimary)

                            Text(language.nativeName)
                                .font(layout.captionFont)
                                .foregroundStyle(ColorSystem.textTertiary)
                        }

                        Spacer()

                        if language.id == selectedLanguage.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: layout.iconMedium, weight: .semibold))
                                .foregroundStyle(ColorSystem.primary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Voice Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Debug Logs Settings Section

private struct DebugLogsSettingsSection: View {
    @StateObject private var logStore = DebugLogStore.shared
    @State private var showClearLogsConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Section Header
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                Text("DEBUG LOGS")
                    .font(Typography.badge)
            }
            .foregroundStyle(ColorSystem.textTertiary)
            .padding(.horizontal, Spacing.xs)

            // Section Content
            VStack(spacing: 0.5) {
                // Persist Logs Toggle
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(ColorSystem.primary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Persist Logs to File")
                            .font(Typography.body)
                            .foregroundStyle(ColorSystem.textPrimary)

                        Text("Save logs across app restarts")
                            .font(Typography.caption2)
                            .foregroundStyle(ColorSystem.textTertiary)
                    }

                    Spacer()

                    Toggle("", isOn: $logStore.persistenceEnabled)
                        .labelsHidden()
                        .tint(ColorSystem.primary)
                        .scaleEffect(0.85)
                        .onChange(of: logStore.persistenceEnabled) { _, newValue in
                            Haptics.selection()
                            if newValue {
                                logStore.forceSave()
                            }
                        }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(ColorSystem.terminalBgElevated)

                // File Info (only when persistence enabled)
                if logStore.persistenceEnabled {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "doc.badge.clock")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorSystem.textTertiary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Log File Size")
                                .font(Typography.body)
                                .foregroundStyle(ColorSystem.textPrimary)

                            if let lastSave = logStore.lastSaveTime {
                                Text("Last saved: \(lastSave.formatted(.relative(presentation: .named)))")
                                    .font(Typography.caption2)
                                    .foregroundStyle(ColorSystem.textTertiary)
                            }
                        }

                        Spacer()

                        Text(logStore.getFormattedFileSize())
                            .font(Typography.terminal)
                            .foregroundStyle(ColorSystem.textSecondary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(ColorSystem.terminalBgElevated)

                    // Previous Session Logs count
                    if logStore.previousSessionLogCount > 0 {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14))
                                .foregroundStyle(ColorSystem.textTertiary)
                                .frame(width: 20)

                            Text("Previous Sessions")
                                .font(Typography.body)
                                .foregroundStyle(ColorSystem.textPrimary)

                            Spacer()

                            Text("\(logStore.previousSessionLogCount) logs")
                                .font(Typography.terminal)
                                .foregroundStyle(ColorSystem.textSecondary)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(ColorSystem.terminalBgElevated)
                    }

                    // Clear Saved Logs button
                    Button {
                        showClearLogsConfirm = true
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(ColorSystem.error)
                                .frame(width: 20)

                            Text("Clear Saved Logs")
                                .font(Typography.body)
                                .foregroundStyle(ColorSystem.error)

                            Spacer()
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(ColorSystem.terminalBgElevated)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        }
        .animation(.easeInOut(duration: 0.2), value: logStore.persistenceEnabled)
        .confirmationDialog(
            "Clear all saved logs?",
            isPresented: $showClearLogsConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Logs", role: .destructive) {
                logStore.clear(clearPersisted: true)
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all saved debug logs. Current session logs will remain in memory.")
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
