import Foundation
import ServiceManagement

/// Registration of the helper launch agent.
///
/// `SMAppService.agent(plistName:)` resolves the property list inside the
/// *calling* bundle's `Contents/Library/LaunchAgents`, so these only work from
/// an executable running inside the helper app bundle.
public enum ServiceControl {
    public static let agentPlistName = "com.wilfrid.B.apple-calendar-mcp.agent.plist"

    private static var agent: SMAppService {
        SMAppService.agent(plistName: agentPlistName)
    }

    public static var status: SMAppService.Status { agent.status }

    public static var bundlePath: String { Bundle.main.bundlePath }

    /// Registers the agent. launchd bootstraps it immediately and at each login.
    public static func register() throws {
        try agent.register()
    }

    public static func unregister() throws {
        try agent.unregister()
    }

    public static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "not registered"
        case .enabled: "installed"
        // Observed as the state before a first registration, with the plist
        // correctly in place — not, as the name suggests, a missing file.
        case .notFound: "not installed"
        case .requiresApproval: "waiting for your approval in System Settings > General > Login Items"
        @unknown default: "unknown (raw \(status.rawValue))"
        }
    }

    /// Service Management errors are opaque, so surface the raw code alongside
    /// the things actually worth checking rather than guessing at a mapping.
    public static func hint(for error: any Error) -> String {
        let code = (error as NSError).code
        return """
            code \(code) — check that the plist is at \
            Contents/Library/LaunchAgents/\(agentPlistName), that the .app is signed, \
            and look for launchd entries in Console
            """
    }
}
