// InteropEntities.swift
// Meridian — iOS 27 / Swift 6
//
// The wire schema for the cross-app App Group snapshot. These Codable, Sendable
// value types are the iOS replacement for Android's normalized cursor columns
// (`TASK_COLUMNS`, `EVENT_COLUMNS`, …). Both Meridian and ChronosFlow encode/decode
// the SAME shapes, so this file is mirrored byte-for-byte in the ChronosFlow repo.
//
// Design parity with Android:
//   * `due_at` / `start_at` are absolute epoch instants. We carry them as `Date`
//     and encode them as epoch seconds so neither app bakes a wall-clock string in
//     (mirrors the "store an absolute instant, render in the view layer" rule).
//   * `timezone` is an optional IANA id (importer falls back to the system zone).

import Foundation

// MARK: - InteropTask (Android: TASK_COLUMNS / InteropClient.RemoteTask)

/// A shareable to-do/planned task as seen across apps.
///
/// Android columns: `external_id, title, notes, due_at, is_completed, priority,
/// timezone, updated_at`. We keep the fields Meridian actually consumes plus the
/// ones it authors, so the snapshot round-trips losslessly between siblings.
struct InteropTask: Codable, Sendable, Identifiable, Hashable {
    /// Source-app-local stable id (Android `external_id`). Becomes the suffix of
    /// `PlannedTask.externalId` on import.
    let externalId: String
    let title: String
    let notes: String?
    /// Absolute due instant (Android `due_at`, epoch millis). `nil` == undated;
    /// the importer skips undated peer tasks (a Meridian planned task needs a time).
    let dueAt: Date?
    let isCompleted: Bool
    let priority: Int?
    /// IANA zone id (Android `timezone`).
    let timezone: String?
    /// Last-modified instant (Android `updated_at`).
    let updatedAt: Date?

    var id: String { externalId }

    init(
        externalId: String,
        title: String,
        notes: String? = nil,
        dueAt: Date? = nil,
        isCompleted: Bool = false,
        priority: Int? = nil,
        timezone: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.externalId = externalId
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.isCompleted = isCompleted
        self.priority = priority
        self.timezone = timezone
        self.updatedAt = updatedAt
    }
}

// MARK: - InteropEvent (Android: EVENT_COLUMNS / InteropClient.RemoteEvent)

/// A shareable calendar event.
///
/// Android columns: `external_id, title, description, start_at, end_at, timezone,
/// is_all_day, location, updated_at`.
struct InteropEvent: Codable, Sendable, Identifiable, Hashable {
    let externalId: String
    let title: String
    let description: String?
    /// Absolute start instant (Android `start_at`). Required — rows without it are skipped.
    let startAt: Date
    /// Absolute end instant (Android `end_at`); 0/`startAt` when unknown.
    let endAt: Date
    let timezone: String?
    let isAllDay: Bool
    let location: String?
    let updatedAt: Date?

    var id: String { externalId }

    init(
        externalId: String,
        title: String,
        description: String? = nil,
        startAt: Date,
        endAt: Date,
        timezone: String? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.externalId = externalId
        self.title = title
        self.description = description
        self.startAt = startAt
        self.endAt = endAt
        self.timezone = timezone
        self.isAllDay = isAllDay
        self.location = location
        self.updatedAt = updatedAt
    }
}

// MARK: - InteropZone (Android: ZONE_COLUMNS)

/// A shareable saved time zone. Android columns: `external_id, zone_id, display_name, is_home`.
struct InteropZone: Codable, Sendable, Identifiable, Hashable {
    let externalId: String
    /// IANA zone id (Android `zone_id`).
    let zoneId: String
    let displayName: String
    let isHome: Bool

    var id: String { externalId }

    init(externalId: String, zoneId: String, displayName: String, isHome: Bool) {
        self.externalId = externalId
        self.zoneId = zoneId
        self.displayName = displayName
        self.isHome = isHome
    }
}

// MARK: - InteropPerson (Android: PEOPLE_COLUMNS)

/// A shareable person/contact. Android columns: `external_id, name, zone_id,
/// location_name, work_start_hour, work_end_hour`.
struct InteropPerson: Codable, Sendable, Identifiable, Hashable {
    let externalId: String
    let name: String
    let zoneId: String
    let locationName: String?
    let workStartHour: Int
    let workEndHour: Int

    var id: String { externalId }

    init(
        externalId: String,
        name: String,
        zoneId: String,
        locationName: String? = nil,
        workStartHour: Int = 9,
        workEndHour: Int = 17
    ) {
        self.externalId = externalId
        self.name = name
        self.zoneId = zoneId
        self.locationName = locationName
        self.workStartHour = workStartHour
        self.workEndHour = workEndHour
    }
}

// MARK: - InteropSnapshot (the whole App Group payload)

/// The complete versioned payload one app writes for its peer to read — the iOS
/// equivalent of all of Android's provider cursors rolled into one atomic file.
///
/// Versioned so a newer peer build can detect and skip an incompatible schema
/// (parity with ``SharedZoneSnapshot``). The reader treats a newer `version` as
/// "unknown — ignore", staying standalone.
struct InteropSnapshot: Codable, Sendable {
    /// Schema version. Bump when any field shape changes.
    let version: Int
    /// Bundle id of the app that authored this snapshot (for verification / logging).
    let authorBundleId: String
    /// When the snapshot was written.
    let updatedAt: Date

    let tasks: [InteropTask]
    let events: [InteropEvent]
    let zones: [InteropZone]
    let people: [InteropPerson]

    static let currentVersion = 1

    static func empty(author: String) -> InteropSnapshot {
        InteropSnapshot(
            version: currentVersion,
            authorBundleId: author,
            updatedAt: .distantPast,
            tasks: [],
            events: [],
            zones: [],
            people: []
        )
    }

    init(
        version: Int = InteropSnapshot.currentVersion,
        authorBundleId: String,
        updatedAt: Date,
        tasks: [InteropTask] = [],
        events: [InteropEvent] = [],
        zones: [InteropZone] = [],
        people: [InteropPerson] = []
    ) {
        self.version = version
        self.authorBundleId = authorBundleId
        self.updatedAt = updatedAt
        self.tasks = tasks
        self.events = events
        self.zones = zones
        self.people = people
    }
}

// MARK: - Shared JSON coders

/// Coders shared by ``InteropClient`` (read) and ``InteropExporter`` (write) so both
/// apps agree on the encoding. Epoch-seconds dates keep `due_at`/`start_at` as the
/// absolute instants Android stored, with no embedded wall-clock or zone string.
enum InteropCoders {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}
