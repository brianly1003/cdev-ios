import Foundation

/// Token prefixes for identification (matches cdev server)
enum TokenPrefix {
    static let pairing = "cdev_p_"   // Pairing token (for initial QR code connection)
    static let session = "cdev_s_"   // Session/Access token (for ongoing communication)
    static let refresh = "cdev_r_"   // Refresh token (for obtaining new access tokens)
}

/// Token type based on prefix
enum TokenType: String, Codable {
    case pairing
    case session
    case access
    case refresh
    case unknown

    /// Detect token type from token string
    static func from(token: String) -> TokenType {
        if token.hasPrefix(TokenPrefix.pairing) {
            return .pairing
        } else if token.hasPrefix(TokenPrefix.session) {
            return .session  // Also used for access tokens
        } else if token.hasPrefix(TokenPrefix.refresh) {
            return .refresh
        }
        return .unknown
    }
}

/// Access/Refresh token pair from server
/// Returned by /api/auth/exchange and /api/auth/refresh
struct TokenPair: Codable, Equatable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accessTokenExpiresAt = "access_token_expires_at"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresAt = "refresh_token_expires_at"
    }

    // MARK: - Custom Decoding for Date

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)

        // Parse ISO8601 dates
        let accessExpiryString = try container.decode(String.self, forKey: .accessTokenExpiresAt)
        let refreshExpiryString = try container.decode(String.self, forKey: .refreshTokenExpiresAt)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: accessExpiryString) {
            accessTokenExpiresAt = date
        } else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: accessExpiryString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .accessTokenExpiresAt,
                    in: container,
                    debugDescription: "Invalid date format: \(accessExpiryString)"
                )
            }
            accessTokenExpiresAt = date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: refreshExpiryString) {
            refreshTokenExpiresAt = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: refreshExpiryString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .refreshTokenExpiresAt,
                    in: container,
                    debugDescription: "Invalid date format: \(refreshExpiryString)"
                )
            }
            refreshTokenExpiresAt = date
        }
    }

    init(accessToken: String, accessTokenExpiresAt: Date, refreshToken: String, refreshTokenExpiresAt: Date) {
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }

    // MARK: - Computed Properties

    /// Check if access token is expired
    var isAccessTokenExpired: Bool {
        Date() > accessTokenExpiresAt
    }

    /// Check if refresh token is expired
    var isRefreshTokenExpired: Bool {
        Date() > refreshTokenExpiresAt
    }

    /// Time remaining until access token expires (nil if expired)
    var accessTokenTimeRemaining: TimeInterval? {
        let remaining = accessTokenExpiresAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    /// Time remaining until refresh token expires (nil if expired)
    var refreshTokenTimeRemaining: TimeInterval? {
        let remaining = refreshTokenExpiresAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    /// Check if access token needs refresh (within 2 minutes of expiry)
    var needsRefresh: Bool {
        guard let remaining = accessTokenTimeRemaining else { return true }
        return remaining < 120  // Refresh if less than 2 minutes remaining
    }

    /// Check if access token will expire soon (within 5 minutes) - for warning
    var expiresSoon: Bool {
        guard let remaining = accessTokenTimeRemaining else { return true }
        return remaining < 300  // 5 minutes
    }
}

/// Request body for /api/auth/exchange
struct TokenExchangeRequest: Encodable {
    let pairingToken: String

    enum CodingKeys: String, CodingKey {
        case pairingToken = "pairing_token"
    }
}

/// Request body for /api/auth/refresh
struct TokenRefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}
