import EventKit
import Foundation

/// Authorization state for calendar events, in the terms this project reports.
public enum AccessState: String, Sendable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
    case unknown

    /// Whether events can be read at all.
    ///
    /// EventKit has no read-only level: write-only access is enough to create
    /// an event but returns a single empty placeholder calendar, so anything
    /// that reads needs full access.
    public var canRead: Bool { self == .fullAccess }

    public var explanation: String {
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
            "The system reported an authorization status this build does not recognise."
        }
    }
}

/// Reading and requesting the calendar permission.
///
/// Separate from `CalendarAccess` so the installer window can report and
/// request the permission without pulling in the whole event store.
public enum CalendarPermission {

    /// The recorded status. Does not prompt.
    public static func current() -> AccessState {
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
    /// Returns the state as it stands afterwards rather than what the call
    /// returned: reading the status back is the check that can fail.
    public static func requestFullAccess() async -> (granted: Bool, state: AccessState, error: String?) {
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToEvents()
            return (granted, current(), nil)
        } catch {
            return (false, current(), error.localizedDescription)
        }
    }
}
