import AppleCalendarIPC
import Foundation

/// Serves MCP directly over stdin and stdout.
///
/// For development only. A process an MCP client spawns this way is attributed
/// to that client for privacy purposes, so it is never granted calendar access
/// — see the README. Useful to exercise the protocol layer on its own.
func runStdioService(server: Server) async {
    let stdout = StdoutWriter()
    do {
        for try await line in FileHandle.standardInput.bytes.lines {
            let message = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { continue }
            if let reply = await server.respond(to: message) {
                await stdout.send(reply)
            }
        }
    } catch {
        log("stdin ended with an error: \(error)")
    }
}

/// Writes newline-delimited JSON to stdout, one whole message at a time.
///
/// stdout is the protocol channel: nothing but JSON-RPC may ever go there.
actor StdoutWriter {
    private let handle = FileHandle.standardOutput

    func send(_ line: String) {
        var data = Data(line.utf8)
        data.append(0x0A)  // MCP framing: one message per line.
        do {
            try handle.write(contentsOf: data)
        } catch {
            log("stdout write failed: \(error)")
        }
    }
}
