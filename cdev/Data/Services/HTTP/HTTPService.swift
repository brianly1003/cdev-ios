import Foundation

/// HTTP service for REST API communication with agent
final class HTTPService: HTTPServiceProtocol {
    // MARK: - Properties

    var baseURL: URL? {
        didSet {
            // Recreate session with appropriate timeout when baseURL changes
            if let url = baseURL {
                updateSession(for: url)
            }
        }
    }

    /// Authentication token for API requests (access token)
    /// When set, adds `Authorization: Bearer <token>` header to all requests
    var authToken: String?

    private var session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let maxRetries: Int
    private let baseRetryDelay: TimeInterval

    /// Whether current connection is to a remote server (dev tunnel, not localhost)
    private var isRemoteConnection: Bool {
        guard let host = baseURL?.host else { return false }
        return host != "localhost" && host != "127.0.0.1" && !host.hasPrefix("192.168.")
    }

    // MARK: - Init

    init(
        maxRetries: Int = Constants.Network.httpMaxRetries,
        retryDelay: TimeInterval = Constants.Network.httpRetryDelay
    ) {
        // Start with default timeout, will be updated when baseURL is set
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.Network.requestTimeout
        configuration.timeoutIntervalForResource = Constants.Network.requestTimeout * 2
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.maxRetries = maxRetries
        self.baseRetryDelay = retryDelay
    }

    /// Apply authorization header to request if token is available
    private func applyAuthorization(to request: inout URLRequest) {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Update session configuration based on connection type
    private func updateSession(for url: URL) {
        let host = url.host ?? ""
        let isLocal = host == "localhost" || host == "127.0.0.1" || host.hasPrefix("192.168.")

        let timeout = isLocal ? Constants.Network.requestTimeoutLocal : Constants.Network.requestTimeout

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2

        // Invalidate old session and create new one
        session.invalidateAndCancel()
        session = URLSession(configuration: configuration)

        AppLogger.network("HTTP timeout set to \(Int(timeout))s for \(isLocal ? "local" : "remote") connection")
    }

    // MARK: - Public Methods

    func get<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        guard let baseURL = baseURL else {
            AppLogger.network("[HTTP] GET \(path) - No baseURL configured", type: .error)
            throw AppError.serverUnreachable
        }

        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw AppError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthorization(to: &request)

        // Capture headers for cURL generation
        let headers = request.allHTTPHeaderFields

        // Build query params string for logging
        let queryParamsStr = queryItems?.isEmpty == false
            ? queryItems!.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            : nil

        let startTime = Date()
        logRequest(method: "GET", path: path, queryItems: queryItems, body: nil, fullURL: url.absoluteString, headers: headers)

        do {
            let (data, response) = try await executeWithRetry(request: request, path: path)
            let duration = Date().timeIntervalSince(startTime)

            try validateResponse(
                response,
                data: data,
                method: "GET",
                path: path,
                queryParams: queryParamsStr,
                requestBody: nil,
                duration: duration,
                fullURL: url.absoluteString,
                headers: headers
            )

            return try decoder.decode(T.self, from: data)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logRequestError(error, method: "GET", path: path, duration: duration)
            throw error
        }
    }

    func post<T: Decodable, B: Encodable>(path: String, body: B?) async throws -> T {
        let data = try await performPost(path: path, body: body)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decodingFailed(underlying: error)
        }
    }

    func post<B: Encodable>(path: String, body: B?) async throws {
        _ = try await performPost(path: path, body: body)
    }

    func delete<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        guard let baseURL = baseURL else {
            AppLogger.network("[HTTP] DELETE \(path) - No baseURL configured", type: .error)
            throw AppError.serverUnreachable
        }

        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw AppError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthorization(to: &request)

        // Capture headers for cURL generation
        let headers = request.allHTTPHeaderFields

        // Build query params string for logging
        let queryParamsStr = queryItems?.isEmpty == false
            ? queryItems!.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            : nil

        let startTime = Date()
        logRequest(method: "DELETE", path: path, queryItems: queryItems, body: nil, fullURL: url.absoluteString, headers: headers)

        do {
            let (data, response) = try await executeWithRetry(request: request, path: path)
            let duration = Date().timeIntervalSince(startTime)

            try validateResponse(
                response,
                data: data,
                method: "DELETE",
                path: path,
                queryParams: queryParamsStr,
                requestBody: nil,
                duration: duration,
                fullURL: url.absoluteString,
                headers: headers
            )

            return try decoder.decode(T.self, from: data)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logRequestError(error, method: "DELETE", path: path, duration: duration)
            throw error
        }
    }

    func healthCheck() async throws -> Bool {
        guard let baseURL = baseURL else {
            return false
        }

        let url = baseURL.appendingPathComponent("/health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Token Authentication

    /// Exchange pairing token for access/refresh token pair
    /// This endpoint does NOT require existing auth token
    /// - Parameter pairingToken: The pairing token from QR code
    /// - Returns: TokenPair with access and refresh tokens
    func exchangePairingToken(_ pairingToken: String) async throws -> TokenPair {
        guard let baseURL = baseURL else {
            throw AppError.serverUnreachable
        }

        let url = baseURL.appendingPathComponent("/api/auth/exchange")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Note: No Authorization header - pairing token is in the body

        let body = TokenExchangeRequest(pairingToken: pairingToken)
        request.httpBody = try encoder.encode(body)

        AppLogger.network("[HTTP] → POST /api/auth/exchange (exchanging pairing token)")

        let startTime = Date()
        let (data, response) = try await session.data(for: request)
        let duration = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            AppLogger.network("[HTTP] ← 200 /api/auth/exchange (\(Int(duration * 1000))ms)")
            do {
                return try decoder.decode(TokenPair.self, from: data)
            } catch {
                throw AppError.decodingFailed(underlying: error)
            }

        case 202:
            let pending = try? decoder.decode(PairingPendingResponse.self, from: data)
            AppLogger.network("[HTTP] ← 202 /api/auth/exchange (\(Int(duration * 1000))ms) pending approval", type: .warning)
            throw AppError.pairingApprovalPending(
                requestID: pending?.requestID,
                expiresAt: pending?.expiresAt
            )

        case 401:
            let errorBody = decodeAPIErrorMessage(from: data) ?? "no body"
            AppLogger.network("[HTTP] ✗ 401 /api/auth/exchange - \(errorBody)", type: .error)
            throw AppError.tokenInvalid

        case 403:
            let errorBody = decodeAPIErrorMessage(from: data) ?? "no body"
            AppLogger.network("[HTTP] ✗ 403 /api/auth/exchange - \(errorBody)", type: .error)
            if errorBody.localizedCaseInsensitiveContains("rejected") {
                throw AppError.pairingFailed(reason: "Pairing request rejected on cdev host.")
            }
            throw AppError.tokenInvalid

        default:
            let errorBody = decodeAPIErrorMessage(from: data)
            AppLogger.network("[HTTP] ✗ \(httpResponse.statusCode) /api/auth/exchange - \(errorBody ?? "no body")", type: .error)
            throw AppError.httpRequestFailed(statusCode: httpResponse.statusCode, message: errorBody)
        }
    }

    /// Refresh access token using refresh token
    /// This endpoint does NOT require existing auth token
    /// - Parameter refreshToken: The refresh token from previous token pair
    /// - Returns: New TokenPair with fresh access and refresh tokens
    func refreshTokenPair(_ refreshToken: String) async throws -> TokenPair {
        guard let baseURL = baseURL else {
            throw AppError.serverUnreachable
        }

        let url = baseURL.appendingPathComponent("/api/auth/refresh")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Note: No Authorization header - refresh token is in the body

        let body = TokenRefreshRequest(refreshToken: refreshToken)
        request.httpBody = try encoder.encode(body)

        AppLogger.network("[HTTP] → POST /api/auth/refresh (refreshing token pair)")

        let startTime = Date()
        let (data, response) = try await session.data(for: request)
        let duration = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        if (200...299).contains(httpResponse.statusCode) {
            AppLogger.network("[HTTP] ← \(httpResponse.statusCode) /api/auth/refresh (\(Int(duration * 1000))ms)")
            return try decoder.decode(TokenPair.self, from: data)
        } else {
            let errorBody = String(data: data, encoding: .utf8)
            AppLogger.network("[HTTP] ✗ \(httpResponse.statusCode) /api/auth/refresh - \(errorBody ?? "no body")", type: .error)

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // Refresh token expired or invalid - user needs to re-pair
                throw AppError.refreshTokenExpired
            }
            throw AppError.httpRequestFailed(statusCode: httpResponse.statusCode, message: errorBody)
        }
    }

    /// Revoke refresh token (explicit disconnect)
    /// This endpoint does NOT require existing auth token
    /// - Parameter refreshToken: The refresh token to revoke
    func revokeRefreshToken(_ refreshToken: String) async throws {
        guard let baseURL = baseURL else {
            throw AppError.serverUnreachable
        }

        let url = baseURL.appendingPathComponent("/api/auth/revoke")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = TokenRevokeRequest(refreshToken: refreshToken)
        request.httpBody = try encoder.encode(body)

        AppLogger.network("[HTTP] → POST /api/auth/revoke (revoking refresh token)")

        let startTime = Date()
        let (_, response) = try await session.data(for: request)
        let duration = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        if (200...299).contains(httpResponse.statusCode) {
            AppLogger.network("[HTTP] ← \(httpResponse.statusCode) /api/auth/revoke (\(Int(duration * 1000))ms)")
            return
        }

        AppLogger.network("[HTTP] ✗ \(httpResponse.statusCode) /api/auth/revoke", type: .error)
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw AppError.refreshTokenExpired
        }
        throw AppError.httpRequestFailed(statusCode: httpResponse.statusCode, message: nil)
    }

    // MARK: - Private

    private func performPost<B: Encodable>(path: String, body: B?) async throws -> Data {
        guard let baseURL = baseURL else {
            AppLogger.network("[HTTP] POST \(path) - No baseURL configured", type: .error)
            throw AppError.serverUnreachable
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthorization(to: &request)

        var bodyString: String?
        if let body = body {
            let bodyData = try encoder.encode(body)
            request.httpBody = bodyData
            bodyString = String(data: bodyData, encoding: .utf8)
        }

        // Capture headers for cURL generation
        let headers = request.allHTTPHeaderFields

        let startTime = Date()
        logRequest(method: "POST", path: path, queryItems: nil, body: bodyString, fullURL: url.absoluteString, headers: headers)

        do {
            let (data, response) = try await executeWithRetry(request: request, path: path)
            let duration = Date().timeIntervalSince(startTime)

            try validateResponse(
                response,
                data: data,
                method: "POST",
                path: path,
                queryParams: nil,
                requestBody: bodyString,
                duration: duration,
                fullURL: url.absoluteString,
                headers: headers
            )

            return data
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logRequestError(error, method: "POST", path: path, duration: duration)
            throw error
        }
    }

    private func validateResponse(
        _ response: URLResponse,
        data: Data,
        method: String,
        path: String,
        queryParams: String?,
        requestBody: String?,
        duration: TimeInterval,
        fullURL: String?,
        headers: [String: String]?
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        let statusCode = httpResponse.statusCode
        let durationMs = Int(duration * 1000)
        let responseBody = String(data: data, encoding: .utf8)

        // Strip Authorization header to prevent token persistence in log file
        let sanitizedHeaders = headers?.filter { $0.key.lowercased() != "authorization" }

        if (200...299).contains(statusCode) {
            AppLogger.network("[HTTP] ← \(statusCode) \(path) (\(durationMs)ms)")

            // Log success to debug store (with cURL-ready data)
            Task { @MainActor in
                DebugLogStore.shared.logHTTPResponse(
                    method: method,
                    path: path,
                    queryParams: queryParams,
                    requestBody: requestBody,
                    status: statusCode,
                    responseBody: responseBody,
                    duration: duration,
                    fullURL: fullURL,
                    headers: sanitizedHeaders
                )
            }
        } else {
            let errorDetail = describeHTTPError(statusCode)
            AppLogger.network("[HTTP] ✗ \(statusCode) \(path) (\(durationMs)ms) - \(errorDetail)", type: .error)
            if let msg = responseBody, !msg.isEmpty {
                AppLogger.network("[HTTP]   Response: \(msg.prefix(200))", type: .error)
            }

            // Log error to debug store (with cURL-ready data)
            Task { @MainActor in
                DebugLogStore.shared.logHTTPResponse(
                    method: method,
                    path: path,
                    queryParams: queryParams,
                    requestBody: requestBody,
                    status: statusCode,
                    responseBody: responseBody,
                    duration: duration,
                    fullURL: fullURL,
                    headers: sanitizedHeaders
                )
            }

            // Throw specific error for authentication failures
            switch statusCode {
            case 401:
                throw AppError.tokenInvalid
            case 403:
                throw AppError.tokenExpired
            default:
                throw AppError.httpRequestFailed(statusCode: statusCode, message: responseBody)
            }
        }
    }

    /// Human-readable description of HTTP error codes
    private func describeHTTPError(_ statusCode: Int) -> String {
        switch statusCode {
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict (Claude already running)"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway (server/tunnel issue)"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout (server/tunnel slow or down)"
        default: return "HTTP Error"
        }
    }

    /// Decode common JSON API error payload (`{"error":"..."}`), fallback to raw body string.
    private func decodeAPIErrorMessage(from data: Data) -> String? {
        if let decoded = try? decoder.decode(APIErrorResponse.self, from: data) {
            return decoded.error
        }
        return String(data: data, encoding: .utf8)
    }

    /// Log outgoing request with params/body
    private func logRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]?,
        body: String?,
        fullURL: String?,
        headers: [String: String]?
    ) {
        var logParts: [String] = ["[HTTP] → \(method) \(path)"]

        // Build query params string
        var queryParamsStr: String?
        if let queryItems = queryItems, !queryItems.isEmpty {
            let params = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            logParts.append("?\(params)")
            queryParamsStr = params
        }

        AppLogger.network(logParts.joined())

        // Log body on separate line if present
        if let body = body, !body.isEmpty {
            AppLogger.network("[HTTP]   body: \(body)")
        }

        // Log to debug store for admin tool (with cURL-ready data)
        // Strip Authorization header to prevent token persistence in log file
        let sanitizedHeaders = headers?.filter { $0.key.lowercased() != "authorization" }
        Task { @MainActor in
            DebugLogStore.shared.logHTTPRequest(
                method: method,
                path: path,
                queryParams: queryParamsStr,
                body: body,
                fullURL: fullURL,
                headers: sanitizedHeaders
            )
        }
    }

    /// Log detailed error information for failed requests
    private func logRequestError(_ error: Error, method: String, path: String, duration: TimeInterval) {
        let durationMs = Int(duration * 1000)

        // Don't log cancellation errors as errors - they're expected behavior
        if isCancellationError(error) {
            AppLogger.network("[HTTP] ⊘ \(method) \(path) cancelled")
            return
        }

        if let appError = error as? AppError {
            switch appError {
            case .httpRequestFailed:
                // Already logged in validateResponse
                break
            case .decodingFailed(let underlying):
                AppLogger.network("[HTTP] ✗ \(method) \(path) - Decode error: \(underlying.localizedDescription)", type: .error)
            default:
                AppLogger.network("[HTTP] ✗ \(method) \(path) (\(durationMs)ms) - \(appError.localizedDescription)", type: .error)
            }
        } else {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                let errorDesc = describeURLError(nsError.code)
                AppLogger.network("[HTTP] ✗ \(method) \(path) (\(durationMs)ms) - \(errorDesc)", type: .error)
            } else {
                AppLogger.network("[HTTP] ✗ \(method) \(path) (\(durationMs)ms) - \(error.localizedDescription)", type: .error)
            }
        }
    }

    /// Human-readable description of URL error codes
    private func describeURLError(_ code: Int) -> String {
        switch code {
        case NSURLErrorTimedOut: return "Request timed out"
        case NSURLErrorCannotConnectToHost: return "Cannot connect to server"
        case NSURLErrorNetworkConnectionLost: return "Network connection lost"
        case NSURLErrorNotConnectedToInternet: return "No internet connection"
        case NSURLErrorCannotFindHost: return "Cannot find server"
        case NSURLErrorSecureConnectionFailed: return "SSL/TLS connection failed"
        case NSURLErrorCancelled: return "Request cancelled"
        default: return "Network error (code: \(code))"
        }
    }

    /// Check if error is a cancellation (expected behavior, not a real error)
    private func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    /// Check if error is retryable (transient network issues)
    private func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        // Retryable network errors - transient connectivity issues only.
        // Certificate errors (bad date, untrusted) must NOT be retried as they may
        // indicate a MITM attack or misconfigured server and should fail immediately.
        let retryableCodes: Set<Int> = [
            NSURLErrorNetworkConnectionLost,     // -1005
            NSURLErrorNotConnectedToInternet,    // -1009
            NSURLErrorTimedOut,                  // -1001
            NSURLErrorCannotConnectToHost,       // -1004
            NSURLErrorCannotFindHost,            // -1003
            NSURLErrorSecureConnectionFailed,    // -1200
        ]

        return retryableCodes.contains(nsError.code)
    }

    /// Execute request with automatic retry for transient errors (exponential backoff)
    private func executeWithRetry(
        request: URLRequest,
        path: String,
        attempt: Int = 0
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            if isRetryableError(error) && attempt < maxRetries {
                // Exponential backoff: 1s, 2s, 4s for remote; 0.5s, 1s, 2s for local
                let backoffMultiplier = isRemoteConnection ? 2.0 : 1.0
                let delay = baseRetryDelay * backoffMultiplier * pow(2, Double(attempt))

                let nsError = error as NSError
                let errorDesc = describeURLError(nsError.code)
                AppLogger.network("[HTTP] ⟳ Retry \(attempt + 1)/\(maxRetries) for \(path) in \(String(format: "%.1f", delay))s (\(errorDesc))", type: .warning)

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await executeWithRetry(request: request, path: path, attempt: attempt + 1)
            }
            throw error
        }
    }
}
