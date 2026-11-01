import Foundation
import Testing
@testable import AppleCalendarMCP

/// The version lives in three files. A comment claimed the selftest kept the
/// bridge's in step; nothing did, until this.
struct VersionTests {
    private static let resources = URL(filePath: #filePath)
        .deletingLastPathComponent()  // AppleCalendarMCPTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // the package
        .appending(path: "Resources")

    @Test("Every embedded plist carries serverVersion", arguments: ["Info.plist", "BridgeInfo.plist"])
    func plist(_ name: String) throws {
        let data = try Data(contentsOf: Self.resources.appending(path: name))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(plist?["CFBundleShortVersionString"] as? String == serverVersion)
    }
}
