import Foundation
import Testing
@testable import AppleCalendarMCP

/// Openings inside working hours. Pure arithmetic over busy intervals: the
/// EventKit fetch in front of it is not exercised here.
struct OpeningsTests {
    let calendar: Calendar

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        self.calendar = calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    private func openings(
        _ busy: [DateInterval], from: Date, to: Date, minutes: Double = 30, hours: WorkingHours? = nil
    ) throws -> [DateInterval] {
        CalendarAccess.openings(
            from: from, to: to,
            busy: CalendarAccess.merge(busy.sorted { $0.start < $1.start }),
            minimum: minutes * 60,
            hours: try hours ?? WorkingHours(),
            calendar: calendar)
    }

    @Test("An end hour of 24 reaches midnight, and only that day's midnight")
    func untilMidnight() throws {
        let busy = [DateInterval(start: try at(7, 9), end: try at(7, 20))]
        let found = try openings(busy, from: try at(7, 0), to: try at(9, 0),
                                 hours: try WorkingHours(start: 8, end: 24))
        #expect(found == [
            DateInterval(start: try at(7, 8), end: try at(7, 9)),
            DateInterval(start: try at(7, 20), end: try at(8, 0)),
            DateInterval(start: try at(8, 8), end: try at(9, 0)),
        ])
    }

    @Test("Midnight is found on the day the clocks go back")
    func untilMidnightAcrossTimeChange() throws {
        // 25 October 2026: Paris goes from 03:00 back to 02:00.
        let found = try openings([], from: try at(0, 0, month: 10, day: 25), to: try at(0, 0, month: 10, day: 26),
                                 hours: try WorkingHours(start: 22, end: 24))
        #expect(found == [
            DateInterval(start: try at(22, 0, month: 10, day: 25), end: try at(0, 0, month: 10, day: 26)),
        ])
    }

    private func at(_ hour: Int, _ minute: Int, month: Int, day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)))
    }

    @Test("Busy time splits the day, and short gaps are dropped")
    func oneDay() throws {
        let busy = [
            DateInterval(start: try at(7, 10), end: try at(7, 11)),
            DateInterval(start: try at(7, 11, 15), end: try at(7, 12)),  // leaves a 15-minute gap
        ]
        let found = try openings(busy, from: try at(7, 0), to: try at(8, 0))
        #expect(found == [
            DateInterval(start: try at(7, 9), end: try at(7, 10)),
            DateInterval(start: try at(7, 12), end: try at(7, 18)),
        ])
    }

    @Test("An interval spanning two days blocks both, and the scan resumes after it")
    func acrossDays() throws {
        let busy = [
            DateInterval(start: try at(7, 17), end: try at(8, 10)),
            DateInterval(start: try at(9, 9), end: try at(9, 18)),
        ]
        let found = try openings(busy, from: try at(7, 0), to: try at(10, 0))
        #expect(found == [
            DateInterval(start: try at(7, 9), end: try at(7, 17)),
            DateInterval(start: try at(8, 10), end: try at(8, 18)),
        ])
    }

    @Test("A busy interval that starts after the window does not end the scan early")
    func laterIntervalsIgnored() throws {
        let busy = [DateInterval(start: try at(9, 12), end: try at(9, 13))]
        let found = try openings(busy, from: try at(7, 0), to: try at(8, 0))
        #expect(found == [DateInterval(start: try at(7, 9), end: try at(7, 18))])
    }

    @Test("A year of busy days gives the same answer as day-by-day reasoning")
    func longRange() throws {
        // One hour busy at 12:00 every day for a year: every day has exactly
        // two openings, 9–12 and 13–18.
        let start = try at(1, 0)
        let end = try #require(calendar.date(byAdding: .day, value: 365, to: start))
        var busy: [DateInterval] = []
        var day = start
        while day < end {
            let noon = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day))
            busy.append(DateInterval(start: noon, duration: 3600))
            day = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        }
        let found = try openings(busy, from: start, to: end)
        #expect(found.count == 365 * 2)
        #expect(found.allSatisfy { calendar.component(.hour, from: $0.start) == 9 || calendar.component(.hour, from: $0.start) == 13 })
    }
}
