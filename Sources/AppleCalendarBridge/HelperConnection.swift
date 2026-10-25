import AppleCalendarIPC
import Foundation
import XPC
import os

/// The connection to the helper, replaced after any error.
///
/// Measured on 2026-10-25: when the helper is unregistered — which every
/// reinstall does — a connection receives `XPC_ERROR_CONNECTION_INVALID` and
/// stays invalid for good, even after the helper is registered again, while a
/// new connection to the same name works at once. Holding one connection for
/// the bridge's whole life therefore left it answering nothing until the
/// client restarted it.
///
/// An unregistration first shows up as *interrupted*, though — the same error
/// a helper that merely exited produces — and *invalid* only arrives with the
/// next message, which is then lost. So the connection is dropped on either:
/// a new one worked in every case measured, after a restart and after a
/// re-registration alike, and costs one connection to open.
///
/// Reconnecting is lazy — the next message opens the new connection — so a
/// helper that stays away costs nothing but an error per message.
final class HelperConnection: Sendable {
    private let queue: DispatchQueue
    private let state = OSAllocatedUnfairLock<XPCBox<xpc_connection_t>?>(initialState: nil)

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// The connection to send on, opened if there is none.
    func current() -> xpc_connection_t {
        state.withLock { held in
            if let held { return held }
            let opened = XPCBox(open())
            held = opened
            return opened
        }.value
    }

    /// Forgets `connection` after an error, so the next message opens another.
    /// True when this call dropped it, false when it was already gone.
    @discardableResult
    func noteFailure(_ error: xpc_object_t, on connection: xpc_connection_t) -> Bool {
        guard xpc_get_type(error) == XPC_TYPE_ERROR else { return false }
        let failed = XPCBox(connection)
        let dropped = state.withLock { held in
            // Only if it is still the one held: a reply arriving late from an
            // older connection must not throw away a newer, working one.
            guard held?.value === failed.value else { return false }
            held = nil
            return true
        }
        // Closed outside the lock. Cancelling delivers one more error to this
        // connection's handler, which lands here and finds it already gone.
        if dropped {
            xpc_connection_cancel(connection)
        }
        return dropped
    }

    private func open() -> xpc_connection_t {
        let connection = xpc_connection_create_mach_service(machServiceName, queue, 0)
        let box = XPCBox(connection)
        xpc_connection_set_event_handler(connection) { [weak self] event in
            guard xpc_get_type(event) == XPC_TYPE_ERROR,
                  self?.noteFailure(event, on: box.value) == true
            else {
                return  // Not an error, or the echo of our own cancel.
            }
            let reason = xpc_dictionary_get_string(event, XPC_ERROR_KEY_DESCRIPTION)
                .map { String(cString: $0) } ?? "unknown error"
            log("lost the helper (\(reason)) — the next message reconnects")
        }
        xpc_connection_resume(connection)
        return connection
    }
}
