import AppleCalendarIPC
import Foundation

/// MCP revisions this server can speak, newest first.
private let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

/// The MCP server. Transport-agnostic on purpose: the same actor serves XPC in
/// production and stdio in development, and every side effect stays behind
/// `CalendarAccess`.
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
            return encode(RPCResponse.failure(id: .null, error: .parseError()))
        }

        guard let id = request.id else { return nil }

        do {
            let result = try await perform(request)
            return encode(RPCResponse.success(id: id, result: result))
        } catch let error as RPCError {
            return encode(RPCResponse.failure(id: id, error: error))
        } catch {
            return encode(
                RPCResponse.failure(id: id, error: .internalError(error.localizedDescription))
            )
        }
    }

    private func encode(_ value: JSONValue) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            log("dropped a reply that could not be encoded")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
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
