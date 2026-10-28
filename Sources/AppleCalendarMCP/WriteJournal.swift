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

    func recordCreation(_ event: EventInfo) {
        write([
            "action": "create",
            "after": JournalSnapshot(event).json,
        ])
    }

    /// The event as it was and as it is: the state after alone cannot say what
    /// to put back, and an occurrence edited on its own has already lost its
    /// series by then. Fields that are not logged are named when they change.
    func recordUpdate(
        _ update: CalendarAccess.Update, scope: RecurrenceScope, occurrenceStart: Date?
    ) {
        let (before, after) = (update.before, update.after)
        var fields: [String: JSONValue] = [
            "action": "update",
            "span": .string(scope.rawValue),
            "before": JournalSnapshot(before).json,
            "after": JournalSnapshot(after).json,
            "changedFields": .array(Self.changedFields(before: before, after: after).map { .string($0) }),
        ]
        if let occurrenceStart {
            fields["occurrenceStart"] = .string(Timestamp.string(from: occurrenceStart))
        }
        if let remaining = update.remainingSeries {
            // The part left behind by a split, with its new end.
            fields["remainingSeries"] = JournalSnapshot(remaining).json
        }
        write(fields)
    }

    /// Everything a deletion removed, not only the event addressed: deleting a
    /// series also takes the parts EventKit split off it.
    func recordDeletion(
        _ deletion: CalendarAccess.Deletion, scope: RecurrenceScope, occurrenceStart: Date?
    ) {
        var fields: [String: JSONValue] = [
            "action": "delete",
            "span": .string(scope.rawValue),
            "target": JournalSnapshot(deletion.target).json,
            "removed": .array(deletion.removed.map(\.json)),
        ]
        if let occurrenceStart {
            fields["occurrenceStart"] = .string(Timestamp.string(from: occurrenceStart))
        }
        if let scanned = deletion.scanned {
            // Parts beginning after this were removed too, but not listed.
            fields["scanned"] = .object([
                "from": .string(Timestamp.string(from: scanned.start)),
                "to": .string(Timestamp.string(from: scanned.end)),
            ])
        }
        write(fields)
    }

    /// The names of the fields that differ — values only for those the
    /// snapshot already carries, so notes, location and url stay out of the log.
    static func changedFields(before: EventInfo, after: EventInfo) -> [String] {
        var names: [String] = []
        if before.title != after.title { names.append("title") }
        if before.start != after.start { names.append("start") }
        if before.end != after.end { names.append("end") }
        if before.isAllDay != after.isAllDay { names.append("isAllDay") }
        if before.calendarID != after.calendarID { names.append("calendar") }
        if before.location != after.location { names.append("location") }
        if before.notes != after.notes { names.append("notes") }
        if before.url != after.url { names.append("url") }
        if before.recurrence != after.recurrence { names.append("recurrence") }
        return names
    }

    private func write(_ fields: [String: JSONValue]) {
        var entry = fields
        entry["at"] = .string(Timestamp.string(from: .now))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(JSONValue.object(entry)) else {
            log("dropped a journal entry that could not be encoded")
            return
        }
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
