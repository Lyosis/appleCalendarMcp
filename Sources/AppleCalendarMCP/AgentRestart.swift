import AppleCalendarIPC
import AppleCalendarSetup
import Foundation
import os
import XPC

/// Ends the agent once a reply has gone out, so launchd starts a new one — the
/// only way it sees a calendar grant made since it started. See
/// `FreshAccessState`.
///
/// The agent is started on demand: launchd runs it again on the next message,
/// and the bridge reconnects on its own.
enum AgentRestart {

    private struct State {
        var startedAt: ContinuousClock.Instant?
        var requested = false
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// Called once, as the agent starts serving.
    static func markStarted() {
        state.withLock { $0.startedAt = .now }
    }

    /// How long the agent has been serving; zero if it is not the agent.
    static var uptime: Duration {
        state.withLock { $0.startedAt.map { $0.duration(to: .now) } ?? .zero }
    }

    static func request() {
        state.withLock { $0.requested = true }
    }

    /// After a reply is sent: ends the process once it is on its way, if a
    /// restart was asked for.
    ///
    /// Nothing that writes can be cut short. A restart is only asked for while
    /// this process cannot read the calendar, so no call has got past the
    /// access check — and that is checked once more here.
    static func afterReply(on connection: xpc_connection_t) {
        guard state.withLock({ $0.requested }), !CalendarPermission.current().canRead else { return }
        xpc_connection_send_barrier(connection) {
            log("restarting: calendar access was granted since this agent started")
            exit(EXIT_SUCCESS)
        }
    }
}
