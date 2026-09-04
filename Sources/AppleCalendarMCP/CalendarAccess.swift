import CoreGraphics
import EventKit
import Foundation

/// Authorization state for calendar events, in the terms this server reports.
enum AccessState: String, Sendable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
    case unknown

    /// Whether events can be read at all. Write-only access is enough to create
    /// an event but not to see one, which is a distinction worth surfacing.
    var canRead: Bool { self == .fullAccess }

    var explanation: String {
        switch self {
        case .notDetermined:
            "No decision has been recorded yet. The system will ask the first time access is requested."
        case .restricted:
            "Access is blocked by a policy such as Screen Time or an MDM profile, and cannot be granted here."
        case .denied:
            "Access was refused. Grant it in System Settings > Privacy & Security > Calendars."
        case .writeOnly:
            "Only event creation is allowed. Reading events needs full access."
        case .fullAccess:
            "Full read and write access to calendar events."
        case .unknown:
            "The system reported an authorization status this build does not recognize."
        }
    }
}

/// A calendar, flattened into something that can safely cross actor boundaries.
struct CalendarInfo: Sendable, Equatable {
    let id: String
    let title: String
    let source: String
    let sourceType: String
    let isWritable: Bool
    let isDefaultForNewEvents: Bool
    let color: String?

    var json: JSONValue {
        var value: [String: JSONValue] = [
            "id": .string(id),
            "title": .string(title),
            "source": .string(source),
            "sourceType": .string(sourceType),
            "isWritable": .bool(isWritable),
            "isDefaultForNewEvents": .bool(isDefaultForNewEvents),
        ]
        if let color {
            value["color"] = .string(color)
        }
        return .object(value)
    }
}

/// Owns the single `EKEventStore` and everything that touches it.
///
/// `EKEventStore` and `EKCalendar` are not `Sendable`, so they never leave this
/// actor: every method converts to a value type before returning. Strict
/// concurrency enforces that, rather than leaving it to discipline.
actor CalendarAccess {
    /// Internal rather than private so the operations in CalendarOperations.swift
    /// can reach it. It still never leaves the actor.
    let store = EKEventStore()

    /// The recorded authorization status. Does not prompt.
    nonisolated static func currentState() -> AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        @unknown default: .unknown
        }
    }

    /// Asks for full access, prompting if the system decides to.
    ///
    /// Returns the state as it stands afterwards, which is not always what the
    /// call returned: reading the status back is the check that can fail.
    func requestAccess() async -> (granted: Bool, state: AccessState, error: String?) {
        do {
            let granted = try await store.requestFullAccessToEvents()
            return (granted, Self.currentState(), nil)
        } catch {
            return (false, Self.currentState(), error.localizedDescription)
        }
    }

    /// Every event calendar the store can see.
    ///
    /// Callers that have just crossed the not-determined boundary must call
    /// `reset()` first: Apple's documentation is explicit that a store queried
    /// before access was granted keeps returning nothing afterwards.
    func calendars() -> [CalendarInfo] {
        let defaultIdentifier = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    source: calendar.source?.title ?? "Unknown",
                    sourceType: Self.describe(calendar.source?.sourceType),
                    isWritable: calendar.allowsContentModifications,
                    isDefaultForNewEvents: calendar.calendarIdentifier == defaultIdentifier,
                    color: Self.hexString(from: calendar.cgColor)
                )
            }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// Discards cached state. Required after access is granted mid-process.
    func reset() {
        store.reset()
    }

    // MARK: - Conversion

    private static func describe(_ sourceType: EKSourceType?) -> String {
        switch sourceType {
        case .local: "local"
        case .exchange: "exchange"
        case .calDAV: "caldav"  // iCloud reports as CalDAV, named "iCloud".
        case .mobileMe: "mobileme"
        case .subscribed: "subscribed"
        case .birthdays: "birthdays"
        case .none: "unknown"
        @unknown default: "unknown"
        }
    }

    private static func hexString(from cgColor: CGColor?) -> String? {
        guard let cgColor,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3
        else {
            return nil
        }
        let channels = components.prefix(3).map { component -> UInt8 in
            UInt8(clamping: Int((component * 255).rounded()))
        }
        return "#" + channels.map { String(format: "%02X", $0) }.joined()
    }
}
