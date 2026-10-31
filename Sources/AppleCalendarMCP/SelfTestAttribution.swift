import AppleCalendarSetup
import Darwin
import Foundation

/// Whose calendar permission the selftest is looking at.
enum SelfTestAttribution: Equatable {
    /// This bundle's own: the run was started disclaimed by `--selftest`.
    case own
    /// Whatever process macOS holds responsible for the caller — a terminal,
    /// an editor — which says nothing about the agent.
    case caller(String)

    /// For the run that carries `DisclaimedSpawn.marker`. The marker alone
    /// proves nothing — anyone can type it — so the parent must be this same
    /// executable, which only passes the marker after disclaiming.
    static func ofDisclaimedRun() -> SelfTestAttribution {
        guard let own = Bundle.main.executablePath.flatMap(Ancestry.resolvedPath),
              let parent = Ancestry.path(of: getppid()).flatMap(Ancestry.resolvedPath),
              parent == own
        else {
            return .caller("\(DisclaimedSpawn.marker) was not passed by --selftest itself")
        }
        return .own
    }
}
