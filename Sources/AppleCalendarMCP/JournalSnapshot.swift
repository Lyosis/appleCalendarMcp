import Foundation

/// What the change journal keeps of one event: enough to tell which event it
/// was and to recreate it by hand, and nothing written by other people beyond
/// its title. Location, notes and url stay out of the log; a change to them is
/// recorded by name only.
struct JournalSnapshot: Sendable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendar: String
    let isAllDay: Bool
    /// How the series repeats, in words; nil for a single event — including an
    /// occurrence that was edited on its own, which EventKit detaches.
    let recurrence: String?

    init(
        id: String, title: String, start: Date, end: Date,
        calendar: String, isAllDay: Bool, recurrence: String?
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendar = calendar
        self.isAllDay = isAllDay
        self.recurrence = recurrence
    }

    init(_ event: EventInfo) {
        self.init(
            id: event.id, title: event.title, start: event.start, end: event.end,
            calendar: event.calendarTitle, isAllDay: event.isAllDay, recurrence: event.recurrence)
    }

    /// One occurrence: a series shares its identifier across occurrences.
    var occurrenceKey: String { "\(id)@\(start.timeIntervalSinceReferenceDate)" }

    var json: JSONValue {
        var fields: [String: JSONValue] = [
            "eventId": .string(id),
            "title": .string(title),
            "start": .string(Timestamp.string(from: start)),
            "end": .string(Timestamp.string(from: end)),
            "calendar": .string(calendar),
            "isAllDay": .bool(isAllDay),
        ]
        if let recurrence {
            fields["recurrence"] = .string(recurrence)
        }
        return .object(fields)
    }

    /// The events that were in `before` and are no longer in `after`, one per
    /// identifier — its earliest occurrence — in chronological order.
    ///
    /// Deleting a series also takes the parts EventKit split off from it: a
    /// series cut in two by a "this and future" change, an occurrence edited
    /// on its own. Each carries its own identifier (measured on 2026-10-23),
    /// so comparing what is there before and after is what finds them all —
    /// rather than guessing how EventKit relates them.
    static func removed(before: [JournalSnapshot], after: [JournalSnapshot]) -> [JournalSnapshot] {
        let remaining = Set(after.map(\.occurrenceKey))
        var earliest: [String: JournalSnapshot] = [:]
        for event in before where !remaining.contains(event.occurrenceKey) {
            if let known = earliest[event.id], known.start <= event.start { continue }
            earliest[event.id] = event
        }
        return earliest.values.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }
}
