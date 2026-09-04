import Foundation
import os

/// The Mach service the helper agent advertises and the bridge connects to.
///
/// This must stay identical to the `MachServices` key in the launch agent's
/// property list; the two are a single contract expressed in two places.
public let machServiceName = "com.wilfrid.B.apple-calendar-mcp.agent"

/// Keys of the XPC dictionary carrying one MCP message each way.
public enum IPCKey {
    /// One JSON-RPC message, exactly as the MCP client wrote it.
    public static let request = "request"
    /// The JSON-RPC reply. Absent when the request was a notification.
    public static let response = "response"
}

private let logger = Logger(subsystem: "com.wilfrid.B.apple-calendar-mcp", category: "mcp")

/// Diagnostics channel.
///
/// Goes to the unified log as well as stderr: launchd discards a job's stderr,
/// so a helper that only wrote there would refuse connections for reasons
/// nobody could ever read. Recover them with
///
///     log show --last 5m --predicate 'subsystem == "com.wilfrid.B.apple-calendar-mcp"'
///
/// Never stdout: on the bridge side that is the MCP protocol stream, and one
/// stray line there breaks the client's parser.
public func log(_ message: String) {
    // Marked public because these are our own diagnostics — process paths and
    // refusal reasons, never calendar content, which must stay out of the log.
    logger.notice("\(message, privacy: .public)")
    let line = "[apple-calendar-mcp] \(message)\n"
    try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
}

/// Carries an XPC object across a concurrency boundary.
///
/// XPC objects are reference counted and documented as safe to use from more
/// than one queue, but they carry no `Sendable` conformance. This box asserts
/// exactly that and nothing else — it is not a licence to box other types.
public struct XPCBox<Value>: @unchecked Sendable {
    public let value: Value
    public init(_ value: Value) { self.value = value }
}
