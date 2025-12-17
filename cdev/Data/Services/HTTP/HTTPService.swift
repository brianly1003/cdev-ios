import Foundation

/// HTTP service for REST API communication with agent
final class HTTPService: HTTPServiceProtocol {
    // MARK: - Properties

    var baseURL: URL?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Init

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.Network.requestTimeout
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
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

        let (data, response) = try await session.data(for: request)

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

        let (data, response) = try await session.data(for: request)

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
}
