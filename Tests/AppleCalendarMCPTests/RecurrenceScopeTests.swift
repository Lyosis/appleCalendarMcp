import Testing
@testable import AppleCalendarMCP

/// `span` must say exactly one of three things; a typo used to fall back to
/// the default without a word.
struct RecurrenceScopeTests {
    @Test("Absent means one occurrence")
    func defaultScope() throws {
        #expect(try RecurrenceScope(argument: nil) == .thisEvent)
    }

    @Test("The three names", arguments: RecurrenceScope.allCases)
    func accepted(_ scope: RecurrenceScope) throws {
        #expect(try RecurrenceScope(argument: scope.rawValue) == scope)
    }

    @Test("Anything else is refused", arguments: ["futureevents", "FutureEvents", "all", "", "allEvents"])
    func refused(_ text: String) {
        #expect(throws: CalendarError.self) { try RecurrenceScope(argument: text) }
    }
}
