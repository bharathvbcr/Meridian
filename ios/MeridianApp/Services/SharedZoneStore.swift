// SharedZoneStore.swift
// Meridian — iOS 27 / Swift 6
//
// Writes a snapshot of the user's pinned zones into the App Group container so the
// widget extension (and Live Activities) can render the world clock without a SwiftData
// dependency. The widget reads `SharedZoneStore.loadSnapshot()`.

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - App Group

/// Identifiers shared by the app, widget, and Live Activity targets.
enum AppGroup {
    /// The App Group container identifier. Must match the entitlement on every target.
    static let identifier = "group.com.example.meridian"
}

// MARK: - SharedZoneSnapshot

/// A Codable, Sendable snapshot of a single pinned zone, suitable for cross-process transfer.
///
/// We intentionally store only the primitive fields the widget needs (it computes local
/// wall-clock time itself from `tzId`) rather than the SwiftData `@Model`, which is not
/// available to the widget target and is not Sendable.
struct SharedZone: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let tzId: String
    let displayName: String
    let isHome: Bool
    let orderIndex: Int

    init(id: String, tzId: String, displayName: String, isHome: Bool, orderIndex: Int) {
        self.id = id
        self.tzId = tzId
        self.displayName = displayName
        self.isHome = isHome
        self.orderIndex = orderIndex
    }
}

/// The full payload written to the App Group. Versioned so future widget builds can
/// detect and skip incompatible snapshots.
struct SharedZoneSnapshot: Codable, Sendable {
    /// Schema version. Bump when the shape of ``zones`` changes.
    let version: Int
    /// Pinned zones in display order.
    let zones: [SharedZone]
    /// When the snapshot was written (used by the widget for staleness display).
    let updatedAt: Date

    static let currentVersion = 1

    static let empty = SharedZoneSnapshot(version: currentVersion, zones: [], updatedAt: .distantPast)
}

// MARK: - SharedZoneStore

/// Reads and writes the pinned-zone snapshot to the shared App Group `UserDefaults`.
///
/// Both the app and the widget link this file; the app calls ``save(zones:)`` whenever the
/// pinned set changes, and the widget timeline provider calls ``loadSnapshot()``.
enum SharedZoneStore {

    /// Key under which the encoded snapshot is stored in the shared defaults.
    private static let snapshotKey = "meridian.sharedZoneSnapshot"

    /// Shared `UserDefaults` backed by the App Group container.
    /// Falls back to `.standard` only if the suite cannot be created (misconfigured
    /// entitlements in a debug build) so the app does not crash.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Write

    /// Encodes and persists the given pinned zones to the App Group container, then asks
    /// WidgetKit to reload its timelines so the change is reflected promptly.
    ///
    /// - Parameter zones: The pinned zones, already in display order.
    static func save(zones: [SharedZone]) {
        let snapshot = SharedZoneSnapshot(
            version: SharedZoneSnapshot.currentVersion,
            zones: zones,
            updatedAt: Date()
        )
        save(snapshot: snapshot)
    }

    /// Persists a fully-formed snapshot.
    static func save(snapshot: SharedZoneSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: snapshotKey)
            reloadWidgets()
        } catch {
            // Encoding a small fixed-shape payload should never fail; swallow to avoid
            // taking down the caller on a best-effort widget sync.
        }
    }

    // MARK: - Read

    /// Loads the most recent snapshot, or ``SharedZoneSnapshot/empty`` when none exists
    /// or the stored payload is from an incompatible (newer) schema version.
    static func loadSnapshot() -> SharedZoneSnapshot {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? decoder.decode(SharedZoneSnapshot.self, from: data),
            snapshot.version <= SharedZoneSnapshot.currentVersion
        else {
            return .empty
        }
        return snapshot
    }

    /// Convenience: just the pinned zones, in display order.
    static func loadZones() -> [SharedZone] {
        loadSnapshot().zones
    }

    /// Clears the stored snapshot (e.g. on sign-out / data reset).
    static func clear() {
        defaults.removeObject(forKey: snapshotKey)
        reloadWidgets()
    }

    // MARK: - WidgetKit

    /// Reloads all widget timelines. No-op in targets that do not link WidgetKit.
    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        // VERIFY: WidgetCenter.shared.reloadAllTimelines() — stable since iOS 14.
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
