import Darwin
@testable import AppleCalendarMCP

/// A made-up process table. Each process is "signed" by the policy step whose
/// name it carries, and by nothing else.
final class FakeProcesses: ProcessInspector {
    struct Process {
        let parent: pid_t
        let started: UInt64
        let name: String
        /// What the process was started with, as the kernel reports it.
        var arguments: [String]? = nil
        /// What it is running now.
        var executable: String? = nil
    }

    var table: [pid_t: Process]
    /// Start times returned from the second read onwards, to simulate a
    /// process replaced while it was being checked.
    var laterStartTimes: [pid_t: UInt64] = [:]
    private var reads: [pid_t: Int] = [:]

    init(_ table: [pid_t: Process]) {
        self.table = table
    }

    func parent(of pid: pid_t) -> pid_t? {
        table[pid]?.parent
    }

    func startTime(of pid: pid_t) -> UInt64? {
        reads[pid, default: 0] += 1
        if reads[pid, default: 0] > 1, let later = laterStartTimes[pid] {
            return later
        }
        return table[pid]?.started
    }

    func satisfies(_ pid: pid_t, _ step: ClientPolicy.Step) -> Bool {
        table[pid]?.name == step.name
    }

    func arguments(of pid: pid_t) -> [String]? {
        table[pid]?.arguments
    }

    func executablePath(of pid: pid_t) -> String? {
        table[pid]?.executable
    }

    /// Paths resolve to themselves, except the links listed here.
    var links: [String: String] = [:]

    func resolvedPath(_ path: String) -> String? {
        links[path] ?? path
    }
}
