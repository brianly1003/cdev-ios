import SwiftUI

/// Image attachment strip following cdev design system
/// Uses: ColorSystem, ResponsiveLayout, Spacing, Animations
struct ImageAttachmentStrip: View {
    @Binding var attachedImages: [AttachedImageState]
    let onRemove: (UUID) -> Void
    let onAddMore: () -> Void
    let onRetry: (UUID) -> Void
    let canAddMore: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    /// Thumbnail size: 60pt iPhone, 72pt iPad
    private var thumbnailSize: CGFloat { layout.isCompact ? 60 : 72 }

    /// Strip height includes thumbnail + padding
    private var stripHeight: CGFloat { thumbnailSize + Spacing.sm }  // 72pt iPhone, 84pt iPad

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {  // 8pt spacing between thumbnails
                ForEach(attachedImages) { attached in
                    AttachedImageThumbnail(
                        image: attached.thumbnail,
                        uploadState: attached.uploadState,
                        size: thumbnailSize,
                        onRemove: { onRemove(attached.id) },
                        onRetry: { onRetry(attached.id) }
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale(scale: 0.5).combined(with: .opacity)
                    ))
                }

                // Add more button (when < 4 images)
                if canAddMore {
                    AddMoreImageButton(size: thumbnailSize, action: onAddMore)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.top, Spacing.xs)  // 4pt top padding
        }
        .frame(height: stripHeight)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .fill(Color.black.opacity(0.0))  // Semi-transparent like AttachmentMenuPopup
        )
        // .overlay(
        //     RoundedRectangle(cornerRadius: CornerRadius.medium)
        //         .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        // )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .animation(Animations.stateChange, value: attachedImages.count)
    }
}

// MARK: - Attached Image Thumbnail

/// Thumbnail view following cdev design system
/// Uses: ColorSystem, Spacing, CornerRadius, Typography
struct AttachedImageThumbnail: View {
    let image: UIImage
    let uploadState: ImageUploadState
    let size: CGFloat
    let onRemove: () -> Void
    let onRetry: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Image preview with corner radius
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))  // 8pt
                .overlay(uploadStateOverlay)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .strokeBorder(borderColor, lineWidth: 1.5)
                )

            // Remove button - white X on semi-transparent background
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .offset(x: Spacing.xxs + 2, y: -(Spacing.xxs + 2))  // 6pt offset
        }
        .offset(y: dragOffset)
        .gesture(removeGesture)
        .opacity(isDragging ? 0.5 : 1.0)
    }

    @ViewBuilder
    private var uploadStateOverlay: some View {
        switch uploadState {
        case .pending:
            // Slight dim - using standard opacity
            Color.black.opacity(0.2)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

        case .uploading(let progress):
            ZStack {
                Color.black.opacity(0.4)
                CircularProgressView(progress: progress, size: size * 0.45)  // ~28pt for 60pt thumbnail
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

        case .uploaded:
            // Success checkmark using ColorSystem.success (Terminal Mint)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ColorSystem.success)  // #68D391 dark mode
                        .background(Circle().fill(.white).padding(2))
                        .padding(Spacing.xxs)  // 4pt
                }
            }

        case .failed:
            // Error state using ColorSystem.error (Signal Coral)
            Button(action: onRetry) {
                ZStack {
                    ColorSystem.error.opacity(0.3)  // Soft coral-red overlay
                    VStack(spacing: Spacing.xxxs) {  // 2pt spacing
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        Text("Retry")
                            .font(Typography.badge)  // 9pt bold rounded
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)

        case .cancelled:
            EmptyView()
        }
    }

    private var borderColor: Color {
        switch uploadState {
        case .uploaded: return ColorSystem.success.opacity(0.5)  // Green glow when uploaded
        case .failed: return ColorSystem.error.opacity(0.5)      // Red glow when failed
        default: return .clear
        }
    }

    // Drag down to remove gesture - threshold at 30pt
    private var removeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    isDragging = true
                    dragOffset = min(value.translation.height, 50)
                }
            }
            .onEnded { value in
                isDragging = false
                if value.translation.height > 30 {
                    Haptics.medium()
                    onRemove()
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    dragOffset = 0
                }
            }
    }
}

// MARK: - Add More Button

/// Add more button following cdev design system
struct AddMoreImageButton: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xxs) {  // 4pt spacing
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                Text("Add")
                    .font(Typography.badge)  // 9pt rounded bold
            }
            .foregroundStyle(ColorSystem.textTertiary)  // #718096
            .frame(width: size, height: size)
            .background(ColorSystem.terminalBgHighlight)  // #282D36
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))  // 8pt
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .strokeBorder(
                        ColorSystem.textQuaternary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [Spacing.xxs])  // 4pt dashes
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        // Empty state with add button
        ImageAttachmentStrip(
            attachedImages: .constant([]),
            onRemove: { _ in },
            onAddMore: {},
            onRetry: { _ in },
            canAddMore: true
        )

        Divider()

        // With sample images (would need real images in preview)
    }
    .background(ColorSystem.terminalBgElevated)
}
