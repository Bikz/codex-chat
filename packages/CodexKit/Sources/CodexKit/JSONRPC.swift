import Foundation

enum JSONRPCID: Sendable, Codable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON-RPC id")
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        }
    }

    var intValue: Int? {
        if case let .int(value) = self {
            return value
        }
        return nil
    }
}

struct JSONRPCRequestEnvelope: Sendable, Codable {
    let id: JSONRPCID?
    let method: String
    let params: JSONValue?

    init(id: Int?, method: String, params: JSONValue?) {
        self.id = id.map(JSONRPCID.int)
        self.method = method
        self.params = params
    }

    init(id: JSONRPCID?, method: String, params: JSONValue?) {
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JSONRPCResponseErrorEnvelope: Sendable, Codable, Hashable {
    let code: Int
    let message: String
    let data: JSONValue?
}

struct JSONRPCMessageEnvelope: Sendable, Codable, Hashable {
    let id: JSONRPCID?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: JSONRPCResponseErrorEnvelope?

    var isResponse: Bool {
        id != nil && (result != nil || error != nil)
    }

    var isNotification: Bool {
        id == nil && method != nil
    }

    var isServerRequest: Bool {
        id != nil && method != nil && result == nil && error == nil
    }
}

extension JSONRPCMessageEnvelope {
    static func notification(method: String, params: JSONValue? = nil) -> JSONRPCMessageEnvelope {
        JSONRPCMessageEnvelope(id: nil, method: method, params: params, result: nil, error: nil)
    }

    static func response(id: Int, result: JSONValue) -> JSONRPCMessageEnvelope {
        JSONRPCMessageEnvelope(id: .int(id), method: nil, params: nil, result: result, error: nil)
    }

    static func response(id: JSONRPCID, result: JSONValue) -> JSONRPCMessageEnvelope {
        JSONRPCMessageEnvelope(id: id, method: nil, params: nil, result: result, error: nil)
    }

    static func response(id: Int, error: JSONRPCResponseErrorEnvelope) -> JSONRPCMessageEnvelope {
        JSONRPCMessageEnvelope(id: .int(id), method: nil, params: nil, result: nil, error: error)
    }

    static func response(id: JSONRPCID, error: JSONRPCResponseErrorEnvelope) -> JSONRPCMessageEnvelope {
        JSONRPCMessageEnvelope(id: id, method: nil, params: nil, result: nil, error: error)
    }
}
