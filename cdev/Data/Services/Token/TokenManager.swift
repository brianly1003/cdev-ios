import Foundation

/// Manages token lifecycle including storage, refresh, and expiry handling
/// Integrates with cdev server's token refresh mechanism:
/// - Pairing token (60s) → exchanged for access/refresh pair
/// - Access token (15min) → used for API calls
/// - Refresh token (7 days) → used to get new access tokens
final class TokenManager {
    // MARK: - Singleton

    static let shared = TokenManager()

    // MARK: - Constants

    private enum KeychainKeys {
        static let accessToken = "cdev.accessToken"
        static let accessTokenExpiry = "cdev.accessTokenExpiry"
        static let refreshToken = "cdev.refreshToken"
        static let refreshTokenExpiry = "cdev.refreshTokenExpiry"
        static let serverHost = "cdev.serverHost"  // Host tokens are associated with
    }

    /// Refresh access token when less than this time remains
    private let refreshThreshold: TimeInterval = 120  // 2 minutes

    /// Warn user when less than this time remains
    private let warningThreshold: TimeInterval = 300  // 5 minutes

    // MARK: - Properties

    private let keychain: KeychainService
    private let timerQueue = DispatchQueue(label: "com.cdev.tokenmanager.timers", qos: .utility)
    private var refreshTimer: DispatchSourceTimer?
    private var httpService: HTTPServiceProtocol?

    /// Called when tokens are refreshed successfully
    var onTokensRefreshed: ((TokenPair) -> Void)?

    /// Called when refresh fails and re-pairing is needed
    var onRefreshFailed: ((Error) -> Void)?

    /// Called when access token will expire soon (for UI warning)
    var onTokenExpiringSoon: ((TimeInterval) -> Void)?

    // MARK: - Init

    private init() {
        self.keychain = KeychainService()
    }

    /// Set HTTP service for token refresh calls
    func setHTTPService(_ service: HTTPServiceProtocol) {
        self.httpService = service
    }

    // MARK: - Token Storage

    /// Store token pair securely
    func storeTokenPair(_ tokenPair: TokenPair, forHost host: String) {
        do {
            try keychain.save(tokenPair.accessToken, forKey: KeychainKeys.accessToken)
            try keychain.save(tokenPair.refreshToken, forKey: KeychainKeys.refreshToken)
            try keychain.save(String(tokenPair.accessTokenExpiresAt.timeIntervalSince1970), forKey: KeychainKeys.accessTokenExpiry)
            try keychain.save(String(tokenPair.refreshTokenExpiresAt.timeIntervalSince1970), forKey: KeychainKeys.refreshTokenExpiry)
            try keychain.save(host, forKey: KeychainKeys.serverHost)

            AppLogger.log("[TokenManager] Token pair stored for host: \(host)")
            AppLogger.log("[TokenManager] Access token expires: \(tokenPair.accessTokenExpiresAt)")
            AppLogger.log("[TokenManager] Refresh token expires: \(tokenPair.refreshTokenExpiresAt)")

            // Schedule refresh timer
            scheduleRefreshTimer(for: tokenPair)
        } catch {
            AppLogger.log("[TokenManager] Failed to store token pair: \(error)", type: .error)
        }
    }

    /// Get stored token pair (nil if not stored or expired)
    func getStoredTokenPair() -> TokenPair? {
        do {
            guard let accessToken = try keychain.loadString(forKey: KeychainKeys.accessToken),
                  let refreshToken = try keychain.loadString(forKey: KeychainKeys.refreshToken),
                  let accessExpiryStr = try keychain.loadString(forKey: KeychainKeys.accessTokenExpiry),
                  let refreshExpiryStr = try keychain.loadString(forKey: KeychainKeys.refreshTokenExpiry),
                  let accessExpiry = Double(accessExpiryStr),
                  let refreshExpiry = Double(refreshExpiryStr) else {
                return nil
            }

            let tokenPair = TokenPair(
                accessToken: accessToken,
                accessTokenExpiresAt: Date(timeIntervalSince1970: accessExpiry),
                refreshToken: refreshToken,
                refreshTokenExpiresAt: Date(timeIntervalSince1970: refreshExpiry)
            )

            // If refresh token is expired, clear stored tokens
            if tokenPair.isRefreshTokenExpired {
                AppLogger.log("[TokenManager] Stored refresh token expired, clearing tokens")
                clearTokens()
                return nil
            }

            return tokenPair
        } catch {
            AppLogger.log("[TokenManager] Failed to load stored tokens: \(error)", type: .error)
            return nil
        }
    }

    /// Get the host associated with stored tokens
    func getStoredHost() -> String? {
        try? keychain.loadString(forKey: KeychainKeys.serverHost)
    }

    /// Get current valid access token, refreshing if needed
    /// Returns nil if no valid tokens or refresh fails
    func getValidAccessToken() async -> String? {
        guard let tokenPair = getStoredTokenPair() else {
            return nil
        }

        // If access token is still valid and not near expiry, return it
        if !tokenPair.needsRefresh {
            return tokenPair.accessToken
        }

        // If refresh token is expired, cannot get valid token
        if tokenPair.isRefreshTokenExpired {
            AppLogger.log("[TokenManager] Refresh token expired, need re-pairing")
            clearTokens()
            onRefreshFailed?(AppError.refreshTokenExpired)
            return nil
        }

        // Refresh the token
        do {
            let newPair = try await refreshTokenPair(using: tokenPair.refreshToken)
            return newPair.accessToken
        } catch {
            AppLogger.log("[TokenManager] Token refresh failed: \(error)", type: .error)

            // If access token is still valid, keep using it and retry refresh later
            if !tokenPair.isAccessTokenExpired {
                AppLogger.log("[TokenManager] Using existing access token (still valid) despite refresh failure")
                return tokenPair.accessToken
            }

            if isRefreshTokenInvalid(error) {
                onRefreshFailed?(error)
            }
            return nil
        }
    }

    /// Clear all stored tokens
    func clearTokens() {
        stopRefreshTimer()

        do {
            try keychain.delete(forKey: KeychainKeys.accessToken)
            try keychain.delete(forKey: KeychainKeys.refreshToken)
            try keychain.delete(forKey: KeychainKeys.accessTokenExpiry)
            try keychain.delete(forKey: KeychainKeys.refreshTokenExpiry)
            try keychain.delete(forKey: KeychainKeys.serverHost)
            AppLogger.log("[TokenManager] Tokens cleared")
        } catch {
            AppLogger.log("[TokenManager] Failed to clear tokens: \(error)", type: .error)
        }
    }

    /// Revoke refresh token on server and clear local tokens.
    /// Used for explicit disconnect to invalidate the session immediately.
    func revokeStoredRefreshToken() async {
        guard let tokenPair = getStoredTokenPair() else {
            clearTokens()
            return
        }

        if tokenPair.isRefreshTokenExpired {
            AppLogger.log("[TokenManager] Refresh token already expired, clearing tokens")
            clearTokens()
            return
        }

        guard let httpService = httpService else {
            AppLogger.log("[TokenManager] No HTTP service configured, clearing tokens", type: .warning)
            clearTokens()
            return
        }

        do {
            try await httpService.revokeRefreshToken(tokenPair.refreshToken)
            AppLogger.log("[TokenManager] Refresh token revoked")
        } catch {
            AppLogger.log("[TokenManager] Failed to revoke refresh token: \(error)", type: .warning)
        }

        clearTokens()
    }

    // MARK: - Token Exchange

    /// Exchange pairing token for access/refresh token pair
    /// Called after QR code scan
    func exchangePairingToken(_ pairingToken: String, host: String) async throws -> TokenPair {
        guard let httpService = httpService else {
            throw AppError.serverUnreachable
        }

        AppLogger.log("[TokenManager] Exchanging pairing token for host: \(host)")

        let tokenPair = try await httpService.exchangePairingToken(pairingToken)

        // Store the new token pair
        storeTokenPair(tokenPair, forHost: host)

        return tokenPair
    }

    /// Refresh token pair using refresh token
    func refreshTokenPair(using refreshToken: String) async throws -> TokenPair {
        guard let httpService = httpService else {
            throw AppError.serverUnreachable
        }

        AppLogger.log("[TokenManager] Refreshing token pair")

        let newPair = try await httpService.refreshTokenPair(refreshToken)

        // Store the new token pair (host stays the same)
        if let host = getStoredHost() {
            storeTokenPair(newPair, forHost: host)
        }

        onTokensRefreshed?(newPair)

        return newPair
    }

    // MARK: - Automatic Refresh Timer

    private func scheduleRefreshTimer(for tokenPair: TokenPair) {
        stopRefreshTimer()

        guard let timeRemaining = tokenPair.accessTokenTimeRemaining else {
            AppLogger.log("[TokenManager] Access token already expired")
            return
        }

        // Calculate when to refresh (2 minutes before expiry)
        let refreshIn = max(0, timeRemaining - refreshThreshold)

        // Also schedule warning if within warning threshold
        if timeRemaining <= warningThreshold {
            onTokenExpiringSoon?(timeRemaining)
        }

        if refreshIn <= 0 {
            // Need to refresh immediately
            Task {
                await performTokenRefresh()
            }
            return
        }

        AppLogger.log("[TokenManager] Scheduling token refresh in \(Int(refreshIn))s")

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + refreshIn)
        timer.setEventHandler { [weak self] in
            Task {
                await self?.performTokenRefresh()
            }
        }
        timer.resume()
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    private func performTokenRefresh() async {
        guard let tokenPair = getStoredTokenPair() else {
            AppLogger.log("[TokenManager] No token pair to refresh")
            return
        }

        if tokenPair.isRefreshTokenExpired {
            AppLogger.log("[TokenManager] Refresh token expired during auto-refresh", type: .warning)
            onRefreshFailed?(AppError.refreshTokenExpired)
            return
        }

        do {
            _ = try await refreshTokenPair(using: tokenPair.refreshToken)
            AppLogger.log("[TokenManager] Auto-refresh succeeded")
        } catch {
            AppLogger.log("[TokenManager] Auto-refresh failed: \(error)", type: .error)
            if isRefreshTokenInvalid(error) {
                onRefreshFailed?(error)
            }
        }
    }

    private func isRefreshTokenInvalid(_ error: Error) -> Bool {
        if let appError = error as? AppError {
            switch appError {
            case .refreshTokenExpired, .tokenInvalid:
                return true
            case .httpRequestFailed(let statusCode, _):
                return statusCode == 401 || statusCode == 403
            default:
                return false
            }
        }
        return false
    }

    // MARK: - Token Status

    /// Check if we have valid stored tokens
    var hasValidTokens: Bool {
        guard let tokenPair = getStoredTokenPair() else { return false }
        return !tokenPair.isRefreshTokenExpired
    }

    /// Get time until access token expires
    var accessTokenTimeRemaining: TimeInterval? {
        getStoredTokenPair()?.accessTokenTimeRemaining
    }

    /// Get time until refresh token expires
    var refreshTokenTimeRemaining: TimeInterval? {
        getStoredTokenPair()?.refreshTokenTimeRemaining
    }
}
