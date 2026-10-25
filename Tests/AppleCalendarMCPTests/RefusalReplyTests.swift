import Foundation
import Testing
@testable import AppleCalendarMCP

/// A refused client is told why, in JSON-RPC, instead of waiting on a
/// connection that was cut.
struct RefusalReplyTests {
    private func decode(_ reply: String?) throws -> [String: Any] {
        let text = try #require(reply)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test("A request gets the refusal under its own id")
    func request() throws {
        let reply = try decode(RPCResponse.refusal(
            to: #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{}}"#,
            reason: "no"
        ))
        #expect(reply["id"] as? Int == 7)
        #expect(reply["result"] == nil)
        let error = try #require(reply["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32001)
        #expect(error["message"] as? String == "no")
    }

    @Test("A notification gets nothing")
    func notification() {
        #expect(RPCResponse.refusal(
            to: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            reason: "no"
        ) == nil)
    }

    @Test("Garbage gets a parse error")
    func garbage() throws {
        let reply = try decode(RPCResponse.refusal(to: "not json", reason: "no"))
        let error = try #require(reply["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32700)
    }
}
