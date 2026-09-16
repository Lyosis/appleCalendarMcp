import SwiftUI

/// The installer window.
///
/// It exists because the calendar permission can only be granted to an
/// application the system launched — the same constraint that shapes the whole
/// project. Since the bundle has to exist anyway, it may as well be the place
/// where setup happens and where someone looks when it stops working.
@main
struct AppleCalendarMCPApp: App {
    var body: some Scene {
        Window("Apple Calendar for MCP", id: "setup") {
            SetupWindow()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
