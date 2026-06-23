// PermissionsManager.swift
// Meridian — iOS 27 / Swift 6, strict concurrency
//
// Unified, observable view of every runtime permission the app uses: notifications,
// calendar, contacts, and location. Each domain repository owns the actual request
// (so EKEventStore / CNContactStore never leave their actors); this manager only
// surfaces *status* and routes request calls to the right place for the settings UI.

import Contacts
import CoreLocation
import EventKit
import Foundation
import Observation
import UserNotifications

// MARK: - PermissionState

/// Normalized, framework-agnostic permission state for the UI.
enum PermissionState: Sendable {
    case notDetermined
    case granted
    case denied
    /// Partial access (e.g. limited contacts / write-only calendar / provisional notifications).
    case limited

    /// `true` when the app can perform its primary action for this domain.
    var isUsable: Bool {
        self == .granted || self == .limited
    }
}

// MARK: - PermissionsSnapshot

/// Immutable snapshot of all four permission states at a moment in time.
struct PermissionsSnapshot: Sendable, Equatable {
    var notifications: PermissionState = .notDetermined
    var calendar: PermissionState = .notDetermined
    var contacts: PermissionState = .notDetermined
    var location: PermissionState = .notDetermined
}

// MARK: - PermissionsManager

/// Observable aggregator the settings / onboarding screens bind to.
///
/// `@MainActor` so SwiftUI can observe it directly; the underlying status reads are cheap
/// and main-safe. Requests are delegated to the owning repositories where required.
@MainActor
@Observable
final class PermissionsManager {

    static let shared = PermissionsManager()

    /// Latest known states. Call ``refresh()`` to re-poll the system.
    private(set) var snapshot = PermissionsSnapshot()

    private let calendarRepository: CalendarRepository
    private let contactsRepository: ContactsRepository
    private let locationResolver: LocationZoneResolver

    init(
        calendarRepository: CalendarRepository = CalendarRepository(),
        contactsRepository: ContactsRepository = ContactsRepository(),
        locationResolver: LocationZoneResolver = LocationZoneResolver()
    ) {
        self.calendarRepository = calendarRepository
        self.contactsRepository = contactsRepository
        self.locationResolver = locationResolver
    }

    // MARK: - Refresh

    /// Re-reads all four statuses without prompting and updates ``snapshot``.
    func refresh() async {
        async let notifications = notificationState()
        let calendar = Self.calendarState(EKEventStore.authorizationStatus(for: .event))
        let contacts = Self.contactsState(CNContactStore.authorizationStatus(for: .contacts))
        let location = Self.locationState(locationResolver.authStatus)

        snapshot = PermissionsSnapshot(
            notifications: await notifications,
            calendar: calendar,
            contacts: contacts,
            location: location
        )
    }

    // MARK: - Requests

    /// Requests notification authorization (alert + sound + badge), then refreshes.
    @discardableResult
    func requestNotifications() async -> PermissionState {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        let state = await notificationState()
        snapshot.notifications = state
        return granted ? state : .denied
    }

    /// Requests full calendar access via the calendar repository, then refreshes.
    @discardableResult
    func requestCalendar() async -> PermissionState {
        let granted = await calendarRepository.requestAccess()
        let state = Self.calendarState(EKEventStore.authorizationStatus(for: .event))
        snapshot.calendar = state
        return granted ? state : .denied
    }

    /// Requests contacts access via the contacts repository, then refreshes.
    @discardableResult
    func requestContacts() async -> PermissionState {
        let granted = await contactsRepository.requestAccess()
        let state = Self.contactsState(CNContactStore.authorizationStatus(for: .contacts))
        snapshot.contacts = state
        return granted ? state : .denied
    }

    /// Requests when-in-use location authorization via the resolver, then refreshes.
    @discardableResult
    func requestLocation() async -> PermissionState {
        let status = await locationResolver.requestAuthorization()
        let state: PermissionState
        switch status {
        case .authorized:    state = .granted
        case .denied:        state = .denied
        case .notDetermined: state = .notDetermined
        }
        snapshot.location = state
        return state
    }

    // MARK: - Mapping helpers

    private func notificationState() async -> PermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .granted
        case .provisional, .ephemeral:
            return .limited
        @unknown default:
            return .denied
        }
    }

    private static func calendarState(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .fullAccess:
            return .granted
        case .writeOnly:
            return .limited
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private static func contactsState(_ status: CNAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .granted
        case .limited:
            return .limited
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private static func locationState(_ status: LocationAuthStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized:    return .granted
        case .denied:        return .denied
        }
    }
}
