import SwiftUI

/// Settings view - compact, essential settings only
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Constants.UserDefaults.showTimestamps) private var showTimestamps = true
    @AppStorage(Constants.UserDefaults.syntaxHighlighting) private var syntaxHighlighting = true
    @AppStorage(Constants.UserDefaults.hapticFeedback) private var hapticFeedback = true
    @AppStorage(Constants.UserDefaults.autoReconnect) private var autoReconnect = true

    var body: some View {
        NavigationStack {
            List {
                // Display
                Section("Display") {
                    Toggle("Show Timestamps", isOn: $showTimestamps)
                    Toggle("Syntax Highlighting", isOn: $syntaxHighlighting)
                }

                // Behavior
                Section("Behavior") {
                    Toggle("Haptic Feedback", isOn: $hapticFeedback)
                    Toggle("Auto-Reconnect", isOn: $autoReconnect)
                }

                // Connection
                Section("Connection") {
                    Button("Disconnect", role: .destructive) {
                        // TODO: Implement disconnect
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/brianly1003/cdev-ios")!) {
                        HStack {
                            Text("Source Code")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
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

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
