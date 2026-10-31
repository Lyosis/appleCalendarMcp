import Darwin
import Foundation

/// Starts a program as its own responsible process, the way Claude's
/// `disclaimer` starts MCP servers.
///
/// macOS checks a privacy permission against the responsible process, not
/// against the process asking. Run from a terminal, `--selftest` reported the
/// terminal's calendar permission: measured on 2026-10-31, `notDetermined` from
/// a shell while the agent held `fullAccess`. Started disclaimed, it is checked
/// against this bundle's own grant — the one the agent uses.
///
/// `responsibility_spawnattrs_setdisclaim` is in no public header; Claude,
/// Chromium and others rely on it. It is looked up when needed rather than
/// linked, so a macOS release without it leaves the selftest unable to measure
/// the agent's permission, and saying so, instead of unable to launch at all.
enum DisclaimedSpawn {

    /// The argument that marks the disclaimed run, so it never starts another.
    static let marker = "--disclaimed"

    enum Outcome: Equatable {
        case exited(Int32)
        case killed(signal: Int32)
        case notStarted(String)
    }

    private typealias SetDisclaim = @convention(c) (
        UnsafeMutablePointer<posix_spawnattr_t?>, Int32
    ) -> Int32

    private static func setDisclaim() -> SetDisclaim? {
        // RTLD_DEFAULT: every image loaded in the process.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "responsibility_spawnattrs_setdisclaim")
        else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetDisclaim.self)
    }

    static var isAvailable: Bool {
        setDisclaim() != nil
    }

    /// Runs `path` with `arguments`, disclaimed, sharing this process's
    /// standard streams and environment, and waits for it to end.
    static func run(_ path: String, arguments: [String]) -> Outcome {
        guard let setDisclaim = setDisclaim() else {
            return .notStarted("this macOS has no responsibility_spawnattrs_setdisclaim")
        }
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            return .notStarted("posix_spawnattr_init failed")
        }
        defer { posix_spawnattr_destroy(&attributes) }
        let disclaimed = setDisclaim(&attributes, 1)
        guard disclaimed == 0 else {
            return .notStarted("responsibility_spawnattrs_setdisclaim failed: \(String(cString: strerror(disclaimed)))")
        }

        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + environment).forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, path, nil, &attributes, argv, environment)
        guard spawned == 0 else {
            return .notStarted("posix_spawn failed: \(String(cString: strerror(spawned)))")
        }

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            guard errno == EINTR else {
                return .notStarted("waitpid failed: \(String(cString: strerror(errno)))")
            }
        }
        // WIFEXITED, WEXITSTATUS and WTERMSIG are macros Swift does not import.
        let signal = status & 0x7f
        return signal == 0 ? .exited((status >> 8) & 0xff) : .killed(signal: signal)
    }
}
