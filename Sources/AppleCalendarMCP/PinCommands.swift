import AppleCalendarSetup
import Foundation

/// The command-line side of client pinning.
enum PinCommands {

    static func show() -> Bool {
        guard let text = ClientPin.requirementText() else {
            print("  pinned client   none")
            print("""
                  warning         Without a pin, any process on this Mac signed by the
                                  same team as this helper can read and change your
                                  calendar through it. Run --pin-client-auto from the
                                  MCP client you intend to use.
                """)
            return false
        }
        print("  pinned client   \(text)")
        return true
    }

    /// Pins the application at `path`.
    static func pin(path: String) -> Bool {
        do {
            let text = try ClientPin.pin(applicationAt: path)
            print("  pinned          \(path)")
            print("  requirement     \(text)")
            print("  effect          Only connections with this application among their")
            print("                  ancestors are accepted from now on.")
            return true
        } catch {
            print("  FAILED          \(error.localizedDescription)")
            return false
        }
    }

    /// Pins whatever application launched this process.
    ///
    /// Run it from the MCP client and the right thing is pinned without anyone
    /// having to know a path: whoever is installing is whoever gets access.
    static func pinLaunchingApplication() -> Bool {
        guard let path = Ancestry.launchingApplication() else {
            print("  FAILED          No application above this process to pin.")
            print("                  Run this from inside your MCP client, or pass")
            print("                  --pin-client /path/to/Client.app instead.")
            print("  ancestors       \(Ancestry.summary())")
            return false
        }
        print("  detected        \(path)")
        return pin(path: path)
    }

    static func unpin() -> Bool {
        do {
            try ClientPin.unpin()
            print("  unpinned        any client signed by this team is now accepted")
            return true
        } catch {
            print("  FAILED          \(error.localizedDescription)")
            return false
        }
    }
}
