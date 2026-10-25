import Foundation
import Testing
@testable import AppleCalendarBridge

/// When the helper cannot answer, the bridge answers instead — under the
/// request's own id, so the client matches it rather than timing out.
struct BridgeReplyTests {
    private func decode(_ reply: String?) throws -> [String: Any] {
        let text = try #require(reply)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test("A numeric id comes back as a number")
    func numericID() throws {
        let reply = try decode(BridgeReply.unreachable(
            answering: #"{"jsonrpc":"2.0","id":42,"method":"tools/call"}"#
        ))
        #expect(reply["id"] as? Int == 42)
        let error = try #require(reply["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32002)
        #expect(reply["result"] == nil)
    }

    @Test("A string id comes back as the same string")
    func stringID() throws {
        let reply = try decode(BridgeReply.unreachable(
            answering: #"{"jsonrpc":"2.0","id":"abc-1","method":"ping"}"#
        ))
        #expect(reply["id"] as? String == "abc-1")
    }

    @Test("A notification gets nothing", arguments: [
        #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
        #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#,
    ])
    func notification(_ message: String) {
        #expect(BridgeReply.unreachable(answering: message) == nil)
    }

    @Test("A line that is not JSON gets the error under a null id")
    func garbage() throws {
        let reply = try decode(BridgeReply.unreachable(answering: "not json"))
        #expect(reply["id"] is NSNull)
        #expect(reply["error"] != nil)
    }
}
