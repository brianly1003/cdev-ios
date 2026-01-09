import Foundation

// MARK: - Upload Response

/// Response from POST /api/images
struct ImageUploadResponse: Codable {
    let success: Bool
    let id: String
    let localPath: String
    let mimeType: String
    let size: Int64
    let expiresAt: Int64

    enum CodingKeys: String, CodingKey {
        case success, id, size
        case localPath = "local_path"
        case mimeType = "mime_type"
        case expiresAt = "expires_at"
    }

    /// Expiration date computed from Unix timestamp
    var expirationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(expiresAt))
    }

    /// Human-readable size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Image Info Response

/// Response from GET /api/images?id=xxx or items in list response
struct ImageInfoResponse: Codable, Identifiable {
    let id: String
    let localPath: String
    let mimeType: String
    let size: Int64
    let createdAt: Int64
    let expiresAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, size
        case localPath = "local_path"
        case mimeType = "mime_type"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    var creationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    var expirationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(expiresAt))
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Time remaining until expiration
    var timeRemaining: String {
        let remaining = expirationDate.timeIntervalSince(Date())
        if remaining <= 0 {
            return "Expired"
        }
        let minutes = Int(remaining / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - List Response

/// Response from GET /api/images
struct ImageListResponse: Codable {
    let images: [ImageInfoResponse]
    let count: Int
    let totalSizeBytes: Int64
    let maxImages: Int
    let maxTotalSizeMB: Int

    enum CodingKeys: String, CodingKey {
        case images, count
        case totalSizeBytes = "total_size_bytes"
        case maxImages = "max_images"
        case maxTotalSizeMB = "max_total_size_mb"
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    var usagePercentage: Double {
        let maxBytes = Int64(maxTotalSizeMB) * 1024 * 1024
        return Double(totalSizeBytes) / Double(maxBytes) * 100
    }
}

// MARK: - Stats Response

/// Response from GET /api/images/stats
struct ImageStatsResponse: Codable {
    let imageCount: Int
    let totalSizeBytes: Int64
    let maxImages: Int
    let maxTotalSizeMB: Int
    let maxSingleSizeMB: Int
    let canAcceptUpload: Bool
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case reason
        case imageCount = "image_count"
        case totalSizeBytes = "total_size_bytes"
        case maxImages = "max_images"
        case maxTotalSizeMB = "max_total_size_mb"
        case maxSingleSizeMB = "max_single_size_mb"
        case canAcceptUpload = "can_accept_upload"
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    var availableSlots: Int {
        max(0, maxImages - imageCount)
    }

    var availableBytes: Int64 {
        let maxBytes = Int64(maxTotalSizeMB) * 1024 * 1024
        return max(0, maxBytes - totalSizeBytes)
    }
}

// MARK: - Delete Response

/// Response from DELETE /api/images?id=xxx
struct ImageDeleteResponse: Codable {
    let success: Bool
    let id: String
    let message: String?
}

// MARK: - Clear All Response

/// Response from DELETE /api/images/all
struct ImageClearAllResponse: Codable {
    let success: Bool
    let message: String?
    let deleted: Int
}

// MARK: - Error Response

/// Error response from image API
struct ImageErrorResponse: Codable {
    let error: String
    let message: String?

    /// Map error code to ImageUploadError
    func toUploadError(statusCode: Int, retryAfter: Int? = nil) -> ImageUploadError {
        switch error {
        case "rate_limit_exceeded":
            return .rateLimited(retryAfter: retryAfter ?? 60)
        case "image_too_large":
            return .tooLarge(maxMB: 10)
        case "unsupported_type":
            return .unsupportedFormat(supported: ["JPEG", "PNG", "GIF", "WebP"])
        case "storage_full":
            return .storageFull
        case "missing_workspace_id":
            return .missingWorkspaceId
        case "invalid_workspace":
            return .invalidWorkspace
        default:
            return .serverError(statusCode: statusCode, message: message)
        }
    }
}
