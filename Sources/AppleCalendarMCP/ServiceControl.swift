import Foundation
import ServiceManagement

/// Registration of the helper launch agent.
///
/// `SMAppService.agent(plistName:)` resolves the property list inside the
/// *calling* bundle's `Contents/Library/LaunchAgents`, so these commands only
/// work when this executable runs from inside the helper app bundle.
enum ServiceControl {
    static let agentPlistName = "com.wilfrid.B.apple-calendar-mcp.agent.plist"

    private static var agent: SMAppService {
        SMAppService.agent(plistName: agentPlistName)
    }

    /// Registers the agent. launchd bootstraps it immediately and at each login.
    static func register() -> Bool {
        report("bundle", Bundle.main.bundlePath)
        do {
            try agent.register()
            report("register", "ok")
        } catch {
            report("register", "FAILED — \(error.localizedDescription)")
            report("hint", hint(for: error))
            return false
        }
        report("status", describe(agent.status))
        return true
    }

    static func unregister() -> Bool {
        do {
            try agent.unregister()
            report("unregister", "ok")
        } catch {
            // Already-absent is not a failure worth a non-zero exit here.
            report("unregister", "FAILED — \(error.localizedDescription)")
            return false
        }
        report("status", describe(agent.status))
        return true
    }

    static func status() -> Bool {
        report("bundle", Bundle.main.bundlePath)
        let current = agent.status
        report("status", describe(current))
        return current == .enabled
    }

    // MARK: - Presentation

    private static func report(_ label: String, _ value: String) {
        print("  \(label.padding(toLength: 12, withPad: " ", startingAt: 0)) \(value)")
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "notRegistered — never registered, or already unregistered"
        case .enabled: "enabled — launchd will run it"
        case .requiresApproval: "requiresApproval — the person must allow it in System Settings > General > Login Items"
        // Observed as the state before a first registration, with the plist
        // correctly in place — not, as the name suggests, a missing file.
        case .notFound: "notFound — launchd has no record of this job yet"
        @unknown default: "unknown (raw \(status.rawValue))"
        }
    }

    /// Service Management errors are opaque, so surface the raw code alongside
    /// the things actually worth checking rather than guessing at a mapping.
    private static func hint(for error: any Error) -> String {
        let code = (error as NSError).code
        return """
            code \(code) — check that the plist is at \
            Contents/Library/LaunchAgents/\(agentPlistName), that the .app is signed, \
            and look for launchd entries in Console
            """
    }
}
