import Testing
@testable import AppleCalendarMCP

/// Before, -30 set an alert after the start, 8.5 was rounded and a string set
/// no alert — each time with a success.
struct AlarmMinutesTests {
    private func read(_ value: JSONValue) throws -> Int? {
        try AlarmMinutes.read(.object(["alarmMinutesBefore": value]))
    }

    @Test("Absent or null means no alert")
    func absent() throws {
        #expect(try AlarmMinutes.read(.object([:])) == nil)
        #expect(try read(.null) == nil)
    }

    @Test("Whole minutes from the start to four weeks before are kept", arguments: [
        (JSONValue.int(0), 0), (.int(15), 15), (.double(15), 15), (.int(40_320), 40_320),
    ])
    func kept(_ value: JSONValue, _ expected: Int) throws {
        #expect(try read(value) == expected)
    }

    @Test("Anything else is refused, never rounded or dropped", arguments: [
        JSONValue.int(-30), .int(-1), .int(40_321), .int(10_000_000),
        .double(8.5), .double(1e300), .string("15"), .bool(true),
    ])
    func refused(_ value: JSONValue) {
        #expect(throws: ToolFailure.self) { try read(value) }
    }
}
