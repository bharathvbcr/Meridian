import Foundation
import ActivityKit
import os

/// Drives the EventCountdown Live Activity — the iOS analogue of Android's `CountdownWorker` /
/// `LiveUpdates` ongoing countdown notification (§5.7).
///
/// Behavior parity with Android:
/// - Show a live countdown only when the next upcoming event is within a 24h window
///   (`liveWindow`, == Android `LIVE_WINDOW_MILLIS`).
/// - Keep exactly one activity alive, matched to the soonest future task.
/// - End the activity once the event passes or no task qualifies.
///
/// iOS improvement: instead of polling every 15 minutes to re-render a countdown string, the
/// Live Activity uses the system `Text(timerInterval:)` clock, so the visible countdown ticks on its
/// own. Background refresh (`BackgroundRefreshScheduler`) only needs to re-evaluate which event is next.
@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    /// Window before an event during which the live countdown is shown — matches Android
    /// `Reminders.LIVE_WINDOW_MILLIS` (24h).
    static let liveWindow: TimeInterval = 24 * 60 * 60

    private let log = Logger(subsystem: "com.example.meridian", category: "LiveActivity")

    /// The currently running activity, if any.
    private var currentActivity: Activity<EventCountdownAttributes>?
    /// The task id backing `currentActivity`, used to detect when the "next" event changes.
    private var currentTaskId: String?

    private init() {}

    // MARK: - Public API

    /// Reconcile the Live Activity against the full set of planned tasks.
    ///
    /// Picks the soonest future task; if it falls within `liveWindow` it starts or updates the
    /// activity, otherwise it ends any running activity. Safe to call repeatedly (idempotent).
    ///
    /// - Parameters:
    ///   - tasks: candidate events. Each tuple is the task's stable id, title, and start instant.
    ///   - now: injectable clock for testing; defaults to the current instant.
    func reconcile(tasks: [(id: String, title: String, date: Date)], now: Date = Date()) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Activities disabled by the user/system — tear down anything we may have left running.
            await endCurrent()
            return
        }

        let next = tasks
            .filter { $0.date > now }
            .min { $0.date < $1.date }

        guard let next, next.date.timeIntervalSince(now) <= Self.liveWindow else {
            await endCurrent()
            return
        }

        if currentTaskId == next.id, let activity = currentActivity {
            await update(activity, title: next.title, date: next.date)
        } else {
            // The next event changed (or none was running): end the old one and start fresh.
            await endCurrent()
            await start(taskId: next.id, title: next.title, date: next.date)
        }
    }

    /// Force-end the live countdown (e.g. when the last task is deleted).
    func end() async {
        await endCurrent()
    }

    // MARK: - Lifecycle

    private func start(taskId: String, title: String, date: Date) async {
        let attributes = EventCountdownAttributes(taskId: taskId)
        let state = EventCountdownAttributes.ContentState(eventTitle: title, eventDate: date)
        let content = ActivityContent(state: state, staleDate: date)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            currentTaskId = taskId
            log.debug("Started live activity for task \(taskId, privacy: .public)")
        } catch {
            log.error("Failed to start live activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func update(_ activity: Activity<EventCountdownAttributes>, title: String, date: Date) async {
        let state = EventCountdownAttributes.ContentState(eventTitle: title, eventDate: date)
        let content = ActivityContent(state: state, staleDate: date)
        await activity.update(content)
    }

    private func endCurrent() async {
        // End any tracked activity, plus defensively any orphaned activities (e.g. after a relaunch).
        if let activity = currentActivity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for activity in Activity<EventCountdownAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        currentTaskId = nil
    }
}
