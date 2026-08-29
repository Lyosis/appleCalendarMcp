import AppleCalendarIPC
import Foundation
import XPC

/// Serves MCP over the Mach service the launch agent advertises.
///
/// This is how the helper runs in production: launchd is its parent, so it is
/// its own responsible process and holds the calendar permission in its own
/// name. Never returns.
func runXPCService(server: Server) -> Never {
    let queue = DispatchQueue(label: machServiceName + ".xpc", attributes: .concurrent)

    let listener = xpc_connection_create_mach_service(
        machServiceName,
        queue,
        UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER)
    )

    xpc_connection_set_event_handler(listener) { event in
        guard xpc_get_type(event) == XPC_TYPE_CONNECTION else { return }
        accept(unsafeBitCast(event, to: xpc_connection_t.self), server: server)
    }

    xpc_connection_resume(listener)
    log("listening on \(machServiceName)")
    dispatchMain()
}

/// Accepts one client connection, after checking who it is.
private func accept(_ connection: xpc_connection_t, server: Server) {
    // Refuse any peer not signed by the same team as this helper. Passing nil
    // means "the same team identifier as the calling process", which survives
    // certificate rotation where a hand-written requirement string would not.
    let status = xpc_connection_set_peer_team_identity_requirement(connection, nil)
    guard status == 0 else {
        log("refused a connection: could not require the peer's team identity (\(status))")
        xpc_connection_cancel(connection)
        return
    }

    let peer = XPCBox(connection)

    xpc_connection_set_event_handler(connection) { event in
        guard xpc_get_type(event) == XPC_TYPE_DICTIONARY,
              let raw = xpc_dictionary_get_string(event, IPCKey.request),
              let message = String(validatingCString: raw)
        else {
            return
        }

        let incoming = XPCBox(event)
        Task {
            guard let reply = xpc_dictionary_create_reply(incoming.value) else { return }
            // A notification produces no response, and the empty reply is what
            // releases the bridge's pending callback.
            if let response = await server.respond(to: message) {
                xpc_dictionary_set_string(reply, IPCKey.response, response)
            }
            xpc_connection_send_message(peer.value, reply)
        }
    }

    xpc_connection_resume(connection)
}
