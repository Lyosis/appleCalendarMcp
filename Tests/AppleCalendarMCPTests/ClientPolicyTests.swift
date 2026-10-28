import Darwin
import Testing
@testable import AppleCalendarMCP

/// The chain above the bridge must be exactly Claude Desktop's, measured on
/// 2026-10-25: bridge <- disclaimer <- Claude Desktop <- launchd.
struct ClientPolicyTests {
    typealias P = FakeProcesses.Process

    private static let bridge = "/Users/me/Applications/AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp-bridge"
    private static let disclaimer = "/Applications/Claude.app/Contents/Helpers/disclaimer"

    /// The measured chain: Claude (100), its disclaimer (200), the bridge (300),
    /// with disclaimer's arguments as measured on 2026-10-28.
    private func claudeDesktop() -> FakeProcesses {
        FakeProcesses([
            100: P(parent: 1, started: 1_000, name: "Claude Desktop"),
            200: P(parent: 100, started: 2_000, name: "disclaimer",
                   arguments: [Self.disclaimer, "--pgroup", "--", Self.bridge]),
            300: P(parent: 200, started: 3_000, name: "bridge", executable: Self.bridge),
        ])
    }

    /// The bypass measured on 2026-10-28: another MCP server, started by
    /// disclaimer, replaced itself with the bridge. Same pid, same parent.
    @Test("An MCP server that turned itself into the bridge is refused")
    func execBypass() {
        let processes = claudeDesktop()
        processes.table[200] = P(parent: 100, started: 2_000, name: "disclaimer",
                                 arguments: [Self.disclaimer, "--pgroup", "--", "/bin/bash", "poc.sh", "exec"])
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) != .allowed)
    }

    @Test("Naming the bridge as an argument of another program is not enough")
    func bridgeAsArgument() {
        let processes = claudeDesktop()
        processes.table[200] = P(parent: 100, started: 2_000, name: "disclaimer",
                                 arguments: [Self.disclaimer, "--pgroup", "--", "/bin/bash", Self.bridge])
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) != .allowed)
    }

    @Test("A link named like the bridge but leading elsewhere is refused")
    func disguisedLink() {
        let processes = claudeDesktop()
        let fake = "/tmp/x/AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp-bridge"
        processes.table[200] = P(parent: 100, started: 2_000, name: "disclaimer",
                                 arguments: [Self.disclaimer, "--pgroup", "--", fake])
        processes.links[fake] = "/tmp/x/evil"
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) != .allowed)
    }

    @Test("A link that does lead to the bridge is accepted")
    func honestLink() {
        let processes = claudeDesktop()
        let link = "/Users/me/bin/calendar-bridge"
        processes.table[200] = P(parent: 100, started: 2_000, name: "disclaimer",
                                 arguments: [Self.disclaimer, "--pgroup", "--", link])
        processes.links[link] = Self.bridge
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) == .allowed)
    }

    @Test("Unreadable or unfamiliar launcher arguments fail closed", arguments: [
        nil,
        [String](),
        ["/Applications/Claude.app/Contents/Helpers/disclaimer"],
        ["/Applications/Claude.app/Contents/Helpers/disclaimer", "--pgroup", "--"],
        ["/Applications/Claude.app/Contents/Helpers/disclaimer",
         "/Users/me/Applications/AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp-bridge"],
    ] as [[String]?])
    func unfamiliarArguments(_ arguments: [String]?) {
        let processes = claudeDesktop()
        processes.table[200] = P(parent: 100, started: 2_000, name: "disclaimer", arguments: arguments)
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) != .allowed)
    }

    @Test("The measured Claude Desktop chain is allowed")
    func allowed() {
        #expect(ClientPolicy.evaluate(peer: 300, using: claudeDesktop()) == .allowed)
    }

    /// The hole this policy closes: a shell started by a Claude Code session
    /// has Claude Desktop above it, and was accepted by the old "somewhere
    /// above" check.
    @Test("A bridge run from a Claude Code session's shell is refused")
    func claudeCodeShell() {
        let processes = FakeProcesses([
            100: P(parent: 1, started: 1_000, name: "Claude Desktop"),
            310: P(parent: 100, started: 2_000, name: "disclaimer"),
            320: P(parent: 310, started: 2_100, name: "claude"),
            350: P(parent: 320, started: 2_200, name: "bash"),
            400: P(parent: 350, started: 3_000, name: "bridge"),
        ])
        #expect(ClientPolicy.evaluate(peer: 400, using: processes) != .allowed)
    }

    @Test("Claude's disclaimer started from a terminal is refused")
    func disclaimerFromTerminal() {
        let processes = FakeProcesses([
            50: P(parent: 1, started: 500, name: "Terminal"),
            60: P(parent: 50, started: 600, name: "zsh"),
            200: P(parent: 60, started: 2_000, name: "disclaimer"),
            300: P(parent: 200, started: 3_000, name: "bridge"),
        ])
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) != .allowed)
    }

    @Test("A bridge started by Claude without its disclaimer is refused")
    func noDisclaimer() {
        let processes = FakeProcesses([
            100: P(parent: 1, started: 1_000, name: "Claude Desktop"),
            300: P(parent: 100, started: 3_000, name: "bridge"),
        ])
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) != .allowed)
    }

    @Test("Claude Desktop started by anything but launchd is refused")
    func claudeNotFromLaunchd() {
        let processes = claudeDesktop()
        processes.table[90] = P(parent: 1, started: 900, name: "zsh")
        processes.table[100] = P(parent: 90, started: 1_000, name: "Claude Desktop")
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) != .allowed)
    }

    @Test("An ancestor that started after its child holds a reused id")
    func reusedID() {
        let processes = claudeDesktop()
        processes.table[200] = P(parent: 100, started: 4_000, name: "disclaimer")
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) != .allowed)
    }

    @Test("An ancestor replaced while being checked is refused")
    func replacedDuringCheck() {
        let processes = claudeDesktop()
        processes.laterStartTimes[100] = 1_500
        #expect(ClientPolicy.evaluate(peer: 300, using: processes) != .allowed)
    }

    @Test("A bridge that has already exited is refused")
    func peerGone() {
        #expect(ClientPolicy.evaluate(peer: 999, using: claudeDesktop()) != .allowed)
    }

    @Test("Every requirement in the policy compiles", arguments: ClientPolicy.steps.map(\.name))
    func compiles(_ name: String) throws {
        let step = try #require(ClientPolicy.steps.first { $0.name == name })
        #expect(ClientPolicy.compiled(step) != nil)
    }

    /// The real inspector, on real processes: whatever started this test
    /// runner, it is not Claude Desktop's disclaimer directly.
    @Test("The test runner itself is refused")
    func realProcessRefused() {
        #expect(ClientPolicy.evaluate(peer: getpid(), using: SystemProcessInspector()) != .allowed)
    }
}
