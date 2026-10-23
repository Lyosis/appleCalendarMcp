import Foundation
import Testing
@testable import AppleCalendarMCP

/// Ranges: refused when they mean nothing, bounded so one call cannot hold the
/// store, and still split under EventKit's own four-year cap.
struct RangeTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let day: TimeInterval = 24 * 3600

    @Test("An empty or inverted range is an error, not zero events")
    func emptyAndInverted() {
        #expect(throws: CalendarError.self) {
            try CalendarAccess.checkRange(from: start, to: start, limit: CalendarAccess.eventRangeLimit)
        }
        #expect(throws: CalendarError.self) {
            try CalendarAccess.checkRange(from: start, to: start - 1, limit: CalendarAccess.eventRangeLimit)
        }
    }

    @Test("Ten years for events, one year for openings")
    func limits() throws {
        let tenYears = start.addingTimeInterval(CalendarAccess.eventRangeLimit.seconds)
        try CalendarAccess.checkRange(from: start, to: tenYears, limit: CalendarAccess.eventRangeLimit)
        #expect(throws: CalendarError.self) {
            try CalendarAccess.checkRange(from: start, to: tenYears + 1, limit: CalendarAccess.eventRangeLimit)
        }

        let oneYear = start.addingTimeInterval(CalendarAccess.openingsRangeLimit.seconds)
        try CalendarAccess.checkRange(from: start, to: oneYear, limit: CalendarAccess.openingsRangeLimit)
        #expect(throws: CalendarError.self) {
            try CalendarAccess.checkRange(from: start, to: oneYear + 1, limit: CalendarAccess.openingsRangeLimit)
        }
    }

    @Test("The audit's range, year 1 to 9999, is refused before any work")
    func auditRange() throws {
        let utc = TimeZone.gmt
        // Outside the accepted years, so it does not even parse any more…
        #expect(Timestamp.parse("0001-01-01", in: utc) == nil)
        // …and the widest range that does parse is still far too long.
        let first = try #require(Timestamp.parse("1900-01-01", in: utc))
        let last = try #require(Timestamp.parse("2200-12-31", in: utc))
        #expect(throws: CalendarError.self) {
            try CalendarAccess.checkRange(from: first, to: last, limit: CalendarAccess.eventRangeLimit)
        }
    }

    @Test("A ten-year range is split into windows EventKit honours, end to end")
    func windows() {
        let end = start.addingTimeInterval(CalendarAccess.eventRangeLimit.seconds)
        let windows = CalendarAccess.searchWindows(from: start, to: end)
        #expect(windows.count == 4)
        #expect(windows.first?.start == start)
        #expect(windows.last?.end == end)
        for (left, right) in zip(windows, windows.dropFirst()) {
            #expect(left.end == right.start)
        }
        // EventKit silently truncates anything past four years.
        #expect(windows.allSatisfy { $0.end.timeIntervalSince($0.start) < 4 * 365 * day })
    }
}
