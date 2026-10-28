import Darwin
import Foundation
import Security

/// Walks a process's ancestors and checks them against a code requirement.
///
/// This is what stops someone simply running the bridge themselves: the peer
/// may be correctly signed and still have been started by anything at all, so
/// the question worth asking is who is above it.
public enum Ancestry {

    /// Process ids from `pid` upwards, stopping at launchd.
    public static func chain(from pid: pid_t, maximum: Int = 16) -> [pid_t] {
        var chain: [pid_t] = []
        var current = pid
        while current > 1, chain.count < maximum {
            chain.append(current)
            guard let parent = parent(of: current), parent != current else { break }
            current = parent
        }
        return chain
    }

    public static func parent(of pid: pid_t) -> pid_t? {
        processInfo(pid)?.kp_eproc.e_ppid
    }

    /// When a process started, in microseconds since 1970.
    ///
    /// A parent cannot have started after its child. A process id that reads
    /// otherwise has been reused by another process since — which is how the
    /// policy tells a live ancestor from an impostor holding its old number.
    public static func startTime(of pid: pid_t) -> UInt64? {
        guard let started = processInfo(pid)?.kp_proc.p_starttime else { return nil }
        return UInt64(started.tv_sec) * 1_000_000 + UInt64(started.tv_usec)
    }

    private static func processInfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        // A pid nobody holds still succeeds, with nothing written: size is 0.
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    public static func path(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// The arguments a process was started with, `argv[0]` included.
    ///
    /// Read from the kernel (`KERN_PROCARGS2`), not from the process: what a
    /// launcher was told to run stays readable after the program it started
    /// replaced itself with another. Nil when the kernel refuses — another
    /// user's process, or one that has gone.
    public static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }

        // Layout: argc, the executable path, padding NULs, then argc strings.
        let count = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count >= 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        func nextString() -> String? {
            guard index < size else { return nil }
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            let text = String(decoding: buffer[start..<index], as: UTF8.self)
            return text
        }
        guard nextString() != nil else { return nil }  // the executable path
        while index < size, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        for _ in 0..<count {
            guard let argument = nextString() else { return nil }
            arguments.append(argument)
            index += 1  // past the terminating NUL
        }
        return arguments
    }

    /// `path` with every symbolic link resolved, or nil if it does not exist.
    public static func resolvedPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Whether a running process satisfies a code signing requirement.
    ///
    /// Identifying by process id carries a reuse race for ancestors, which may
    /// have exited: the direct peer is safe, because an open XPC connection
    /// keeps it alive, but a grandparent is not. Callers compare start times
    /// around this check — see `ClientPolicy`.
    public static func satisfies(pid: pid_t, requirement: SecRequirement) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code
        else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    /// The ancestry as readable paths, for diagnostics.
    public static func summary(from pid: pid_t = getpid()) -> String {
        chain(from: pid).compactMap { path(of: $0) }.joined(separator: " <- ")
    }
}
