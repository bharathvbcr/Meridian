// InteropContract.swift
// Meridian — iOS 27 / Swift 6
//
// Cross-app sharing contract between Meridian (this app) and ChronosFlow.
//
// PORTING NOTE — Android used a read-only `ContentProvider` per app
// (`content://<applicationId>.share/<path>`) and queried the *peer's* provider.
// iOS has no cross-app ContentProvider, so the equivalent is a SHARED App Group
// container both sibling apps read/write. Each app writes a versioned JSON
// snapshot of its shareable data to a well-known file inside the App Group; the
// peer reads that file. There is no live IPC — sync happens opportunistically
// (on `scenePhase == .active`).
//
// This file is intentionally mirrored (semantically equivalent, minus the
// SELF/PEER bundle-id swap) in the ChronosFlow repo — there is no shared Swift
// package between the two projects.

import Foundation

/// Static identifiers + paths shared with ChronosFlow over the App Group container.
///
/// Mirrors Android's `InteropContract` object. Where Android used a content
/// authority + cursor columns, iOS uses an App Group container + a Codable
/// snapshot schema (see ``InteropEntities``).
enum InteropContract {

    // MARK: - Bundle identifiers (Android: package names)

    /// This app's bundle id. (Android: `DEVTIME_PACKAGE` / `SELF_PACKAGE`.)
    static let meridianBundleId = "com.Meridian.VBCR"
    /// The sibling app we share with. (Android: `CHRONOSFLOW_PACKAGE`.)
    static let chronosFlowBundleId = "com.ChronosFlow.VBCR"

    /// This app. (Android: `SELF_PACKAGE`.)
    static let selfBundleId = meridianBundleId
    /// The peer app. (Android: `CHRONOSFLOW`.)
    static let peerBundleId = chronosFlowBundleId

    // MARK: - App Group (replaces Android's provider authority)

    /// The shared container both apps mount. Must match the App Group entitlement
    /// on every target of both apps. (Android analogue: the content authority.)
    static let appGroupIdentifier = "group.com.example.meridian"

    /// Apple Developer Team identifier shared by both sibling apps. Used by
    /// ``PeerVerifier`` as the iOS analogue of Android's signing-cert pinning:
    /// the App Sandbox guarantees that only apps entitled to this App Group (which
    /// in turn requires the same team) can read/write the container.
    ///
    /// TODO(release): set this to the real 10-character Team ID before shipping.
    static let teamIdentifier = "ABCDE12345"

    // MARK: - Snapshot file names (Android: provider PATH_* segments)

    /// Each app writes ONE snapshot file describing everything it shares. The peer
    /// reads the file named for *its own* bundle id (i.e. the file the peer wrote).
    ///
    /// (Android exposed `tasks` / `events` / `zones` / `people` etc. as separate
    /// provider paths; on iOS they are sections within a single snapshot file so
    /// the read is one atomic operation.)
    enum SnapshotFile {
        /// File the given app writes for its peers to read. Keyed by the *author's*
        /// bundle id so a single container can hold both apps' snapshots without
        /// collision.
        static func name(forAuthor bundleId: String) -> String {
            "interop-snapshot.\(bundleId).json"
        }

        /// The file the peer (ChronosFlow) authored — what *we* read from.
        static var peer: String { name(forAuthor: peerBundleId) }

        /// The file *we* author — what the peer reads from.
        static var own: String { name(forAuthor: selfBundleId) }
    }

    // MARK: - Section keys (Android: PATH_* constants)

    /// Logical data types within a snapshot (Android provider paths). Meridian
    /// authors `tasks`, `zones`, `people`; it consumes the peer's `tasks` + `events`.
    enum Section: String, Codable, Sendable {
        case tasks
        case events
        case zones
        case people
        case habits
        case medications
        case goals
    }

    // MARK: - Origin tagging (Android: PlannedTask.origin == peer package)

    /// `PlannedTask.origin` value stamped on rows imported from ChronosFlow, so the
    /// exporter excludes them (data never echoes back) and the sync manager can
    /// prune/refresh exactly its own imports. (Android: `InteropContract.CHRONOSFLOW`.)
    static let importOrigin = peerBundleId

    // MARK: - External-id namespacing (Android: "task:"/"event:" prefixes)

    /// Stable `PlannedTask.externalId` for an imported task row.
    static func taskExternalId(_ peerExternalId: String) -> String { "task:\(peerExternalId)" }

    /// Stable `PlannedTask.externalId` for an imported calendar-event row.
    static func eventExternalId(_ peerExternalId: String) -> String { "event:\(peerExternalId)" }
}
