import Foundation
import Testing
@testable import AppleCalendarMCP

/// A new start or end for a whole series moved its first occurrence and made
/// the earlier ones vanish — measured on 2026-10-31. It is refused, and only
/// that.
struct SeriesChangeTests {
    private let seriesStart = Date(timeIntervalSince1970: 1_793_869_200)  // 2026-11-05 10:00 Paris

    private func draft(start: Bool = false, end: Bool = false, title: String? = nil) -> EventDraft {
        var draft = EventDraft()
        if start { draft.start = seriesStart.addingTimeInterval(3 * 86_400) }
        if end { draft.end = seriesStart.addingTimeInterval(3 * 86_400 + 3_600) }
        draft.title = title
        return draft
    }

    @Test("A whole series is refused a new start, a new end, or both", arguments: [
        (true, false), (false, true), (true, true),
    ])
    func refused(_ start: Bool, _ end: Bool) {
        #expect(throws: CalendarError.self) {
            try CalendarAccess.checkSeriesChange(draft(start: start, end: end), scope: .series, seriesStart: seriesStart)
        }
    }

    @Test("The refusal names the first occurrence, so the caller can address it")
    func namesFirstOccurrence() {
        do {
            try CalendarAccess.checkSeriesChange(draft(start: true), scope: .series, seriesStart: seriesStart)
            Issue.record("expected a refusal")
        } catch {
            #expect(error.localizedDescription.contains(Timestamp.string(from: seriesStart)))
            #expect(error.localizedDescription.contains("futureEvents"))
        }
    }

    @Test("Other fields still change a whole series")
    func otherFields() throws {
        try CalendarAccess.checkSeriesChange(draft(title: "Renamed"), scope: .series, seriesStart: seriesStart)
    }

    @Test("One occurrence, or it and the later ones, may still move", arguments: [
        RecurrenceScope.thisEvent, .futureEvents,
    ])
    func otherScopes(_ scope: RecurrenceScope) throws {
        try CalendarAccess.checkSeriesChange(draft(start: true, end: true), scope: scope, seriesStart: seriesStart)
    }
}
