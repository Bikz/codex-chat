import Foundation

struct JSONRPCRequestEnvelope: Sendable, Codable {
    let id: Int?
    let method: String
    let params: JSONValue?
}

struct JSONRPCResponseErrorEnvelope: Sendable, Codable, Hashable {
    let code: Int
    let message: String
    let data: JSONValue?
}

struct JSONRPCMessageEnvelope: Sendable, Codable, Hashable {
    let id: Int?
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
        JSONRPCMessageEnvelope(id: id, method: nil, params: nil, result: result, error: nil)
    }

    static func response(id: Int, error: JSONRPCResponseErrorEnvelope) -> JSONRPCMessageEnvelope {
        JSONRPCMessageEnvelope(id: id, method: nil, params: nil, result: nil, error: error)
    }
}
