import Foundation

let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--version") {
    print(serverVersion)
    exit(0)
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
        apple-calendar-mcp \(serverVersion)
        An MCP server for the Calendar app on macOS, iCloud calendars included.

        Usage:
          apple-calendar-mcp              Serve MCP over stdio (how a client runs it).
          apple-calendar-mcp --selftest   Report identity, permission state and visible
                                          calendars. Exits non-zero if anything is wrong.
          apple-calendar-mcp --request    With --selftest, ask for calendar access,
                                          showing the system prompt if needed.
          apple-calendar-mcp --version    Print the version.

        Helper agent (only from inside the helper .app bundle):
          --register-agent                Register the launch agent with launchd.
          --unregister-agent              Remove it.
          --agent-status                  Report its registration state.
        """)
    exit(0)
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

await Server().run()
