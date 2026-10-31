import Testing
@testable import AppleCalendarMCP

/// Hours that cannot make a window are refused, instead of answering "no
/// openings" — measured on 2026-10-31 for 24, -1 and an inverted day.
struct WorkingHoursTests {

    @Test("Absent hours take the defaults, 9 to 18")
    func defaults() throws {
        let hours = try WorkingHours(arguments: .object([:]))
        #expect(hours == (try WorkingHours(start: 9, end: 18)))
    }

    @Test("An explicit null is the default too")
    func null() throws {
        let hours = try WorkingHours(arguments: .object(["dayStartHour": .null, "dayEndHour": .null]))
        #expect(hours == (try WorkingHours()))
    }

    @Test("The widest valid day runs from 0 to 24")
    func wholeDay() throws {
        let hours = try WorkingHours(arguments: .object(["dayStartHour": .int(0), "dayEndHour": .int(24)]))
        #expect(hours.start == 0 && hours.end == 24)
    }

    @Test("A whole number sent as a decimal is accepted")
    func wholeDecimal() throws {
        let hours = try WorkingHours(arguments: .object(["dayStartHour": .double(8.0)]))
        #expect(hours.start == 8)
    }

    @Test("Hours that cannot make a window are refused", arguments: [
        ["dayStartHour": JSONValue.int(-1)],
        ["dayStartHour": .int(24)],
        ["dayEndHour": .int(0)],
        ["dayEndHour": .int(25)],
        ["dayStartHour": .int(18), "dayEndHour": .int(9)],
        ["dayStartHour": .int(12), "dayEndHour": .int(12)],
        ["dayStartHour": .int(19)],
    ])
    func outOfRange(_ members: [String: JSONValue]) {
        #expect(throws: ToolFailure.self) { try WorkingHours(arguments: .object(members)) }
    }

    @Test("A value that is not a whole number is refused, not rounded or defaulted", arguments: [
        JSONValue.double(8.5),
        .string("8"),
        .bool(true),
        .array([.int(8)]),
    ])
    func notWhole(_ value: JSONValue) {
        #expect(throws: ToolFailure.self) {
            try WorkingHours(arguments: .object(["dayStartHour": value]))
        }
    }
}
