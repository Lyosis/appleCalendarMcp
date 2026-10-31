import AppleCalendarIPC
import AppleCalendarSetup
import Foundation

let argumentList = Array(CommandLine.arguments.dropFirst())
let arguments = Set(argumentList)

if arguments.contains("--version") {
    print(serverVersion)
    exit(0)
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
        apple-calendar-mcp \(serverVersion)
        An MCP server for the Calendar app on macOS, iCloud calendars included.

        Usage:
          apple-calendar-mcp              Serve MCP over XPC. This is how launchd starts
                                          the agent; MCP clients run the bridge instead.
          apple-calendar-mcp --selftest   Report identity, permission state and how many
                                          calendars are visible, measured for this
                                          bundle — the agent — not for the terminal
                                          running it. Exits non-zero if anything is
                                          wrong or could not be measured.
          apple-calendar-mcp --version    Print the version.

        Calendar access is granted from the AppleCalendarMCP window, not from here.
        The agent checks it afresh on every call, so withdrawing it takes effect
        on the next one, and restarts on its own to pick up a grant made while
        it runs.

        Internal:
          --access-state                  Print the permission state, as a new
                                          process sees it. The agent runs this.

        Helper agent (only from inside the helper .app bundle):
          --register-agent                Register the launch agent with launchd.
          --unregister-agent              Remove it.
          --agent-status                  Report its registration state.

        Only Claude Desktop may use the calendar. That is compiled in, not a
        setting: see SECURITY.md.
        """)
    exit(0)
}

// The child the agent runs to see a grant made since it started: a new process
// reads the permission afresh, a running one never does. The status only —
// what --selftest shows anyway — never events, and it never asks.
if arguments.contains(FreshAccessState.argument) {
    print(CalendarPermission.current().rawValue)
    exit(0)
}

if arguments.contains("--register-agent") {
    exit(AgentCommands.register() ? 0 : 1)
}

if arguments.contains("--unregister-agent") {
    exit(AgentCommands.unregister() ? 0 : 1)
}

if arguments.contains("--agent-status") {
    exit(AgentCommands.status() ? 0 : 1)
}

if arguments.contains("--selftest") {
    if arguments.contains(DisclaimedSpawn.marker) {
        exit(await runSelfTest(attribution: .ofDisclaimedRun()) ? 0 : 1)
    }
    // Run again as its own responsible process, so the permission measured is
    // this bundle's — the agent's — and not the terminal's. See DisclaimedSpawn.
    var reason = "the path of this executable is unknown"
    if let path = Bundle.main.executablePath {
        switch DisclaimedSpawn.run(path, arguments: ["--selftest", DisclaimedSpawn.marker]) {
        case .exited(let status):
            exit(status)
        case .killed(let signal):
            print("selftest FAILED — the disclaimed run was killed by signal \(signal)")
            exit(1)
        case .notStarted(let why):
            reason = why
        }
    }
    exit(await runSelfTest(attribution: .caller(reason)) ? 0 : 1)
}

// launchd passes none (see the launch agent plist), so anything left over is a
// mistake — or an option that no longer exists — and must not start a service.
guard argumentList.isEmpty else {
    print("  FAILED          unknown option: \(argumentList.joined(separator: " ")). See --help.")
    exit(2)
}

// No arguments: this is how launchd starts the agent.
//
// This executable holds the calendar grant in its own name, and any process can
// start it as its own responsible process — Claude's `disclaimer` helper does
// exactly that. So the XPC service, with its checks on the peer, is the only
// path here that reads or changes events. Nothing else may be added that does.
runXPCService(server: Server())
