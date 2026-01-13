//
//  TermsOfServiceView.swift
//  Cdev
//
//  Terms of Service for open source MIT-licensed app
//  Terminal-first design following cdev design system
//

import SwiftUI

struct TermsOfServiceView: View {
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
                        licenseSection
                        openSourceRightsSection
                        serviceDescriptionSection
                        acceptableUseSection
                        contentRightsSection
                        warrantySection
                        liabilitySection
                        contributionsSection
                        contactSection

                        // Footer
                        footerSection
                    }
                    .padding(.horizontal, layout.standardPadding)
                    .padding(.vertical, layout.smallPadding)
                }
            }
            .navigationTitle("Terms of Service")
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
            // Document icon
            Image(systemName: "doc.text.fill")
                .font(.system(size: layout.iconXLarge))
                .foregroundStyle(ColorSystem.primary)
                .padding(.bottom, layout.tightSpacing)

            Text("Terms of Service")
                .font(.system(size: layout.isCompact ? 20 : 24, weight: .bold, design: .rounded))
                .foregroundStyle(ColorSystem.textPrimary)
                .multilineTextAlignment(.center)

            Text("Last Updated: January 2026")
                .font(Typography.terminalSmall)
                .foregroundStyle(ColorSystem.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, layout.standardPadding)
    }

    // MARK: - License Section

    private var licenseSection: some View {
        TermsSection(title: "MIT License", icon: "checkmark.seal") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                // MIT badge
                HStack(spacing: layout.tightSpacing) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: layout.iconSmall))
                    Text("OPEN SOURCE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(ColorSystem.success)
                .padding(.horizontal, layout.smallPadding)
                .padding(.vertical, layout.tightSpacing)
                .background(ColorSystem.success.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

                Text("Cdev is released under the MIT License, one of the most permissive open source licenses available.")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // MIT License text
                VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                    Text("Permission is hereby granted, free of charge, to any person obtaining a copy of this software to deal in the Software without restriction, including:")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textSecondary)

                    VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                        TermsBulletPoint("Use, copy, modify, merge")
                        TermsBulletPoint("Publish, distribute, sublicense")
                        TermsBulletPoint("Sell copies of the Software")
                    }
                }
                .padding(layout.smallPadding)
                .background(ColorSystem.terminalBg)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

                Button {
                    if let url = URL(string: "https://github.com/brianly1003/cdev-ios/blob/main/LICENSE") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: layout.tightSpacing) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: layout.iconMedium))
                        Text("View Full License on GitHub")
                            .font(Typography.terminal)
                    }
                    .foregroundStyle(ColorSystem.primary)
                }
            }
        }
    }

    // MARK: - Open Source Rights Section

    private var openSourceRightsSection: some View {
        TermsSection(title: "Your Rights", icon: "hand.raised") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("Under the MIT License, you are free to:")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                    TermsBulletPoint("Use Cdev for any purpose, personal or commercial", color: ColorSystem.success)
                    TermsBulletPoint("Modify the source code to suit your needs", color: ColorSystem.success)
                    TermsBulletPoint("Distribute your modifications", color: ColorSystem.success)
                    TermsBulletPoint("Include Cdev in your own projects", color: ColorSystem.success)
                }

                Text("The only requirement is to include the original copyright notice and license text in any copies or substantial portions of the Software.")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
            }
        }
    }

    // MARK: - Service Description Section

    private var serviceDescriptionSection: some View {
        TermsSection(title: "About Cdev", icon: "iphone.and.arrow.forward") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("Cdev is a free, open source mobile companion for Claude Code that enables you to:")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                    TermsBulletPoint("Monitor Claude Code sessions in real-time")
                    TermsBulletPoint("View terminal output and logs remotely")
                    TermsBulletPoint("Send prompts and interact with your agent")
                    TermsBulletPoint("Manage file diffs and tool permissions")
                    TermsBulletPoint("Connect via QR code pairing")
                }

                // Requirement note
                HStack(alignment: .top, spacing: layout.tightSpacing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: layout.iconSmall))
                        .foregroundStyle(ColorSystem.warning)
                    Text("Requires cdev-agent running on your local network. The app does not function independently.")
                        .font(Typography.terminalSmall)
                        .foregroundStyle(ColorSystem.textSecondary)
                }
                .padding(layout.smallPadding)
                .background(ColorSystem.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
    }

    // MARK: - Acceptable Use Section

    private var acceptableUseSection: some View {
        TermsSection(title: "Acceptable Use", icon: "checkmark.shield") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("While Cdev is open source, we ask that you:")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                    TermsBulletPoint("Use the app in compliance with applicable laws")
                    TermsBulletPoint("Respect others' intellectual property rights")
                    TermsBulletPoint("Not use the app for malicious purposes")
                    TermsBulletPoint("Include attribution if you redistribute")
                }
            }
        }
    }

    // MARK: - Content Rights Section

    private var contentRightsSection: some View {
        TermsSection(title: "Your Content", icon: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                VStack(alignment: .leading, spacing: layout.ultraTightSpacing) {
                    TermsBulletPoint("You retain all rights to your code and prompts")
                    TermsBulletPoint("Your content never passes through our servers")
                    TermsBulletPoint("All communication stays on your local network")
                    TermsBulletPoint("We make no claim to any of your data")
                }

                // Local network badge
                HStack(spacing: layout.tightSpacing) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: layout.iconSmall))
                    Text("LOCAL NETWORK ONLY")
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

    // MARK: - Warranty Section

    private var warrantySection: some View {
        TermsSection(title: "Warranty Disclaimer", icon: "exclamationmark.shield") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("This is standard MIT License language that applies to all open source software distributed under this license.")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Liability Section

    private var liabilitySection: some View {
        TermsSection(title: "Limitation of Liability", icon: "shield.slash") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.")
                    .font(Typography.terminalSmall)
                    .foregroundStyle(ColorSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("You use this software at your own risk. Always backup important data.")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)
            }
        }
    }

    // MARK: - Contributions Section

    private var contributionsSection: some View {
        TermsSection(title: "Contributions", icon: "person.2") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("We welcome contributions to Cdev! By submitting a pull request, you agree that your contribution will be licensed under the same MIT License.")
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
                        Text("Contribute on GitHub")
                            .font(Typography.terminal)
                    }
                    .foregroundStyle(ColorSystem.primary)
                }
            }
        }
    }

    // MARK: - Contact Section

    private var contactSection: some View {
        TermsSection(title: "Contact", icon: "envelope") {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                Text("Questions, issues, or feature requests?")
                    .font(layout.isCompact ? Typography.terminal : Typography.body)
                    .foregroundStyle(ColorSystem.textPrimary)

                VStack(alignment: .leading, spacing: layout.tightSpacing) {
                    HStack(spacing: layout.tightSpacing) {
                        Text("Author:")
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textTertiary)
                        Text("Brian Ly")
                            .font(Typography.terminal)
                            .foregroundStyle(ColorSystem.textPrimary)
                    }

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
                            Text("Open an Issue on GitHub")
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

            Text("Free and open source, forever.")
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

// MARK: - Terms Section Component

private struct TermsSection<Content: View>: View {
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

// MARK: - Terms Bullet Point

private struct TermsBulletPoint: View {
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
    TermsOfServiceView()
}
