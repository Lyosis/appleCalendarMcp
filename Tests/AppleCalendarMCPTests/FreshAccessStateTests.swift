import AppleCalendarSetup
import Testing
@testable import AppleCalendarMCP

/// A running agent never sees a change made elsewhere, either way — measured
/// on 2026-10-31. Every call goes by what a new process sees.
struct FreshAccessStateTests {
    private let settled = FreshAccessState.settleTime + .seconds(1)

    @Test("Goes ahead only when both can read")
    func proceed() {
        #expect(FreshAccessState.decide(inProcess: .fullAccess, fresh: .fullAccess, uptime: settled) == .proceed)
    }

    @Test("A withdrawn grant is refused, whatever this process believes", arguments: [
        (AccessState.fullAccess, AccessState.notDetermined),
        (.fullAccess, .denied),
        (.fullAccess, .writeOnly),
        (.fullAccess, .restricted),
        (.notDetermined, .notDetermined),
        (.denied, .writeOnly),
    ])
    func refuse(_ state: AccessState, _ fresh: AccessState) {
        #expect(FreshAccessState.decide(inProcess: state, fresh: fresh, uptime: settled) == .refuse(fresh))
    }

    @Test("No answer from the child is refused, not trusted", arguments: [
        AccessState.fullAccess, .notDetermined,
    ])
    func unconfirmed(_ state: AccessState) {
        #expect(FreshAccessState.decide(inProcess: state, fresh: nil, uptime: settled) == .unconfirmed)
    }

    @Test("Restarts when a new process can read and this one cannot", arguments: [
        AccessState.notDetermined, .denied, .writeOnly,
    ])
    func restart(_ state: AccessState) {
        #expect(FreshAccessState.decide(inProcess: state, fresh: .fullAccess, uptime: settled) == .restart)
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
