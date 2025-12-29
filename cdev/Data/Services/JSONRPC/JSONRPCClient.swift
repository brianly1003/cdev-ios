import Foundation

// MARK: - JSON-RPC Client Protocol

/// Protocol for JSON-RPC request handling
protocol JSONRPCClientProtocol: Sendable {
    /// Send a request and wait for response
    /// - Parameters:
    ///   - method: JSON-RPC method name
    ///   - params: Request parameters
    ///   - timeout: Optional timeout override (uses default if nil)
    func request<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params?,
        timeout: TimeInterval?
    ) async throws -> Result

    /// Send a notification (no response expected)
    func notify<Params: Encodable>(
        method: String,
        params: Params?
    ) async throws

    /// Handle incoming message (call from WebSocket receive)
    func handleMessage(_ data: Data) async

    /// Cancel all pending requests (call on disconnect)
    func cancelAllPending() async
}

// MARK: - Pending Request

/// Tracks a pending request awaiting response
private struct PendingRequest: Sendable {
    let id: String
    let method: String
    let createdAt: Date
    let continuation: CheckedContinuation<Data, Error>
}

// MARK: - JSON-RPC Client

/// Actor-based JSON-RPC 2.0 client
/// Handles request/response correlation and notification dispatch
actor JSONRPCClient: JSONRPCClientProtocol {
    // MARK: - Properties

    /// WebSocket for sending messages
    private weak var webSocket: WebSocketServiceProtocol?

    /// Pending requests waiting for responses
    private var pendingRequests: [String: PendingRequest] = [:]

    /// Request timeout in seconds
    private let requestTimeout: TimeInterval

    /// JSON encoder for requests
    /// Note: Do NOT use .convertToSnakeCase - CodingKeys handle snake_case explicitly
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    /// JSON decoder for responses
    /// Note: Do NOT use .convertFromSnakeCase - CodingKeys handle snake_case explicitly
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Custom date decoding to handle ISO8601 with fractional seconds
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            // Try with fractional seconds first
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            // Fall back to standard ISO8601 without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }()

    /// Callback for notifications
    private var notificationHandler: ((String, Data) -> Void)?

    // MARK: - Initialization

    init(
        webSocket: WebSocketServiceProtocol? = nil,
        requestTimeout: TimeInterval = 30.0
    ) {
        self.webSocket = webSocket
        self.requestTimeout = requestTimeout
    }

    // MARK: - Configuration

    /// Set the WebSocket service
    func setWebSocket(_ webSocket: WebSocketServiceProtocol) {
        self.webSocket = webSocket
    }

    /// Set notification handler
    func setNotificationHandler(_ handler: @escaping (String, Data) -> Void) {
        self.notificationHandler = handler
    }

    // MARK: - Request/Response

    func request<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params?,
        timeout: TimeInterval? = nil
    ) async throws -> Result {
        guard let webSocket = webSocket else {
            throw JSONRPCClientError.notConnected
        }

        let requestId = JSONRPCId.generate()
        let request = JSONRPCRequest(id: requestId, method: method, params: params)
        let effectiveTimeout = timeout ?? requestTimeout

        // Encode request
        let data: Data
        do {
            data = try encoder.encode(request)
        } catch {
            throw JSONRPCClientError.encodingFailed(underlying: error)
        }

        // Send and wait for response with timeout
        let responseData: Data
        do {
            responseData = try await withThrowingTaskGroup(of: Data.self) { group in
                // Add request task
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        Task {
                            await self.registerPending(
                                id: requestId.stringValue,
                                method: method,
                                continuation: continuation
                            )
                        }
                    }
                }

                // Add timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                    throw JSONRPCClientError.timeout(requestId: requestId.stringValue, method: method)
                }

                // Send the request
                do {
                    try await webSocket.sendRaw(data)
                } catch {
                    // Cancel pending and rethrow
                    removePending(id: requestId.stringValue)
                    throw JSONRPCClientError.encodingFailed(underlying: error)
                }

                // Wait for first result (response or timeout)
                guard let result = try await group.next() else {
                    throw JSONRPCClientError.connectionClosed(requestId: requestId.stringValue)
                }

                // Cancel remaining tasks
                group.cancelAll()

                return result
            }
        } catch {
            // Clean up pending request on ANY error (timeout, cancellation, etc.)
            removePendingAndCancel(id: requestId.stringValue)
            AppLogger.webSocket("RPC request failed: \(method) - \(error.localizedDescription)", type: .error)
            throw error
        }

        // Decode response
        do {
            let response = try decoder.decode(JSONRPCResponse<Result>.self, from: responseData)

            if let error = response.error {
                throw JSONRPCClientError.from(error)
            }

            guard let result = response.result else {
                throw JSONRPCClientError.decodingFailed(
                    underlying: NSError(
                        domain: "JSONRPCClient",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Response missing result"]
                    )
                )
            }

            return result
        } catch let error as JSONRPCClientError {
            throw error
        } catch {
            // Log raw response for debugging decode failures
            if let rawString = String(data: responseData, encoding: .utf8) {
                AppLogger.webSocket("RPC decode failed for \(method). Raw response: \(rawString.prefix(500))", type: .error)
            }
            throw JSONRPCClientError.decodingFailed(underlying: error)
        }
    }

    func notify<Params: Encodable>(
        method: String,
        params: Params?
    ) async throws {
        guard let webSocket = webSocket else {
            throw JSONRPCClientError.notConnected
        }

        let notification = JSONRPCRequest<Params>(id: nil, method: method, params: params)

        do {
            let data = try encoder.encode(notification)
            try await webSocket.sendRaw(data)
        } catch let error as JSONRPCClientError {
            throw error
        } catch {
            throw JSONRPCClientError.encodingFailed(underlying: error)
        }
    }

    // MARK: - Message Handling

    func handleMessage(_ data: Data) async {
        let messageType = JSONRPCMessageType.detect(from: data)

        switch messageType {
        case .response:
            await handleResponse(data)

        case .notification:
            await handleNotification(data)

        case .request:
            // Server sending request to client - not expected in current protocol
            AppLogger.log("Received unexpected JSON-RPC request from server", type: .warning)

        case .unknown:
            // Not a JSON-RPC message - might be legacy format
            AppLogger.log("Received non-JSON-RPC message", type: .info)
        }
    }

    private func handleResponse(_ data: Data) async {
        // Parse raw response to get ID
        guard let rawResponse = try? decoder.decode(JSONRPCRawResponse.self, from: data),
              let id = rawResponse.id else {
            AppLogger.log("Failed to parse response ID", type: .error)
            return
        }

        // Find and complete pending request
        if let pending = pendingRequests.removeValue(forKey: id.stringValue) {
            if rawResponse.isError {
                // Error response - still send data, let caller handle decoding
                pending.continuation.resume(returning: data)
            } else {
                pending.continuation.resume(returning: data)
            }
        } else {
            AppLogger.log("Received response for unknown request: \(id.stringValue)", type: .warning)
        }
    }

    private func handleNotification(_ data: Data) async {
        guard let notification = try? decoder.decode(JSONRPCRawNotification.self, from: data) else {
            AppLogger.log("Failed to parse notification", type: .error)
            return
        }

        // Dispatch to handler
        notificationHandler?(notification.method, data)
    }

    // MARK: - Pending Request Management

    private func registerPending(
        id: String,
        method: String,
        continuation: CheckedContinuation<Data, Error>
    ) {
        pendingRequests[id] = PendingRequest(
            id: id,
            method: method,
            createdAt: Date(),
            continuation: continuation
        )
    }

    private func removePending(id: String) {
        pendingRequests.removeValue(forKey: id)
    }

    /// Remove pending request and cancel its continuation (for timeout/error cleanup)
    private func removePendingAndCancel(id: String) {
        if let pending = pendingRequests.removeValue(forKey: id) {
            // Resume with cancellation error to avoid continuation leak
            pending.continuation.resume(
                throwing: CancellationError()
            )
            AppLogger.webSocket("Cancelled pending request: \(pending.method) [\(id.prefix(8))]", type: .warning)
        }
    }

    func cancelAllPending() async {
        for (_, pending) in pendingRequests {
            pending.continuation.resume(
                throwing: JSONRPCClientError.connectionClosed(requestId: pending.id)
            )
        }
        pendingRequests.removeAll()
    }

    // MARK: - Diagnostics

    /// Get count of pending requests
    var pendingCount: Int {
        pendingRequests.count
    }

    /// Get pending request methods (for debugging)
    var pendingMethods: [String] {
        pendingRequests.values.map { $0.method }
    }
}

// MARK: - WebSocket Extension

/// Extension to add raw data sending capability
extension WebSocketServiceProtocol {
    /// Send raw data (for JSON-RPC messages)
    func sendRaw(_ data: Data) async throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw JSONRPCClientError.encodingFailed(
                underlying: NSError(
                    domain: "JSONRPCClient",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to convert data to string"]
                )
            )
        }

        // Use the protocol method - WebSocketService implements this
        try await send(data: data)
    }
}
