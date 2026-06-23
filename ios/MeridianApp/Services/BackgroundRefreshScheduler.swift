import Foundation
import BackgroundTasks
import os

/// Schedules periodic background work to keep the EventCountdown Live Activity in sync — the iOS
/// analogue of Android's 15-minute `PeriodicWork` (`LiveUpdates.schedulePeriodic` driving
/// `CountdownWorker`, §5.7).
///
/// iOS does not allow exact 15-minute periodic background execution; instead we register a
/// `BGAppRefreshTask` and re-submit it (with a ~15-minute earliest-begin hint) each time it runs.
/// The system coalesces and throttles these based on usage. When the task fires, it re-evaluates
/// which event is "next" and reconciles the Live Activity. The visible countdown itself ticks via
/// the system `Text(timerInterval:)` clock, so missed refreshes do not freeze the display.
@MainActor
final class BackgroundRefreshScheduler {

    static let shared = BackgroundRefreshScheduler()

    /// BGTaskScheduler identifier. Must also be listed under `BGTaskSchedulerPermittedIdentifiers`
    /// in the app's Info.plist.
    static let refreshTaskIdentifier = "com.example.meridian.liveactivity.refresh"

    /// Mirrors Android's 15-minute `PeriodicWorkRequest` cadence (best-effort earliest start).
    static let refreshInterval: TimeInterval = 15 * 60

    private let log = Logger(subsystem: "com.example.meridian", category: "BGRefresh")

    /// Closure invoked when the background task runs (and may be reused for on-demand refreshes).
    /// Supplied by the app at launch; performs the actual Live Activity reconciliation.
    private var refreshHandler: (@MainActor @Sendable () async -> Void)?

    private init() {}

    // MARK: - Registration

    /// Register the background task handler. Call once, during app launch, **before** the app
    /// finishes launching (per `BGTaskScheduler` requirements).
    ///
    /// - Parameter handler: async work to perform on each refresh (typically reconciling the
    ///   Live Activity against current tasks).
    func register(handler: @escaping @MainActor @Sendable () async -> Void) {
        refreshHandler = handler
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            // BGTaskScheduler delivers on the main queue; hop to the main actor explicitly.
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await BackgroundRefreshScheduler.shared.handle(appRefreshTask)
            }
        }
    }

    // MARK: - Scheduling

    /// Submit (or re-submit) the next background refresh. Call after registration, on app
    /// background, and at the end of each refresh to keep the chain alive. Mirrors the "enqueue
    /// unique periodic work" semantics — re-submitting simply replaces the pending request.
    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            log.debug("Scheduled background refresh")
        } catch {
            // Throws under test / on Simulator / when the entitlement is missing — degrade gracefully,
            // matching Android's defensive `runCatching` around WorkManager.
            log.error("Failed to schedule background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Run the refresh handler immediately (analogue of `LiveUpdates.refreshNow`), e.g. right after a
    /// task is added/deleted. Does not affect the scheduled background chain.
    func refreshNow() async {
        await refreshHandler?()
    }

    // MARK: - Task handling

    private func handle(_ task: BGAppRefreshTask) async {
        // Re-arm the chain first so a failure mid-work still leaves a pending request.
        schedule()

        let work = Task { @MainActor in
            await refreshHandler?()
        }

        task.expirationHandler = {
            work.cancel()
        }

        await work.value
        task.setTaskCompleted(success: true)
    }
}
