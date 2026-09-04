import EventKit
import Foundation

/// The fields a caller may set when creating or changing an event.
/// Every one is optional: on an update, nil means "leave this alone".
struct EventDraft: Sendable {
    var title: String?
    var start: Date?
    var end: Date?
    var isAllDay: Bool?
    var location: String?
    var notes: String?
    var url: String?
    var calendarID: String?
    var alarmMinutesBefore: Int?
}

extension CalendarAccess {

    // MARK: - Reading

    /// Events overlapping a range, in chronological order.
    func events(from start: Date, to end: Date, calendarIDs: [String]?) throws -> [EventInfo] {
        let calendars = try resolveCalendars(calendarIDs)
        var seen = Set<String>()
        var results: [EventInfo] = []

        for window in Self.searchWindows(from: start, to: end) {
            let predicate = store.predicateForEvents(
                withStart: window.start, end: window.end, calendars: calendars)
            for event in store.events(matching: predicate) {
                let info = EventInfo(event)
                // Windows abut, so an event spanning a boundary is returned by
                // both. A recurring series shares one identifier, so identity
                // has to include the occurrence's start.
                if seen.insert(info.occurrenceKey).inserted { results.append(info) }
            }
        }
        return results.sorted { $0.start < $1.start }
    }

    func search(
        query: String, from start: Date, to end: Date, calendarIDs: [String]?
    ) throws -> [EventInfo] {
        try events(from: start, to: end, calendarIDs: calendarIDs).filter { event in
            event.title.localizedStandardContains(query)
                || event.location?.localizedStandardContains(query) == true
                || event.notes?.localizedStandardContains(query) == true
        }
    }

    /// Openings of at least `duration`, inside the given hours of each day.
    func freeSlots(
        from start: Date,
        to end: Date,
        duration: TimeInterval,
        calendarIDs: [String]?,
        dayStartHour: Int,
        dayEndHour: Int
    ) throws -> [DateInterval] {
        // An event marked "free" — the way all-day markers usually are — does
        // not make the person unavailable.
        let busy = try events(from: start, to: end, calendarIDs: calendarIDs)
            .filter { $0.availability != "free" && $0.end > $0.start }
            .map { DateInterval(start: $0.start, end: $0.end) }
            .sorted { $0.start < $1.start }
        let merged = Self.merge(busy)

        var slots: [DateInterval] = []
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: start)

        while day < end {
            if let windowStart = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: day),
               let windowEnd = calendar.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: day) {
                let lower = max(windowStart, start)
                let upper = min(windowEnd, end)
                if lower < upper {
                    slots += Self.gaps(
                        in: DateInterval(start: lower, end: upper),
                        busy: merged,
                        minimum: duration
                    )
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return slots
    }

    // MARK: - Writing

    func create(_ draft: EventDraft) throws -> EventInfo {
        guard let title = draft.title, let start = draft.start, let end = draft.end else {
            throw CalendarError.saveFailed("title, start and end are all required")
        }
        guard end >= start else { throw CalendarError.endBeforeStart }

        let event = EKEvent(eventStore: store)
        event.calendar = try writableCalendar(draft.calendarID)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = draft.isAllDay ?? false
        event.location = draft.location
        event.notes = draft.notes
        if let url = draft.url { event.url = URL(string: url) }
        if let minutes = draft.alarmMinutesBefore {
            event.addAlarm(EKAlarm(relativeOffset: -Double(minutes) * 60))
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
        return EventInfo(event)
    }

    func update(
        id: String, occurrenceStart: Date?, span: EKSpan, draft: EventDraft
    ) throws -> EventInfo {
        guard let event = findEvent(id: id, occurrenceStart: occurrenceStart) else {
            throw CalendarError.unknownEvent(id)
        }
        guard event.calendar?.allowsContentModifications == true else {
            throw CalendarError.readOnlyCalendar(event.calendar?.title ?? "unknown")
        }

        if let title = draft.title { event.title = title }
        if let start = draft.start { event.startDate = start }
        if let end = draft.end { event.endDate = end }
        if let isAllDay = draft.isAllDay { event.isAllDay = isAllDay }
        if let location = draft.location { event.location = location }
        if let notes = draft.notes { event.notes = notes }
        if let url = draft.url { event.url = URL(string: url) }
        if let calendarID = draft.calendarID {
            event.calendar = try writableCalendar(calendarID)
        }
        guard event.endDate >= event.startDate else { throw CalendarError.endBeforeStart }

        do {
            try store.save(event, span: span, commit: true)
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
        return EventInfo(event)
    }

    /// Removes one event. Returns what was removed, so the caller can record it.
    func delete(id: String, occurrenceStart: Date?, span: EKSpan) throws -> EventInfo {
        guard let event = findEvent(id: id, occurrenceStart: occurrenceStart) else {
            throw CalendarError.unknownEvent(id)
        }
        guard event.calendar?.allowsContentModifications == true else {
            throw CalendarError.readOnlyCalendar(event.calendar?.title ?? "unknown")
        }
        let removed = EventInfo(event)
        do {
            try store.remove(event, span: span, commit: true)
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
        return removed
    }

    // MARK: - Lookup

    /// Finds an event, and for a recurring series the right occurrence of it.
    ///
    /// `event(withIdentifier:)` answers with the series, not the occurrence, so
    /// addressing a single occurrence means searching a window around its start.
    private func findEvent(id: String, occurrenceStart: Date?) -> EKEvent? {
        guard let occurrenceStart else { return store.event(withIdentifier: id) }
        let day: TimeInterval = 24 * 3600
        let predicate = store.predicateForEvents(
            withStart: occurrenceStart.addingTimeInterval(-day),
            end: occurrenceStart.addingTimeInterval(day),
            calendars: nil
        )
        return store.events(matching: predicate).first {
            $0.eventIdentifier == id
                && abs($0.startDate.timeIntervalSince(occurrenceStart)) < 60
        }
    }

    private func resolveCalendars(_ ids: [String]?) throws -> [EKCalendar]? {
        guard let ids, !ids.isEmpty else { return nil }
        return try ids.map { id in
            guard let calendar = store.calendar(withIdentifier: id) else {
                throw CalendarError.unknownCalendar(id)
            }
            return calendar
        }
    }

    private func writableCalendar(_ id: String?) throws -> EKCalendar {
        let calendar: EKCalendar
        if let id {
            guard let found = store.calendar(withIdentifier: id) else {
                throw CalendarError.unknownCalendar(id)
            }
            calendar = found
        } else {
            guard let fallback = store.defaultCalendarForNewEvents else {
                throw CalendarError.noDefaultCalendar
            }
            calendar = fallback
        }
        guard calendar.allowsContentModifications else {
            throw CalendarError.readOnlyCalendar(calendar.title)
        }
        return calendar
    }

    // MARK: - Ranges

    /// Splits a range into pieces EventKit will honour.
    ///
    /// `predicateForEvents` matches at most four years and shortens anything
    /// longer *silently*, so a caller asking for a decade would get three years
    /// of results and no indication that the rest was dropped.
    static func searchWindows(from start: Date, to end: Date) -> [(start: Date, end: Date)] {
        guard end > start else { return [] }
        let maximum: TimeInterval = 3 * 365 * 24 * 3600  // comfortably inside the cap
        var windows: [(start: Date, end: Date)] = []
        var cursor = start
        while cursor < end {
            let next = min(cursor.addingTimeInterval(maximum), end)
            windows.append((cursor, next))
            cursor = next
        }
        return windows
    }

    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    static func gaps(
        in window: DateInterval, busy: [DateInterval], minimum: TimeInterval
    ) -> [DateInterval] {
        var result: [DateInterval] = []
        var cursor = window.start

        for interval in busy where interval.end > window.start && interval.start < window.end {
            if interval.start > cursor {
                let gap = DateInterval(start: cursor, end: min(interval.start, window.end))
                if gap.duration >= minimum { result.append(gap) }
            }
            cursor = max(cursor, interval.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end {
            let gap = DateInterval(start: cursor, end: window.end)
            if gap.duration >= minimum { result.append(gap) }
        }
        return result
    }
}
