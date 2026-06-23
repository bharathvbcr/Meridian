// CalendarRepository.swift
// Meridian — iOS 27, Swift 6, strict concurrency
//
// Actor-isolated wrapper around EventKit: read events for a window, and write a
// zone-aware event directly (parity with Android `insertCalendarEvent` / EventActions).
//
// Requires NSCalendarsFullAccessUsageDescription in Info.plist.

import EventKit
import Foundation

// CalendarEventModel is defined in Models.swift (canonical).

// MARK: - InsertEventResult

/// Outcome of an event write so callers can surface success/failure explicitly
/// (mirrors Android `EventActionResult`).
enum InsertEventResult: Sendable, Equatable {
    case success(eventId: String)
    case failure(reason: String)
}

/// Default length for a scheduled meeting with no explicit duration (mirrors Android
/// `DEFAULT_EVENT_DURATION_MINUTES`).
let defaultEventDurationMinutes = 60

// MARK: - CalendarRepository

/// Actor that serialises all EventKit access, satisfying Swift 6 strict-concurrency
/// requirements. `EKEventStore` is not `Sendable`, so it never leaves the actor boundary.
actor CalendarRepository {

    // MARK: Private state

    private let store = EKEventStore()

    // MARK: - Authorization

    /// Current `EKAuthorizationStatus` for events, without triggering a prompt.
    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Prompts the user for Full Access to Calendar events (iOS 17+ API).
    /// Returns `true` when access was granted (or already granted).
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            // Typically EKErrorDomain code 1 (denied by user or MDM).
            return false
        }
    }

    /// Prompts for write-only access (sufficient to insert events without reading).
    /// Returns `true` when granted or already at write-only/full access.
    func requestWriteAccess() async -> Bool {
        switch authorizationStatus {
        case .fullAccess, .writeOnly:
            return true
        default:
            break
        }
        do {
            return try await store.requestWriteOnlyAccessToEvents()
        } catch {
            return false
        }
    }

    // MARK: - Fetching

    /// Fetches all calendar events whose start date falls within `[from, to]`.
    /// Returns an empty array when full calendar access is not granted.
    func fetchEvents(from startDate: Date, to endDate: Date) async -> [CalendarEventModel] {
        guard authorizationStatus == .fullAccess else { return [] }

        let predicate = store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil   // nil = all calendars
        )

        let ekEvents = store.events(matching: predicate)
        return ekEvents
            .sorted { $0.startDate < $1.startDate }
            .map(CalendarEventModel.init(ekEvent:))
    }

    /// Convenience: fetch events for a single calendar day in a given timezone.
    func fetchEventsForDay(_ day: Date, timeZone: TimeZone = .current) async -> [CalendarEventModel] {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        guard
            let startOfDay = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: day),
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: day)
        else { return [] }

        return await fetchEvents(from: startOfDay, to: endOfDay)
    }

    // MARK: - Writing

    /// Inserts a zone-aware event into the user's default calendar (parity with Android's
    /// `insertCalendarEvent`). The event's `timeZone` is stamped from `zoneId` so it lands at
    /// the correct wall-clock time for that IANA zone, exactly as on Android.
    ///
    /// Requests write access if needed. `startInstant` is an absolute `Date` (the view layer
    /// is responsible for choosing it); the model never bakes UTC strings.
    ///
    /// - Parameters:
    ///   - title: Event title.
    ///   - startInstant: Absolute start `Date`.
    ///   - durationMinutes: Length in minutes (defaults to ``defaultEventDurationMinutes``).
    ///   - zoneId: IANA zone identifier stamped on the event, e.g. `"Asia/Tokyo"`.
    /// - Returns: ``InsertEventResult/success(eventId:)`` or ``InsertEventResult/failure(reason:)``.
    func insertEvent(
        title: String,
        startInstant: Date,
        durationMinutes: Int = defaultEventDurationMinutes,
        zoneId: String
    ) async -> InsertEventResult {
        guard await requestWriteAccess() else {
            return .failure(reason: "Calendar access is required to add the event.")
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            return .failure(reason: "No calendar is available to add the event.")
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startInstant
        event.endDate = startInstant.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.timeZone = TimeZone(identifier: zoneId) ?? .current
        event.calendar = calendar

        do {
            try store.save(event, span: .thisEvent, commit: true)
            let id = event.eventIdentifier ?? event.calendarItemIdentifier
            return .success(eventId: id)
        } catch {
            return .failure(reason: "Couldn't save the event to your calendar.")
        }
    }
}

// MARK: - CalendarEventModel + EKEvent initialiser

private extension CalendarEventModel {
    /// Converts an `EKEvent` into a `Sendable` domain model.
    /// Must only be called from within the `CalendarRepository` actor.
    init(ekEvent event: EKEvent) {
        // Extract RGBA components from CGColor so the model stays Sendable.
        var colorComponents: [CGFloat]? = nil
        if let cgColor = event.calendar?.cgColor,
           let components = cgColor.components,
           cgColor.numberOfComponents >= 3 {
            colorComponents = Array(components.prefix(4))
        }

        self.init(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "(No Title)",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar?.title ?? "",
            calendarColorComponents: colorComponents,
            notes: event.notes,
            location: event.location,
            hasAttendees: !(event.attendees?.isEmpty ?? true)
        )
    }
}
