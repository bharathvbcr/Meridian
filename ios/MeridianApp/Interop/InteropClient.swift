// InteropClient.swift
// Meridian — iOS 27 / Swift 6
//
// Reads ChronosFlow's interop snapshot from the SHARED App Group container. This is
// the iOS replacement for Android's `InteropClient`, which queried the peer's
// ContentProvider cursors. Every call degrades to an empty result when ChronosFlow
// isn't installed, hasn't published a snapshot, the App Group is unavailable, or the
// payload is corrupt/untrusted — Meridian always works standalone.
//
// There is no live IPC on iOS: "the peer" is simply whatever snapshot file the peer
// last wrote into the container. `isPeerInstalled()` is therefore approximated by
// "has the peer ever published a (non-empty) snapshot here?" — see the doc on that
// method for why this is the correct behavioural analogue.

import Foundation
import os

/// Reads the peer (ChronosFlow) snapshot out of the App Group container.
///
/// `Sendable`: it holds only immutable configuration and touches the filesystem,
/// so it is safe to call from any actor. The sync manager drives it on the main actor.
/// `@unchecked` because the stored `FileManager` is not `Sendable`, but it is process-global
/// and thread-safe for the read-only operations used here.
struct InteropClient: @unchecked Sendable {

    private let log = Logger(subsystem: "com.example.meridian", category: "Interop")

    /// File manager is process-global and thread-safe for the operations we use.
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Availability (Android: isPeerInstalled / isPeerShareAvailable)

    /// URL of the peer's snapshot file inside the shared container, or `nil` when the
    /// App Group itself is unavailable (entitlement missing).
    private var peerSnapshotURL: URL? {
        PeerVerifier.sharedContainerURL()?
            .appendingPathComponent(InteropContract.SnapshotFile.peer, isDirectory: false)
    }

    /// `true` when the peer has published a snapshot we can see.
    ///
    /// Android's `isPeerInstalled()` asked the package manager whether ChronosFlow
    /// was installed. iOS apps cannot enumerate other installed apps, but the only
    /// observable consequence of "peer installed" that mattered for sync was "the
    /// peer has data for us to read", which on iOS means "the peer wrote a snapshot
    /// into our shared container". A peer that is installed but has shared nothing
    /// still writes an (empty) snapshot via its exporter, so file presence is the
    /// faithful analogue.
    func isPeerInstalled() -> Bool {
        guard let url = peerSnapshotURL else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    /// `true` when ChronosFlow has published a snapshot AND that snapshot is trusted
    /// (same-team App Group provenance). Mirrors Android `isPeerShareAvailable()`:
    /// the precondition every fetch checks internally, exposed so the sync manager
    /// can branch (notably for reminder ownership) without re-reading.
    func isPeerShareAvailable() -> Bool {
        PeerVerifier.isPeerShareAvailable(peerSnapshotExists: isPeerInstalled())
            && readSnapshot() != nil
    }

    // MARK: - Fetch (Android: fetchPeerTasks / fetchPeerEvents)

    /// The peer's shareable tasks, or `[]` on any failure. (Android `fetchPeerTasks`.)
    /// Undated tasks are passed through here; the sync manager skips them (parity:
    /// Android filtered `dueAt == null` in `syncFromPeer`).
    func fetchPeerTasks() -> [InteropTask] {
        readSnapshot()?.tasks ?? []
    }

    /// The peer's shareable calendar events, or `[]` on any failure. (Android
    /// `fetchPeerEvents`.)
    func fetchPeerEvents() -> [InteropEvent] {
        readSnapshot()?.events ?? []
    }

    // MARK: - Snapshot read + trust

    /// Reads, decodes and trust-checks the peer snapshot. Returns `nil` (→ empty
    /// fetches, standalone behaviour) on any failure, exactly like Android's `query`
    /// swallowing `SecurityException` / missing-provider exceptions.
    func readSnapshot() -> InteropSnapshot? {
        guard let url = peerSnapshotURL else {
            log.debug("Interop: shared container unavailable — staying standalone.")
            return nil
        }
        guard fileManager.fileExists(atPath: url.path) else {
            log.debug("Interop: peer has not published a snapshot.")
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            log.debug("Interop: failed to read peer snapshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let snapshot: InteropSnapshot
        do {
            snapshot = try InteropCoders.decoder.decode(InteropSnapshot.self, from: data)
        } catch {
            log.debug("Interop: peer snapshot undecodable (schema drift?): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // Android: confirm the owner of the authority is the real, pinned peer before
        // trusting its rows. iOS: confirm same-team App Group provenance + author id.
        guard PeerVerifier.isPeerTrusted(snapshot: snapshot) else {
            log.warning("Interop: peer snapshot failed trust check — ignoring.")
            return nil
        }
        return snapshot
    }
}
