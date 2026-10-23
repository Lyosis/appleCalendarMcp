/// Which part of a recurring event a change or a deletion applies to.
///
/// Spelled out by the caller, never inferred: EventKit's lookup by identifier
/// answers with the *first* occurrence of a series, so an implicit default
/// used to act on the oldest occurrence — or, with `.futureEvents`, on the
/// whole series — while the caller believed it was addressing something else.
enum RecurrenceScope: String, Sendable, CaseIterable {
    /// One occurrence, named by `occurrenceStart`. Also the only scope a
    /// non-recurring event has, and the default.
    case thisEvent
    /// An occurrence, named by `occurrenceStart`, and every later one.
    case futureEvents
    /// Every occurrence. Takes no `occurrenceStart`.
    case series

    /// Reads the `span` argument. Anything but the three names is refused
    /// rather than quietly read as the default.
    init(argument: String?) throws {
        guard let argument else {
            self = .thisEvent
            return
        }
        guard let scope = RecurrenceScope(rawValue: argument) else {
            throw CalendarError.badSpan(argument)
        }
        self = scope
    }
}
