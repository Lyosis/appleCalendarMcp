import AppleCalendarIPC
import Foundation
import XPC
import os

/// Pumps MCP messages between the client's pipes and the helper agent.
///
/// The bridge deliberately understands nothing about MCP: it moves lines. That
/// is what lets it stay free of any privacy permission of its own — the helper
/// holds the calendar access, and this process only carries bytes to it.
func runBridge() async {
    let queue = DispatchQueue(label: machServiceName + ".bridge", attributes: .concurrent)
    let output = OutputWriter()

    let connection = xpc_connection_create_mach_service(machServiceName, queue, 0)
    xpc_connection_set_event_handler(connection) { event in
        guard xpc_get_type(event) == XPC_TYPE_ERROR else { return }
        log("cannot reach the helper — check `apple-calendar-mcp --agent-status`")
    }
    xpc_connection_resume(connection)

    let peer = XPCBox(connection)
    let pending = PendingReplies()

    do {
        for try await line in FileHandle.standardInput.bytes.lines {
            let message = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { continue }

            let request = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_string(request, IPCKey.request, message)

            // Asynchronous so a slow calendar query cannot stall the messages
            // queued behind it; JSON-RPC matches replies by id, not by order.
            pending.enter()
            xpc_connection_send_message_with_reply(peer.value, request, queue) { reply in
                defer { pending.leave() }
                guard xpc_get_type(reply) == XPC_TYPE_DICTIONARY else {
                    log("the helper did not reply")
                    return
                }
                guard let raw = xpc_dictionary_get_string(reply, IPCKey.response),
                      let response = String(validatingCString: raw)
                else {
                    return  // A notification: nothing to write back.
                }
                output.send(response)
            }
        }
    } catch {
        log("stdin ended with an error: \(error)")
    }

    // stdin is closed, but replies may still be in flight. Leaving now would
    // drop them, which looks to the client like a request that never returned.
    await pending.drain()
}

/// Counts replies still owed by the helper, so the bridge can outlive stdin
/// just long enough to deliver them.
final class PendingReplies: Sendable {
    // Not Mutex: that needs macOS 15, above this project's floor.
    private let state = OSAllocatedUnfairLock(initialState: 0)

    func enter() { state.withLock { $0 += 1 } }
    func leave() { state.withLock { $0 -= 1 } }

    /// Waits for every outstanding reply, giving up after a bounded delay so a
    /// helper that never answers cannot keep the bridge alive forever.
    func drain(timeout: Duration = .seconds(10)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while state.withLock({ $0 }) > 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let stranded = state.withLock { $0 }
        if stranded > 0 {
            log("gave up waiting for \(stranded) reply(ies) from the helper")
        }
    }
}

/// Serialises writes to stdout across the reply callbacks, which arrive on a
/// concurrent queue and would otherwise interleave mid-line.
struct OutputWriter: Sendable {
    private let queue = DispatchQueue(label: machServiceName + ".bridge.stdout")

    func send(_ line: String) {
        queue.async {
            var data = Data(line.utf8)
            data.append(0x0A)
            try? FileHandle.standardOutput.write(contentsOf: data)
        }
    }
}
