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
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    public static func path(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// Whether a running process satisfies a code signing requirement.
    ///
    /// Identifying by process id carries a reuse race for ancestors, which may
    /// have exited: the direct peer is safe, because an open XPC connection
    /// keeps it alive, but a grandparent is not. Stated in SECURITY.md rather
    /// than papered over.
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

    /// The application bundle a process's executable lives in, if any.
    public static func bundlePath(forExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/Contents/MacOS/") else { return nil }
        return String(path[path.startIndex..<range.lowerBound]) + ".app"
    }

    /// The outermost application above this process — the one a person launched.
    ///
    /// Used by --pin-client-auto: whoever is running us is, by construction,
    /// whoever is installing us.
    public static func launchingApplication() -> String? {
        var found: String?
        for pid in chain(from: getpid()) {
            if let path = path(of: pid), let bundle = bundlePath(forExecutable: path) {
                found = bundle  // keep going; the last one is closest to launchd
            }
        }
        return found
    }

    /// The ancestry as readable paths, for diagnostics.
    public static func summary(from pid: pid_t = getpid()) -> String {
        chain(from: pid).compactMap { path(of: $0) }.joined(separator: " <- ")
    }
}
