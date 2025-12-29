import Foundation

/// JSON-RPC 2.0 protocol version
let jsonRPCVersion = "2.0"

// MARK: - Request ID

/// JSON-RPC ID can be string, number, or null
/// Per spec, we support string and integer IDs
enum JSONRPCId: Codable, Hashable, Sendable {
    case string(String)
    case number(Int)

    /// Generate a unique request ID
    static func generate() -> JSONRPCId {
        .string(UUID().uuidString)
    }

    /// String representation for correlation
    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let str = try? container.decode(String.self) {
            self = .string(str)
            return
        }

        if let num = try? container.decode(Int.self) {
            self = .number(num)
            return
        }

        // Try float and convert to int
        if let float = try? container.decode(Double.self) {
            self = .number(Int(float))
            return
        }

        throw DecodingError.typeMismatch(
            JSONRPCId.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected string or number for JSON-RPC ID"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):
            try container.encode(s)
        case .number(let n):
            try container.encode(n)
        }
    }
}

// MARK: - Request

/// JSON-RPC 2.0 Request
/// If id is nil, this is a notification (no response expected)
struct JSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: Params?

    init(id: JSONRPCId? = nil, method: String, params: Params? = nil) {
        self.jsonrpc = jsonRPCVersion
        self.id = id
        self.method = method
        self.params = params
    }

    /// Create a request with auto-generated ID
    static func request(method: String, params: Params?) -> JSONRPCRequest {
        JSONRPCRequest(id: .generate(), method: method, params: params)
    }

    /// Create a notification (no ID, no response expected)
    static func notification(method: String, params: Params?) -> JSONRPCRequest {
        JSONRPCRequest(id: nil, method: method, params: params)
    }
}

/// Empty params for requests that don't need parameters
struct EmptyParams: Codable, Sendable {
    static let shared = EmptyParams()
}

// MARK: - Response

/// JSON-RPC 2.0 Response with generic result type
struct JSONRPCResponse<Result: Decodable>: Decodable {
    let jsonrpc: String
    let id: JSONRPCId?
    let result: Result?
    let error: JSONRPCErrorObject?

    var isError: Bool { error != nil }
    var isSuccess: Bool { error == nil && result != nil }
}

/// Raw response for initial parsing before we know the result type
struct JSONRPCRawResponse: Decodable {
    let jsonrpc: String
    let id: JSONRPCId?
    let result: AnyCodable?
    let error: JSONRPCErrorObject?

    var isError: Bool { error != nil }
    var isNotification: Bool { id == nil }
}

// MARK: - Notification

/// JSON-RPC 2.0 Notification (server → client, no response expected)
struct JSONRPCNotification<Params: Decodable>: Decodable {
    let jsonrpc: String
    let method: String
    let params: Params?
}

/// Raw notification for initial parsing
struct JSONRPCRawNotification: Decodable {
    let jsonrpc: String
    let method: String
    let params: AnyCodable?

    /// Check if this looks like a notification (has method, no id)
    static func isNotification(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["method"] != nil && json["id"] == nil
    }
}

// MARK: - Error Object

/// JSON-RPC 2.0 Error object
struct JSONRPCErrorObject: Decodable, Error, Sendable {
    let code: Int
    let message: String
    let data: AnyCodable?

    var localizedDescription: String {
        if let data = data {
            return "\(message) (code: \(code), data: \(data))"
        }
        return "\(message) (code: \(code))"
    }
}

// MARK: - Message Detection

/// Helper to detect JSON-RPC message type
enum JSONRPCMessageType {
    case request
    case response
    case notification
    case unknown

    static func detect(from data: Data) -> JSONRPCMessageType {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        guard json["jsonrpc"] as? String == jsonRPCVersion else {
            return .unknown
        }

        let hasId = json["id"] != nil
        let hasMethod = json["method"] != nil
        let hasResult = json["result"] != nil
        let hasError = json["error"] != nil

        if hasMethod && !hasId {
            return .notification
        } else if hasMethod && hasId {
            return .request
        } else if hasId && (hasResult || hasError) {
            return .response
        }

        return .unknown
    }
}

// MARK: - AnyCodable

/// Type-erased Codable for handling arbitrary JSON
/// Uses @unchecked Sendable because:
/// - The struct is immutable (let value)
/// - Only stores JSON-compatible primitives (Bool, Int, Double, String, Array, Dict, NSNull)
/// - These values are thread-safe for reading
struct AnyCodable: Codable, @unchecked Sendable, CustomStringConvertible {
    let value: Any

    var description: String {
        String(describing: value)
    }

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode AnyCodable"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unable to encode AnyCodable"
                )
            )
        }
    }

    // MARK: - Value Accessors

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
    var arrayValue: [Any]? { value as? [Any] }
    var dictionaryValue: [String: Any]? { value as? [String: Any] }
}
