import Foundation

/// The one reply the bridge writes itself: when the helper could not answer.
///
/// The bridge otherwise understands nothing about MCP. This is the exception,
/// kept to reading a request's `id`, because the alternative is silence — and
/// a client waiting on silence times out a minute later with nothing to say.
enum BridgeReply {
    /// JSON-RPC leaves -32000 to -32099 to implementations; the helper uses
    /// -32001 for a refused client.
    static let unreachableCode = -32002

    static let unreachableMessage = """
        apple-calendar-mcp: the helper did not answer — it may be stopped, \
        being reinstalled or not registered. The request may or may not have \
        been carried out: check before retrying a change. If this persists, \
        run `apple-calendar-mcp --agent-status`.
        """

    /// The error for `message`, under its own id; nil for a notification,
    /// which must never be answered. A line that is not a JSON object gets
    /// the error under a null id, as JSON-RPC asks when the id is unknown.
    static func unreachable(answering message: String) -> String? {
        let id: Any
        if let object = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any] {
            guard let value = object["id"], !(value is NSNull) else { return nil }
            id = value
        } else {
            id = NSNull()
        }

        let reply: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": unreachableCode, "message": unreachableMessage],
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: reply, options: [.withoutEscapingSlashes]
        ) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
