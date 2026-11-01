/// How long before an event its alert goes off, as `create_event` takes it.
///
/// Before this, the value was taken as given: -30 set an alert half an hour
/// after the start, 8.5 was rounded to 9, and a string or a number too large
/// for an integer set no alert at all — each time with a success.
enum AlarmMinutes {

    /// Four weeks: far beyond the day before or the week before.
    static let maximum = 40_320

    /// Nil when absent: no alert. 0 alerts at the start.
    static func read(_ arguments: JSONValue) throws -> Int? {
        guard let minutes = try WholeNumber.read(arguments, "alarmMinutesBefore", unit: "minutes") else {
            return nil
        }
        let range = "from 0 (at the start) to \(maximum) (four weeks before)"
        guard minutes >= 0 else {
            throw ToolFailure("""
                alarmMinutesBefore must be \(range), not \(minutes): an alert after \
                the start is not offered. Nothing was created.
                """)
        }
        guard minutes <= maximum else {
            throw ToolFailure("alarmMinutesBefore must be \(range), not \(minutes). Nothing was created.")
        }
        return minutes
    }
}
