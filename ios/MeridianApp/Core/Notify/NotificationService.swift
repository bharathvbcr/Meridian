// NotificationService.swift
// Meridian — iOS 27 / Swift 6
//
// One-time authorization + notification category registration for the reminder
// pipeline (§5.7). Ports the Android channel/category model from `Reminders.kt`
// and `ReminderReceiver.kt`:
//   - "meridian_reminders" channel  -> `Category.reminder`
//   - "meridian_live" channel       -> `Category.liveCountdown`
// Tapping a reminder deep-links into the planner (meridian://plan), exactly as the
// Android `ReminderReceiver` builds its `meridian://plan` tap intent.

import Foundation
import UserNotifications

/// Centralized owner of notification permission and category configuration.
///
/// `@MainActor` because it touches process-wide UNUserNotificationCenter state and
/// is consumed from SwiftUI / the @MainActor view model. All async work is awaited.
@MainActor
final class NotificationService {

    // MARK: Singleton

    static let shared = NotificationService()

    // MARK: Constants (mirror Reminders.kt)

    /// Stable identifiers shared with `ReminderScheduler` and `NotificationDelegate`.
    enum Identifiers {
        /// One-time event reminder (fires at `timestamp - leadMinutes`).
        static let reminderCategory = "meridian_reminders"
        /// Ongoing pre-event countdown (Live Activity companion).
        static let liveCountdownCategory = "meridian_live"

        /// userInfo keys carried on a reminder (mirror Reminders.EXTRA_*).
        static let keyTitle = "extra_title"
        static let keyZone  = "extra_zone"
        static let keyTime  = "extra_time"
        static let keyId    = "extra_id"
        /// Deep-link URL the tap should route to.
        static let keyDeepLink = "extra_deeplink"
    }

    /// Deep link target tapping a reminder routes to (matches Android `meridian://plan`).
    static let reminderDeepLink = URL(string: "meridian://plan")!

    // MARK: Private state

    private let center = UNUserNotificationCenter.current()
    private var didConfigure = false

    private init() {}

    // MARK: - Authorization

    /// Requests notification authorization exactly once per launch and ensures the
    /// reminder/live-countdown categories are registered. Safe to call repeatedly;
    /// the underlying request is idempotent and the OS coalesces it.
    ///
    /// - Returns: `true` if notifications are authorized (or provisionally so).
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        configureCategoriesIfNeeded()

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await requestAuthorization()
        @unknown default:
            return await requestAuthorization()
        }
    }

    /// Performs the actual authorization prompt. Mirrors Android's runtime
    /// POST_NOTIFICATIONS request; failures degrade gracefully to `false`.
    private func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Current authorization status without prompting.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Category registration

    /// Registers the reminder + live-countdown categories once. Both are simple
    /// tap-to-open categories on iOS; the Android side distinguishes them only by
    /// channel, so no custom actions are required for behavioral parity.
    func configureCategoriesIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        let reminder = UNNotificationCategory(
            identifier: Identifiers.reminderCategory,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let liveCountdown = UNNotificationCategory(
            identifier: Identifiers.liveCountdownCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([reminder, liveCountdown])
    }

    /// Installs the foreground/tap delegate. Call once at launch (e.g. from the
    /// app's init / `onAppear`). Idempotent.
    func installDelegate(_ delegate: NotificationDelegate) {
        configureCategoriesIfNeeded()
        center.delegate = delegate
    }
}
