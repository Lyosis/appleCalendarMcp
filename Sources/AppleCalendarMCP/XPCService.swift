import AppleCalendarIPC
import AppleCalendarSetup
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
        if xpc_get_type(event) == XPC_TYPE_ERROR {
            // Measured: a process that is not the launchd job owning this name
            // gets Connection invalid straight away and would otherwise idle
            // forever, serving nothing. Say so and leave; launchd starts the
            // real job again on the next message.
            let reason = xpc_dictionary_get_string(event, XPC_ERROR_KEY_DESCRIPTION)
                .map { String(cString: $0) } ?? "unknown error"
            log("cannot listen on \(machServiceName): \(reason)")
            exit(EXIT_FAILURE)
        }
        guard xpc_get_type(event) == XPC_TYPE_CONNECTION else { return }
        accept(unsafeBitCast(event, to: xpc_connection_t.self), server: server)
    }

    log("listening on \(machServiceName)")
    xpc_connection_resume(listener)
    dispatchMain()
}

/// Accepts one client connection, after checking who it is.
private func accept(_ connection: xpc_connection_t, server: Server) {
    // Refuse any peer that is not our bridge: signed by the same team as this
    // helper *and* under the bridge's signing identifier. The team is taken
    // from this process, so it survives certificate rotation where a
    // hand-written requirement string would not. Passing nil here would accept
    // every binary the team has ever signed.
    let status = xpc_connection_set_peer_team_identity_requirement(connection, bridgeSigningIdentifier)
    guard status == 0 else {
        log("refused a connection: could not require the peer's team identity (\(status))")
        xpc_connection_cancel(connection)
        return
    }

    // The team check says the peer is our bridge. It says nothing about who
    // started it — and the bridge is a public binary anyone can run. So also
    // require that the pinned client is somewhere above it.
    guard clientIsAuthorised(connection) else {
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

/// Whether the pinned client is an ancestor of the connecting process.
///
/// With nothing pinned this returns true and says so: refusing every client on
/// a fresh install would be a puzzle, not a protection. The warning is the
/// honest half of that trade.
private func clientIsAuthorised(_ connection: xpc_connection_t) -> Bool {
    guard let requirement = ClientPin.compiled() else {
        log(
            """
            no client is pinned: any process on this Mac that runs the bridge \
            can read and change the calendar through this helper. \
            Run `apple-calendar-mcp --pin-client-auto` from your MCP client.
            """)
        return true
    }

    let pid = xpc_connection_get_pid(connection)
    let chain = Ancestry.chain(from: pid)
    guard chain.contains(where: { Ancestry.satisfies(pid: $0, requirement: requirement) }) else {
        let names = chain.compactMap { Ancestry.path(of: $0) }.joined(separator: " <- ")
        log("refused a connection: the pinned client is not among \(names)")
        return false
    }
    return true
}
