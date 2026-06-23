// InteropExporter.swift
// Meridian — iOS 27 / Swift 6
//
// Publishes Meridian's shareable data into the SHARED App Group container for the
// peer (ChronosFlow) to read. This is the iOS replacement for Android's read-only
// `InteropProvider`: instead of serving cursors on demand, we serialize an
// `InteropSnapshot` and write it atomically whenever our data changes (and on
// scenePhase changes), and the peer reads that file at its leisure.
//
// Parity with Android's provider rules:
//   * Only SELF-AUTHORED rows are shared: planned tasks with `origin == nil`
//     (Android `WHERE origin IS NULL`). Imported copies are never re-shared, so
//     data never echoes back and forth.
//   * Meridian owns tasks, zones and people; events/habits/medications/goals are
//     left empty (Android served empty cursors for types it doesn't own — here they
//     are simply empty arrays in the snapshot).

import Foundation
import os

/// Serializes Meridian's shareable data to the App Group container for peers.
///
/// `@MainActor` because it reads SwiftData via ``TaskInteropRepository`` (which holds
/// a non-`Sendable` `ModelContext`).
@MainActor
struct InteropExporter {

    private let log = Logger(subsystem: "com.example.meridian", category: "Interop")

    private let repository: TaskInteropRepository
    private let fileManager: FileManager

    init(repository: TaskInteropRepository, fileManager: FileManager = .default) {
        self.repository = repository
        self.fileManager = fileManager
    }

    // MARK: - Export

    /// Builds and atomically writes our snapshot into the shared container. No-op
    /// when the App Group is unavailable (Android: provider simply never queried).
    func exportSnapshot() {
        guard PeerVerifier.mayExport() else {
            log.debug("Interop: shared container unavailable — skipping export.")
            return
        }
        guard let url = ownSnapshotURL() else { return }

        let snapshot: InteropSnapshot
        do {
            snapshot = try buildSnapshot()
        } catch {
            log.error("Interop: failed to build snapshot: \(error.localizedDescription, privacy: .public)")
            return
        }

        do {
            let data = try InteropCoders.encoder.encode(snapshot)
            // Atomic write so a peer never reads a half-written file.
            try data.write(to: url, options: [.atomic])
            log.info("Interop: exported \(snapshot.tasks.count) task(s), \(snapshot.zones.count) zone(s), \(snapshot.people.count) person(s).")
        } catch {
            log.error("Interop: failed to write snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Snapshot assembly (Android: tasksCursor / zonesCursor / peopleCursor)

    private func buildSnapshot() throws -> InteropSnapshot {
        // Tasks: self-authored only (origin IS NULL), in display order.
        let tasks = try repository.nativeTasks().map { task in
            InteropTask(
                externalId: task.id,         // Android served the row id as external_id
                title: task.title,
                notes: nil,                  // Android served notes = null
                dueAt: task.timestamp,       // Android due_at (absolute instant)
                isCompleted: false,          // Android is_completed = 0
                priority: nil,               // Android priority = null
                timezone: task.tzId,         // Android timezone (IANA id)
                updatedAt: task.timestamp    // Android updated_at = timestamp
            )
        }

        // Zones: all saved zones, external_id == zone_id == IANA id.
        let zones = try repository.sharableZones().map { zone in
            InteropZone(
                externalId: zone.id,
                zoneId: zone.id,
                displayName: zone.displayName,
                isHome: zone.isHome
            )
        }

        // People: external_id == stable person id (UUID string).
        let people = try repository.sharablePeople().map { person in
            InteropPerson(
                externalId: person.id.uuidString,
                name: person.name,
                zoneId: person.tzId,
                locationName: person.displayName.isEmpty ? nil : person.displayName,
                workStartHour: person.workStartHour,
                workEndHour: person.workEndHour
            )
        }

        return InteropSnapshot(
            version: InteropSnapshot.currentVersion,
            authorBundleId: InteropContract.selfBundleId,
            updatedAt: Date(),
            tasks: tasks,
            events: [],   // Meridian does not own shareable events.
            zones: zones,
            people: people
        )
    }

    // MARK: - Paths

    private func ownSnapshotURL() -> URL? {
        PeerVerifier.sharedContainerURL()?
            .appendingPathComponent(InteropContract.SnapshotFile.own, isDirectory: false)
    }
}
