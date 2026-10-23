import Foundation
import Testing
@testable import AppleCalendarMCP

/// What the model reads about the tools. Goes through `Server.respond`, so it
/// also covers the JSON-RPC envelope, without touching any event.
struct CatalogueTests {
    private func toolList() async throws -> [JSONValue] {
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#
        let reply = try #require(await Server().respond(to: request))
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(reply.utf8))
        return try #require(decoded["result"]?["tools"]?.arrayValue)
    }

    @Test("update_event and delete_event list exactly the three spans", arguments: ["update_event", "delete_event"])
    func spanIsEnumerated(_ name: String) async throws {
        let tools = try await toolList()
        let tool = try #require(tools.first { $0["name"]?.stringValue == name })
        let span = try #require(tool["inputSchema"]?["properties"]?["span"])
        let values = try #require(span["enum"]?.arrayValue).compactMap(\.stringValue)
        #expect(values == RecurrenceScope.allCases.map(\.rawValue))
    }

    @Test("A malformed message is a parse error, not silence")
    func parseError() async throws {
        let reply = try #require(await Server().respond(to: "not json"))
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(reply.utf8))
        #expect(decoded["error"]?["code"]?.intValue == -32700)
    }
}
