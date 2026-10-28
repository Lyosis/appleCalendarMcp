import Foundation
import Testing
@testable import AppleCalendarMCP

/// What a deletion removed, found by comparing the calendar before and after.
/// The case behind it, measured on 2026-10-23: deleting a weekly series that
/// had been split in two and had one occurrence edited on its own removed
/// three identifiers, and the journal named one.
struct JournalRemovalTests {
    private let week: TimeInterval = 7 * 24 * 3600
    private let origin = Date(timeIntervalSinceReferenceDate: 815_000_000)

    private func event(_ id: String, week index: Int, recurrence: String? = nil) -> JournalSnapshot {
        let start = origin.addingTimeInterval(Double(index) * week)
        return JournalSnapshot(
            id: id, title: id, start: start, end: start.addingTimeInterval(3600),
            calendar: "MCP test", isAllDay: false, recurrence: recurrence)
    }

    @Test("A split series, its detached occurrence and its tail are all listed, once each")
    func splitSeries() {
        let before = [
            event("A", week: 0, recurrence: "every week"),
            event("A", week: 1, recurrence: "every week"),
            event("A/RID=2", week: 2),
            event("B", week: 3, recurrence: "every week"),
            event("B", week: 4, recurrence: "every week"),
            event("unrelated", week: 2),
        ]
        let after = [event("unrelated", week: 2)]

        let removed = JournalSnapshot.removed(before: before, after: after)
        #expect(removed.map(\.id) == ["A", "A/RID=2", "B"])
        // Each one at its earliest occurrence, with how it repeats.
        #expect(removed[0].start == origin)
        #expect(removed[2].start == origin.addingTimeInterval(3 * week))
        #expect(removed[2].recurrence == "every week")
    }

    @Test("The earliest occurrence is kept whatever order the events come in")
    func unordered() {
        let before = [3, 0, 2, 1].map { event("A", week: $0, recurrence: "every week") }
        let removed = JournalSnapshot.removed(before: before, after: [])
        #expect(removed.count == 1)
        #expect(removed.first?.start == origin)
    }

    @Test("Nothing removed when nothing changed")
    func nothing() {
        let events = [event("A", week: 0), event("B", week: 1)]
        #expect(JournalSnapshot.removed(before: events, after: events).isEmpty)
    }

    @Test("Only the occurrences that went count: a series cut short is listed from its first lost one")
    func cutShort() {
        let before = (0..<4).map { event("A", week: $0, recurrence: "every week") }
        let after = Array(before.prefix(2))
        let removed = JournalSnapshot.removed(before: before, after: after)
        #expect(removed.count == 1)
        #expect(removed.first?.start == origin.addingTimeInterval(2 * week))
    }
}
