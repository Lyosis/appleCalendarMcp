import Foundation

/// The hours of each day that `find_free_slots` searches, in the Mac's time
/// zone. Only valid hours make one, so the search never has to second-guess
/// them.
///
/// Measured on 2026-10-31, before this existed: an end hour of 24, a start
/// hour of -1 or a start after the end each answered "0 openings" without an
/// error — read by a model as a full day — and 8.5 was quietly rounded to 9.
struct WorkingHours: Equatable, Sendable {
    /// The hour the window opens, 0 to 23.
    let start: Int
    /// The hour it closes, 1 to 24, after `start`. 24 is the next midnight.
    let end: Int

    init(start: Int = 9, end: Int = 18) throws {
        guard (0...23).contains(start) else {
            throw ToolFailure("dayStartHour must be an hour from 0 to 23, not \(start).")
        }
        guard (1...24).contains(end) else {
            throw ToolFailure("dayEndHour must be an hour from 1 to 24 (24 is midnight), not \(end).")
        }
        guard start < end else {
            throw ToolFailure("dayStartHour (\(start)) must come before dayEndHour (\(end)).")
        }
        self.start = start
        self.end = end
    }

    /// From the tool's `dayStartHour` and `dayEndHour`; an absent one takes
    /// its default.
    init(arguments: JSONValue) throws {
        let defaults = try WorkingHours()
        try self.init(
            start: try WholeNumber.read(arguments, "dayStartHour", unit: "hours") ?? defaults.start,
            end: try WholeNumber.read(arguments, "dayEndHour", unit: "hours") ?? defaults.end)
    }

    /// The window on `day`, which must be the start of a day. Nil if the
    /// calendar cannot place it.
    func window(on day: Date, calendar: Calendar) -> DateInterval? {
        let closes = end == 24
            ? calendar.date(byAdding: .day, value: 1, to: day)
            : calendar.date(bySettingHour: end, minute: 0, second: 0, of: day)
        guard let opens = calendar.date(bySettingHour: start, minute: 0, second: 0, of: day),
              let closes,
              opens < closes
        else {
            return nil
        }
        return DateInterval(start: opens, end: closes)
    }
}
