import AppleCalendarSetup
import Foundation
import Observation
import ServiceManagement

/// The helper's registration, reduced to what the window has wording for.
enum HelperState {
    case installed
    case notInstalled
    case needsApproval
}

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
    private(set) var helper: HelperState = .notInstalled

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

    func refresh() {
        access = CalendarPermission.current()

        helper =
            switch ServiceControl.status {
            case .enabled: .installed
            case .requiresApproval: .needsApproval
            default: .notInstalled
            }
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
