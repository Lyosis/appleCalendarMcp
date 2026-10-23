import AppleCalendarIPC
import Foundation

/// An append-only record of every change made to the calendar.
///
/// The helper holds a permission that anything able to reach it can use, and no
/// check closes that completely — a request that arrives through the client is
/// indistinguishable from one the person actually meant. This does not prevent
/// misuse; it makes misuse visible afterwards, which is the honest claim.
actor WriteJournal {
    private let url: URL

    init() {
        url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/apple-calendar-mcp-writes.log")
    }

    /// The path, so tools can tell the caller where the record lives.
    nonisolated var path: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/apple-calendar-mcp-writes.log").path(percentEncoded: false)
    }

    func record(
        action: String, event: EventInfo, scope: RecurrenceScope, occurrenceStart: Date?
    ) {
        var fields: [String: JSONValue] = [
            "at": .string(Timestamp.string(from: .now)),
            "action": .string(action),
            "span": .string(scope.rawValue),
            "eventId": .string(event.id),
            "title": .string(event.title),
            "start": .string(Timestamp.string(from: event.start)),
            "end": .string(Timestamp.string(from: event.end)),
            "calendar": .string(event.calendarTitle),
        ]
        // Which occurrence was addressed, and how the series repeats: without
        // them, a line saying "deleted" cannot tell one Monday from every one.
        if let occurrenceStart {
            fields["occurrenceStart"] = .string(Timestamp.string(from: occurrenceStart))
        }
        if let recurrence = event.recurrence {
            fields["recurrence"] = .string(recurrence)
        }
        let entry = JSONValue.object(fields)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entry) else { return }
        append(data)
    }

    private func append(_ data: Data) {
        var line = data
        line.append(0x0A)

        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path(percentEncoded: false)) {
            try? manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            manager.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            log("could not open the write journal at \(url.path(percentEncoded: false))")
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            log("could not append to the write journal: \(error)")
        }
    }
}
