import AppleCalendarSetup
import Darwin
import EventKit
import Foundation

/// Measures what the process actually is, what the system actually grants it,
/// and what it can actually read — in that order, with the checks that would
/// invalidate the measurement reported alongside the results.
///
/// Every section can fail. A run that prints only good news is a run where
/// every one of those checks had the opportunity to say otherwise.
func runSelfTest(requestAccess: Bool) async -> Bool {
    var passed = true

    func check(_ label: String, _ value: String, ok: Bool?) {
        let mark = switch ok {
        case true: "ok  "
        case false: "FAIL"
        case nil: "    "
        }
        print("  [\(mark)] \(label.padding(toLength: 26, withPad: " ", startingAt: 0)) \(value)")
        if ok == false { passed = false }
    }

    print("apple-calendar-mcp \(serverVersion) — selftest")
    print("")

    // MARK: Identity — who the system thinks is asking

    print("identity")
    let executablePath = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "unknown"
    check("executable", executablePath, ok: nil)
    check("bundle identifier", Bundle.main.bundleIdentifier ?? "none (bare CLI)", ok: nil)
    // Which bundle the runtime resolves decides where SMAppService looks for
    // the agent plist, and which identity TCC records a decision against.
    check("bundle path", Bundle.main.bundlePath, ok: nil)
    check("parent process", parentProcessDescription(), ok: nil)

    // The usage description has to be readable at runtime or the system has no
    // text to put in the permission prompt. This is what proves -sectcreate
    // worked, rather than assuming it did.
    let usageDescription = Bundle.main.object(
        forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription"
    ) as? String
    check(
        "usage description",
        usageDescription.map { "\"\($0.prefix(48))…\"" } ?? "ABSENT — prompt has no text",
        ok: usageDescription != nil
    )

    // Version drift between the constant and the embedded plist.
    let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    check(
        "plist version matches",
        "\(bundleVersion ?? "absent") vs \(serverVersion)",
        ok: bundleVersion == nil ? nil : bundleVersion == serverVersion
    )
    print("")

    // MARK: Authorization — recorded status, before and after

    print("authorization")
    let stateBefore = CalendarPermission.current()
    check("status before", stateBefore.rawValue, ok: nil)

    let access = CalendarAccess()
    if requestAccess, stateBefore == .notDetermined {
        print("  ...  requesting full access (a prompt may appear)")
        let outcome = await access.requestAccess()
        check("request returned", outcome.granted ? "granted" : "refused", ok: nil)
        if let error = outcome.error {
            check("request error", error, ok: false)
        }
        await access.reset()
    } else if stateBefore == .notDetermined {
        print("  ...  no decision recorded; re-run with --request to prompt")
    }

    let stateAfter = CalendarPermission.current()
    check("status after", stateAfter.rawValue, ok: stateAfter.canRead)
    check("meaning", stateAfter.explanation, ok: nil)
    print("")

    // MARK: Data — does the grant actually yield anything

    print("data")
    guard stateAfter.canRead else {
        check("calendars readable", "skipped — no read access", ok: false)
        return finish(passed: false)
    }

    let calendars = await access.calendars()
    // Full access with zero calendars means something is wrong that the status
    // alone would not have revealed.
    check(
        "calendars visible",
        "\(calendars.count)",
        ok: !calendars.isEmpty
    )
    for calendar in calendars.prefix(20) {
        let flags = calendar.isWritable ? "writable" : "read-only"
        print("         \(calendar.source) / \(calendar.title)  (\(calendar.sourceType), \(flags))")
    }
    if calendars.count > 20 {
        print("         … and \(calendars.count - 20) more")
    }

    // A test whose conditions changed while it ran proves nothing.
    let stateAtEnd = CalendarPermission.current()
    check(
        "status unchanged during run",
        stateAtEnd == stateAfter ? "\(stateAtEnd.rawValue)" : "CHANGED: \(stateAfter.rawValue) -> \(stateAtEnd.rawValue)",
        ok: stateAtEnd == stateAfter
    )

    return finish(passed: passed)

    func finish(passed: Bool) -> Bool {
        print("")
        print(passed ? "selftest passed" : "selftest FAILED")
        return passed
    }
}

/// The process that launched this one — the crux of how macOS attributes the
/// calendar permission for a tool with no bundle of its own.
private func parentProcessDescription() -> String {
    let parent = getppid()
    var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
    let length = proc_pidpath(parent, &buffer, UInt32(buffer.count))
    guard length > 0 else { return "\(parent) (path unavailable)" }
    return "\(parent) \(String(decoding: buffer.prefix(Int(length)), as: UTF8.self))"
}
