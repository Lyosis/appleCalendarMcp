import AppleCalendarIPC
import Foundation

/// An append-only record of every change made to the calendar.
///
/// The helper holds a permission that anything able to reach it can use, and no
/// check closes that completely — a request that arrives through the client is
/// indistinguishable from one the person actually meant. This does not prevent
/// misuse; it makes misuse visible afterwards, which is the honest claim.
///
/// A record that fails silently would make that claim false without anyone
/// knowing. So a change is refused when the journal cannot be opened, and a
/// failure to append after the change is thrown, for the result to say so.
actor WriteJournal {
    /// Why the journal could not be written.
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/apple-calendar-mcp-writes.log")

    private let url: URL

    /// Another location only for tests.
    init(url: URL = WriteJournal.defaultURL) {
        self.url = url
    }

    /// The path, so tools can tell the caller where the record lives.
    nonisolated var path: String {
        url.path(percentEncoded: false)
    }

    /// Throws unless the journal can be opened for writing, creating it if it
    /// is missing. Called before a change, so a journal that cannot be written
    /// stops the change rather than lets it go unrecorded. It cannot foresee
    /// everything — a disk filling up in between — which is why appending
    /// still throws.
    func checkWritable() throws {
        try open().close()
    }

    func recordCreation(_ event: EventInfo) throws {
        try write([
            "action": "create",
            "after": JournalSnapshot(event).json,
        ])
    }

    /// The event as it was and as it is: the state after alone cannot say what
    /// to put back, and an occurrence edited on its own has already lost its
    /// series by then. Fields that are not logged are named when they change.
    func recordUpdate(
        _ update: CalendarAccess.Update, scope: RecurrenceScope, occurrenceStart: Date?
    ) throws {
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
        try write(fields)
    }

    /// Everything a deletion removed, not only the event addressed: deleting a
    /// series also takes the parts EventKit split off it.
    func recordDeletion(
        _ deletion: CalendarAccess.Deletion, scope: RecurrenceScope, occurrenceStart: Date?
    ) throws {
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
        try write(fields)
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

    private func write(_ fields: [String: JSONValue]) throws {
        var entry = fields
        entry["at"] = .string(Timestamp.string(from: .now))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(JSONValue.object(entry)) else {
            throw failure("an entry could not be encoded")
        }
        try append(data)
    }

    /// Internal rather than private so tests can make it fail on its own.
    func append(_ data: Data) throws {
        var line = data
        line.append(0x0A)

        let handle = try open()
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            throw failure("could not append to \(path): \(Self.describe(error))")
        }
    }

    /// The journal, open for writing — created first if it is missing.
    private func open() throws -> FileHandle {
        let manager = FileManager.default
        if !manager.fileExists(atPath: path) {
            try? manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard manager.createFile(atPath: path, contents: nil) else {
                throw failure("could not create \(path)")
            }
        }
        do {
            return try FileHandle(forWritingTo: url)
        } catch {
            throw failure("could not open \(path): \(Self.describe(error))")
        }
    }

    /// The error in English, whatever the Mac's language: these messages reach
    /// the model and end up in public issues, like every diagnostic here.
    /// `localizedDescription` came back in French — measured on 2026-11-01.
    /// The C library's text for the underlying POSIX error is not localised.
    static func describe(_ error: any Error) -> String {
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSPOSIXErrorDomain {
                return "\(String(cString: strerror(Int32(nsError.code)))) (errno \(nsError.code))"
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let nsError = error as NSError
        return "\(nsError.domain) error \(nsError.code)"
    }

    /// Logged as well as thrown, so the failure is on record even if the
    /// caller loses it.
    private func failure(_ message: String) -> Failure {
        log("change journal: \(message)")
        return Failure(message)
    }
}
