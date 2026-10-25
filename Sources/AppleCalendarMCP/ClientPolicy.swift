import Darwin
import Security

/// Which client may reach the calendar, compiled into the helper.
///
/// There is nothing to configure, on purpose. A pin kept in the keychain could
/// be deleted by any process running as the person — `security
/// delete-generic-password` does it without a prompt — and an empty pin meant
/// "accept everyone". A policy that lives in the signed binary can only be
/// changed by shipping another signed binary.
///
/// The chain has to match exactly, link by link, from the bridge up to launchd.
/// "The client is somewhere above" is not enough: measured on 2026-10-25, a
/// shell started by a Claude Code session has Claude Desktop above it too, so
/// any command run from that shell — including one a model was talked into —
/// got full calendar access through the bridge.
enum ClientPolicy {

    /// One process the chain must contain, above the bridge.
    struct Step: Sendable {
        /// How the step is named in the log and in `--selftest`.
        let name: String
        /// A code requirement, copied from the program's own designated
        /// requirement (`codesign -d -r-`): its identifier and its team, so
        /// updates and certificate renewals by the same publisher still match.
        let requirement: String
        /// Where the program is normally installed, for `--selftest` only. The
        /// check on a connection never looks at paths.
        let installedPath: String
    }

    /// The processes above the bridge, nearest first, measured on 2026-10-25
    /// with Claude Desktop 3.6556.2. Sessions of Claude Code inside the app use
    /// the same chain: the app itself starts the MCP servers it declares.
    /// Directly above the last step comes launchd, and nothing else.
    static let steps: [Step] = [
        Step(
            name: "disclaimer",
            requirement: """
                identifier disclaimer and anchor apple generic \
                and certificate 1[field.1.2.840.113635.100.6.2.6] \
                and certificate leaf[field.1.2.840.113635.100.6.1.13] \
                and certificate leaf[subject.OU] = Q6L2SF6YDW
                """,
            installedPath: "/Applications/Claude.app/Contents/Helpers/disclaimer"
        ),
        Step(
            name: "Claude Desktop",
            requirement: """
                identifier "com.anthropic.claudefordesktop" and anchor apple generic \
                and certificate 1[field.1.2.840.113635.100.6.2.6] \
                and certificate leaf[field.1.2.840.113635.100.6.1.13] \
                and certificate leaf[subject.OU] = Q6L2SF6YDW
                """,
            installedPath: "/Applications/Claude.app"
        ),
    ]

    /// What the client is told when it is refused. The detail — which process
    /// was where — goes to the log, not to the model.
    static let refusalMessage = """
        apple-calendar-mcp accepts only Claude Desktop as its client, and this \
        connection did not come from it. See SECURITY.md in the project's repository.
        """

    enum Verdict: Equatable, Sendable {
        case allowed
        case refused(String)
    }

    /// Whether the process `peer` — the bridge — was started by an allowed client.
    static func evaluate(peer: pid_t, using system: some ProcessInspector) -> Verdict {
        guard var childStart = system.startTime(of: peer) else {
            return .refused("the bridge (\(peer)) has already exited")
        }
        var child = peer

        for step in steps {
            guard let parent = system.parent(of: child), parent > 1 else {
                return .refused("\(step.name) is not above process \(child)")
            }
            // Read before the signature check and again after it, so the
            // process that passed is the one whose start time was compared.
            guard let started = system.startTime(of: parent) else {
                return .refused("process \(parent) exited while being checked")
            }
            guard started <= childStart else {
                return .refused("process \(parent) started after its child: its id was reused")
            }
            guard system.satisfies(parent, step) else {
                return .refused("process \(parent) is not \(step.name)")
            }
            guard system.startTime(of: parent) == started else {
                return .refused("process \(parent) changed while being checked")
            }
            child = parent
            childStart = started
        }

        guard system.parent(of: child) == 1 else {
            return .refused("\(steps.last?.name ?? "the client") was not started by launchd")
        }
        return .allowed
    }

    /// The step's requirement, compiled. Nil only if the text above is wrong,
    /// which the tests rule out; the check then refuses rather than allows.
    static func compiled(_ step: Step) -> SecRequirement? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(step.requirement as CFString, [], &requirement)
                == errSecSuccess
        else {
            return nil
        }
        return requirement
    }
}
