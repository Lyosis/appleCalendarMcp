import Foundation

/// MCP revisions this server can speak, newest first.
private let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

/// The MCP server: reads newline-delimited JSON-RPC from stdin, answers on
/// stdout, and keeps every side effect behind `CalendarAccess`.
actor Server {
    private let calendar = CalendarAccess()
    private let output = StdoutWriter()

    func run() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                let message = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !message.isEmpty else { continue }
                await handle(message)
            }
        } catch {
            log("stdin ended with an error: \(error)")
        }
    }

    // MARK: - Dispatch

    private func handle(_ message: String) async {
        let request: RPCRequest
        do {
            request = try JSONDecoder().decode(RPCRequest.self, from: Data(message.utf8))
        } catch {
            await output.send(RPCResponse.failure(id: .null, error: .parseError()))
            return
        }

        // A notification carries no id and must never be answered, not even on
        // failure.
        guard let id = request.id else { return }

        do {
            let result = try await perform(request)
            await output.send(RPCResponse.success(id: id, result: result))
        } catch let error as RPCError {
            await output.send(RPCResponse.failure(id: id, error: error))
        } catch {
            await output.send(
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

    // MARK: - Tools

    private func toolList() -> JSONValue {
        .object([
            "tools": .array([
                .object([
                    "name": "check_access",
                    "description": """
                        Report whether this server is allowed to read and write the \
                        Calendar app's events, and what to do about it if not. Use \
                        this first when a calendar tool fails.
                        """,
                    "inputSchema": .object([
                        "type": "object",
                        "properties": .object([
                            "request": .object([
                                "type": "boolean",
                                "description": """
                                    Ask the system for access if no decision has been \
                                    recorded yet. This may show a permission prompt. \
                                    Defaults to false, which only reports the status.
                                    """,
                            ])
                        ]),
                        "additionalProperties": false,
                    ]),
                ]),
                .object([
                    "name": "list_calendars",
                    "description": """
                        List every calendar available on this Mac, including iCloud \
                        ones, with the identifier needed to read or write events in \
                        them and whether they accept changes.
                        """,
                    "inputSchema": .object([
                        "type": "object",
                        "properties": .object([:]),
                        "additionalProperties": false,
                    ]),
                ]),
            ])
        ])
    }

    private func callTool(_ request: RPCRequest) async throws -> JSONValue {
        guard let name = request.arguments["name"]?.stringValue else {
            throw RPCError.invalidParams("Missing tool name")
        }
        let arguments = request.arguments["arguments"] ?? .object([:])

        switch name {
        case "check_access": return await checkAccess(arguments)
        case "list_calendars": return await listCalendars()
        default: throw RPCError.invalidParams("Unknown tool: \(name)")
        }
    }

    private func checkAccess(_ arguments: JSONValue) async -> JSONValue {
        var state = CalendarAccess.currentState()
        var requested = false

        if arguments["request"]?.boolValue == true, state == .notDetermined {
            requested = true
            let outcome = await calendar.requestAccess()
            state = outcome.state
            if let error = outcome.error {
                log("access request failed: \(error)")
            }
        }

        return toolResult(
            JSONValue.object([
                "status": .string(state.rawValue),
                "canReadEvents": .bool(state.canRead),
                "explanation": .string(state.explanation),
                "promptRequested": .bool(requested),
            ]).prettyPrinted(),
            isError: !state.canRead
        )
    }

    private func listCalendars() async -> JSONValue {
        var state = CalendarAccess.currentState()

        // The first read is what naturally triggers the system prompt.
        if state == .notDetermined {
            state = await calendar.requestAccess().state
            // Apple's documentation: a store that was queried before access was
            // granted keeps returning nothing until it is reset.
            await calendar.reset()
        }

        guard state.canRead else {
            return toolResult(
                "Cannot read calendars: \(state.explanation)",
                isError: true
            )
        }

        let calendars = await calendar.calendars()
        return toolResult(
            JSONValue.object([
                "count": .int(calendars.count),
                "calendars": .array(calendars.map(\.json)),
            ]).prettyPrinted()
        )
    }

    private func toolResult(_ text: String, isError: Bool = false) -> JSONValue {
        .object([
            "content": .array([.object(["type": "text", "text": .string(text)])]),
            "isError": .bool(isError),
        ])
    }
}
