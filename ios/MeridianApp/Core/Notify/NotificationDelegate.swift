// NotificationDelegate.swift
// Meridian — iOS 27 / Swift 6
//
// UNUserNotificationCenterDelegate implementing:
//   - foreground presentation (banner + sound while the app is active), and
//   - tap routing to the meridian:// deep link.
//
// This is the iOS analogue of Android's `ReminderReceiver` tap-intent
// (`PendingIntent.getActivity(... meridian://plan ...)`): tapping a reminder
// deep-links into the planner. Routing is surfaced through `onDeepLink`, which the
// app wires to the same handler used for incoming `onOpenURL` events.

import Foundation
import UserNotifications

/// Bridges UNUserNotificationCenter callbacks into SwiftUI. The actual navigation
/// is delegated to `onDeepLink`, which the app sets to its URL router so that taps
/// and external `meridian://` links share one code path.
///
/// `NSObject` subclass (required by the delegate protocol) and `@MainActor` because
/// the callbacks fire on the main queue and it mutates UI-facing routing state.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Invoked with the deep-link URL when the user taps a reminder. Wire this to
    /// the same router used by `View.onOpenURL`. Set on the main actor at launch.
    var onDeepLink: (@MainActor (URL) -> Void)?

    // MARK: - Foreground presentation

    /// Presents reminders while the app is in the foreground (banner + sound),
    /// mirroring the high-priority Android channel behaviour.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // VERIFY: `.banner`/`.list` available since iOS 14; current on iOS 27.
        [.banner, .list, .sound]
    }

    // MARK: - Tap handling

    /// Routes a tapped reminder to its deep link. Prefers an explicit URL stored in
    /// `userInfo` (so per-task targets are possible); falls back to the canonical
    /// planner link, matching Android's fixed `meridian://plan` tap intent.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Ignore explicit dismiss actions — only act on a real tap / default action.
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }

        let userInfo = response.notification.request.content.userInfo
        let url = (userInfo[NotificationService.Identifiers.keyDeepLink] as? String)
            .flatMap(URL.init(string:))
            ?? NotificationService.reminderDeepLink

        await routeOnMain(url)
    }

    /// Hops to the main actor to invoke the deep-link handler. The delegate methods
    /// are `nonisolated async` (per the protocol's Sendable requirements), so the
    /// actual UI mutation is funnelled through the main actor here.
    private func routeOnMain(_ url: URL) async {
        await MainActor.run {
            self.onDeepLink?(url)
        }
    }
}
