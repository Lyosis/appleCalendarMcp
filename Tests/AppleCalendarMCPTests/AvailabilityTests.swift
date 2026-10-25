import Testing
@testable import AppleCalendarMCP

/// Which events make the person unavailable when looking for openings.
/// Measured on 2026-10-25: birthdays and public holidays are all-day events
/// whose calendar records no availability ("unknown"), and they used to empty
/// the whole day around them.
struct AvailabilityTests {
    @Test("Busy, tentative and unavailable block, all-day or not", arguments: [
        ("busy", false), ("busy", true),
        ("tentative", false), ("tentative", true),
        ("unavailable", false), ("unavailable", true),
    ])
    func blocks(_ availability: String, _ isAllDay: Bool) {
        #expect(CalendarAccess.blocksTime(availability: availability, isAllDay: isAllDay))
    }

    @Test("Free never blocks", arguments: [false, true])
    func free(_ isAllDay: Bool) {
        #expect(!CalendarAccess.blocksTime(availability: "free", isAllDay: isAllDay))
    }

    @Test("An all-day marker with no availability — a birthday, a holiday — does not block")
    func allDayMarker() {
        #expect(!CalendarAccess.blocksTime(availability: "unknown", isAllDay: true))
    }

    @Test("A timed event with no availability still blocks")
    func timedWithoutAvailability() {
        #expect(CalendarAccess.blocksTime(availability: "unknown", isAllDay: false))
    }
}
