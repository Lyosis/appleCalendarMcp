import AppleCalendarSetup
import Testing
@testable import AppleCalendarMCP

/// The server never asks for calendar access: it says where to grant it.
struct AccessAdviceTests {

    @Test("No decision yet sends the person to the app, and promises no prompt")
    func notDetermined() {
        let advice = AccessState.notDetermined.adviceForClient
        #expect(advice.contains("AppleCalendarMCP.app"))
        #expect(!advice.contains("will ask"))
    }

    @Test("Other states keep the shared explanation", arguments: [
        AccessState.denied, .restricted, .writeOnly, .fullAccess,
    ])
    func otherStates(_ state: AccessState) {
        #expect(state.adviceForClient == state.explanation)
    }
}
