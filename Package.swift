// swift-tools-version: 6.0
import PackageDescription

// Explicit rather than inherited: a guarantee you cannot see being enforced is
// a guarantee you cannot trust.
let strictConcurrency: [SwiftSetting] = [.swiftLanguageMode(.v6)]

/// Embeds an Info.plist straight into the __TEXT segment.
///
/// A bare command-line tool has no bundle, so this is what gives the executable
/// a stable identity and — for the helper — the usage description the system
/// shows in the permission prompt. The helper's .app bundle reuses the same file.
func embeddedPlist(_ path: String) -> [LinkerSetting] {
    [
        .unsafeFlags([
            "-Xlinker", "-sectcreate",
            "-Xlinker", "__TEXT",
            "-Xlinker", "__info_plist",
            "-Xlinker", path,
        ])
    ]
}

let package = Package(
    name: "apple-calendar-mcp",
    platforms: [
        // Minimum justified by the most demanding API actually used:
        // xpc_connection_set_peer_team_identity_requirement, macOS 14.4+.
        // It is what lets the helper accept only peers signed by the same team
        // as itself, so anyone can build and sign this project with their own
        // certificate without editing a hardcoded team identifier.
        // (requestFullAccessToEvents needs 14.0, SMAppService 13.0.)
        .macOS("14.4")
    ],
    products: [
        // Runs as a launch agent, holds the calendar permission.
        .executable(name: "apple-calendar-mcp", targets: ["AppleCalendarMCP"]),
        // Spawned by the MCP client, forwards messages to the helper.
        .executable(name: "apple-calendar-mcp-bridge", targets: ["AppleCalendarBridge"]),
    ],
    targets: [
        .target(
            name: "AppleCalendarIPC",
            path: "Sources/AppleCalendarIPC",
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "AppleCalendarMCP",
            dependencies: ["AppleCalendarIPC"],
            path: "Sources/AppleCalendarMCP",
            swiftSettings: strictConcurrency,
            linkerSettings: embeddedPlist("Resources/Info.plist")
        ),
        .executableTarget(
            name: "AppleCalendarBridge",
            dependencies: ["AppleCalendarIPC"],
            path: "Sources/AppleCalendarBridge",
            swiftSettings: strictConcurrency,
            linkerSettings: embeddedPlist("Resources/BridgeInfo.plist")
        ),
    ]
)
