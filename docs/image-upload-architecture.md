# Image Upload Architecture Design

> **Status:** Design Phase
> **Goal:** Enable sending images from cdev-ios → cdev-agent → Claude Code CLI
> **Principle:** Simple, elegant, local file path approach

---

## Executive Summary

This document outlines a streamlined architecture for image upload functionality:

1. **cdev-ios** - Native iOS image capture, selection, and upload
2. **cdev-agent** - Store images locally in `.cdev/images/` folder
3. **Claude Code CLI** - Reference images by local file path (Claude reads them directly)

**Key Insight:** Claude Code CLI can read images directly from local file paths. No need for base64 encoding via stdin - just store the image locally and pass the path in the prompt.

---

## Folder Structure Redesign

### Current Structure
```
repo/
├── .cdev-logs/           # Claude output logs
│   └── claude_12345.jsonl
└── ...
```

### New Structure
```
repo/
├── .cdev/                # All cdev-agent data
│   ├── logs/             # Claude output logs (renamed from .cdev-logs)
│   │   └── claude_12345.jsonl
│   └── images/           # Uploaded images from mobile
│       ├── img_abc123.jpg
│       ├── img_def456.png
│       └── ...
└── ...
```

**Benefits:**
- Single `.cdev/` folder for all cdev-agent data
- Easy to `.gitignore` the entire folder
- Images accessible to Claude Code CLI via local path
- Simple cleanup (just delete `.cdev/images/`)

---

## Target Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              cdev-ios                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ Camera/Photos│  │ Screenshot   │  │ Clipboard    │  │ Share Ext    │    │
│  │ Picker       │  │ Capture      │  │ Paste        │  │ Receive      │    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
│         └──────────────────┴──────────────────┴──────────────────┘          │
│                                    │                                         │
│                         ┌──────────▼──────────┐                             │
│                         │ ImageProcessingService│                            │
│                         │ - Compress/Resize     │                            │
│                         │ - EXIF correction     │                            │
│                         │ - Format conversion   │                            │
│                         └──────────┬──────────┘                             │
│                                    │                                         │
│                         ┌──────────▼──────────┐                             │
│                         │ HTTP Multipart       │                             │
│                         │ POST /api/images     │                             │
│                         └──────────┬──────────┘                             │
└──────────────────────────────────────┼──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              cdev-agent                                      │
│                         ┌──────────────────────┐                            │
│                         │ POST /api/images      │                            │
│                         │ - Multipart handler   │                            │
│                         │ - Size validation     │                            │
│                         │ - Format validation   │                            │
│                         └──────────┬───────────┘                            │
│                                    │                                         │
│                         ┌──────────▼──────────┐                             │
│                         │ Save to .cdev/images │                             │
│                         │ - Generate filename  │                            │
│                         │ - Return local path  │                            │
│                         └──────────┬──────────┘                             │
│                                    │                                         │
│                         ┌──────────▼──────────┐                             │
│                         │ POST /api/claude/run │                             │
│                         │ {                    │                             │
│                         │   "prompt": "...",   │                             │
│                         │   "image_paths": []  │  ← Local paths             │
│                         │ }                    │                             │
│                         └──────────┬──────────┘                             │
│                                    │                                         │
│                         ┌──────────▼──────────┐                             │
│                         │ ClaudeManager        │                             │
│                         │ - Build prompt with  │                             │
│                         │   image paths        │                             │
│                         └──────────┬──────────┘                             │
└──────────────────────────────────────┼──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Claude Code CLI                                    │
│                                                                              │
│  Prompt includes image path:                                                 │
│  "Look at the screenshot at .cdev/images/img_abc123.jpg and fix the bug"   │
│                                                                              │
│  Claude Code reads the image file directly from local filesystem            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Security, Performance & Edge Cases

### Rate Limiting & Spam Prevention

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Multi-Layer Protection                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Layer 1: iOS Client                                                         │
│  ├── Max 4 images per prompt                                                │
│  ├── Max 5MB per image (after compression)                                  │
│  ├── Debounce upload button (500ms)                                         │
│  └── Queue with max 10 pending uploads                                      │
│                                                                              │
│  Layer 2: cdev-agent HTTP                                                    │
│  ├── Rate limit: 10 uploads/minute per session                              │
│  ├── Max request size: 20MB                                                 │
│  ├── Connection timeout: 30s                                                │
│  └── Reject if .cdev/images/ > 100MB total                                  │
│                                                                              │
│  Layer 3: Disk Storage                                                       │
│  ├── Max 50 images in .cdev/images/                                         │
│  ├── Auto-cleanup images older than 1 hour                                  │
│  ├── LRU eviction when limit reached                                        │
│  └── Unique filenames prevent overwrites                                    │
│                                                                              │
│  Layer 4: Claude CLI                                                         │
│  ├── Image size validated by Claude                                         │
│  └── Token budget limits prevent abuse                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Storage Limits & Cleanup

```go
// internal/services/image_storage.go

const (
    MaxImagesCount      = 50              // Max images in folder
    MaxTotalSizeMB      = 100             // Max total size
    MaxSingleImageMB    = 10              // Max single image
    ImageTTL            = 1 * time.Hour   // Auto-cleanup after 1 hour
    CleanupInterval     = 5 * time.Minute // Check every 5 minutes
)

type StorageStats struct {
    ImageCount   int
    TotalSizeBytes int64
    OldestImage  time.Time
}

func (s *ImageStorage) CanAcceptUpload(sizeBytes int64) (bool, string) {
    stats := s.GetStats()

    // Check count limit
    if stats.ImageCount >= MaxImagesCount {
        return false, "Too many images. Please wait for cleanup or delete old images."
    }

    // Check size limit
    if stats.TotalSizeBytes + sizeBytes > MaxTotalSizeMB * 1024 * 1024 {
        return false, "Storage full. Please wait for cleanup."
    }

    return true, ""
}
```

### Security Considerations

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Security Layers                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Upload Validation                                                        │
│     ├── Verify magic bytes (not just extension)                             │
│     │   JPEG: FF D8 FF                                                      │
│     │   PNG:  89 50 4E 47                                                   │
│     │   GIF:  47 49 46 38                                                   │
│     │   WebP: 52 49 46 46                                                   │
│     ├── Reject executables disguised as images                              │
│     ├── Sanitize filename (alphanumeric + extension only)                   │
│     └── Strip all EXIF data (GPS, camera info, etc.)                        │
│                                                                              │
│  2. Storage Security                                                         │
│     ├── Store in .cdev/images/ only (no path traversal)                     │
│     ├── Read-only from Claude CLI perspective                               │
│     ├── No execution permissions (chmod 644)                                │
│     └── Random filenames (UUID-based)                                       │
│                                                                              │
│  3. Path Security                                                            │
│     ├── Validate image_path is within .cdev/images/                         │
│     ├── Reject paths with "..", absolute paths                              │
│     ├── Only allow .jpg, .png, .gif, .webp extensions                       │
│     └── Verify file exists before passing to Claude                         │
│                                                                              │
│  4. Privacy                                                                  │
│     ├── EXIF GPS stripped before storage                                    │
│     ├── Images deleted after TTL (1 hour)                                   │
│     ├── Not synced to git (.gitignore .cdev/)                               │
│     └── User can manually clear via API                                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Edge Cases & Solutions

| # | Edge Case | Solution |
|---|-----------|----------|
| 1 | **Large image (>5MB after compression)** | Reject with clear error message |
| 2 | **Spam uploads (>10/min)** | Rate limit with 429 response |
| 3 | **Storage full (>100MB)** | Reject + trigger cleanup of oldest |
| 4 | **Malformed image (can't decode)** | Validate with image library before saving |
| 5 | **Path traversal attack** | Strict filename sanitization, no ".." |
| 6 | **Image deleted before Claude reads** | Verify exists before passing path |
| 7 | **Network interruption mid-upload** | Partial file cleanup on error |
| 8 | **Concurrent uploads same hash** | Use atomic rename to prevent race |
| 9 | **HEIC format from iPhone** | Convert to JPEG on iOS before upload |
| 10 | **Corrupted image data** | Validate magic bytes + try decode |
| 11 | **Disk full** | Check available space before write |
| 12 | **Slow upload timeout** | 30s timeout with resume hint |
| 13 | **Invalid session token** | 401 error, prompt re-pairing |
| 14 | **Agent restart mid-upload** | Client retry with same data |
| 15 | **Multiple agents same repo** | Each agent has own .cdev folder |

### Future: CloudRelay Considerations

When moving to CloudRelay architecture:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Current: Direct Connection                                │
│                                                                              │
│   iOS ──────────────────────────────────────────────────► cdev-agent        │
│         POST /api/images                                  .cdev/images/     │
│         (Local network, fast)                             (Local disk)      │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                    Future: CloudRelay                                        │
│                                                                              │
│   iOS ───► CloudRelay ───► cdev-agent                                       │
│            (Internet)      (Tunnel)                                          │
│                                                                              │
│   Option A: Relay Pass-through                                               │
│   ┌──────────┐    ┌──────────────┐    ┌─────────────┐                       │
│   │   iOS    │───►│  CloudRelay  │───►│ cdev-agent  │                       │
│   │ 5MB img  │    │ (streams)    │    │ .cdev/images│                       │
│   └──────────┘    └──────────────┘    └─────────────┘                       │
│   Pros: Simple, same as current                                              │
│   Cons: Slow for large images, bandwidth cost                               │
│                                                                              │
│   Option B: CloudRelay CDN (Recommended for production)                      │
│   ┌──────────┐    ┌──────────────┐                                          │
│   │   iOS    │───►│  CloudRelay  │◄───┐                                     │
│   │ 5MB img  │    │  (R2/S3 CDN) │    │                                     │
│   └──────────┘    └──────────────┘    │                                     │
│                         │             │                                      │
│                         │ Signed URL  │ Download                             │
│                         ▼             │                                      │
│                   ┌─────────────┐     │                                      │
│                   │ cdev-agent  │─────┘                                      │
│                   │ .cdev/images│                                            │
│                   └─────────────┘                                            │
│   Pros: Fast uploads, CDN caching, lower agent bandwidth                    │
│   Cons: More complex, requires CDN setup                                    │
│                                                                              │
│   Option C: Hybrid (Start with A, migrate to B)                             │
│   - Start with pass-through for simplicity                                   │
│   - Add CDN later for performance                                            │
│   - API remains same from iOS perspective                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### CloudRelay API Design (Future-Proof)

```go
// API response includes image_id that works with both local and cloud storage
type ImageUploadResponse struct {
    ImageID     string `json:"image_id"`      // Unique identifier
    LocalPath   string `json:"local_path"`    // .cdev/images/xxx.jpg (current)
    RemoteURL   string `json:"remote_url"`    // CloudRelay CDN URL (future)
    ExpiresAt   string `json:"expires_at"`    // TTL timestamp
}

// POST /api/claude/run accepts both formats
type RunClaudeRequest struct {
    Prompt     string   `json:"prompt"`
    ImageIDs   []string `json:"image_ids"`    // Works with local or remote
    // Agent resolves image_id to local path or downloads from CDN
}
```

---

## Detailed Component Design

### 1. cdev-ios Components

#### 1.1 ImageAttachment Model

```swift
// Domain/Models/ImageAttachment.swift

struct ImageAttachment: Identifiable, Equatable {
    let id: UUID
    let originalImage: UIImage
    let processedData: Data          // Compressed JPEG
    let mimeType: String             // "image/jpeg" or "image/png"
    let originalSize: CGSize
    let processedSize: CGSize
    let fileSizeBytes: Int
    let source: ImageSource
    let createdAt: Date

    enum ImageSource: String, Codable {
        case camera
        case photoLibrary
        case screenshot
        case clipboard
        case shareExtension
        case files                    // Files app
    }

    // Computed
    var isOversized: Bool { fileSizeBytes > Constants.Image.maxUploadSize }
    var aspectRatio: CGFloat { processedSize.width / processedSize.height }
}

// Upload state tracking
enum ImageUploadState: Equatable {
    case pending
    case uploading(progress: Double)
    case uploaded(imageId: String, localPath: String)
    case failed(error: String)
    case cancelled
}

struct AttachedImage: Identifiable {
    let id: UUID
    let attachment: ImageAttachment
    var uploadState: ImageUploadState
    var remoteImageId: String?       // Set after successful upload
    var localPath: String?           // Local path on agent
}
```

#### 1.2 ImageProcessingService

```swift
// Data/Services/ImageProcessingService.swift

protocol ImageProcessingServiceProtocol {
    func process(_ image: UIImage, source: ImageAttachment.ImageSource) async throws -> ImageAttachment
    func generateThumbnail(_ image: UIImage, size: CGSize) -> UIImage
}

actor ImageProcessingService: ImageProcessingServiceProtocol {

    private let maxDimension: CGFloat = 2048      // Claude's recommended max
    private let jpegQuality: CGFloat = 0.85       // Balance quality/size
    private let maxFileSize: Int = 5_000_000      // 5MB limit

    func process(_ image: UIImage, source: ImageAttachment.ImageSource) async throws -> ImageAttachment {
        // 1. Fix EXIF orientation
        let oriented = fixOrientation(image)

        // 2. Resize if needed (maintain aspect ratio)
        let resized = resizeIfNeeded(oriented, maxDimension: maxDimension)

        // 3. Compress to JPEG
        var quality = jpegQuality
        var data = resized.jpegData(compressionQuality: quality)!

        // 4. Iteratively reduce quality if still too large
        while data.count > maxFileSize && quality > 0.3 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)!
        }

        // 5. If still too large, resize further
        if data.count > maxFileSize {
            let smallerDimension = maxDimension * 0.7
            let smaller = resizeIfNeeded(resized, maxDimension: smallerDimension)
            data = smaller.jpegData(compressionQuality: jpegQuality)!
        }

        // 6. Generate content hash for deduplication
        let hash = SHA256.hash(data: data).hexString

        return ImageAttachment(
            id: UUID(),
            originalImage: image,
            processedData: data,
            mimeType: "image/jpeg",
            originalSize: image.size,
            processedSize: resized.size,
            fileSizeBytes: data.count,
            contentHash: hash,
            source: source,
            createdAt: Date()
        )
    }

    private func fixOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return normalized
    }

    private func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }

        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
```

#### 1.3 ImageUploadManager

```swift
// Data/Services/ImageUploadManager.swift

protocol ImageUploadManagerProtocol {
    func upload(_ attachment: ImageAttachment) async throws -> String  // Returns imageId
    func cancelUpload(_ attachmentId: UUID)
    var uploadProgress: AsyncStream<(UUID, Double)> { get }
}

actor ImageUploadManager: ImageUploadManagerProtocol {
    private let httpService: HTTPServiceProtocol
    private let maxConcurrentUploads = 3
    private var activeUploads: [UUID: URLSessionUploadTask] = [:]
    private var progressContinuation: AsyncStream<(UUID, Double)>.Continuation?

    lazy var uploadProgress: AsyncStream<(UUID, Double)> = {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }()

    func upload(_ attachment: ImageAttachment) async throws -> String {
        // Check for duplicate by hash (skip if already uploaded)
        if let existing = await checkDuplicate(hash: attachment.contentHash) {
            return existing.imageId
        }

        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add image data
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n")
        body.append("Content-Type: \(attachment.mimeType)\r\n\r\n")
        body.append(attachment.processedData)
        body.append("\r\n--\(boundary)--\r\n")

        // Add metadata
        let metadata = [
            "content_hash": attachment.contentHash,
            "source": attachment.source.rawValue,
            "original_width": Int(attachment.originalSize.width),
            "original_height": Int(attachment.originalSize.height)
        ]

        // Upload with progress tracking
        let response: ImageUploadResponse = try await httpService.uploadMultipart(
            path: "/api/images",
            body: body,
            boundary: boundary,
            onProgress: { [weak self] progress in
                self?.progressContinuation?.yield((attachment.id, progress))
            }
        )

        return response.imageId
    }

    func cancelUpload(_ attachmentId: UUID) {
        activeUploads[attachmentId]?.cancel()
        activeUploads.removeValue(forKey: attachmentId)
    }
}

struct ImageUploadResponse: Codable {
    let imageId: String
    let url: String?                  // Optional CDN URL
    let expiresAt: Date?              // TTL for temp storage
}
```

#### 1.4 Enhanced ActionBarView with Image Support

```swift
// Presentation/Screens/Dashboard/Components/ActionBarView.swift

struct ActionBarView: View {
    // Existing bindings...
    @Binding var attachedImages: [AttachedImage]

    // New state
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        VStack(spacing: 0) {
            // Image preview strip (if images attached)
            if !attachedImages.isEmpty {
                ImagePreviewStrip(
                    images: attachedImages,
                    onRemove: { id in
                        attachedImages.removeAll { $0.id == id }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main input row
            HStack(spacing: Spacing.xs) {
                // Attachment button (opens menu)
                AttachmentButton(
                    onCamera: { showCamera = true },
                    onPhotoLibrary: { showImagePicker = true },
                    onPaste: { pasteFromClipboard() },
                    onScreenshot: { captureScreenshot() }
                )

                // Text input (existing)
                promptTextField

                // Send button (existing, now handles images too)
                sendButton
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: .photoLibrary) { image in
                Task { await addImage(image, source: .photoLibrary) }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                Task { await addImage(image, source: .camera) }
            }
        }
    }

    private func addImage(_ image: UIImage, source: ImageAttachment.ImageSource) async {
        let processed = try? await imageProcessingService.process(image, source: source)
        guard let attachment = processed else { return }

        let attached = AttachedImage(
            id: UUID(),
            attachment: attachment,
            uploadState: .pending
        )

        await MainActor.run {
            attachedImages.append(attached)
        }
    }
}

// MARK: - Attachment Button

struct AttachmentButton: View {
    let onCamera: () -> Void
    let onPhotoLibrary: () -> Void
    let onPaste: () -> Void
    let onScreenshot: () -> Void

    @State private var showMenu = false

    var body: some View {
        Menu {
            Button { onCamera() } label: {
                Label("Take Photo", systemImage: "camera")
            }

            Button { onPhotoLibrary() } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }

            Button { onPaste() } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
            }

            Button { onScreenshot() } label: {
                Label("Capture Screenshot", systemImage: "camera.viewfinder")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(ColorSystem.primary)
        }
    }
}

// MARK: - Image Preview Strip

struct ImagePreviewStrip: View {
    let images: [AttachedImage]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(images) { attached in
                    ImagePreviewThumbnail(
                        image: attached.attachment.originalImage,
                        state: attached.uploadState,
                        onRemove: { onRemove(attached.id) }
                    )
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .frame(height: 80)
        .background(ColorSystem.terminalBgElevated)
    }
}

struct ImagePreviewThumbnail: View {
    let image: UIImage
    let state: ImageUploadState
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(uploadOverlay)

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .offset(x: 6, y: -6)
        }
    }

    @ViewBuilder
    private var uploadOverlay: some View {
        switch state {
        case .pending:
            EmptyView()
        case .uploading(let progress):
            ZStack {
                Color.black.opacity(0.5)
                CircularProgressView(progress: progress)
            }
        case .uploaded:
            ZStack {
                Color.black.opacity(0.3)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .failed:
            ZStack {
                Color.red.opacity(0.3)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        case .cancelled:
            EmptyView()
        }
    }
}
```

#### 1.5 Enhanced RunClaudeRequest

```swift
// Domain/Models/RunClaudeRequest.swift

struct RunClaudeRequest: Encodable {
    let prompt: String
    let mode: SessionMode
    let sessionId: String?
    let imageIds: [String]?           // NEW: Reference uploaded images

    enum CodingKeys: String, CodingKey {
        case prompt
        case mode
        case sessionId = "session_id"
        case imageIds = "image_ids"
    }
}
```

---

### 2. cdev-agent Components

#### 2.1 Folder Structure Migration

```go
// internal/app/app.go - Updated initialization

const (
    CdevDir       = ".cdev"
    CdevLogsDir   = ".cdev/logs"
    CdevImagesDir = ".cdev/images"
)

func (a *App) Start(ctx context.Context) error {
    // ... existing code ...

    // Create .cdev directory structure
    cdevDir := filepath.Join(a.cfg.Repository.Path, CdevDir)
    logsDir := filepath.Join(a.cfg.Repository.Path, CdevLogsDir)
    imagesDir := filepath.Join(a.cfg.Repository.Path, CdevImagesDir)

    os.MkdirAll(logsDir, 0755)
    os.MkdirAll(imagesDir, 0755)

    // Update Claude Manager to use new logs location
    a.claudeManager.SetLogDir(logsDir)

    // Initialize Image Storage
    a.imageStorage = NewImageStorage(imagesDir)

    // ... rest of existing code ...
}
```

#### 2.2 Image Storage Service (Simplified)

```go
// internal/services/image_storage.go

package services

import (
    "fmt"
    "io"
    "os"
    "path/filepath"
    "sync"
    "time"

    "github.com/google/uuid"
)

const (
    MaxImagesCount   = 50
    MaxTotalSizeMB   = 100
    MaxSingleImageMB = 10
    ImageTTL         = 1 * time.Hour
    CleanupInterval  = 5 * time.Minute
)

type ImageStorage struct {
    baseDir     string
    mu          sync.RWMutex
    cleanupTick *time.Ticker
}

type StoredImage struct {
    ID        string    `json:"id"`
    LocalPath string    `json:"local_path"`  // Relative path: .cdev/images/xxx.jpg
    FullPath  string    `json:"full_path"`   // Absolute path for internal use
    MimeType  string    `json:"mime_type"`
    Size      int64     `json:"size"`
    CreatedAt time.Time `json:"created_at"`
    ExpiresAt time.Time `json:"expires_at"`
}

func NewImageStorage(baseDir string) *ImageStorage {
    storage := &ImageStorage{
        baseDir: baseDir,
    }

    os.MkdirAll(baseDir, 0755)

    // Start cleanup goroutine
    storage.cleanupTick = time.NewTicker(CleanupInterval)
    go storage.cleanupLoop()

    return storage
}

func (s *ImageStorage) Store(reader io.Reader, mimeType string, repoPath string) (*StoredImage, string, error) {
    // Check storage limits
    if ok, msg := s.CanAcceptUpload(0); !ok {
        return nil, "", fmt.Errorf(msg)
    }

    // Generate unique filename
    id := uuid.New().String()[:12]
    ext := mimeTypeToExt(mimeType)
    filename := fmt.Sprintf("img_%s%s", id, ext)
    fullPath := filepath.Join(s.baseDir, filename)

    // Write to temp file first, then atomic rename
    tempPath := fullPath + ".tmp"
    file, err := os.Create(tempPath)
    if err != nil {
        return nil, "", fmt.Errorf("failed to create image file: %w", err)
    }

    // Copy with size limit
    limitReader := io.LimitReader(reader, MaxSingleImageMB*1024*1024+1)
    size, err := io.Copy(file, limitReader)
    file.Close()

    if err != nil {
        os.Remove(tempPath)
        return nil, "", fmt.Errorf("failed to write image: %w", err)
    }

    if size > MaxSingleImageMB*1024*1024 {
        os.Remove(tempPath)
        return nil, "", fmt.Errorf("image exceeds max size of %dMB", MaxSingleImageMB)
    }

    // Atomic rename
    if err := os.Rename(tempPath, fullPath); err != nil {
        os.Remove(tempPath)
        return nil, "", fmt.Errorf("failed to save image: %w", err)
    }

    // Set permissions (read-only for others)
    os.Chmod(fullPath, 0644)

    // Calculate relative path from repo root
    relPath := filepath.Join(CdevImagesDir, filename)

    stored := &StoredImage{
        ID:        id,
        LocalPath: relPath,
        FullPath:  fullPath,
        MimeType:  mimeType,
        Size:      size,
        CreatedAt: time.Now(),
        ExpiresAt: time.Now().Add(ImageTTL),
    }

    return stored, relPath, nil
}

func (s *ImageStorage) GetLocalPath(imageID string) (string, error) {
    // Find image by ID prefix
    files, err := os.ReadDir(s.baseDir)
    if err != nil {
        return "", fmt.Errorf("failed to read images dir: %w", err)
    }

    for _, f := range files {
        if !f.IsDir() && containsID(f.Name(), imageID) {
            fullPath := filepath.Join(s.baseDir, f.Name())
            // Verify file exists and is readable
            if _, err := os.Stat(fullPath); err == nil {
                return filepath.Join(CdevImagesDir, f.Name()), nil
            }
        }
    }

    return "", fmt.Errorf("image not found: %s", imageID)
}

func (s *ImageStorage) CanAcceptUpload(sizeBytes int64) (bool, string) {
    files, err := os.ReadDir(s.baseDir)
    if err != nil {
        return true, "" // Allow if can't read (dir might not exist yet)
    }

    var totalSize int64
    count := 0
    for _, f := range files {
        if !f.IsDir() {
            count++
            if info, err := f.Info(); err == nil {
                totalSize += info.Size()
            }
        }
    }

    if count >= MaxImagesCount {
        return false, "Too many images. Oldest will be cleaned up in a few minutes."
    }

    if totalSize+sizeBytes > MaxTotalSizeMB*1024*1024 {
        return false, "Image storage full. Please wait for cleanup."
    }

    return true, ""
}

func (s *ImageStorage) cleanupLoop() {
    for range s.cleanupTick.C {
        s.cleanup()
    }
}

func (s *ImageStorage) cleanup() {
    files, err := os.ReadDir(s.baseDir)
    if err != nil {
        return
    }

    cutoff := time.Now().Add(-ImageTTL)
    for _, f := range files {
        if f.IsDir() {
            continue
        }
        info, err := f.Info()
        if err != nil {
            continue
        }
        if info.ModTime().Before(cutoff) {
            os.Remove(filepath.Join(s.baseDir, f.Name()))
        }
    }
}

func mimeTypeToExt(mimeType string) string {
    switch mimeType {
    case "image/jpeg":
        return ".jpg"
    case "image/png":
        return ".png"
    case "image/gif":
        return ".gif"
    case "image/webp":
        return ".webp"
    default:
        return ".jpg"
    }
}

func containsID(filename, id string) bool {
    return len(filename) > 4 && filename[4:4+len(id)] == id
}
```

#### 2.3 Image Upload HTTP Handler

```go
// internal/server/http/images.go

package http

import (
    "encoding/json"
    "net/http"
    "strings"
)

// POST /api/images
func (s *Server) handleImageUpload(w http.ResponseWriter, r *http.Request) {
    // Rate limiting check
    if !s.rateLimiter.Allow("images") {
        http.Error(w, "Too many uploads. Please wait.", http.StatusTooManyRequests)
        return
    }

    // Limit request size
    r.Body = http.MaxBytesReader(w, r.Body, 20*1024*1024)

    if err := r.ParseMultipartForm(10 << 20); err != nil {
        http.Error(w, "Failed to parse multipart form", http.StatusBadRequest)
        return
    }

    file, header, err := r.FormFile("image")
    if err != nil {
        http.Error(w, "No image file provided", http.StatusBadRequest)
        return
    }
    defer file.Close()

    // Validate content type
    contentType := header.Header.Get("Content-Type")
    if !isValidImageType(contentType) {
        http.Error(w, "Invalid image type. Supported: jpeg, png, gif, webp", http.StatusBadRequest)
        return
    }

    // Validate magic bytes
    buf := make([]byte, 8)
    if _, err := file.Read(buf); err != nil {
        http.Error(w, "Failed to read image", http.StatusBadRequest)
        return
    }
    if !isValidMagicBytes(buf, contentType) {
        http.Error(w, "Invalid image format", http.StatusBadRequest)
        return
    }
    // Reset file position
    file.Seek(0, 0)

    // Store image
    stored, localPath, err := s.imageStorage.Store(file, contentType, s.repoPath)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    // Return response
    response := ImageUploadResponse{
        ImageID:   stored.ID,
        LocalPath: localPath,
        Size:      stored.Size,
        MimeType:  stored.MimeType,
        ExpiresAt: stored.ExpiresAt.Format(time.RFC3339),
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}

type ImageUploadResponse struct {
    ImageID   string `json:"image_id"`
    LocalPath string `json:"local_path"`
    Size      int64  `json:"size"`
    MimeType  string `json:"mime_type"`
    ExpiresAt string `json:"expires_at"`
}

func isValidImageType(contentType string) bool {
    validTypes := []string{"image/jpeg", "image/png", "image/gif", "image/webp"}
    for _, t := range validTypes {
        if strings.HasPrefix(contentType, t) {
            return true
        }
    }
    return false
}

func isValidMagicBytes(buf []byte, contentType string) bool {
    switch contentType {
    case "image/jpeg":
        return len(buf) >= 3 && buf[0] == 0xFF && buf[1] == 0xD8 && buf[2] == 0xFF
    case "image/png":
        return len(buf) >= 4 && buf[0] == 0x89 && buf[1] == 0x50 && buf[2] == 0x4E && buf[3] == 0x47
    case "image/gif":
        return len(buf) >= 4 && buf[0] == 0x47 && buf[1] == 0x49 && buf[2] == 0x46 && buf[3] == 0x38
    case "image/webp":
        return len(buf) >= 4 && buf[0] == 0x52 && buf[1] == 0x49 && buf[2] == 0x46 && buf[3] == 0x46
    }
    return false
}
```

#### 2.4 Enhanced Claude Manager (Simplified)

```go
// internal/adapters/claude/manager.go (modified)

type RunClaudeCommand struct {
    Prompt     string   `json:"prompt"`
    Mode       string   `json:"mode"`
    SessionID  string   `json:"session_id,omitempty"`
    ImagePaths []string `json:"image_paths,omitempty"`  // Local paths like .cdev/images/img_xxx.jpg
}

func (m *Manager) StartWithSession(ctx context.Context, prompt string, mode SessionMode, sessionID string, imagePaths []string) error {
    // ... existing validation ...

    // Build command arguments
    cmdArgs := make([]string, len(m.args))
    copy(cmdArgs, m.args)

    // Add session mode flags
    switch mode {
    case SessionModeContinue:
        if sessionID == "" {
            return fmt.Errorf("session_id is required for continue mode")
        }
        cmdArgs = append(cmdArgs, "--resume", sessionID)
    }

    if m.skipPermissions {
        cmdArgs = append(cmdArgs, "--dangerously-skip-permissions")
    }

    // Build prompt with image references
    finalPrompt := prompt
    if len(imagePaths) > 0 {
        // Validate all image paths exist
        for _, imgPath := range imagePaths {
            fullPath := filepath.Join(m.workDir, imgPath)
            if _, err := os.Stat(fullPath); os.IsNotExist(err) {
                return fmt.Errorf("image not found: %s", imgPath)
            }
            // Security: ensure path is within .cdev/images/
            if !strings.HasPrefix(imgPath, ".cdev/images/") {
                return fmt.Errorf("invalid image path: %s", imgPath)
            }
        }

        // Append image paths to prompt
        // Claude Code CLI can read images from local paths
        imageRefs := strings.Join(imagePaths, ", ")
        finalPrompt = fmt.Sprintf("%s\n\n[Attached images: %s]", prompt, imageRefs)
    }

    cmdArgs = append(cmdArgs, finalPrompt)

    // ... rest of existing implementation ...
}
```

---

### 3. Edge Cases & Solutions

| # | Edge Case | Solution |
|---|-----------|----------|
| 1 | **Large image (>5MB)** | Progressive compression: reduce quality 0.85→0.3, then resize |
| 2 | **Multiple images (>4)** | Queue with max 4 concurrent, batch upload UI |
| 3 | **Network interruption** | Retry with exponential backoff, resume from chunk |
| 4 | **Unsupported format** | Convert HEIC/RAW to JPEG automatically |
| 5 | **Image too large for context** | Warn user, suggest cropping or multiple prompts |
| 6 | **EXIF orientation wrong** | Fix orientation before compression |
| 7 | **Upload cancelled** | Clean up temp files, remove from queue |
| 8 | **Duplicate image** | Hash-based deduplication on both client and server |
| 9 | **Offline mode** | Queue locally, upload when online |
| 10 | **Memory pressure** | Process one image at a time, release immediately |
| 11 | **Server timeout** | Chunked upload with resumable protocol |
| 12 | **Rate limiting** | Respect 429 responses, show user feedback |
| 13 | **Token budget exceeded** | Estimate image tokens, warn before send |
| 14 | **Paste non-image** | Validate clipboard content type |
| 15 | **Camera permission denied** | Graceful fallback, show settings link |
| 16 | **Photo library permission** | Request with purpose string, handle denial |
| 17 | **Screenshot capture** | Use UIScreen.main.snapshotView, handle in background |
| 18 | **Share extension** | Handle NSItemProvider async loading |
| 19 | **Background upload** | URLSession background configuration |
| 20 | **App terminated during upload** | Resume on next launch with pending queue |
| 21 | **Server storage full** | Return 507, show user-friendly error |
| 22 | **Image expired on server** | Re-upload if needed before send |
| 23 | **Slow connection** | Show progress, allow cancel, suggest wifi |
| 24 | **Vision model unavailable** | Graceful fallback with explanation |
| 25 | **Concurrent session images** | Namespace images by session |

---

### 4. Security Considerations

```
┌─────────────────────────────────────────────────────────────────┐
│                      Security Layers                             │
├─────────────────────────────────────────────────────────────────┤
│ 1. Client-side                                                   │
│    ├── Strip EXIF GPS data before upload                        │
│    ├── Validate file magic bytes (not just extension)           │
│    └── Encrypt image data in transit (HTTPS)                    │
│                                                                  │
│ 2. Transport                                                     │
│    ├── TLS 1.3 minimum                                          │
│    ├── Certificate pinning (optional)                           │
│    └── Request signing (optional)                               │
│                                                                  │
│ 3. Server-side                                                   │
│    ├── Content-Type validation                                  │
│    ├── Magic byte verification                                  │
│    ├── Size limits enforced                                     │
│    ├── Filename sanitization                                    │
│    ├── Storage in non-executable directory                      │
│    ├── TTL-based auto-deletion                                  │
│    └── No direct URL access (only via API)                      │
│                                                                  │
│ 4. Privacy                                                       │
│    ├── Images stored temporarily only                           │
│    ├── No cloud backup of images                                │
│    ├── User can delete before send                              │
│    └── Clear all on disconnect                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

### 5. UI/UX Specifications

#### Image Attachment Button States

```
┌──────────────────────────────────────────────────────────┐
│                    Attachment Menu                        │
│  ┌────────────────────────────────────────────────────┐  │
│  │ 📷  Take Photo                                     │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ 🖼️  Photo Library                                  │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ 📋  Paste from Clipboard                           │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ 📱  Capture Screenshot                             │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

#### Image Preview Strip

```
┌──────────────────────────────────────────────────────────┐
│ ┌────┐ ┌────┐ ┌────┐                                    │
│ │ 📷 │ │ 📷 │ │ 📷 │  ← Horizontal scroll               │
│ │ ×  │ │ ⏳ │ │ ✓  │  ← Upload states                   │
│ └────┘ └────┘ └────┘                                    │
│ Pending  50%   Done                                      │
├──────────────────────────────────────────────────────────┤
│ [+] │ What's in these images?              │    [➤]     │
└──────────────────────────────────────────────────────────┘
```

#### Upload Progress Indicator

```swift
// Circular progress with percentage
struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(ColorSystem.primary, lineWidth: 3)
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
    }
}
```

---

### 6. Implementation Phases

#### Phase 1: Foundation
**cdev-agent:**
- [ ] Rename `.cdev-logs` to `.cdev/logs/` folder structure
- [ ] Create `.cdev/images/` folder on startup
- [ ] Implement ImageStorage service with limits and cleanup
- [ ] Add POST /api/images endpoint with validation
- [ ] Add rate limiting middleware
- [ ] Update .gitignore template to include `.cdev/`

**cdev-ios:**
- [ ] ImageAttachment model
- [ ] ImageProcessingService (resize, compress, HEIC→JPEG)
- [ ] HTTPService multipart upload support

#### Phase 2: Core UI
**cdev-ios:**
- [ ] AttachmentButton with menu (camera, library, paste)
- [ ] ImagePicker integration (camera + photo library)
- [ ] ImagePreviewStrip component with thumbnails
- [ ] Upload progress tracking (circular progress)
- [ ] Enhanced ActionBarView with attachment support
- [ ] Error states and retry UI

#### Phase 3: Backend Integration
**cdev-agent:**
- [ ] Enhanced RunClaudeCommand with image_paths
- [ ] ClaudeManager validates and includes image paths in prompt
- [ ] Add DELETE /api/images/:id endpoint

**cdev-ios:**
- [ ] Update RunClaudeRequest with image_paths
- [ ] Handle upload response and store local_path
- [ ] Pass image_paths when sending prompt

#### Phase 4: Polish & Edge Cases
- [ ] Clipboard paste support (detect image in clipboard)
- [ ] Screenshot capture functionality
- [ ] EXIF stripping on iOS before upload
- [ ] Comprehensive error handling and user feedback
- [ ] Storage full warnings
- [ ] Rate limit exceeded UI feedback

---

### 7. Testing Strategy

```
Unit Tests:
├── ImageProcessingServiceTests
│   ├── testResizePreservesAspectRatio
│   ├── testCompressionReducesSize
│   ├── testEXIFOrientationFixed
│   └── testHashGenerationConsistent
├── ImageUploadManagerTests
│   ├── testUploadSuccess
│   ├── testUploadRetryOnFailure
│   ├── testCancellation
│   └── testDeduplication
└── ImageStorageTests (Go)
    ├── TestStoreAndRetrieve
    ├── TestDuplicateDetection
    ├── TestTTLExpiration
    └── TestConcurrentAccess

Integration Tests:
├── testEndToEndImageUpload
├── testImageInClaudePrompt
├── testMultipleImagesInPrompt
└── testLargeImageHandling

UI Tests:
├── testImagePickerFlow
├── testPreviewStripDisplay
├── testUploadProgressDisplay
└── testErrorStateDisplay
```

---

### 8. Metrics & Monitoring

Track these metrics to ensure quality:

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Upload success rate | >99% | <95% |
| Average upload time | <3s | >10s |
| Compression ratio | >50% | <30% |
| Memory peak | <100MB | >200MB |
| Duplicate detection | >95% | <80% |
| TTL cleanup rate | 100% | <99% |

---

## Summary

This architecture provides:

1. **Simple & Elegant** - Store images locally, pass file paths to Claude CLI
2. **No Base64 Overhead** - Claude reads files directly from disk
3. **Future-Proof** - API design works with both local and CloudRelay
4. **Security First** - Multi-layer validation, rate limiting, TTL cleanup
5. **Spam Prevention** - 4 layers of protection (iOS → HTTP → Disk → Claude)
6. **Edge Case Coverage** - 15+ scenarios handled with clear solutions

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Local file paths (not base64) | Simpler, faster, Claude CLI native support |
| `.cdev/` folder structure | Clean organization, easy to .gitignore |
| 1 hour TTL | Balance usability vs disk usage |
| 50 images / 100MB limit | Prevent abuse while allowing normal use |
| UUID-based filenames | Security (no path traversal), uniqueness |
| Magic byte validation | Prevent fake images / executable uploads |

### CloudRelay Migration Path

1. **Start with Option A** (pass-through) - Same code, works immediately
2. **Migrate to Option B** (CDN) when:
   - Users complain about slow uploads
   - Bandwidth costs become significant
   - Need to support larger files
3. **API remains stable** - iOS doesn't need to change

No competitor has this level of mobile-to-CLI image integration for AI coding tools.
