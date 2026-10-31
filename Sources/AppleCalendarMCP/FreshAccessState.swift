import AppleCalendarSetup
import Foundation
import os

/// The calendar permission as a new process sees it.
///
/// A running process never sees a change made elsewhere, either way. Measured
/// on 2026-10-31: the agent kept reading `notDetermined` a minute after access
/// was granted from the window, while a fresh process read `fullAccess`; and
/// after the grant was withdrawn, an agent started before kept listing
/// calendars and reading events. So every call asks a child — which macOS
/// attributes to this bundle, the agent being its own responsible process —
/// and goes by its answer, not by this process's.
enum FreshAccessState {

    /// The argument that runs this executable as that child.
    static let argument = "--access-state"

    /// How long the agent must have run before it trusts that it is stale. A
    /// younger one already started after the grant, so disagreeing with its
    /// child means the two are attributed differently, and restarting again
    /// would not help.
    static let settleTime: Duration = .seconds(10)

    enum Outcome: Equatable {
        /// Both can read: go ahead.
        case proceed
        /// A new process cannot read, whatever this one believes: refuse, and
        /// say why in the terms of the state it sees.
        case refuse(AccessState)
        /// No answer from the child. Refused rather than trusted: a guarantee
        /// that lapses silently whenever the check cannot run is no guarantee.
        case unconfirmed
        /// Granted since this process started: restart to pick it up.
        case restart
        /// A process that already started after the grant still cannot read.
        case disagreement
    }

    static func decide(inProcess state: AccessState, fresh: AccessState?, uptime: Duration) -> Outcome {
        guard let fresh else { return .unconfirmed }
        guard fresh.canRead else { return .refuse(fresh) }
        if state.canRead { return .proceed }
        return uptime >= settleTime ? .restart : .disagreement
    }

    /// What the child printed, or nil for anything else.
    static func parse(_ output: String) -> AccessState? {
        AccessState(rawValue: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Runs the child and reads its answer. Nil — and the call refused — if it
    /// could not be run, failed, or took longer than `timeout`, in which case
    /// it is left to end alone:
    /// killing it by pid afterwards could hit a process that reused the number.
    static func read(timeout: Duration = .seconds(5)) async -> AccessState? {
        guard let path = Bundle.main.executablePath else { return nil }
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = [argument]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let reader = output.fileHandleForReading

        return await withCheckedContinuation { continuation in
            // Whichever comes first, the child ending or the timeout, answers.
            let answered = OSAllocatedUnfairLock(initialState: false)
            let answer: @Sendable (AccessState?) -> Void = { state in
                let first = answered.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: state) }
            }

            process.terminationHandler = { child in
                // The answer is one word, far below the pipe's buffer, so the
                // child never blocks writing it before this reads.
                let data = (try? reader.readToEnd()) ?? Data()
                let succeeded = child.terminationReason == .exit && child.terminationStatus == 0
                answer(succeeded ? parse(String(decoding: data, as: UTF8.self)) : nil)
            }
            do {
                try process.run()
            } catch {
                answer(nil)
                return
            }
            Task {
                try? await Task.sleep(for: timeout)
                answer(nil)
            }
        }
    }
}
