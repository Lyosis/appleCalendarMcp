import Foundation

/// An inbound JSON-RPC 2.0 message.
///
/// A message with no `id` is a notification and must never be answered.
struct RPCRequest: Decodable, Sendable {
    let id: JSONValue?
    let method: String
    let params: JSONValue?

    /// The `params` object, or an empty object when the caller sent none.
    var arguments: JSONValue {
        params ?? .object([:])
    }
}

/// A JSON-RPC error, and the only error type the dispatcher reports verbatim.
struct RPCError: Error, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?

    init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    static func parseError() -> RPCError {
        RPCError(code: -32700, message: "Parse error")
    }

    static func methodNotFound(_ method: String) -> RPCError {
        RPCError(code: -32601, message: "Unknown method: \(method)")
    }

    static func invalidParams(_ reason: String) -> RPCError {
        RPCError(code: -32602, message: reason)
    }

    static func internalError(_ reason: String) -> RPCError {
        RPCError(code: -32603, message: reason)
    }
}

enum RPCResponse {
    /// Builds a success envelope. `result` and `error` are mutually exclusive
    /// by construction here, rather than by convention at the call site.
    static func success(id: JSONValue, result: JSONValue) -> JSONValue {
        .object(["jsonrpc": "2.0", "id": id, "result": result])
    }

    static func failure(id: JSONValue, error: RPCError) -> JSONValue {
        var payload: [String: JSONValue] = [
            "code": .int(error.code),
            "message": .string(error.message),
        ]
        if let data = error.data {
            payload["data"] = data
        }
        return .object(["jsonrpc": "2.0", "id": id, "error": .object(payload)])
    }
}
