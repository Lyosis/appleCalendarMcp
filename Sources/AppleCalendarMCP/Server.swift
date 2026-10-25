import AppleCalendarIPC
import Foundation

/// MCP revisions this server can speak, newest first.
private let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

/// The MCP server. Transport-agnostic on purpose: XPC hands it one message at a
/// time, so the protocol layer can be exercised without a transport, and every
/// side effect stays behind `CalendarAccess`.
actor Server {
    let calendar = CalendarAccess()
    let journal = WriteJournal()

    // MARK: - Dispatch

    /// Handles one JSON-RPC message and returns the reply to send back, or nil
    /// when the message was a notification, which must never be answered.
    func respond(to message: String) async -> String? {
        let request: RPCRequest
        do {
            request = try JSONDecoder().decode(RPCRequest.self, from: Data(message.utf8))
        } catch {
            return RPCResponse.encode(RPCResponse.failure(id: .null, error: .parseError()))
        }

        guard let id = request.id else { return nil }

        do {
            let result = try await perform(request)
            return RPCResponse.encode(RPCResponse.success(id: id, result: result))
        } catch let error as RPCError {
            return RPCResponse.encode(RPCResponse.failure(id: id, error: error))
        } catch {
            return RPCResponse.encode(
                RPCResponse.failure(id: id, error: .internalError(error.localizedDescription))
            )
        }
    }

    private func perform(_ request: RPCRequest) async throws -> JSONValue {
        switch request.method {
        case "initialize": initialize(request)
        case "ping": .object([:])
        case "tools/list": toolList()
        case "tools/call": try await callTool(request)
        default: throw RPCError.methodNotFound(request.method)
        }
    }

    private func initialize(_ request: RPCRequest) -> JSONValue {
        // Echo the client's revision when it is one we know, otherwise answer
        // with ours and let the client decide whether it can proceed.
        let requested = request.arguments["protocolVersion"]?.stringValue
        let agreed = requested.flatMap { supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? supportedProtocolVersions[0]

        return .object([
            "protocolVersion": .string(agreed),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object([
                "name": "apple-calendar-mcp",
                "version": .string(serverVersion),
            ]),
        ])
    }
}
