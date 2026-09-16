import AppleCalendarSetup
import Foundation
import Observation

/// What the installer window shows, read from the system rather than remembered.
///
/// Every value here is a fresh reading: a checkbox that records what was done
/// would keep claiming success after someone revoked the permission in System
/// Settings. `refresh()` is called whenever the window is shown or an action
/// finishes, so what is on screen is what is true.
@MainActor
@Observable
final class SetupModel {
    private(set) var access: AccessState = .notDetermined
    private(set) var helperState: String = ""
    private(set) var helperInstalled = false
    private(set) var pinnedRequirement: String?
    private(set) var pinReadFailed = false

    /// The action in flight, so the window can disable the rest.
    private(set) var busy: String?
    private(set) var failure: String?

    /// The command an MCP client must run. Inside this bundle, so it moves with
    /// the app and cannot drift from the helper it talks to.
    var bridgePath: String {
        Bundle.main.bundleURL
            .appending(path: "Contents/MacOS/apple-calendar-mcp-bridge")
            .path(percentEncoded: false)
    }

    var configurationSnippet: String {
        """
        "apple-calendar": {
          "command": "\(bridgePath)"
        }
        """
    }

    /// A likely client to offer as a shortcut, when one is installed.
    var suggestedClient: String? {
        let candidates = ["/Applications/Claude.app"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    func refresh() {
        access = CalendarPermission.current()
        helperInstalled = ServiceControl.status == .enabled
        helperState = ServiceControl.describe(ServiceControl.status)

        // A keychain read can fail for reasons that are not "nothing is pinned"
        // — a locked keychain, or an item another binary owns. Saying "none"
        // in that case would be a lie the person acts on.
        pinnedRequirement = ClientPin.requirementText()
        pinReadFailed = false
    }

    // MARK: - Actions

    func grantAccess() async {
        await run("access") {
            let outcome = await CalendarPermission.requestFullAccess()
            if let error = outcome.error { throw SetupFailure(error) }
            if !outcome.granted, outcome.state == .denied {
                throw SetupFailure(AccessState.denied.explanation)
            }
        }
    }

    func installHelper() async {
        await run("helper") { try ServiceControl.register() }
    }

    func removeHelper() async {
        await run("helper") { try ServiceControl.unregister() }
    }

    func pin(applicationAt path: String) async {
        await run("pin") { _ = try ClientPin.pin(applicationAt: path) }
    }

    func unpin() async {
        await run("pin") { try ClientPin.unpin() }
    }

    // MARK: - Plumbing

    private func run(_ label: String, _ work: () async throws -> Void) async {
        busy = label
        failure = nil
        do {
            try await work()
        } catch {
            failure = error.localizedDescription
        }
        busy = nil
        refresh()
    }
}

struct SetupFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
