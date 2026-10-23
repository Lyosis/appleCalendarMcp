import Foundation
import Testing
@testable import AppleCalendarMCP

/// The parser is where a time could be silently replaced by midnight, so
/// every case here is one that used to come out wrong or must never start to.
struct TimestampTests {
    /// A fixed zone, so the tests do not depend on where the Mac is.
    let paris: TimeZone

    init() throws {
        paris = try #require(TimeZone(identifier: "Europe/Paris"))
    }

    private func utc(_ text: String) -> Date? {
        Timestamp.parse(text, in: .gmt)
    }

    private func instant(
        _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0, offsetHours: Int
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: offsetHours * 3600))
        return try #require(
            calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s)))
    }

    @Test("A time without an offset keeps its time, read in the given zone")
    func naiveTimeIsLocalNotMidnight() throws {
        // The audit's case: this used to parse as 2026-09-03 22:00 UTC.
        #expect(try instant(2026, 9, 4, 14, 30, offsetHours: 2) == Timestamp.parse("2026-09-04T14:30:00", in: paris))
        #expect(try instant(2026, 9, 4, 14, 30, offsetHours: 2) == Timestamp.parse("2026-09-04T14:30", in: paris))
    }

    @Test("Offsets in every accepted spelling")
    func offsets() throws {
        let expected = try instant(2026, 9, 4, 14, 30, offsetHours: 2)
        #expect(Timestamp.parse("2026-09-04T14:30:00+02:00", in: paris) == expected)
        #expect(Timestamp.parse("2026-09-04T14:30:00+0200", in: paris) == expected)
        #expect(Timestamp.parse("2026-09-04T12:30:00Z", in: paris) == expected)
        #expect(Timestamp.parse("2026-09-04 14:30:00+02:00", in: paris) == expected)  // used to be midnight
        #expect(Timestamp.parse("2026-09-04T08:30:00-04:00", in: paris) == expected)
    }

    @Test("Fractions are read as fractions")
    func fractions() throws {
        let date = try #require(utc("2026-09-04T12:30:00.5Z"))
        let noonThirty = try instant(2026, 9, 4, 12, 30, offsetHours: 0)
        #expect(date.timeIntervalSince(noonThirty) == 0.5)
    }

    @Test("A bare date is midnight in the given zone")
    func bareDate() throws {
        #expect(try instant(2026, 9, 4, 0, 0, offsetHours: 2) == Timestamp.parse("2026-09-04", in: paris))
    }

    @Test(
        "Refused rather than moved somewhere else",
        arguments: [
            "2026-02-30",                     // used to become 1 March
            "2026-02-30T10:00:00Z",
            "2026-09-04T25:00:00Z",
            "2026-09-04T24:00:00Z",
            "2026-09-04T14:60:00Z",
            "2026-09-04T14:30:60Z",
            "2026-09-04T14:30:00+19:00",      // no such offset
            "2026-09-04T14:30:00+02:00 and then some",
            "2026-09-04T",
            "2026-9-4",
            "26-09-04",
            "",
            "tomorrow",
            "٢٠٢٦-٠٩-٠٤",                    // non-ASCII digits
            "0001-01-01",                     // outside the accepted years
            "9999-12-31",
        ])
    func refused(_ text: String) {
        #expect(Timestamp.parse(text, in: paris) == nil)
    }

    @Test("A local time skipped by the daylight-saving change is refused")
    func skippedLocalTime() throws {
        // Paris moves from 02:00 to 03:00 on 29 March 2026.
        #expect(Timestamp.parse("2026-03-29T02:30:00", in: paris) == nil)
        #expect(try instant(2026, 3, 29, 3, 30, offsetHours: 2) == Timestamp.parse("2026-03-29T03:30:00", in: paris))
        // An explicit offset names an instant, so the gap does not apply.
        #expect(try instant(2026, 3, 29, 2, 30, offsetHours: 1) == Timestamp.parse("2026-03-29T02:30:00+01:00", in: paris))
    }

    @Test("The edges of the accepted years")
    func yearBounds() {
        #expect(utc("1900-01-01") != nil)
        #expect(utc("2200-12-31T23:59:59Z") != nil)
        #expect(utc("1899-12-31") == nil)
        #expect(utc("2201-01-01") == nil)
    }
}
