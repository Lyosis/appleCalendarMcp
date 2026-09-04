import AppleCalendarSetup
import Foundation

/// The command-line side of launch agent registration.
enum AgentCommands {

    static func register() -> Bool {
        report("bundle", ServiceControl.bundlePath)
        do {
            try ServiceControl.register()
            report("register", "ok")
        } catch {
            report("register", "FAILED — \(error.localizedDescription)")
            report("hint", ServiceControl.hint(for: error))
            return false
        }
        report("status", ServiceControl.describe(ServiceControl.status))
        return true
    }

    static func unregister() -> Bool {
        do {
            try ServiceControl.unregister()
            report("unregister", "ok")
        } catch {
            report("unregister", "FAILED — \(error.localizedDescription)")
            return false
        }
        report("status", ServiceControl.describe(ServiceControl.status))
        return true
    }

    static func status() -> Bool {
        report("bundle", ServiceControl.bundlePath)
        let current = ServiceControl.status
        report("status", ServiceControl.describe(current))
        return current == .enabled
    }

    private static func report(_ label: String, _ value: String) {
        print("  \(label.padding(toLength: 12, withPad: " ", startingAt: 0)) \(value)")
    }
}
