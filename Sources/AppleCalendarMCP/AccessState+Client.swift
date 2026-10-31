import AppleCalendarSetup

extension AccessState {
    /// What the server tells its client about this state.
    ///
    /// The server never asks for access: a prompt raised by a tool call comes
    /// at a moment the model chose — perhaps one a web page talked it into —
    /// with nothing on screen saying why, and the call waits until someone
    /// answers. The setup window is where the person decides, knowing what for.
    var adviceForClient: String {
        switch self {
        case .notDetermined:
            """
            Calendar access has not been granted yet. Ask the person to open \
            AppleCalendarMCP.app and grant it there; this server never asks for it.
            """
        default:
            explanation
        }
    }

    /// Access was granted after this server started, which it only sees by
    /// starting again. See `FreshAccessState`.
    static let grantedSinceStart = """
        Calendar access was granted after this server started. It restarts now \
        to pick it up: call the tool again.
        """

    /// A server that started after the grant still cannot read, while a new
    /// process can: the two are not attributed to the same app.
    static let disagreement = """
        This server cannot read the calendar, yet a new process started by it \
        can. Run `apple-calendar-mcp --selftest` and include its output in a \
        bug report.
        """
}
