// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "apple-calendar-mcp",
    platforms: [
        // Minimum justified by requestFullAccessToEvents(), macOS 14.0+.
        .macOS(.v14)
    ],
    products: [
        .executable(name: "apple-calendar-mcp", targets: ["AppleCalendarMCP"])
    ],
    targets: [
        .executableTarget(
            name: "AppleCalendarMCP",
            path: "Sources/AppleCalendarMCP",
            swiftSettings: [
                // Explicit rather than inherited: a guarantee you cannot see
                // being enforced is a guarantee you cannot trust.
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                // A bare command-line tool has no bundle, so the usage
                // description the system shows in the permission prompt has to
                // be embedded straight into the __TEXT segment. The .app bundle
                // built for distribution reuses the very same file.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        )
    ]
)
