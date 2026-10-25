import AppleCalendarSetup
import Darwin

/// The real processes, as the kernel and the code signing services see them.
struct SystemProcessInspector: ProcessInspector {
    func parent(of pid: pid_t) -> pid_t? {
        Ancestry.parent(of: pid)
    }

    func startTime(of pid: pid_t) -> UInt64? {
        Ancestry.startTime(of: pid)
    }

    func satisfies(_ pid: pid_t, _ step: ClientPolicy.Step) -> Bool {
        guard let requirement = ClientPolicy.compiled(step) else { return false }
        return Ancestry.satisfies(pid: pid, requirement: requirement)
    }
}
