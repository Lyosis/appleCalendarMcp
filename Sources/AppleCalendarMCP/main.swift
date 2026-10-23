import AppleCalendarIPC
import AppleCalendarSetup
import Foundation

let argumentList = Array(CommandLine.arguments.dropFirst())
let arguments = Set(argumentList)

/// The value following a flag, for the options that take one.
func value(after flag: String) -> String? {
    guard let index = argumentList.firstIndex(of: flag),
          argumentList.index(after: index) < argumentList.endIndex
    else {
        return nil
    }
    return argumentList[argumentList.index(after: index)]
}

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

        Which client may use the calendar:
          --pin-client-auto               Pin whichever application launched this
                                          command. Run it from your MCP client.
          --pin-client <path>             Pin a specific application bundle.
          --show-pin                      Print the pinned client, if any.
          --unpin-client                  Remove the pin. Any process that runs the
                                          bridge is then accepted.
        """)
    exit(0)
}

if arguments.contains("--show-pin") {
    exit(PinCommands.show() ? 0 : 1)
}

if arguments.contains("--pin-client-auto") {
    exit(PinCommands.pinLaunchingApplication() ? 0 : 1)
}

if arguments.contains("--pin-client") {
    guard let path = value(after: "--pin-client") else {
        print("  FAILED          --pin-client needs the path to an application bundle.")
        exit(1)
    }
    exit(PinCommands.pin(path: path) ? 0 : 1)
}

if arguments.contains("--unpin-client") {
    exit(PinCommands.unpin() ? 0 : 1)
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
