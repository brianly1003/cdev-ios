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

        // Build query params string for logging
        let queryParamsStr = queryItems?.isEmpty == false
            ? queryItems!.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            : nil

        let startTime = Date()
        logRequest(method: "GET", path: path, queryItems: queryItems, body: nil)

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
                duration: duration
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

        // Build query params string for logging
        let queryParamsStr = queryItems?.isEmpty == false
            ? queryItems!.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            : nil

        let startTime = Date()
        logRequest(method: "DELETE", path: path, queryItems: queryItems, body: nil)

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
                duration: duration
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

        var bodyString: String?
        if let body = body {
            let bodyData = try encoder.encode(body)
            request.httpBody = bodyData
            bodyString = String(data: bodyData, encoding: .utf8)
        }

        let startTime = Date()
        logRequest(method: "POST", path: path, queryItems: nil, body: bodyString)

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
                duration: duration
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
        duration: TimeInterval
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        let statusCode = httpResponse.statusCode
        let durationMs = Int(duration * 1000)
        let responseBody = String(data: data, encoding: .utf8)

        if (200...299).contains(statusCode) {
            AppLogger.network("[HTTP] ← \(statusCode) \(path) (\(durationMs)ms)")

            // Log success to debug store
            Task { @MainActor in
                DebugLogStore.shared.logHTTPResponse(
                    method: method,
                    path: path,
                    queryParams: queryParams,
                    requestBody: requestBody,
                    status: statusCode,
                    responseBody: responseBody,
                    duration: duration
                )
            }
        } else {
            let errorDetail = describeHTTPError(statusCode)
            AppLogger.network("[HTTP] ✗ \(statusCode) \(path) (\(durationMs)ms) - \(errorDetail)", type: .error)
            if let msg = responseBody, !msg.isEmpty {
                AppLogger.network("[HTTP]   Response: \(msg.prefix(200))", type: .error)
            }

            // Log error to debug store
            Task { @MainActor in
                DebugLogStore.shared.logHTTPResponse(
                    method: method,
                    path: path,
                    queryParams: queryParams,
                    requestBody: requestBody,
                    status: statusCode,
                    responseBody: responseBody,
                    duration: duration
                )
            }

            throw AppError.httpRequestFailed(statusCode: statusCode, message: responseBody)
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

    /// Log outgoing request with params/body
    private func logRequest(method: String, path: String, queryItems: [URLQueryItem]?, body: String?) {
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

        // Log to debug store for admin tool
        Task { @MainActor in
            DebugLogStore.shared.logHTTPRequest(
                method: method,
                path: path,
                queryParams: queryParamsStr,
                body: body
            )
        }
    }

    /// Log detailed error information for failed requests
    private func logRequestError(_ error: Error, method: String, path: String, duration: TimeInterval) {
        let durationMs = Int(duration * 1000)

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
        default: return "Network error (code: \(code))"
        }
    }

    /// Check if error is retryable (transient network issues)
    private func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        // Retryable network errors
        let retryableCodes: Set<Int> = [
            NSURLErrorNetworkConnectionLost,     // -1005
            NSURLErrorNotConnectedToInternet,    // -1009
            NSURLErrorTimedOut,                  // -1001
            NSURLErrorCannotConnectToHost,       // -1004
            NSURLErrorCannotFindHost,            // -1003
            NSURLErrorSecureConnectionFailed,    // -1200
            NSURLErrorServerCertificateHasBadDate, // -1201
            NSURLErrorServerCertificateUntrusted,  // -1202
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
