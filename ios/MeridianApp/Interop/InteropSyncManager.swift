// InteropSyncManager.swift
// Meridian — iOS 27 / Swift 6
//
// Pulls ChronosFlow's tasks + calendar events out of the shared App Group container
// and mirrors them into Meridian's `PlannedTask`s. Direct port of Android's
// `InteropSyncManager`, driven on `scenePhase == .active` instead of a one-shot
// background sync.
//
// Idempotent imports: each upstream row maps to a stable `PlannedTask.externalId`
// ("task:<id>" / "event:<id>"), so repeated syncs update in place rather than
// duplicating. Rows that vanish upstream are pruned. Imported rows carry
// `origin == InteropContract.importOrigin` (the peer's bundle id), which the
// exporter excludes from sharing, so data never echoes back and forth.
//
// Reminder reconciliation: when ChronosFlow is connected it becomes the sole
// notifier, so Meridian cancels its own task reminders; when ChronosFlow is gone,
// Meridian (re)schedules them so notifications still fire — exactly one app notifies
// for any given task.

import Foundation
import SwiftData
import os

/// Orchestrates a single peer-import pass + reminder reconciliation.
///
/// `@MainActor`: it touches SwiftData (via ``TaskInteropRepository``) and the
/// `@MainActor` ``ReminderScheduler``.
@MainActor
final class InteropSyncManager {

    private let log = Logger(subsystem: "com.example.meridian", category: "Interop")

    private let client: InteropClient
    private let repository: TaskInteropRepository
    private let reminderScheduler: ReminderScheduler
    /// System IANA zone id used when a peer row has no timezone (Android `systemZoneId`).
    private let systemZoneId: @Sendable () -> String

    /// Origin tag for imported rows (Android `private val origin = CHRONOSFLOW`).
    private let origin = InteropContract.importOrigin

    init(
        client: InteropClient = InteropClient(),
        repository: TaskInteropRepository,
        reminderScheduler: ReminderScheduler = .shared,
        systemZoneId: @escaping @Sendable () -> String = { TimeZone.current.identifier }
    ) {
        self.client = client
        self.repository = repository
        self.reminderScheduler = reminderScheduler
        self.systemZoneId = systemZoneId
    }

    // MARK: - Sync (Android: syncFromPeer)

    /// Reads the peer snapshot and reconciles imports + reminders. Call on
    /// `scenePhase == .active`. Never throws — degrades to standalone on any failure
    /// (Android wrapped the whole body in try/catch).
    func syncFromPeer() async {
        do {
            await reconcileOwnReminders()

            // If the peer hasn't published a snapshot, do nothing — and deliberately
            // leave any previously imported rows untouched, so a transient
            // uninstall/reinstall (or a not-yet-written snapshot) doesn't churn the
            // mirror. When the peer IS present but shares nothing, the prune below
            // removes stale rows. (Android: `if (!client.isPeerInstalled()) return`.)
            guard client.isPeerInstalled() else {
                log.info("Interop: peer not present — skipping sync, keeping existing imports.")
                return
            }

            let tasks = client.fetchPeerTasks()
            let events = client.fetchPeerEvents()

            var keep: [String] = []

            for t in tasks {
                // A Meridian planned task needs a time; skip undated peer tasks.
                guard let due = t.dueAt else { continue }
                let externalId = InteropContract.taskExternalId(t.externalId)
                try upsert(externalId: externalId, title: t.title, timestamp: due, timezone: t.timezone)
                keep.append(externalId)
            }
            for e in events {
                let externalId = InteropContract.eventExternalId(e.externalId)
                try upsert(externalId: externalId, title: e.title, timestamp: e.startAt, timezone: e.timezone)
                keep.append(externalId)
            }

            if keep.isEmpty {
                try repository.deleteAllImported(origin: origin)
            } else {
                try repository.deleteImported(origin: origin, notIn: keep)
            }
            try repository.save()
            log.info("Interop sync from peer: \(keep.count) item(s) mirrored.")
        } catch {
            log.warning("Interop sync failed (continuing standalone): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reminder reconciliation (Android: reconcileOwnReminders)

    /// Cancels Meridian's own task reminders when the peer is the active notifier, or
    /// (re)schedules them when it isn't — so exactly one app reminds for any task.
    /// Only locally-authored tasks are touched; imported rows are the peer's
    /// responsibility.
    private func reconcileOwnReminders() async {
        let peerNotifier = client.isPeerShareAvailable()
        let nativeTasks: [PlannedTask]
        do {
            nativeTasks = try repository.nativeTasks()
        } catch {
            log.warning("Interop: could not load native tasks for reminder reconciliation: \(error.localizedDescription, privacy: .public)")
            return
        }
        for task in nativeTasks {
            if peerNotifier {
                reminderScheduler.cancel(id: task.id)
            } else {
                // Snapshot Sendable fields and schedule (ReminderScheduler is async).
                let detached = PlannedTask(
                    id: task.id,
                    title: task.title,
                    timestamp: task.timestamp,
                    tzId: task.tzId
                )
                await reminderScheduler.schedule(detached)
            }
        }
    }

    // MARK: - Upsert (Android: upsert)

    private func upsert(externalId: String, title: String, timestamp: Date, timezone: String?) throws {
        let zone = timezone?.trimmingCharacters(in: .whitespaces).nilIfBlank ?? systemZoneId()
        let resolvedTitle = title.trimmingCharacters(in: .whitespaces).nilIfBlank ?? "(untitled)"
        try repository.upsertImported(
            externalId: externalId,
            title: resolvedTitle,
            timestamp: timestamp,
            tzId: zone,
            origin: origin
        )
    }
}

// MARK: - String helper

private extension String {
    /// `nil` when the string is empty/blank, else `self`. (Android `ifBlank` / `takeIf { isNotBlank() }`.)
    var nilIfBlank: String? { isEmpty ? nil : self }
}
