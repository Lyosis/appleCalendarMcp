import AppleCalendarIPC
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
          apple-calendar-mcp --serve-stdio
                                          Serve MCP over stdin/stdout. Development only —
                                          a client that spawns this is never granted
                                          calendar access. See the README.
          apple-calendar-mcp --selftest   Report identity, permission state and visible
                                          calendars. Exits non-zero if anything is wrong.
          apple-calendar-mcp --request    With --selftest, ask for calendar access,
                                          showing the system prompt if needed.
          apple-calendar-mcp --version    Print the version.

        Helper agent (only from inside the helper .app bundle):
          --register-agent                Register the launch agent with launchd.
          --unregister-agent              Remove it.
          --agent-status                  Report its registration state.

        Which client may use the calendar:
          --pin-client-auto               Pin whichever application launched this
                                          command. Run it from your MCP client.
          --pin-client <path>             Pin a specific application bundle.
          --show-pin                      Print the pinned client, if any.
          --unpin-client                  Remove the pin. Any client signed by the
                                          same team as this helper is then accepted.
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
    exit(ServiceControl.register() ? 0 : 1)
}

if arguments.contains("--unregister-agent") {
    exit(ServiceControl.unregister() ? 0 : 1)
}

if arguments.contains("--agent-status") {
    exit(ServiceControl.status() ? 0 : 1)
}

if arguments.contains("--selftest") {
    let passed = await runSelfTest(requestAccess: arguments.contains("--request"))
    exit(passed ? 0 : 1)
}

if arguments.contains("--serve-stdio") {
    await runStdioService(server: Server())
    exit(0)
}

// No arguments: this is how launchd starts the agent.
runXPCService(server: Server())
