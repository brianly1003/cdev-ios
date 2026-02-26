# Image Upload UI Design - cdev-ios

> **Status:** Design Complete
> **Principle:** Compact, Fast, Developer-First
> **Goal:** Enable developers to quickly share screenshots/images with Claude Code while maintaining the terminal-first aesthetic

---

## Executive Summary

This design introduces image upload capabilities to cdev-ios with a **one-tap workflow** that respects the app's compact, terminal-focused design. The UI integrates seamlessly into the existing `ActionBarView` without disrupting the current user experience.

**Key Design Decisions:**
1. **Inline Attachment Strip** - Images appear as compact thumbnails above the input field
2. **Quick Actions Menu** - Single tap opens camera/library/clipboard/screenshot options
3. **Progressive Upload** - Images upload immediately, show inline progress
4. **Drag-to-Remove** - Swipe down on thumbnail to remove (no extra taps)

---

## UI Architecture

### Component Hierarchy

```
ActionBarView (enhanced)
├── ImageAttachmentStrip (NEW - conditional)
│   ├── AttachedImageThumbnail (60x60pt)
│   │   ├── Image preview
│   │   ├── Upload progress overlay
│   │   ├── Status indicator (✓/⚠/×)
│   │   └── Remove gesture target
│   └── AddMoreButton (when < 4 images)
├── HStack (existing input row)
│   ├── ImageAttachButton (NEW - replaces/augments voice button position)
│   ├── BashModeToggle (existing)
│   ├── StopButton (existing, conditional)
│   └── PromptInputField (existing)
│       ├── RainbowTextField
│       ├── ClearButton
│       └── SendButton
└── CommandSuggestionsOverlay (existing)
```

---

## Component Designs

### 1. ImageAttachButton

**Location:** Left side of ActionBarView, before bash toggle
**Size:** 32x32pt (iPhone), 36x36pt (iPad) - matches bash toggle

```
┌──────────────────────────────────────────────────────────────────┐
│  [📎]  [>_]  ┌────────────────────────────────────────┐  [➤]    │
│  attach bash │ Ask Claude...                          │  send   │
│              └────────────────────────────────────────┘          │
└──────────────────────────────────────────────────────────────────┘
```

**States:**
- **Default:** Plus icon with subtle circle background
- **Has Images:** Badge count overlay (1-4)
- **Uploading:** Pulsing animation
- **Error:** Red dot indicator

**Interaction:**
- Tap → Opens attachment menu (sheet on iPhone, popover on iPad)
- Long press → Quick photo library access (power user shortcut)

```swift
/// Image attachment button following cdev design system
/// Uses: ColorSystem, ResponsiveLayout, Typography, Spacing, CornerRadius
struct ImageAttachButton: View {
    let attachedCount: Int
    let isUploading: Bool
    let hasError: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Main icon - uses layout.iconAction (14pt iPhone, 16pt iPad)
                Image(systemName: attachedCount > 0 ? "photo.stack" : "plus.circle.fill")
                    .font(.system(size: layout.iconAction, weight: .semibold))
                    .foregroundStyle(attachedCount > 0 ? ColorSystem.primary : ColorSystem.textTertiary)
                    .frame(width: layout.indicatorSize, height: layout.indicatorSize) // 32pt iPhone, 36pt iPad
                    .background(
                        attachedCount > 0
                            ? ColorSystem.primary.opacity(0.15)  // Teal tint when active
                            : ColorSystem.terminalBgHighlight    // #282D36 dark mode
                    )
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(
                                attachedCount > 0 ? ColorSystem.primaryGlow : .clear,
                                lineWidth: layout.borderWidthThick  // 1.5pt iPhone, 2pt iPad
                            )
                    )

                // Count badge - using Typography.badge styling
                if attachedCount > 0 {
                    Text("\(attachedCount)")
                        .font(Typography.badge)  // 9pt rounded bold
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(ColorSystem.primary)  // Cdev Teal
                        .clipShape(Circle())
                        .offset(x: Spacing.xxs, y: -Spacing.xxs)  // 4pt offset
                }

                // Error indicator - using ColorSystem.error (soft coral-red)
                if hasError {
                    Circle()
                        .fill(ColorSystem.error)  // #FC8181 dark mode
                        .frame(width: layout.dotSize + 2, height: layout.dotSize + 2)  // 8pt iPhone
                        .offset(x: Spacing.xxs, y: -Spacing.xxs)
                }

                // Uploading pulse animation
                if isUploading {
                    Circle()
                        .stroke(ColorSystem.primary, lineWidth: layout.borderWidth)
                        .frame(width: layout.indicatorSize + Spacing.xxs, height: layout.indicatorSize + Spacing.xxs)
                        .opacity(0.5)
                        .scaleEffect(1.2)
                        .animation(Animations.pulse, value: isUploading)
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onLongPress() }
        )
    }
}
```

---

### 2. Attachment Menu (Sheet/Popover)

**Design:** Compact action sheet with 4 options
**Animation:** Spring from bottom (iPhone), popover (iPad)

```
┌─────────────────────────────────────────┐
│           Attach Image                   │
├─────────────────────────────────────────┤
│  📷  Take Photo                          │
│  🖼️  Photo Library                       │
│  📋  Paste from Clipboard                │
│  📱  Capture App Screenshot              │
├─────────────────────────────────────────┤
│  ⓘ  Max 4 images • 10MB each            │
└─────────────────────────────────────────┘
```

```swift
/// Attachment menu following cdev design system
/// Uses: ColorSystem, Typography, Spacing, CornerRadius
struct AttachmentMenuView: View {
    let onCamera: () -> Void
    let onPhotoLibrary: () -> Void
    let onPaste: () -> Void
    let onScreenshot: () -> Void
    let clipboardHasImage: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        VStack(spacing: 0) {
            // Header - using Typography.bodyBold
            Text("Attach Image")
                .font(Typography.bodyBold)
                .foregroundStyle(ColorSystem.textPrimary)  // Warm off-white #E2E8F0
                .padding(.vertical, Spacing.md)  // 16pt

            Divider()
                .background(ColorSystem.terminalBgHighlight)  // #282D36

            // Actions - consistent row styling
            VStack(spacing: 0) {
                AttachmentMenuRow(
                    icon: "camera.fill",
                    title: "Take Photo",
                    action: { dismiss(); onCamera() }
                )

                AttachmentMenuRow(
                    icon: "photo.on.rectangle",
                    title: "Photo Library",
                    action: { dismiss(); onPhotoLibrary() }
                )

                AttachmentMenuRow(
                    icon: "doc.on.clipboard",
                    title: "Paste from Clipboard",
                    subtitle: clipboardHasImage ? nil : "No image in clipboard",
                    isDisabled: !clipboardHasImage,
                    action: { dismiss(); onPaste() }
                )

                AttachmentMenuRow(
                    icon: "camera.viewfinder",
                    title: "Capture App Screenshot",
                    action: { dismiss(); onScreenshot() }
                )
            }

            Divider()
                .background(ColorSystem.terminalBgHighlight)

            // Info footer - using Typography.caption2 and ColorSystem.textQuaternary
            HStack(spacing: Spacing.xs) {  // 8pt spacing
                Image(systemName: "info.circle")
                    .font(.system(size: layout.iconSmall))  // 9pt iPhone, 10pt iPad
                Text("Max 4 images • 10MB each • Expires in 1 hour")
                    .font(Typography.caption2)
            }
            .foregroundStyle(ColorSystem.textQuaternary)  // Disabled gray #4A5568
            .padding(.vertical, Spacing.sm)  // 12pt
        }
        .background(ColorSystem.terminalBgElevated)  // Elevated surface #1E2128
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))  // 12pt
        .padding(.horizontal, Spacing.md)  // 16pt
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
}

/// Menu row following cdev design system
struct AttachmentMenuRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layout: ResponsiveLayout { ResponsiveLayout.current(for: sizeClass) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {  // 12pt spacing
                Image(systemName: icon)
                    .font(.system(size: layout.iconLarge, weight: .medium))  // 16pt iPhone, 18pt iPad
                    .foregroundStyle(isDisabled ? ColorSystem.textQuaternary : ColorSystem.primary)
                    .frame(width: layout.iconXLarge)  // 24pt iPhone, 28pt iPad

                VStack(alignment: .leading, spacing: Spacing.xxxs) {  // 2pt spacing
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(isDisabled ? ColorSystem.textQuaternary : ColorSystem.textPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Typography.caption2)
                            .foregroundStyle(ColorSystem.textQuaternary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: layout.iconMedium, weight: .semibold))  // 12pt iPhone, 14pt iPad
                    .foregroundStyle(ColorSystem.textQuaternary)
            }
            .padding(.horizontal, Spacing.md)  // 16pt
            .padding(.vertical, Spacing.sm)    // 12pt
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
```

---

### 3. ImageAttachmentStrip

**Location:** Above the main input row, inside ActionBarView
**Animation:** Slides up when images added, collapses when empty
**Height:** 72pt (60pt thumbnail + 12pt padding)

```
┌──────────────────────────────────────────────────────────────────┐
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌──────┐                       │
│  │  img1  │ │  img2  │ │  img3  │ │  +   │  ← horizontal scroll  │
│  │   ✓    │ │  75%   │ │   ⚠    │ │ add  │                       │
│  └────────┘ └────────┘ └────────┘ └──────┘                       │
├──────────────────────────────────────────────────────────────────┤
│  [📎]  [>_]  ┌────────────────────────────────┐  [➤]             │
└──────────────────────────────────────────────────────────────────┘
```

```swift
/// Image attachment strip following cdev design system
/// Uses: ColorSystem, ResponsiveLayout, Spacing, Animations
struct ImageAttachmentStrip: View {
    @Binding var attachedImages: [AttachedImageState]
    let onRemove: (UUID) -> Void
    let onAddMore: () -> Void
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
                        onRemove: { onRemove(attached.id) }
                    )
                    .transition(.asymmetric(
                        insertion: Animations.fadeScale,
                        removal: .scale(scale: 0.5).combined(with: .opacity)
                    ))
                }

                // Add more button (when < 4 images)
                if canAddMore {
                    AddMoreImageButton(size: thumbnailSize, action: onAddMore)
                        .transition(Animations.fadeScale)
                }
            }
            .padding(.horizontal, layout.smallPadding)  // 8pt iPhone, 12pt iPad
            .padding(.vertical, Spacing.xxs)  // 4pt vertical padding
        }
        .frame(height: stripHeight)
        .background(ColorSystem.terminalBg)  // Main background #16181D
        .animation(Animations.stateChange, value: attachedImages.count)
    }
}

/// Thumbnail view following cdev design system
/// Uses: ColorSystem, Spacing, CornerRadius, Typography
struct AttachedImageThumbnail: View {
    let image: UIImage
    let uploadState: ImageUploadState
    let size: CGFloat
    let onRemove: () -> Void

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

        case .cancelled:
            EmptyView()
        }
    }

    private var borderColor: Color {
        switch uploadState {
        case .uploaded: return ColorSystem.successGlow  // Green glow when uploaded
        case .failed: return ColorSystem.errorGlow      // Red glow when failed
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
                withAnimation(Animations.spring) {
                    dragOffset = 0
                }
            }
    }
}

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
```

---

### 4. CircularProgressView

**Reusable component for upload progress**

```swift
/// Circular progress indicator following cdev design system
/// Uses: ColorSystem.primary (Cdev Teal) for progress arc
struct CircularProgressView: View {
    let progress: Double
    var size: CGFloat = 30
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            // Background circle - subtle white
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: lineWidth)

            // Progress arc - using ColorSystem.primary (Cdev Teal #4FD1C5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ColorSystem.primary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Animations.stateChange, value: progress)

            // Percentage text - using rounded design for consistency
            Text("\(Int(progress * 100))")
                .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
```

---

## State Management

### AttachedImageState Model

```swift
struct AttachedImageState: Identifiable, Equatable {
    let id: UUID
    let originalImage: UIImage
    let thumbnail: UIImage         // 60x60 for preview
    let processedData: Data        // Compressed for upload
    let mimeType: String
    let sizeBytes: Int
    let source: ImageSource
    var uploadState: ImageUploadState
    var serverImageId: String?     // Set after successful upload
    var serverLocalPath: String?   // .cdev/images/xxx.jpg

    enum ImageSource: String {
        case camera
        case photoLibrary
        case clipboard
        case screenshot
    }

    var isUploaded: Bool {
        if case .uploaded = uploadState { return true }
        return false
    }

    var canRetry: Bool {
        if case .failed = uploadState { return true }
        return false
    }
}

enum ImageUploadState: Equatable {
    case pending
    case uploading(progress: Double)
    case uploaded(imageId: String, localPath: String)
    case failed(error: String)
    case cancelled
}
```

### ViewModel Integration

```swift
// In DashboardViewModel
@Published var attachedImages: [AttachedImageState] = []
@Published var isShowingAttachmentMenu: Bool = false

// Computed
var canAttachMoreImages: Bool { attachedImages.count < 4 }
var hasAttachedImages: Bool { !attachedImages.isEmpty }
var isUploadingImages: Bool { attachedImages.contains {
    if case .uploading = $0.uploadState { return true }
    return false
}}
var allImagesUploaded: Bool { attachedImages.allSatisfy { $0.isUploaded } }

// Actions
func attachImage(_ image: UIImage, source: AttachedImageState.ImageSource) async {
    // 1. Process image (resize, compress)
    // 2. Generate thumbnail
    // 3. Add to attachedImages with .pending state
    // 4. Start upload immediately
    // 5. Update state as upload progresses
}

func removeAttachedImage(_ id: UUID) {
    attachedImages.removeAll { $0.id == id }
    // Cancel upload if in progress
}

func retryUpload(_ id: UUID) async {
    // Re-upload failed image
}

// Enhanced sendPrompt
func sendPrompt() async {
    // Wait for all uploads to complete (or skip failed ones)
    let uploadedPaths = attachedImages
        .filter { $0.isUploaded }
        .compactMap { $0.serverLocalPath }

    // Construct prompt with image paths
    var finalPrompt = promptText
    if !uploadedPaths.isEmpty {
        finalPrompt += "\n\n[Attached images: \(uploadedPaths.joined(separator: ", "))]"
    }

    // Send via existing runClaude API
    // Clear attachedImages on success
}
```

---

## User Flows

### Flow 1: Quick Screenshot Share (Primary Use Case)

```
User encounters bug in simulator
        ↓
Takes screenshot (⌘+Shift+4 or device)
        ↓
Opens cdev-ios, pastes from clipboard (or taps attach → paste)
        ↓
Image appears in strip, auto-uploads
        ↓
Types "fix this UI bug shown in screenshot"
        ↓
Taps send → Claude receives image path + prompt
        ↓
Claude analyzes and responds with fix
```

**Optimization:** Detect clipboard image on app foreground, show subtle indicator on attach button.

### Flow 2: Multi-Image Context

```
User needs to show multiple files/screens
        ↓
Taps attach → Photo Library
        ↓
Selects up to 4 images
        ↓
All appear in strip, upload in parallel
        ↓
Progress shown per-image
        ↓
Types "compare these implementations and suggest improvements"
        ↓
Send when all uploaded (or prompt to wait)
```

### Flow 3: Camera Capture

```
User has physical device with issue
        ↓
Taps attach → Take Photo
        ↓
Camera opens, user captures
        ↓
Auto-processes (orientation, compression)
        ↓
Uploads immediately
        ↓
Ready to send
```

---

## Error Handling UI

### Upload Errors

| Error | User Message | Action |
|-------|--------------|--------|
| `image_too_large` | "Image too large (max 10MB)" | Suggest reselecting |
| `rate_limit_exceeded` | "Too many uploads, wait 60s" | Show countdown |
| `storage_full` | "Server storage full" | Offer to clear old images |
| `unsupported_type` | "Format not supported" | List supported formats |
| `network_error` | "Upload failed" | Retry button |
| `timeout` | "Upload timed out" | Retry button |

### Error Display

```swift
// In attachment strip - failed images show:
// 1. Red overlay with warning icon
// 2. "Retry" label
// 3. Tap to retry OR swipe to remove

// Toast notification for errors:
CdevToast(
    message: "Image upload failed: Too large",
    type: .error,
    action: ("Retry", { retryUpload() })
)
```

---

## Accessibility

```swift
// AttachButton
.accessibilityLabel("Attach image")
.accessibilityHint("Opens menu to attach photos, take pictures, or paste from clipboard")
.accessibilityValue(attachedCount > 0 ? "\(attachedCount) images attached" : "No images attached")

// Thumbnail
.accessibilityLabel("Attached image \(index + 1)")
.accessibilityHint("Double tap to remove")
.accessibilityAddTraits(uploadState == .uploading ? .updatesFrequently : [])

// Progress
.accessibilityValue("Uploading \(Int(progress * 100)) percent")
```

---

## Performance Considerations

1. **Thumbnail Generation:** Generate 60x60pt thumbnails immediately for smooth UI
2. **Background Upload:** Use URLSession background configuration
3. **Memory:** Release original UIImage after processing, keep only Data
4. **Parallel Uploads:** Max 2 concurrent to avoid overwhelming network
5. **Caching:** Don't cache uploaded images (they expire on server anyway)

---

## iPad Optimizations

```swift
// Use popover instead of sheet for attachment menu
.popover(isPresented: $isShowingAttachmentMenu, arrowEdge: .bottom) {
    AttachmentMenuView(...)
        .frame(width: 280)
}

// Larger thumbnails on iPad
private var thumbnailSize: CGFloat { layout.isCompact ? 60 : 80 }

// Keyboard shortcut
.keyboardShortcut("i", modifiers: [.command])  // ⌘I to attach
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (Data Layer)
- [ ] `ImageAttachment` model
- [ ] `ImageProcessingService` (resize, compress, HEIC→JPEG)
- [ ] `ImageUploadService` (multipart upload, progress tracking)
- [ ] Response models matching API

### Phase 2: Basic UI
- [ ] `ImageAttachButton` component
- [ ] `AttachmentMenuView` sheet
- [ ] `ImagePicker` wrapper (PHPicker)
- [ ] Integration into `ActionBarView`

### Phase 3: Attachment Strip
- [ ] `ImageAttachmentStrip` component
- [ ] `AttachedImageThumbnail` with states
- [ ] `CircularProgressView`
- [ ] Drag-to-remove gesture

### Phase 4: ViewModel Integration
- [ ] `attachedImages` state in `DashboardViewModel`
- [ ] Auto-upload on attach
- [ ] Enhanced `sendPrompt()` with image paths
- [ ] Error handling and retry

### Phase 5: Polish
- [ ] Clipboard image detection
- [ ] Screenshot capture
- [ ] iPad popover optimization
- [ ] Keyboard shortcuts (⌘I)
- [ ] Accessibility labels

---

## File Structure

```
cdev/
├── Domain/
│   └── Models/
│       ├── ImageAttachment.swift          # AttachedImageState, ImageUploadState
│       └── ImageUploadResponse.swift      # API response models
├── Data/
│   └── Services/
│       ├── ImageProcessingService.swift   # Resize, compress, HEIC conversion
│       └── ImageUploadService.swift       # HTTP multipart upload
└── Presentation/
    └── Screens/
        └── Dashboard/
            └── Components/
                ├── ImageAttachButton.swift
                ├── AttachmentMenuView.swift
                ├── ImageAttachmentStrip.swift
                ├── AttachedImageThumbnail.swift
                └── CircularProgressView.swift
```

---

## Summary

This design delivers a **fast, compact, developer-focused** image upload experience:

| Feature | Benefit |
|---------|---------|
| One-tap attach | No friction to share screenshots |
| Inline progress | Know exactly when ready to send |
| Drag-to-remove | No modal confirmations |
| Auto-upload | Images ready before prompt typed |
| Clipboard detection | Even faster for screenshots |
| Compact strip | Minimal vertical space |
| Error recovery | Clear retry path |

**Differentiator:** No other mobile AI coding tool offers this level of seamless screenshot-to-Claude integration.
