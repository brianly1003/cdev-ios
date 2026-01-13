import SwiftUI

/// Floating attachment menu popup - Messenger-style floating card above action bar
/// Compact UI matching CommandSuggestionsView styling
struct AttachmentMenuPopup: View {
    let onCamera: () -> Void
    let onPhotoLibrary: () -> Void
    let onScreenshot: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AttachmentMenuRow(icon: "camera.fill", title: "Camera", action: onCamera)
            Divider().background(ColorSystem.terminalBgHighlight)
            AttachmentMenuRow(icon: "photo.on.rectangle", title: "Photos", action: onPhotoLibrary)
            Divider().background(ColorSystem.terminalBgHighlight)
            AttachmentMenuRow(icon: "camera.viewfinder", title: "Screenshot", action: onScreenshot)
        }
        .frame(width: 160)  // Compact fixed width - fits all labels
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorSystem.terminalBgElevated)
                .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ColorSystem.terminalBgHighlight, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            AppLogger.log("[AttachmentMenu] Popup appeared")
        }
    }
}

/// Compact menu row - matches CommandSuggestionsView styling
private struct AttachmentMenuRow: View {
    let icon: String
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            AppLogger.log("[AttachmentMenu] \(title) tapped")
            Haptics.light()
            action()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isDisabled ? ColorSystem.textQuaternary : ColorSystem.primary)
                    .frame(width: 20)

                Text(title)
                    .font(Typography.terminal)  // 12pt mono - matches CommandSuggestionsView
                    .foregroundStyle(isDisabled ? ColorSystem.textQuaternary : ColorSystem.textPrimary)

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        ColorSystem.terminalBg
            .ignoresSafeArea()

        VStack {
            Spacer()

            // Floating popup
            AttachmentMenuPopup(
                onCamera: { print("Camera") },
                onPhotoLibrary: { print("Photos") },
                onScreenshot: { print("Screenshot") }
            )
            .padding(.leading, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: -60)

            // Simulated action bar
            HStack {
                Circle()
                    .fill(ColorSystem.primary)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(45))  // Shows as ×
                    )

                RoundedRectangle(cornerRadius: 8)
                    .fill(ColorSystem.terminalBgHighlight)
                    .frame(height: 36)
            }
            .padding()
        }
    }
}
