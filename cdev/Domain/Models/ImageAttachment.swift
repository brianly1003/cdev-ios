import UIKit

// MARK: - Image Attachment State

/// Represents an attached image with its upload state
/// Used for tracking images from selection through upload to send
struct AttachedImageState: Identifiable, Equatable {
    let id: UUID
    let originalImage: UIImage
    let thumbnail: UIImage           // 60x60 for preview strip
    let processedData: Data          // Compressed JPEG for upload
    let mimeType: String             // "image/jpeg" or "image/png"
    let sizeBytes: Int
    let source: ImageSource
    let createdAt: Date
    var uploadState: ImageUploadState
    var serverImageId: String?       // Set after successful upload
    var serverLocalPath: String?     // .cdev/images/xxx.jpg

    /// Source of the image
    enum ImageSource: String, Codable {
        case camera
        case photoLibrary
        case clipboard
        case screenshot
        case files
    }

    // MARK: - Computed Properties

    var isUploaded: Bool {
        if case .uploaded = uploadState { return true }
        return false
    }

    var canRetry: Bool {
        if case .failed = uploadState { return true }
        return false
    }

    var isUploading: Bool {
        if case .uploading = uploadState { return true }
        return false
    }

    var uploadProgress: Double? {
        if case .uploading(let progress) = uploadState {
            return progress
        }
        return nil
    }

    // MARK: - Equatable

    static func == (lhs: AttachedImageState, rhs: AttachedImageState) -> Bool {
        lhs.id == rhs.id &&
        lhs.uploadState == rhs.uploadState &&
        lhs.serverImageId == rhs.serverImageId
    }
}

// MARK: - Upload State

/// Upload state for an attached image
enum ImageUploadState: Equatable {
    case pending
    case uploading(progress: Double)
    case uploaded(imageId: String, localPath: String)
    case failed(error: String)
    case cancelled

    static func == (lhs: ImageUploadState, rhs: ImageUploadState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending):
            return true
        case (.uploading(let p1), .uploading(let p2)):
            return abs(p1 - p2) < 0.01
        case (.uploaded(let id1, let path1), .uploaded(let id2, let path2)):
            return id1 == id2 && path1 == path2
        case (.failed(let e1), .failed(let e2)):
            return e1 == e2
        case (.cancelled, .cancelled):
            return true
        default:
            return false
        }
    }
}

// MARK: - Image Upload Error

/// Errors that can occur during image upload
enum ImageUploadError: Error, LocalizedError {
    case invalidResponse
    case tooLarge(maxMB: Int)
    case unsupportedFormat(supported: [String])
    case rateLimited(retryAfter: Int)
    case storageFull
    case serverError(statusCode: Int, message: String?)
    case networkError(underlying: Error)
    case processingFailed(reason: String)
    case cancelled
    case missingWorkspaceId
    case invalidWorkspace

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .tooLarge(let maxMB):
            return "Image exceeds \(maxMB)MB limit"
        case .unsupportedFormat(let supported):
            return "Unsupported format. Use: \(supported.joined(separator: ", "))"
        case .rateLimited(let retryAfter):
            return "Too many uploads. Wait \(retryAfter)s"
        case .storageFull:
            return "Server storage full"
        case .serverError(let code, let message):
            return message ?? "Server error (\(code))"
        case .networkError:
            return "Network error"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        case .cancelled:
            return "Upload cancelled"
        case .missingWorkspaceId:
            return "Workspace ID required"
        case .invalidWorkspace:
            return "Workspace not found"
        }
    }
}

// MARK: - Constants

extension AttachedImageState {
    enum Constants {
        static let maxImages = 4
        static let maxSingleImageMB = 10
        static let maxSingleImageBytes = maxSingleImageMB * 1024 * 1024
        static let thumbnailSize: CGFloat = 60
        static let maxDimension: CGFloat = 2048
        static let jpegQuality: CGFloat = 0.85
        static let supportedFormats = ["JPEG", "PNG", "GIF", "WebP"]
    }
}
