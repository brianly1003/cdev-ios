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

        AppLogger.network("GET \(path)")

        let (data, response) = try await executeWithRetry(request: request, path: path)

        try validateResponse(response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decodingFailed(underlying: error)
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

        AppLogger.network("DELETE \(path)")

        let (data, response) = try await executeWithRetry(request: request, path: path)

        try validateResponse(response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decodingFailed(underlying: error)
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
            throw AppError.serverUnreachable
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            request.httpBody = try encoder.encode(body)
        }

        AppLogger.network("POST \(path)")

        let (data, response) = try await executeWithRetry(request: request, path: path)

        try validateResponse(response, data: data)

        return data
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            AppLogger.network("HTTP error \(httpResponse.statusCode): \(message ?? "unknown")", type: .error)
            throw AppError.httpRequestFailed(statusCode: httpResponse.statusCode, message: message)
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

                AppLogger.network("Retry \(attempt + 1)/\(maxRetries) for \(path) in \(String(format: "%.1f", delay))s")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await executeWithRetry(request: request, path: path, attempt: attempt + 1)
            }
            throw error
        }
    }
}
