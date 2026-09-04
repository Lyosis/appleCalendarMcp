import AppleCalendarIPC
import AppleCalendarSetup
import EventKit
import Foundation

/// A tool that could not do what was asked, for a reason the caller can fix.
/// Reported inside the result rather than as a protocol error, so the model
/// reads the reason and can correct itself.
struct ToolFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

extension Server {

    // MARK: - Catalogue

    func toolList() -> JSONValue {
        .object([
            "tools": .array([
                tool(
                    "check_access",
                    """
                    Report whether this server may read and write Calendar events, and \
                    what to do about it if not. Use this first when another calendar \
                    tool fails.
                    """,
                    properties: [
                        "request": schema(
                            "boolean",
                            """
                            Ask the system for access when no decision has been recorded \
                            yet, which may show a permission prompt. Defaults to false.
                            """)
                    ]),
                tool(
                    "list_calendars",
                    """
                    List every calendar on this Mac, iCloud included, with the identifier \
                    other tools need and whether it accepts changes.
                    """),
                tool(
                    "list_events",
                    """
                    List events overlapping a time range, oldest first. Ranges longer than \
                    three years are split internally, so a decade works.
                    """,
                    properties: [
                        "start": schema("string", "Start of the range, ISO 8601, e.g. 2026-09-04T00:00:00+02:00."),
                        "end": schema("string", "End of the range, ISO 8601."),
                        "calendarIds": arraySchema("Limit to these calendars. Defaults to all of them."),
                        "includeDetails": schema(
                            "boolean",
                            """
                            Also return location, notes, url and attendees. These carry \
                            other people's writing, so they are withheld by default.
                            """),
                        "limit": schema("integer", "Maximum events to return. Defaults to 100, capped at 500."),
                    ],
                    required: ["start", "end"]),
                tool(
                    "search_events",
                    """
                    Find events whose title, location or notes contain some text, within \
                    a time range. Matching ignores case and accents.
                    """,
                    properties: [
                        "query": schema("string", "Text to look for."),
                        "start": schema("string", "Start of the range, ISO 8601."),
                        "end": schema("string", "End of the range, ISO 8601."),
                        "calendarIds": arraySchema("Limit to these calendars."),
                        "includeDetails": schema("boolean", "Also return location, notes, url and attendees."),
                        "limit": schema("integer", "Maximum events to return. Defaults to 100, capped at 500."),
                    ],
                    required: ["query", "start", "end"]),
                tool(
                    "find_free_slots",
                    """
                    Find openings of at least a given length, within working hours. Events \
                    marked free — as all-day markers usually are — do not block a slot.
                    """,
                    properties: [
                        "start": schema("string", "Start of the range to search, ISO 8601."),
                        "end": schema("string", "End of the range to search, ISO 8601."),
                        "durationMinutes": schema("integer", "How long the opening must be."),
                        "calendarIds": arraySchema("Consider only these calendars as busy."),
                        "dayStartHour": schema("integer", "First hour of the working day, 0-23. Defaults to 9."),
                        "dayEndHour": schema("integer", "Last hour of the working day, 0-23. Defaults to 18."),
                    ],
                    required: ["start", "end", "durationMinutes"]),
                tool(
                    "create_event",
                    "Create an event. Goes to the default calendar unless calendarId says otherwise.",
                    properties: [
                        "title": schema("string", "Title of the event."),
                        "start": schema("string", "When it starts, ISO 8601."),
                        "end": schema("string", "When it ends, ISO 8601."),
                        "calendarId": schema("string", "Calendar to create it in. Must accept changes."),
                        "isAllDay": schema("boolean", "Whether it occupies whole days."),
                        "location": schema("string", "Where it happens."),
                        "notes": schema("string", "Free text attached to the event."),
                        "url": schema("string", "A link to attach."),
                        "alarmMinutesBefore": schema("integer", "Add an alert this many minutes beforehand."),
                    ],
                    required: ["title", "start", "end"]),
                tool(
                    "update_event",
                    """
                    Change an existing event. Only the fields you pass are altered. For a \
                    recurring event, pass occurrenceStart to address one occurrence.
                    """,
                    properties: [
                        "id": schema("string", "Identifier from list_events or search_events."),
                        "occurrenceStart": schema(
                            "string",
                            """
                            Start of the occurrence to change, ISO 8601. Required for a \
                            recurring event; without it the series is matched instead.
                            """),
                        "span": schema(
                            "string",
                            """
                            "thisEvent" changes only this occurrence, "futureEvents" changes \
                            it and every later one. Defaults to thisEvent.
                            """),
                        "title": schema("string", "New title."),
                        "start": schema("string", "New start, ISO 8601."),
                        "end": schema("string", "New end, ISO 8601."),
                        "isAllDay": schema("boolean", "Whether it occupies whole days."),
                        "location": schema("string", "New location."),
                        "notes": schema("string", "New notes, replacing what was there."),
                        "url": schema("string", "New link."),
                        "calendarId": schema("string", "Move the event to this calendar."),
                    ],
                    required: ["id"]),
                tool(
                    "delete_event",
                    """
                    Delete one event. Requires confirm: true, deletes a single event per \
                    call, and every deletion is written to the change journal.
                    """,
                    properties: [
                        "id": schema("string", "Identifier from list_events or search_events."),
                        "occurrenceStart": schema("string", "Start of the occurrence to delete, ISO 8601."),
                        "span": schema("string", "\"thisEvent\" or \"futureEvents\". Defaults to thisEvent."),
                        "confirm": schema("boolean", "Must be true. Nothing is deleted without it."),
                    ],
                    required: ["id", "confirm"]),
            ])
        ])
    }

    // MARK: - Dispatch

    func callTool(_ request: RPCRequest) async throws -> JSONValue {
        guard let name = request.arguments["name"]?.stringValue else {
            throw RPCError.invalidParams("Missing tool name")
        }
        let arguments = request.arguments["arguments"] ?? .object([:])

        do {
            switch name {
            case "check_access": return await checkAccess(arguments)
            case "list_calendars": return try await listCalendars()
            case "list_events": return try await listEvents(arguments)
            case "search_events": return try await searchEvents(arguments)
            case "find_free_slots": return try await findFreeSlots(arguments)
            case "create_event": return try await createEvent(arguments)
            case "update_event": return try await updateEvent(arguments)
            case "delete_event": return try await deleteEvent(arguments)
            default: throw RPCError.invalidParams("Unknown tool: \(name)")
            }
        } catch let error as RPCError {
            throw error
        } catch {
            return toolResult(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Access

    private func checkAccess(_ arguments: JSONValue) async -> JSONValue {
        var state = CalendarPermission.current()
        var prompted = false

        if arguments["request"]?.boolValue == true, state == .notDetermined {
            prompted = true
            state = await calendar.requestAccess().state
            await calendar.reset()
        }

        return toolResult(
            JSONValue.object([
                "status": .string(state.rawValue),
                "canReadEvents": .bool(state.canRead),
                "explanation": .string(state.explanation),
                "promptRequested": .bool(prompted),
                "changeJournal": .string(journal.path),
            ]).prettyPrinted(),
            isError: !state.canRead
        )
    }

    /// EventKit has no read-only level: reading anything needs full access.
    private func ensureAccess() async throws {
        var state = CalendarPermission.current()
        if state == .notDetermined {
            state = await calendar.requestAccess().state
            await calendar.reset()
        }
        guard state.canRead else {
            throw ToolFailure(
                "\(state.explanation) Run `apple-calendar-mcp --selftest` to see the details.")
        }
    }

    // MARK: - Reading

    private func listCalendars() async throws -> JSONValue {
        try await ensureAccess()
        let calendars = await calendar.calendars()
        return toolResult(
            JSONValue.object([
                "count": .int(calendars.count),
                "calendars": .array(calendars.map(\.json)),
            ]).prettyPrinted())
    }

    private func listEvents(_ arguments: JSONValue) async throws -> JSONValue {
        try await ensureAccess()
        let start = try requiredDate(arguments, "start")
        let end = try requiredDate(arguments, "end")
        let events = try await calendar.events(
            from: start, to: end, calendarIDs: calendarIDs(arguments))
        return eventsResult(events, arguments: arguments)
    }

    private func searchEvents(_ arguments: JSONValue) async throws -> JSONValue {
        try await ensureAccess()
        let query = try requiredString(arguments, "query")
        let start = try requiredDate(arguments, "start")
        let end = try requiredDate(arguments, "end")
        let events = try await calendar.search(
            query: query, from: start, to: end, calendarIDs: calendarIDs(arguments))
        return eventsResult(events, arguments: arguments)
    }

    private func findFreeSlots(_ arguments: JSONValue) async throws -> JSONValue {
        try await ensureAccess()
        let start = try requiredDate(arguments, "start")
        let end = try requiredDate(arguments, "end")
        guard let minutes = arguments["durationMinutes"]?.intValue, minutes > 0 else {
            throw ToolFailure("durationMinutes must be a positive number of minutes.")
        }

        let slots = try await calendar.freeSlots(
            from: start,
            to: end,
            duration: Double(minutes) * 60,
            calendarIDs: calendarIDs(arguments),
            dayStartHour: arguments["dayStartHour"]?.intValue ?? 9,
            dayEndHour: arguments["dayEndHour"]?.intValue ?? 18
        )

        return toolResult(
            JSONValue.object([
                "count": .int(slots.count),
                "slots": .array(
                    slots.map { slot in
                        .object([
                            "start": .string(Timestamp.string(from: slot.start)),
                            "end": .string(Timestamp.string(from: slot.end)),
                            "minutes": .int(Int(slot.duration / 60)),
                        ])
                    }),
            ]).prettyPrinted())
    }

    // MARK: - Writing

    private func createEvent(_ arguments: JSONValue) async throws -> JSONValue {
        try await ensureAccess()
        var draft = EventDraft()
        draft.title = try requiredString(arguments, "title")
        draft.start = try requiredDate(arguments, "start")
        draft.end = try requiredDate(arguments, "end")
        draft.calendarID = arguments["calendarId"]?.stringValue
        draft.isAllDay = arguments["isAllDay"]?.boolValue
        draft.location = arguments["location"]?.stringValue
        draft.notes = arguments["notes"]?.stringValue
        draft.url = arguments["url"]?.stringValue
        draft.alarmMinutesBefore = arguments["alarmMinutesBefore"]?.intValue

        let event = try await calendar.create(draft)
        await journal.record(action: "create", event: event, span: "thisEvent")

        return toolResult(
            JSONValue.object([
                "created": event.json(includeDetails: true),
                "changeJournal": .string(journal.path),
            ]).prettyPrinted())
    }

    private func updateEvent(_ arguments: JSONValue) async throws -> JSONValue {
        try await ensureAccess()
        let id = try requiredString(arguments, "id")

        var draft = EventDraft()
        draft.title = arguments["title"]?.stringValue
        draft.start = try optionalDate(arguments, "start")
        draft.end = try optionalDate(arguments, "end")
        draft.isAllDay = arguments["isAllDay"]?.boolValue
        draft.location = arguments["location"]?.stringValue
        draft.notes = arguments["notes"]?.stringValue
        draft.url = arguments["url"]?.stringValue
        draft.calendarID = arguments["calendarId"]?.stringValue

        let event = try await calendar.update(
            id: id,
            occurrenceStart: try optionalDate(arguments, "occurrenceStart"),
            span: span(arguments),
            draft: draft
        )
        await journal.record(action: "update", event: event, span: spanName(arguments))

        return toolResult(
            JSONValue.object([
                "updated": event.json(includeDetails: true),
                "changeJournal": .string(journal.path),
            ]).prettyPrinted())
    }

    private func deleteEvent(_ arguments: JSONValue) async throws -> JSONValue {
        try await ensureAccess()
        guard arguments["confirm"]?.boolValue == true else {
            throw CalendarError.notConfirmed
        }
        let id = try requiredString(arguments, "id")

        let removed = try await calendar.delete(
            id: id,
            occurrenceStart: try optionalDate(arguments, "occurrenceStart"),
            span: span(arguments)
        )
        await journal.record(action: "delete", event: removed, span: spanName(arguments))

        return toolResult(
            JSONValue.object([
                "deleted": removed.json(includeDetails: false),
                "changeJournal": .string(journal.path),
            ]).prettyPrinted())
    }

    // MARK: - Shaping

    private func eventsResult(_ events: [EventInfo], arguments: JSONValue) -> JSONValue {
        let includeDetails = arguments["includeDetails"]?.boolValue ?? false
        let limit = min(max(arguments["limit"]?.intValue ?? 100, 1), 500)
        let shown = Array(events.prefix(limit))

        return toolResult(
            JSONValue.object([
                "note": .string(untrustedContentNotice),
                "count": .int(shown.count),
                "total": .int(events.count),
                "truncated": .bool(events.count > shown.count),
                "events": .array(shown.map { $0.json(includeDetails: includeDetails) }),
            ]).prettyPrinted())
    }

    func toolResult(_ text: String, isError: Bool = false) -> JSONValue {
        .object([
            "content": .array([.object(["type": "text", "text": .string(text)])]),
            "isError": .bool(isError),
        ])
    }
}

// MARK: - Schema helpers

private func schema(_ type: String, _ description: String) -> JSONValue {
    .object(["type": .string(type), "description": .string(description)])
}

private func arraySchema(_ description: String) -> JSONValue {
    .object([
        "type": "array",
        "items": .object(["type": "string"]),
        "description": .string(description),
    ])
}

private func tool(
    _ name: String,
    _ description: String,
    properties: [String: JSONValue] = [:],
    required: [String] = []
) -> JSONValue {
    var input: [String: JSONValue] = [
        "type": "object",
        "properties": .object(properties),
        "additionalProperties": false,
    ]
    if !required.isEmpty {
        input["required"] = .array(required.map { .string($0) })
    }
    return .object([
        "name": .string(name),
        "description": .string(description),
        "inputSchema": .object(input),
    ])
}

// MARK: - Argument helpers

private func requiredString(_ arguments: JSONValue, _ key: String) throws -> String {
    guard let value = arguments[key]?.stringValue, !value.isEmpty else {
        throw ToolFailure("\(key) is required.")
    }
    return value
}

private func requiredDate(_ arguments: JSONValue, _ key: String) throws -> Date {
    let text = try requiredString(arguments, key)
    guard let date = Timestamp.parse(text) else {
        throw CalendarError.badTimestamp(field: key, value: text)
    }
    return date
}

private func optionalDate(_ arguments: JSONValue, _ key: String) throws -> Date? {
    guard let text = arguments[key]?.stringValue else { return nil }
    guard let date = Timestamp.parse(text) else {
        throw CalendarError.badTimestamp(field: key, value: text)
    }
    return date
}

private func calendarIDs(_ arguments: JSONValue) -> [String]? {
    arguments["calendarIds"]?.arrayValue?.compactMap(\.stringValue)
}

private func spanName(_ arguments: JSONValue) -> String {
    arguments["span"]?.stringValue == "futureEvents" ? "futureEvents" : "thisEvent"
}

private func span(_ arguments: JSONValue) -> EKSpan {
    spanName(arguments) == "futureEvents" ? .futureEvents : .thisEvent
}
