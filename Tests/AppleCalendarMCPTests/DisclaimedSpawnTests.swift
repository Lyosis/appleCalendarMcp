import Testing
@testable import AppleCalendarMCP

/// `--selftest` measures the agent's permission only through this spawn, and
/// the call it rests on is not public: these say so the day a macOS release
/// takes it away, instead of the selftest quietly reporting the terminal's.
struct DisclaimedSpawnTests {

    @Test("This macOS still offers responsibility_spawnattrs_setdisclaim")
    func available() {
        #expect(DisclaimedSpawn.isAvailable)
    }

    @Test("The exit status of the disclaimed program is passed on", arguments: [
        ("/usr/bin/true", Int32(0)),
        ("/usr/bin/false", Int32(1)),
    ])
    func exitStatus(_ program: String, _ status: Int32) {
        #expect(DisclaimedSpawn.run(program, arguments: []) == .exited(status))
    }

    @Test("A disclaimed program killed by a signal is reported as such")
    func killed() {
        #expect(DisclaimedSpawn.run("/bin/sh", arguments: ["-c", "kill -9 $$"]) == .killed(signal: 9))
    }

    @Test("A program that does not exist is not started")
    func missing() {
        guard case .notStarted = DisclaimedSpawn.run("/nonexistent/apple-calendar-mcp", arguments: []) else {
            Issue.record("expected notStarted")
            return
        }
    }
}
