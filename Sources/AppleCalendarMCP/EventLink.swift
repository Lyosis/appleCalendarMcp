import Foundation

/// The link a caller gives for an event, read strictly.
///
/// `URL(string:)` alone was used before. Measured on 2026-11-01: it returns
/// nil for "https://exa mple.com" or "http://[bad", which erased the event's
/// existing link while the tool reported success; and it accepts anything
/// else — "not a url" as a relative link, "javascript:", "file:///etc/passwd",
/// "shortcuts://run-shortcut?name=…", which runs one of the person's shortcuts
/// when clicked. The model writes these links, sometimes from text other
/// people wrote, so only links that open a page or a message are accepted.
enum EventLink {

    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    /// What `text` asks for: "" removes the link, anything else must be an
    /// http or https link with a host, or a mailto link with an address.
    static func change(from text: String) throws -> EventDraft.Link {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .remove }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme)
        else {
            throw CalendarError.badLink
        }
        let addressed = scheme == "mailto" ? !url.path().isEmpty : !(url.host() ?? "").isEmpty
        guard addressed else { throw CalendarError.badLink }
        return .set(url)
    }
}
