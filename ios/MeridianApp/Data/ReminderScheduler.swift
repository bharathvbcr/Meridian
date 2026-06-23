// ReminderScheduler.swift
// Meridian — iOS 27 / Swift 6
//
// Schedules and cancels local notifications for event reminders (§5.7). Direct
// port of the Android `ReminderScheduler` + `ReminderReceiver` pipeline:
//
//   triggerAt = task.timestamp - reminderLeadMinutes
//   if triggerAt <= now          -> skip (event/lead already passed)
//   if reminderLeadMinutes < 0   -> skip (reminders disabled)
//
// Each request is keyed by the task id so re-scheduling replaces the previous
// reminder (Android's FLAG_UPDATE_CURRENT) and cancellation is exact.
//
// On iOS the alarm + the "post notification" step from `ReminderReceiver` collapse
// into a single scheduled `UNNotificationRequest`: the system posts it at the
// trigger date with the deep link + content the receiver used to build.

import Foundation
import UserNotifications

/// Schedules per-task local notifications via `UNUserNotificationCenter`.
///
/// `@MainActor` to match the view model that drives it and the process-wide
/// notification center; all work is `async`.
@MainActor
final class ReminderScheduler {

    // MARK: Singleton

    static let shared = ReminderScheduler()

    // MARK: Dependencies

    private let center: UNUserNotificationCenter
    private let service: NotificationService
    private let settingsRepository: SettingsRepository

    /// Override-able clock for testability (mirrors `System.currentTimeMillis()`).
    private let now: () -> Date

    /// Returns `true` when the peer (ChronosFlow) is the active notifier. Mirrors
    /// Android `ReminderScheduler`'s `isPeerNotifier: () -> Boolean` dependency
    /// (backed by `InteropClient.isPeerShareAvailable()`): consulted on EVERY
    /// `schedule(_:)` call so Meridian never arms a reminder while the peer owns
    /// notifications — preserving the "exactly one notifier" invariant on the
    /// in-app add/edit path, not just during interop sync reconciliation.
    private let isPeerNotifier: () -> Bool

    init(
        center: UNUserNotificationCenter = .current(),
        service: NotificationService = .shared,
        settingsRepository: SettingsRepository = .shared,
        now: @escaping () -> Date = { Date() },
        isPeerNotifier: @escaping () -> Bool = { InteropClient().isPeerShareAvailable() }
    ) {
        self.center = center
        self.service = service
        self.settingsRepository = settingsRepository
        self.now = now
        self.isPeerNotifier = isPeerNotifier
    }

    // MARK: - Request identifier

    /// Notification request identifier for a task. Stable + 1:1 with the task id so
    /// re-scheduling replaces and `cancel(id:)` removes exactly one request.
    private func requestId(for taskId: String) -> String {
        "meridian.reminder.\(taskId)"
    }

    // MARK: - Schedule

    /// Schedules (or replaces) the reminder for `task`.
    ///
    /// Behaviour mirrors Android exactly:
    /// - `reminderLeadMinutes < 0` disables reminders → cancels any existing one.
    /// - The trigger fires at `timestamp - leadMinutes`; if that instant is in the
    ///   past the reminder is skipped (and any stale one is cancelled).
    /// - Requesting authorization is a no-op once already granted/denied.
    func schedule(_ task: PlannedTask) async {
        // Peer-notifier guard (Android ReminderScheduler.kt:33-36): if ChronosFlow is
        // the active notifier, Meridian must not arm a reminder — cancel any existing
        // one and return before computing the trigger. Runs on EVERY schedule call
        // (including the in-app add/edit path) to keep the "exactly one notifier"
        // invariant without waiting for the next interop sync pass.
        if isPeerNotifier() {
            cancel(id: task.id)
            return
        }

        let leadMinutes = settingsRepository.settings.reminderLeadMinutes

        // Negative lead means reminders are disabled (Android parity).
        guard leadMinutes >= 0 else {
            cancel(id: task.id)
            return
        }

        let leadInterval = TimeInterval(leadMinutes * 60)
        let triggerDate = task.timestamp.addingTimeInterval(-leadInterval)

        // Skip past triggers; clear any previously scheduled reminder for this id.
        guard triggerDate > now() else {
            cancel(id: task.id)
            return
        }

        // Ensure permission + categories are configured before adding the request.
        let authorized = await service.requestAuthorizationIfNeeded()
        guard authorized else { return }

        let content = makeContent(for: task)
        let trigger = makeTrigger(at: triggerDate)
        let request = UNNotificationRequest(
            identifier: requestId(for: task.id),
            content: content,
            trigger: trigger
        )

        // Replace any existing request with the same id, then add.
        center.removePendingNotificationRequests(withIdentifiers: [requestId(for: task.id)])
        do {
            try await center.add(request)
        } catch {
            // Degrade gracefully — mirrors Android swallowing SecurityException.
        }
    }

    // MARK: - Cancel

    /// Cancels the reminder for `id`, if any (pending and already-delivered).
    ///
    /// Main-actor isolated (inherits the class isolation): the body touches
    /// `requestId(for:)` and `self.center`, both main-actor-isolated. Both callers
    /// (`MainViewModel.deleteTask`, `InteropSyncManager.reconcileOwnReminders`,
    /// and `schedule(_:)` above) already run on the main actor, so no `nonisolated`
    /// entry point is needed.
    func cancel(id: String) {
        let rid = requestId(for: id)
        center.removePendingNotificationRequests(withIdentifiers: [rid])
        center.removeDeliveredNotifications(withIdentifiers: [rid])
    }

    // MARK: - Content (mirrors ReminderReceiver)

    /// Builds the notification content the way Android's `ReminderReceiver` built
    /// its `NotificationCompat` post: title = task title, body = "Starts <time> (<zone>)",
    /// reminder category, and a `meridian://plan` deep link in `userInfo`.
    private func makeContent(for task: PlannedTask) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = task.title.isEmpty ? "Upcoming event" : task.title
        content.body = Self.buildWhen(date: task.timestamp, zoneId: task.tzId)
        content.sound = .default
        content.categoryIdentifier = NotificationService.Identifiers.reminderCategory
        content.userInfo = [
            NotificationService.Identifiers.keyTitle: task.title,
            NotificationService.Identifiers.keyZone: task.tzId,
            NotificationService.Identifiers.keyTime: task.timestamp.timeIntervalSince1970,
            NotificationService.Identifiers.keyId: task.id,
            NotificationService.Identifiers.keyDeepLink:
                NotificationService.reminderDeepLink.absoluteString,
        ]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        return content
    }

    /// Exact wall-clock trigger at `date`. A calendar trigger (down to the second)
    /// is iOS's closest analogue to Android's `setExactAndAllowWhileIdle`.
    private func makeTrigger(at date: Date) -> UNCalendarNotificationTrigger {
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    /// "Starts 9:05 AM, Tue Jun 24 (America/New_York)" — mirrors
    /// `ReminderReceiver.buildWhen` (pattern "h:mm a, EEE MMM d").
    private static func buildWhen(date: Date, zoneId: String) -> String {
        let tz = TimeFormats.safeTimeZone(id: zoneId)
        // Date.FormatStyle is Sendable (preferred over DateFormatter per contract).
        // VERIFY: fluent Symbol builders are stable since iOS 15; amPM:.abbreviated valid on iOS 27.
        let style = Date.FormatStyle(date: .omitted, time: .omitted, timeZone: tz)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day(.defaultDigits)
        return "Starts \(date.formatted(style)) (\(tz.identifier))"
    }
}
