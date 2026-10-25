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
                                          calendars are visible. Exits non-zero if
                                          anything is wrong.
          apple-calendar-mcp --version    Print the version.

        Calendar access is granted from the AppleCalendarMCP window, not from here.

        Helper agent (only from inside the helper .app bundle):
          --register-agent                Register the launch agent with launchd.
          --unregister-agent              Remove it.
          --agent-status                  Report its registration state.

        Only Claude Desktop may use the calendar. That is compiled in, not a
        setting: see SECURITY.md.
        """)
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
    let passed = await runSelfTest()
    exit(passed ? 0 : 1)
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
