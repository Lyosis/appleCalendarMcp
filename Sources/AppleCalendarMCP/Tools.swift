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
                    List events overlapping a time range, oldest first. The range may \
                    cover up to ten years; end must be later than start.
                    """,
                    properties: [
                        "start": schema(
                            "string",
                            """
                            Start of the range, ISO 8601, e.g. 2026-09-04T00:00:00+02:00. \
                            Without an offset the Mac's time zone is used; a bare date \
                            means midnight.
                            """),
                        "end": schema("string", "End of the range, ISO 8601. For one whole day, the next day's date."),
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
                    a time range of up to ten years. Matching ignores case and accents.
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
                    Find openings of at least a given length, within working hours, over \
                    a range of up to one year. Events marked free do not block a slot, \
                    nor do all-day events from calendars that record no availability — \
                    birthdays and public holidays. A day off is therefore not excluded: \
                    check list_events when that matters.
                    """,
                    properties: [
                        "start": schema("string", "Start of the range to search, ISO 8601."),
                        "end": schema("string", "End of the range to search, ISO 8601."),
                        "durationMinutes": schema("integer", "How long the opening must be."),
                        "calendarIds": arraySchema("Consider only these calendars as busy."),
                        "dayStartHour": schema(
                            "integer",
                            "Hour the working day starts, 0-23, in the Mac's time zone. Defaults to 9."),
                        "dayEndHour": schema(
                            "integer",
                            "Hour the working day ends, 1-24 and after dayStartHour; 24 is midnight. Defaults to 18."),
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
                    recurring event, say which part to change: occurrenceStart with span \
                    thisEvent or futureEvents, or span series for every occurrence. A \
                    recurring event addressed without either is refused, and nothing changes.
                    """,
                    properties: [
                        "id": schema("string", "Identifier from list_events or search_events."),
                        "occurrenceStart": schema(
                            "string",
                            """
                            Start of the occurrence to change, ISO 8601, as list_events \
                            returns it. Required for a recurring event unless span is series.
                            """),
                        "span": spanSchema(
                            """
                            "thisEvent" changes only that occurrence, "futureEvents" changes \
                            it and every later one, "series" changes every occurrence and \
                            takes no occurrenceStart. Defaults to thisEvent; any other value \
                            is refused.
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
                    Delete one event — or, for a recurring event, one occurrence, it and \
                    the later ones, or the whole series, as span says. Requires confirm: \
                    true, and every deletion is written to the change journal. Deleting \
                    a series also removes occurrences edited on their own and series \
                    split off from it; eventsRemoved says how many events went.
                    """,
                    properties: [
                        "id": schema("string", "Identifier from list_events or search_events."),
                        "occurrenceStart": schema(
                            "string",
                            """
                            Start of the occurrence to delete, ISO 8601, as list_events \
                            returns it. Required for a recurring event unless span is series.
                            """),
                        "span": spanSchema(
                            """
                            "thisEvent", "futureEvents" or "series" — the last deletes every \
                            occurrence and takes no occurrenceStart. Defaults to thisEvent; \
                            any other value is refused.
                            """),
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
        let range = try requiredRange(arguments, limit: CalendarAccess.eventRangeLimit)
        let events = try await calendar.events(
            from: range.start, to: range.end, calendarIDs: calendarIDs(arguments))
        return eventsResult(events, arguments: arguments)
    }

    private func searchEvents(_ arguments: JSONValue) async throws -> JSONValue {
        try await ensureAccess()
        let query = try requiredString(arguments, "query")
        let range = try requiredRange(arguments, limit: CalendarAccess.eventRangeLimit)
        let events = try await calendar.search(
            query: query, from: range.start, to: range.end, calendarIDs: calendarIDs(arguments))
        return eventsResult(events, arguments: arguments)
    }

    private func findFreeSlots(_ arguments: JSONValue) async throws -> JSONValue {
        try await ensureAccess()
        let range = try requiredRange(arguments, limit: CalendarAccess.openingsRangeLimit)
        guard let minutes = arguments["durationMinutes"]?.intValue, minutes > 0 else {
            throw ToolFailure("durationMinutes must be a positive number of minutes.")
        }
        let hours = try WorkingHours(arguments: arguments)

        let slots = try await calendar.freeSlots(
            from: range.start,
            to: range.end,
            duration: Double(minutes) * 60,
            calendarIDs: calendarIDs(arguments),
            hours: hours
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
        await journal.recordCreation(event)

        return toolResult(
            JSONValue.object([
                "created": event.json(includeDetails: true),
                "changeJournal": .string(journal.path),
            ]).prettyPrinted())
    }

    private func updateEvent(_ arguments: JSONValue) async throws -> JSONValue {
        try await ensureAccess()
        let id = try requiredString(arguments, "id")
        let occurrenceStart = try optionalDate(arguments, "occurrenceStart")
        let scope = try RecurrenceScope(argument: arguments["span"]?.stringValue)

        var draft = EventDraft()
        draft.title = arguments["title"]?.stringValue
        draft.start = try optionalDate(arguments, "start")
        draft.end = try optionalDate(arguments, "end")
        draft.isAllDay = arguments["isAllDay"]?.boolValue
        draft.location = arguments["location"]?.stringValue
        draft.notes = arguments["notes"]?.stringValue
        draft.url = arguments["url"]?.stringValue
        draft.calendarID = arguments["calendarId"]?.stringValue

        let update = try await calendar.update(
            id: id, occurrenceStart: occurrenceStart, scope: scope, draft: draft)
        await journal.recordUpdate(update, scope: scope, occurrenceStart: occurrenceStart)
        let event = update.after

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
        let occurrenceStart = try optionalDate(arguments, "occurrenceStart")
        let scope = try RecurrenceScope(argument: arguments["span"]?.stringValue)

        let deletion = try await calendar.delete(
            id: id, occurrenceStart: occurrenceStart, scope: scope)
        await journal.recordDeletion(deletion, scope: scope, occurrenceStart: occurrenceStart)

        return toolResult(
            JSONValue.object([
                "deleted": deletion.target.json(includeDetails: false),
                // A series takes the parts split off it with it; say how many
                // went, so "deleted one event" is never read into it.
                "eventsRemoved": .int(deletion.removed.count),
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

/// `span`, with its three accepted values listed for the model to read.
private func spanSchema(_ description: String) -> JSONValue {
    .object([
        "type": "string",
        "enum": .array(RecurrenceScope.allCases.map { .string($0.rawValue) }),
        "description": .string(description),
    ])
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

/// `start` and `end`, refused when empty, inverted or longer than `limit`.
private func requiredRange(
    _ arguments: JSONValue, limit: (seconds: TimeInterval, name: String)
) throws -> (start: Date, end: Date) {
    let start = try requiredDate(arguments, "start")
    let end = try requiredDate(arguments, "end")
    try CalendarAccess.checkRange(from: start, to: end, limit: limit)
    return (start, end)
}

private func calendarIDs(_ arguments: JSONValue) -> [String]? {
    arguments["calendarIds"]?.arrayValue?.compactMap(\.stringValue)
}
