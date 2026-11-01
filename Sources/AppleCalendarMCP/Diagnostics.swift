import AppleCalendarIPC
import AppleCalendarSetup
import Darwin
import EventKit
import Foundation
import Security

/// Measures what the process actually is, what the system actually grants it,
/// and what it can actually read — in that order, with the checks that would
/// invalidate the measurement reported alongside the results.
///
/// Every section can fail. A run that prints only good news is a run where
/// every one of those checks had the opportunity to say otherwise.
///
/// Anything can run this with the calendar grant in hand (see main.swift), so
/// it never asks for access and never prints a calendar's name: counts only.
///
/// The permission is only the agent's when `attribution` is `.own`. Otherwise
/// it belongs to whatever started this, and is reported as such, not judged.
func runSelfTest(attribution: SelfTestAttribution) async -> Bool {
    var passed = true

    func check(_ label: String, _ value: String, ok: Bool?) {
        let mark = switch ok {
        case true: "ok  "
        case false: "FAIL"
        case nil: "    "
        }
        print("  [\(mark)] \(label.padding(toLength: 28, withPad: " ", startingAt: 0)) \(value)")
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
    switch attribution {
    case .own:
        check("permission measured for", "this bundle (run disclaimed)", ok: true)
    case .caller(let reason):
        check("permission measured for", "THE CALLER, not the agent — \(reason)", ok: nil)
    }

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

    // The helper accepts only peers carrying this exact signing identifier.
    // If the bridge beside it was signed under another one, every connection
    // is refused, and the log is the only place that would say why.
    let bridge = Bundle.main.bundleURL.appending(path: "Contents/MacOS/apple-calendar-mcp-bridge")
    if FileManager.default.fileExists(atPath: bridge.path(percentEncoded: false)) {
        let found = signingIdentifier(ofExecutableAt: bridge)
        check(
            "bridge identifier",
            "\(found ?? "unreadable") vs \(bridgeSigningIdentifier)",
            ok: found == bridgeSigningIdentifier
        )
        // The bridge carries its own plist, a separate file in the sources:
        // nothing at run time reads its version, so drift would ship unseen.
        let bridgeVersion = embeddedVersion(ofExecutableAt: bridge)
        check(
            "bridge version matches",
            "\(bridgeVersion ?? "unreadable") vs \(serverVersion)",
            ok: bridgeVersion == serverVersion
        )
    } else {
        check("bridge identifier", "no bridge beside this executable", ok: nil)
    }
    print("")

    // MARK: Client — does the installed client still match the compiled policy

    // A signing change on the client's side would turn every connection into
    // a refusal. This says so before anyone has to read the log to find out.
    print("client")
    for step in ClientPolicy.steps {
        guard FileManager.default.fileExists(atPath: step.installedPath) else {
            check(step.name, "not found at \(step.installedPath)", ok: nil)
            continue
        }
        let matches = staticCode(at: step.installedPath, satisfies: step)
        check(
            step.name,
            matches ? "signature matches the policy" : "SIGNATURE DOES NOT MATCH — connections will be refused",
            ok: matches
        )
    }
    print("")

    // MARK: Authorization — the recorded status

    print("authorization")
    let state = CalendarPermission.current()
    guard attribution == .own else {
        // Judging the caller's permission would report a fault that is not
        // there — or hide one that is.
        check("status", "\(state.rawValue) — the caller's, not the agent's", ok: nil)
        print("  ...  ask Claude to run check_access, or open AppleCalendarMCP.app, for the agent's")
        print("")
        print("selftest INCOMPLETE — the agent's permission could not be measured from here")
        return false
    }
    check("status", state.rawValue, ok: state.canRead)
    check("meaning", state.explanation, ok: nil)
    if state == .notDetermined {
        print("  ...  no decision recorded; open AppleCalendarMCP.app to grant access")
    }
    print("")

    // MARK: Data — does the grant actually yield anything

    print("data")
    guard state.canRead else {
        check("calendars readable", "skipped — no read access", ok: false)
        return finish(passed: false)
    }

    let calendars = await CalendarAccess().calendars()
    // Full access with zero calendars means something is wrong that the status
    // alone would not have revealed.
    check(
        "calendars visible",
        "\(calendars.count)",
        ok: !calendars.isEmpty
    )
    let byKind = Dictionary(grouping: calendars, by: \.sourceType)
    for (kind, members) in byKind.sorted(by: { $0.key < $1.key }) {
        let writable = members.filter(\.isWritable).count
        print("         \(kind): \(members.count), \(writable) writable")
    }

    // A test whose conditions changed while it ran proves nothing.
    let stateAtEnd = CalendarPermission.current()
    check(
        "status unchanged during run",
        stateAtEnd == state ? "\(stateAtEnd.rawValue)" : "CHANGED: \(state.rawValue) -> \(stateAtEnd.rawValue)",
        ok: stateAtEnd == state
    )

    return finish(passed: passed)

    func finish(passed: Bool) -> Bool {
        print("")
        print(passed ? "selftest passed" : "selftest FAILED")
        return passed
    }
}

/// The signing identifier recorded in an executable's code signature.
/// The version in the plist an executable carries in its `__info_plist`
/// section. Nil for one without.
private func embeddedVersion(ofExecutableAt url: URL) -> String? {
    let info = CFBundleCopyInfoDictionaryForURL(url as CFURL) as? [String: Any]
    return info?["CFBundleShortVersionString"] as? String
}

private func signingIdentifier(ofExecutableAt url: URL) -> String? {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
          let staticCode
    else {
        return nil
    }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information
          ) == errSecSuccess,
          let information = information as? [String: Any]
    else {
        return nil
    }
    return information[kSecCodeInfoIdentifier as String] as? String
}

/// Whether the program on disk satisfies a policy step's requirement.
private func staticCode(at path: String, satisfies step: ClientPolicy.Step) -> Bool {
    var staticCode: SecStaticCode?
    guard let requirement = ClientPolicy.compiled(step),
          SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode)
            == errSecSuccess,
          let staticCode
    else {
        return false
    }
    return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
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
