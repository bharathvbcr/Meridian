// WatchSyncManager.swift
// Meridian — iOS 27 / Swift 6 (phone side)
//
// Behavioral port of Android `WearSyncManager.kt`. On Android, `syncZones(zones)` pushed a
// `DataMap` of home/second-zone strings over the Wearable Data Layer. Here we push the full
// ordered watchlist plus the next upcoming event to the paired Apple Watch via
// `WCSession.updateApplicationContext`, which keeps only the latest snapshot (perfect for a
// world-clock list + countdown).
//
// Activation + sync wiring (fixes the dead-sync-path regression):
//
//   • `activate(modelContainer:)` is the single entry point the app calls once at launch. It
//     activates the `WCSession` AND subscribes to SwiftData's `ModelContext.didSave`
//     notification on the shared (App-Group-backed) store. Every time the phone persists a zone
//     or task change — from any context: the view-model, interop sync, or a background refresh —
//     the watchlist + next event are re-fetched and pushed to the watch. This mirrors Android,
//     where `WearSyncManager.syncZones` was invoked on every zone mutation, without coupling the
//     watch sync to a specific call site.
//   • The lower-level `activate()` and `sync(zones:tasks:now:)` remain public so callers that
//     already hold the live domain state (e.g. `MainViewModel`) can push a snapshot directly,
//     synchronously, on the main actor.
//
// WatchConnectivity delegate callbacks arrive on a background queue, so the delegate methods
// are `nonisolated`; they hop back to the main actor to mutate shared state and re-send any
// pending snapshot once the session activates.

import Foundation
import SwiftData

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - WatchSyncManager

/// Pushes the phone's world-clock zones and next event to the paired watch.
///
/// `@MainActor`-isolated state (the cached pending payload and activation flag) with
/// `nonisolated` `WCSessionDelegate` conformance, satisfying Swift 6 strict concurrency.
@MainActor
final class WatchSyncManager: NSObject {

    /// Shared singleton, mirroring `SharedZoneStore` / `LiveActivityManager`.
    static let shared = WatchSyncManager()

    /// The most recent payload we attempted to send. Re-sent once the session finishes
    /// activating, or when the watch reachability/installation state changes.
    private var pendingPayload: WatchSyncPayload?

    /// Whether `activate()` has been requested (avoids redundant activations).
    private var didStartActivation = false

    /// The shared store used to re-fetch domain state on every save. Set by
    /// `activate(modelContainer:)`. A fresh `ModelContext` is created per refresh so we never
    /// touch another actor's context.
    private var modelContainer: ModelContainer?

    /// Token for the `ModelContext.didSave` observation, kept alive for the app's lifetime.
    private var didSaveObserver: (any NSObjectProtocol)?

    private override init() {
        super.init()
    }

    deinit {
        if let didSaveObserver {
            NotificationCenter.default.removeObserver(didSaveObserver)
        }
    }

    // MARK: - Activation

    /// Activates the `WCSession` once and wires automatic sync off the shared SwiftData store.
    ///
    /// Call this exactly once during app bootstrap with the App-Group-backed container. After
    /// this, any persisted change to zones or tasks (from the view-model, interop sync, or a
    /// background refresh) automatically pushes a fresh snapshot to the watch — eliminating the
    /// previously dead sync path. An initial snapshot is pushed immediately.
    ///
    /// - Parameter modelContainer: The shared store backing zones and tasks.
    func activate(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        activate()
        observeContextSaves()
        // Push the current state right away so the watch is correct before the first edit.
        syncFromStore()
    }

    /// Activates the `WCSession` once, wiring this object as its delegate. Safe to call
    /// repeatedly. No-op on a device without WatchConnectivity support (e.g. iPad).
    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if !didStartActivation {
            didStartActivation = true
            session.activate()
        }
        #endif
    }

    /// Subscribes to `ModelContext.didSave` on the shared store so every persisted zone/task
    /// change triggers a fresh push to the watch. Idempotent — only installs once.
    ///
    /// We observe with `object: nil` (any context on the process) because the saving context
    /// belongs to other actors (the view-model, interop sync, background refresh) and is not
    /// reachable here; re-fetching from a dedicated context keeps us decoupled from whoever saved.
    private func observeContextSaves() {
        guard didSaveObserver == nil else { return }
        // VERIFY: `ModelContext.didSave` — Notification.Name posted after a successful save
        // (SwiftData, iOS 17+, current on iOS 27). userInfo carries inserted/updated/deleted ids.
        didSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // The notification can be posted from any queue/actor; hop to the main actor to
            // re-fetch and push. `self` is `@MainActor`, so all of `syncFromStore` runs there.
            Task { @MainActor [weak self] in
                self?.syncFromStore()
            }
        }
    }

    /// Re-fetches all zones and tasks from a fresh context off the shared container and pushes
    /// the resulting snapshot. No-op if the container has not been wired via
    /// `activate(modelContainer:)`.
    private func syncFromStore() {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)

        let zoneDescriptor = FetchDescriptor<SavedZone>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        let taskDescriptor = FetchDescriptor<PlannedTask>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        let zones = (try? context.fetch(zoneDescriptor)) ?? []
        let tasks = (try? context.fetch(taskDescriptor)) ?? []
        sync(zones: zones, tasks: tasks)
    }

    // MARK: - Sync (Android `syncZones`)

    /// Builds a snapshot from the current domain state and pushes it to the watch.
    ///
    /// - Parameters:
    ///   - zones: The saved zones, already in `sortOrder`. Mapped to `WatchZone` preserving
    ///     home/order semantics from Android's `home_zone_*` data items.
    ///   - tasks: All planned tasks; the soonest task whose timestamp is `>= now` becomes the
    ///     watch countdown's `nextEvent`.
    ///   - now: The reference instant for "upcoming" (defaults to the live clock).
    func sync(zones: [SavedZone], tasks: [PlannedTask], now: Date = Date()) {
        let watchZones = zones.enumerated().map { index, zone in
            WatchZone(
                id: zone.id,
                tzId: zone.tzId,
                displayName: zone.displayName,
                isHome: zone.isHome,
                orderIndex: zone.sortOrder == 0 ? index : zone.sortOrder
            )
        }

        let nextEvent = tasks
            .filter { $0.timestamp >= now }
            .min { $0.timestamp < $1.timestamp }
            .map { WatchEvent(id: $0.id, title: $0.title, date: $0.timestamp, tzId: $0.tzId) }

        let payload = WatchSyncPayload(
            zones: watchZones,
            nextEvent: nextEvent,
            updatedAt: now
        )

        send(payload)
    }

    /// Encodes and transmits a payload via `updateApplicationContext`, caching it so it can be
    /// re-sent once the session is active. No-op (but still cached) when WatchConnectivity is
    /// unsupported or the session is not yet activated.
    private func send(_ payload: WatchSyncPayload) {
        pendingPayload = payload

        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        // Only the latest context survives, so we don't need to gate on reachability — the
        // watch will pick it up on next launch. We do require an activated session.
        guard session.activationState == .activated else {
            activate()
            return
        }

        // There must be a watch paired with the app installed to bother sending.
        guard session.isPaired, session.isWatchAppInstalled else { return }

        do {
            let context = try WatchSyncEncoding.encode(payload)
            try session.updateApplicationContext(context)
            pendingPayload = nil
        } catch {
            // Keep `pendingPayload` for a retry on the next state change. `updateApplicationContext`
            // throws if called before activation or with non-plist values; our encoding is plist-safe.
            #if DEBUG
            print("[WatchSyncManager] updateApplicationContext failed: \(error)")
            #endif
        }
        #endif
    }

    /// Re-sends the last cached payload, if any (called after activation / state changes).
    private func flushPending() {
        guard let payload = pendingPayload else { return }
        send(payload)
    }
}

// MARK: - WCSessionDelegate

#if canImport(WatchConnectivity)
extension WatchSyncManager: WCSessionDelegate {

    // Delegate callbacks arrive off the main actor; hop back before touching isolated state.

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor in
            if activationState == .activated {
                self.flushPending()
            }
        }
    }

    // The watch may be unpaired/repaired; the phone session must be deactivated then
    // reactivated to bind to the new device. Required on iOS.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate to support switching to a new paired watch.
        session.activate()
    }

    // Watch app was installed/uninstalled or pairing changed — try to deliver any pending snapshot.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.flushPending()
        }
    }
}
#endif
