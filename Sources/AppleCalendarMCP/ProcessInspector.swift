import Darwin

/// What `ClientPolicy` needs to know about running processes.
///
/// A protocol so the policy can be exercised on made-up process trees: the
/// cases worth testing — an impostor in the middle, a reused id — cannot be
/// arranged on demand with real processes.
protocol ProcessInspector {
    func parent(of pid: pid_t) -> pid_t?
    /// Microseconds since 1970, or nil once the process has gone.
    func startTime(of pid: pid_t) -> UInt64?
    func satisfies(_ pid: pid_t, _ step: ClientPolicy.Step) -> Bool
    /// The arguments the process was started with, `argv[0]` included.
    func arguments(of pid: pid_t) -> [String]?
    /// The program the process is running now, symbolic links resolved.
    func executablePath(of pid: pid_t) -> String?
    /// `path` with symbolic links resolved, or nil if it does not exist.
    func resolvedPath(_ path: String) -> String?
}
