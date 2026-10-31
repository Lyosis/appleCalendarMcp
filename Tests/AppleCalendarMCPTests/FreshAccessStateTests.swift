import AppleCalendarSetup
import Testing
@testable import AppleCalendarMCP

/// A running agent never sees a grant made elsewhere — measured on
/// 2026-10-31. It restarts when a new process can read and it cannot, and
/// only then.
struct FreshAccessStateTests {
    private let settled = FreshAccessState.settleTime + .seconds(1)

    @Test("Restarts when a new process can read and this one cannot", arguments: [
        AccessState.notDetermined, .denied, .writeOnly,
    ])
    func restart(_ state: AccessState) {
        #expect(FreshAccessState.decide(inProcess: state, fresh: .fullAccess, uptime: settled) == .restart)
    }

    @Test("Stays when there is nothing new to see", arguments: [
        (AccessState.fullAccess, AccessState?.some(.fullAccess)),
        (.fullAccess, .some(.notDetermined)),
        (.notDetermined, .some(.notDetermined)),
        (.denied, .some(.writeOnly)),
        (.notDetermined, nil),
    ])
    func unchanged(_ state: AccessState, _ fresh: AccessState?) {
        #expect(FreshAccessState.decide(inProcess: state, fresh: fresh, uptime: settled) == .unchanged)
    }

    @Test("An agent that started after the grant does not restart again")
    func young() {
        let young = FreshAccessState.settleTime - .seconds(1)
        #expect(FreshAccessState.decide(inProcess: .notDetermined, fresh: .fullAccess, uptime: young) == .disagreement)
    }

    @Test("The child's answer is read strictly", arguments: [
        ("fullAccess\n", AccessState?.some(.fullAccess)),
        ("notDetermined", .some(.notDetermined)),
        ("", nil),
        ("FullAccess", nil),
        ("fullAccess extra", nil),
    ])
    func parse(_ output: String, _ expected: AccessState?) {
        #expect(FreshAccessState.parse(output) == expected)
    }
}
