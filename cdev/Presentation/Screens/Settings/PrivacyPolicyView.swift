//
//  PrivacyPolicyView.swift
//  Cdev
//
//  Privacy Policy screen for open source app
//  Terminal-first design following cdev design system
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorSystem.terminalBg
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: layout.contentSpacing) {
                        // Header
                        headerSection

                        // Sections
                        openSourceSection
                        dataCollectionSection
                        howItWorksSection
                        networkCommunicationSection
                        localStorageSection
                        thirdPartySection
                        changesSection
                        contactSection

                        // Footer
                        footerSection
                    }
                    .padding(.horizontal, layout.standardPadding)
                    .padding(.vertical, layout.smallPadding)
                }
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ColorSystem.terminalBgElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .presentationDetents(ResponsiveLayout.isIPad ? [.large] : [.large])
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(ColorSystem.primary)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: layout.tightSpacing) {
            // Shield icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: layout.iconXLarge))
                .foregroundStyle(ColorSystem.primary)
                .padding(.bottom, layout.tightSpacing)

            Text("Privacy Policy")
                .font(.system(size: layout.isCompact ? 20 : 24, weight: .bold, design: .rounded))
                .foregroundStyle(ColorSystem.textPrimary)

            Text("Last Updated: January 2026")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, layout.standardPadding)
    }

    // MARK: - Open Source Section

    private var openSourceSection: some View {
        PolicySection(title: "Open Source Transparency", icon: "chevron.left.forwardslash.chevron.right") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                // Open source badge
                HStack(spacing: layout.tightSpacing) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: layout.iconSmall))
                    Text("MIT LICENSE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(ColorSystem.success)
                .padding(.horizontal, layout.smallPadding)
                .padding(.vertical, layout.tightSpacing)
                .background(ColorSystem.success.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

                Text("Cdev is fully open source. You can inspect every line of code to verify our privacy claims. We have nothing to hide.")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if let url = URL(string: "https://github.com/brianly1003/cdev-ios") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: layout.tightSpacing) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: layout.iconMedium))
                        Text("View Source Code on GitHub")
                            .font(Typography.terminal)
                    }
                    .foregroundStyle(ColorSystem.primary)
                }
            }
        }
    }

    // MARK: - Data Collection Section

    private var dataCollectionSection: some View {
        PolicySection(title: "Data Collection", icon: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                // No data badge
                HStack(spacing: layout.tightSpacing) {
                    Text("WE COLLECT:")
                        .font(Typography.badge)
                        .foregroundStyle(ColorSystem.success)
                    Text("NOTHING")
                        .font(Typography.badge)
                        .foregroundStyle(ColorSystem.success)
                }
                .padding(.horizontal, layout.tightSpacing)
                .padding(.vertical, layout.ultraTightSpacing)
                .background(ColorSystem.success.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

                Text("Cdev does not collect, transmit, or store any of your data on external servers:")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                    PolicyBulletPoint("No analytics or tracking", color: ColorSystem.success)
                    PolicyBulletPoint("No crash reporting to external services", color: ColorSystem.success)
                    PolicyBulletPoint("No advertising SDKs", color: ColorSystem.success)
                    PolicyBulletPoint("No user accounts or registration", color: ColorSystem.success)
                    PolicyBulletPoint("No telemetry of any kind", color: ColorSystem.success)
                }
            }
        }
    }

    // MARK: - How It Works Section

    private var howItWorksSection: some View {
        PolicySection(title: "How Cdev Works", icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("Cdev is a companion app that connects directly to your local Claude Code agent. All communication stays within your local network.")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Architecture diagram
                VStack(spacing: layout.ultraTightSpacing) {
                    Text("┌─────────────┐     ┌─────────────┐")
                    Text("│  Your iPhone │ ←→ │ Your Agent  │")
                    Text("│    (Cdev)    │     │  (Computer) │")
                    Text("└─────────────┘     └─────────────┘")
                    Text("        └── Local Network Only ──┘")
                }
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.primary)
                .padding(layout.smallPadding)
                .frame(maxWidth: .infinity)
                .background(ColorSystem.terminalBgElevated)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
    }

    // MARK: - Network Communication Section

    private var networkCommunicationSection: some View {
        PolicySection(title: "Network Communication", icon: "network") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("The app communicates only with your local agent:")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                    PolicyBulletPoint("HTTP/WebSocket to your agent's local IP address")
                    PolicyBulletPoint("Real-time log streaming over your WiFi network")
                    PolicyBulletPoint("Prompts sent directly to your agent, not to any cloud")
                    PolicyBulletPoint("No internet connection required for core functionality")
                }

                // No cloud badge
                HStack(spacing: layout.tightSpacing) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: layout.iconSmall))
                    Text("NO CLOUD SERVERS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(ColorSystem.info)
                .padding(.horizontal, layout.smallPadding)
                .padding(.vertical, layout.tightSpacing)
                .background(ColorSystem.info.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
    }

    // MARK: - Local Storage Section

    private var localStorageSection: some View {
        PolicySection(title: "Local Storage", icon: "internaldrive") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("Cdev stores minimal data locally on your device:")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                    PolicyBulletPoint("Workspace URLs (stored in iOS Keychain)")
                    PolicyBulletPoint("Workspace names for display")
                    PolicyBulletPoint("App preferences (timestamps, theme)")
                    PolicyBulletPoint("Debug logs (optional, stays on device)")
                }

                Text("All local data is deleted when you uninstall the app.")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
        }
    }

    // MARK: - Third Party Section

    private var thirdPartySection: some View {
        PolicySection(title: "Third-Party Services", icon: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                // No third party badge
                HStack(spacing: layout.tightSpacing) {
                    Text("THIRD-PARTY SDKs:")
                        .font(Typography.badge)
                        .foregroundStyle(ColorSystem.success)
                    Text("NONE")
                        .font(Typography.badge)
                        .foregroundStyle(ColorSystem.success)
                }
                .padding(.horizontal, layout.tightSpacing)
                .padding(.vertical, layout.ultraTightSpacing)
                .background(ColorSystem.success.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

                Text("Cdev uses only native Apple frameworks. We do not include any third-party analytics, advertising, or tracking libraries.")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Verify this claim by reviewing our source code.")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textTertiary)
            }
        }
    }

    // MARK: - Changes Section

    private var changesSection: some View {
        PolicySection(title: "Policy Changes", icon: "doc.badge.clock") {
            Text("If this privacy policy changes, updates will be reflected in the source code repository and app release notes. Since we collect no data, changes are unlikely to affect you.")
                .font(layout.isCompact ? Typography.terminal : Typography.body)
                .foregroundStyle(ColorSystem.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Contact Section

    private var contactSection: some View {
        PolicySection(title: "Contact", icon: "envelope") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("Questions or concerns? Reach out or open an issue:")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                VStack(alignment: .leading, spacing: layout.tightSpacing) {
                    Button {
                        if let url = URL(string: "mailto:brianly1003@gmail.com") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: layout.tightSpacing) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: layout.iconMedium))
                            Text("brianly1003@gmail.com")
                                .font(Typography.terminal)
                        }
                        .foregroundStyle(ColorSystem.primary)
                    }

                    Button {
                        if let url = URL(string: "https://github.com/brianly1003/cdev-ios/issues") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: layout.tightSpacing) {
                            Image(systemName: "ladybug.fill")
                                .font(.system(size: layout.iconMedium))
                            Text("GitHub Issues")
                                .font(Typography.terminal)
                        }
                        .foregroundStyle(ColorSystem.primary)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: layout.tightSpacing) {
            Divider()
                .background(ColorSystem.terminalBgHighlight)

            Text("Open source. Privacy by design. Verify it yourself.")
                .font(Typography.terminalSmall)
                .italic()
                .foregroundStyle(ColorSystem.textTertiary)

            Text("© 2026 Brian Ly. MIT License.")
                .font(.system(size: layout.isCompact ? 9 : 11, weight: .medium))
                .foregroundStyle(ColorSystem.textQuaternary)
        }
        .padding(.top, layout.standardPadding)
    }
}

// MARK: - Policy Section Component

private struct PolicySection<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            // Section Header
            HStack(spacing: layout.tightSpacing) {
                Image(systemName: icon)
                    .font(.system(size: layout.iconMedium))
                    .foregroundStyle(ColorSystem.primary)

                Text(title)
                    .font(.system(size: layout.isCompact ? 14 : 16, weight: .semibold))
                    .foregroundStyle(ColorSystem.textPrimary)
            }

            // Content
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(layout.standardPadding)
        .background(ColorSystem.terminalBgElevated)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

// MARK: - Policy Bullet Point

private struct PolicyBulletPoint: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    let text: String
    let color: Color

    init(_ text: String, color: Color = ColorSystem.textPrimary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        HStack(alignment: .top, spacing: layout.tightSpacing) {
            Text("•")
                .font(layout.isCompact ? Typography.terminal : Typography.body)
                .foregroundStyle(color)

            Text(text)
                .font(layout.isCompact ? Typography.terminal : Typography.body)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PrivacyPolicyView()
}
