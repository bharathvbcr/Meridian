// TaskInteropRepository.swift
// Meridian — iOS 27 / Swift 6
//
// SwiftData-backed data access for the interop layer — the iOS replacement for the
// subset of Android's Room `TaskDao` that `InteropSyncManager` and `InteropProvider`
// relied on:
//
//   getNativeTasksOnce()         -> locally-authored tasks (origin IS NULL)
//   getImportedId(origin, ext)   -> existing row id for an import, or nil
//   insertTask(task)             -> upsert (insert or update-in-place)
//   deleteImportedNotIn(origin,) -> prune imports whose externalId vanished upstream
//   deleteAllImported(origin)    -> prune all imports for an origin
//   nativeTasks/zones/people     -> source rows for the exporter (origin IS NULL)
//
// All access is funnelled through a `ModelContext`, so this type is `@MainActor`
// (SwiftData `ModelContext` is not `Sendable`) and matches the actor of the view
// model / reminder scheduler that drive sync.

import Foundation
import SwiftData

/// Repository over `PlannedTask` (+ read-only `SavedZone` / `Person`) for the interop
/// pipeline. Confined to the main actor because it holds a `ModelContext`.
@MainActor
struct TaskInteropRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Native tasks (Android: getNativeTasksOnce — origin IS NULL)

    /// Locally-authored tasks (never imported). Android served only these from the
    /// provider and reconciled reminders only for these.
    func nativeTasks() throws -> [PlannedTask] {
        let descriptor = FetchDescriptor<PlannedTask>(
            predicate: #Predicate { $0.origin == nil },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Imported tasks (Android: import upsert helpers)

    /// All tasks imported from `origin`.
    func importedTasks(origin: String) throws -> [PlannedTask] {
        let descriptor = FetchDescriptor<PlannedTask>(
            predicate: #Predicate { $0.origin == origin }
        )
        return try context.fetch(descriptor)
    }

    /// The persistent `id` of the imported row matching `(origin, externalId)`, or
    /// `nil` if none exists. (Android `getImportedId`.) Used so upserts update the
    /// existing row in place rather than duplicating.
    func importedId(origin: String, externalId: String) throws -> String? {
        var descriptor = FetchDescriptor<PlannedTask>(
            predicate: #Predicate { $0.origin == origin && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.id
    }

    /// Inserts or updates a task keyed by `(origin, externalId)`. Idempotent: a
    /// repeated import with the same external id mutates the existing row instead of
    /// creating a new one. (Android `insertTask` with a reused row id via REPLACE.)
    ///
    /// Returns the persisted task.
    @discardableResult
    func upsertImported(
        externalId: String,
        title: String,
        timestamp: Date,
        tzId: String,
        origin: String
    ) throws -> PlannedTask {
        if let existing = try fetchImported(origin: origin, externalId: externalId) {
            existing.title = title
            existing.timestamp = timestamp
            existing.tzId = tzId
            return existing
        }
        let task = PlannedTask(
            title: title,
            timestamp: timestamp,
            tzId: tzId,
            origin: origin,
            externalId: externalId
        )
        context.insert(task)
        return task
    }

    /// Deletes all imports for `origin` whose `externalId` is NOT in `keep`.
    /// (Android `deleteImportedNotIn`.) Pass an empty `keep` to delete them all
    /// (Android `deleteAllImported`).
    func deleteImported(origin: String, notIn keep: [String]) throws {
        let keepSet = Set(keep)
        for task in try importedTasks(origin: origin) {
            guard let ext = task.externalId, keepSet.contains(ext) else {
                context.delete(task)
                continue
            }
        }
    }

    /// Deletes every imported row for `origin`. (Android `deleteAllImported`.)
    func deleteAllImported(origin: String) throws {
        for task in try importedTasks(origin: origin) {
            context.delete(task)
        }
    }

    // MARK: - Source rows for the exporter (Android: provider cursors)

    /// Locally-authored zones, in display order. Source for the zones the exporter
    /// publishes. (Android `zonesCursor`: all saved_zones ORDER BY orderIndex.)
    func sharableZones() throws -> [SavedZone] {
        let descriptor = FetchDescriptor<SavedZone>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// People, ordered by name. (Android `peopleCursor`: people ORDER BY name ASC.)
    func sharablePeople() throws -> [Person] {
        let descriptor = FetchDescriptor<Person>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Persistence

    /// Flushes pending inserts/updates/deletes. SwiftData autosaves, but we save
    /// explicitly after a sync batch so imports are durable immediately.
    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    // MARK: - Private

    private func fetchImported(origin: String, externalId: String) throws -> PlannedTask? {
        var descriptor = FetchDescriptor<PlannedTask>(
            predicate: #Predicate { $0.origin == origin && $0.externalId == externalId }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
