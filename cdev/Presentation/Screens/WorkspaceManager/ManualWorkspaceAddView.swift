import SwiftUI

// MARK: - Manual Workspace Add View

/// Compact sheet for quickly adding a workspace by path
/// Alternative to Discovery Repos for users who know the exact path
struct ManualWorkspaceAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Callback when workspace is successfully added
    var onAdd: ((String) async throws -> Void)?

    /// Callback when user wants to connect immediately after adding
    var onAddAndConnect: ((RemoteWorkspace) async -> Void)?

    @State private var path: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showSuccess: Bool = false
    @FocusState private var isPathFocused: Bool

    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }
    private var isCompact: Bool { sizeClass == .compact }

    // MARK: - Validation

    /// Check if path looks valid (basic client-side validation)
    private var isPathValid: Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        // Must start with / (absolute path) and have at least one directory
        return trimmed.hasPrefix("/") && trimmed.count > 1 && !trimmed.contains("//")
    }

    /// Validation message for display
    private var validationHint: String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if !trimmed.hasPrefix("/") {
            return "Path must be absolute (start with /)"
        }
        if trimmed.contains("//") {
            return "Invalid path format"
        }
        return nil
    }

    /// Extract repo name from path for display
    private var derivedName: String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header info
                headerSection

                Divider()
                    .background(ColorSystem.terminalBgHighlight)

                // Main form
                ScrollView {
                    VStack(spacing: layout.sectionSpacing) {
                        pathInputSection
                        previewSection
                    }
                    .padding(layout.standardPadding)
                }

                Divider()
                    .background(ColorSystem.terminalBgHighlight)

                // Action buttons
                actionButtons
            }
            .background(ColorSystem.terminalBg)
            .navigationTitle("Add Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(ColorSystem.textSecondary)
                }
            }
            .onAppear {
                // Auto-focus path field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPathFocused = true
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: layout.contentSpacing) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: layout.iconLarge))
                .foregroundStyle(ColorSystem.primary)
                .frame(width: 36, height: 36)
                .background(ColorSystem.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Add")
                    .font(Typography.bodyBold)
                    .foregroundStyle(ColorSystem.textPrimary)

                Text("Enter the full path to your repository")
                    .font(Typography.caption1)
                    .foregroundStyle(ColorSystem.textTertiary)
            }

            Spacer()
        }
        .padding(layout.standardPadding)
        .background(ColorSystem.terminalBgElevated)
    }

    // MARK: - Path Input Section

    private var pathInputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Label
            Text("Repository Path")
                .font(Typography.caption1)
                .fontWeight(.medium)
                .foregroundStyle(ColorSystem.textSecondary)

            // Input field
            HStack(spacing: layout.contentSpacing) {
                Image(systemName: "folder")
                    .font(.system(size: layout.iconMedium))
                    .foregroundStyle(ColorSystem.textTertiary)

                TextField("", text: $path, prompt: Text("/Users/you/projects/repo").foregroundStyle(ColorSystem.textQuaternary))
                    .font(Typography.terminal)
                    .foregroundStyle(ColorSystem.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .focused($isPathFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        if isPathValid && !isLoading {
                            Task { await addWorkspace() }
                        }
                    }

                // Clear button - use iconAction for better tap target
                if !path.isEmpty {
                    Button {
                        path = ""
                        Haptics.light()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: layout.iconAction))
                            .foregroundStyle(ColorSystem.textTertiary)
                            .frame(width: layout.buttonHeightSmall, height: layout.buttonHeightSmall)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, layout.contentSpacing)
            .padding(.vertical, layout.contentSpacing)
            .background(ColorSystem.terminalBgHighlight)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(
                        errorMessage != nil ? ColorSystem.error.opacity(0.5) :
                        (isPathFocused ? ColorSystem.primary.opacity(0.5) : .clear),
                        lineWidth: 1
                    )
            )

            // Validation hint or error
            if let error = errorMessage {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(Typography.caption1)
                }
                .foregroundStyle(ColorSystem.error)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let hint = validationHint {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text(hint)
                        .font(Typography.caption1)
                }
                .foregroundStyle(ColorSystem.warning)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: errorMessage)
        .animation(.easeInOut(duration: 0.15), value: validationHint)
    }

    // MARK: - Preview Section

    @ViewBuilder
    private var previewSection: some View {
        if isPathValid && !derivedName.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Preview")
                    .font(Typography.caption1)
                    .fontWeight(.medium)
                    .foregroundStyle(ColorSystem.textSecondary)

                HStack(spacing: layout.contentSpacing) {
                    // Folder icon
                    Image(systemName: "folder.fill")
                        .font(.system(size: layout.iconMedium))
                        .foregroundStyle(ColorSystem.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(derivedName)
                            .font(Typography.bodyBold)
                            .foregroundStyle(ColorSystem.textPrimary)

                        Text(path.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(Typography.terminalSmall)
                            .foregroundStyle(ColorSystem.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    // Checkmark indicator
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: layout.iconMedium))
                        .foregroundStyle(ColorSystem.success)
                }
                .padding(layout.contentSpacing)
                .background(ColorSystem.terminalBgElevated)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: layout.contentSpacing) {
            // Add button (primary)
            Button {
                Task { await addWorkspace() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: layout.iconMedium))
                    }

                    Text(isLoading ? "Adding..." : "Add Workspace")
                        .font(Typography.buttonLabel)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: layout.buttonHeight)
                .background(
                    isPathValid && !isLoading
                        ? ColorSystem.primary
                        : ColorSystem.primary.opacity(0.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)
            .disabled(!isPathValid || isLoading)
        }
        .padding(layout.standardPadding)
        .background(ColorSystem.terminalBgElevated)
    }

    // MARK: - Actions

    private func addWorkspace() async {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await onAdd?(trimmedPath)
            Haptics.success()

            // Show success and dismiss
            showSuccess = true
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            dismiss()
        } catch {
            Haptics.error()
            errorMessage = extractErrorMessage(from: error)
            isLoading = false
        }
    }

    /// Extract user-friendly error message
    private func extractErrorMessage(from error: Error) -> String {
        if let wsError = error as? WorkspaceManagerError {
            switch wsError {
            case .rpcError(_, let message):
                // Clean up common server error messages
                if message.contains("not a git repository") {
                    return "Not a git repository"
                }
                if message.contains("no such file or directory") || message.contains("does not exist") {
                    return "Path does not exist"
                }
                if message.contains("already exists") || message.contains("already registered") {
                    return "Workspace already added"
                }
                return message
            default:
                return wsError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Preview

#Preview {
    ManualWorkspaceAddView()
}

#Preview("With Path") {
    ManualWorkspaceAddView()
}
