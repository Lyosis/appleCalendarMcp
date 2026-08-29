import Foundation

/// Writes newline-delimited JSON to stdout, one whole message at a time.
///
/// stdout is the protocol channel: nothing but JSON-RPC may ever be written
/// there, or the client's parser breaks. Everything else goes to stderr.
actor StdoutWriter {
    private let handle = FileHandle.standardOutput

    func send(_ message: JSONValue) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard var data = try? encoder.encode(message) else {
            log("dropped a message that could not be encoded")
            return
        }
        data.append(0x0A)  // MCP framing: one message per line.
        do {
            try handle.write(contentsOf: data)
        } catch {
            log("stdout write failed: \(error)")
        }
    }
}

/// Diagnostics channel. Never stdout — see `StdoutWriter`.
func log(_ message: String) {
    let line = "[apple-calendar-mcp] \(message)\n"
    try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
}
