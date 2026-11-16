import Foundation

/// Arbitrary JSON value encoded/decoded cleanly in pure Swift 6 (`Sendable`).
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var jsonString: String {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}

/// JSON-RPC 2.0 request envelope for MCP stdio and HTTP transports.
public struct JSONRPCRequest: Codable, Sendable, Equatable {
    public let jsonrpc: String
    public let id: Int?
    public let method: String
    public let params: JSONValue?

    public init(id: Int? = nil, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 error payload.
public struct JSONRPCError: Codable, Sendable, Equatable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// JSON-RPC 2.0 response envelope.
public struct JSONRPCResponse: Codable, Sendable, Equatable {
    public let jsonrpc: String
    public let id: Int?
    public let result: JSONValue?
    public let error: JSONRPCError?

    public init(id: Int?, result: JSONValue? = nil, error: JSONRPCError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

/// Discovered MCP tool metadata (`tools/list`).
public struct MCPToolDescriptor: Codable, Sendable, Equatable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONValue?
}
