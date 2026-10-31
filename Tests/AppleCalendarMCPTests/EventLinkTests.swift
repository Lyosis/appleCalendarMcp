import Foundation
import Testing
@testable import AppleCalendarMCP

/// The inputs measured on 2026-11-01: some erased the existing link, others
/// were accepted although clicking them runs an app.
struct EventLinkTests {

    @Test("Links that open a page or a message are kept", arguments: [
        ("https://example.com/meeting", "https://example.com/meeting"),
        ("http://example.com", "http://example.com"),
        ("HTTPS://Example.com", "HTTPS://Example.com"),
        ("  https://example.com  ", "https://example.com"),
        ("https://example.com/a b", "https://example.com/a%20b"),
        ("https://example.com/é", "https://example.com/%C3%A9"),
        ("mailto:a@b.c", "mailto:a@b.c"),
    ])
    func kept(_ text: String, _ expected: String) throws {
        #expect(try EventLink.change(from: text) == .set(try #require(URL(string: expected))))
    }

    @Test("An empty link removes it", arguments: ["", "   "])
    func remove(_ text: String) throws {
        #expect(try EventLink.change(from: text) == .remove)
    }

    @Test("What used to erase the link silently is refused", arguments: [
        "https://exa mple.com", "http://[bad",
    ])
    func unparsable(_ text: String) {
        #expect(throws: CalendarError.self) { try EventLink.change(from: text) }
    }

    @Test("Schemes that run something when clicked are refused", arguments: [
        "javascript:alert(1)", "file:///etc/passwd", "shortcuts://run-shortcut?name=X",
        "data:text/html,<script>", "x-apple.systempreferences:",
    ])
    func schemes(_ text: String) {
        #expect(throws: CalendarError.self) { try EventLink.change(from: text) }
    }

    @Test("A link with nowhere to go is refused", arguments: [
        "not a url", "example.com", "https://", "https:///path", "mailto:", "://x",
    ])
    func nowhere(_ text: String) {
        #expect(throws: CalendarError.self) { try EventLink.change(from: text) }
    }
}
