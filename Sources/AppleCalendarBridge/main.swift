import AppleCalendarIPC
import Foundation

let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
        apple-calendar-mcp-bridge
        Forwards MCP messages from an MCP client to the apple-calendar-mcp helper agent.

        This is the command an MCP client should be configured to run. It takes no
        options: it reads JSON-RPC from stdin and writes the replies to stdout.

        If nothing works, check the helper first:
          apple-calendar-mcp --agent-status
          apple-calendar-mcp --selftest
        """)
    exit(0)
}

await runBridge()
