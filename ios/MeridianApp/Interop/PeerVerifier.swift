// PeerVerifier.swift
// Meridian — iOS 27 / Swift 6
//
// Gatekeeper for the cross-app interop channel. Android exported a ContentProvider
// to any caller and authorized each query in code by pinning the caller's signing
// certificate (`PeerVerifier.requireTrusted` / `isTrusted`). iOS has no such caller
// identity at read time — the channel is a SHARED App Group container, and the App
// Sandbox already guarantees that ONLY apps provisioned with that exact App Group
// (which requires the SAME Apple Developer Team) can mount it. So on iOS the trust
// boundary moves from "verify the caller's cert" to "verify the container is the
// genuine shared App Group and the peer is a same-team sibling".
//
// We therefore replace cert pinning (Android) with, in order of strength:
//   1. App Group membership — can we actually access the shared container at all?
//      If not, there is no peer and nothing to trust. (Sandbox-enforced.)
//   2. Team-id provenance — the App Group id is namespaced under our team; only
//      same-team apps can join it, so a snapshot found there came from a sibling.
//   3. (Optional, opt-in) App Attest — a signed assertion the peer can drop into
//      the container proving it is the real ChronosFlow binary on a genuine device,
//      for environments that want hardware-backed peer authenticity.
//
// Anything that fails (1) or (2) is treated as "no trusted peer" and the app stays
// standalone — the exact graceful-degradation behaviour Android had when the peer
// wasn't installed / denied access.

import Foundation
#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// Decides whether the interop channel may be trusted, and (for the export side)
/// whether we should publish data into the shared container at all.
///
/// `Sendable` and stateless — every method derives its answer from the environment.
enum PeerVerifier {

    // MARK: - App Group membership (Android: provider authority owner check)

    /// `true` when this process can actually mount the shared App Group container.
    /// This is the iOS precondition for any interop: if the container URL is `nil`
    /// the entitlement is missing/misconfigured and there is no shared channel.
    /// (Replaces Android's `resolveContentProvider(...) != null`.)
    static func canAccessSharedContainer() -> Bool {
        sharedContainerURL() != nil
    }

    /// URL of the shared App Group container's root, or `nil` if unavailable.
    static func sharedContainerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: InteropContract.appGroupIdentifier
        )
    }

    // MARK: - Peer trust (Android: requireTrusted / isTrusted)

    /// Client-side counterpart of Android's `isTrusted(...)`: returns whether the
    /// interop peer (ChronosFlow) is trustworthy enough for us to import its
    /// snapshot. On iOS this is satisfied by App Group membership + same-team
    /// provenance (both enforced by the sandbox/provisioning), optionally
    /// strengthened by an App Attest assertion when present.
    ///
    /// - Parameter snapshot: the peer-authored snapshot we are about to import, used
    ///   to sanity-check the declared author bundle id matches the expected peer.
    static func isPeerTrusted(snapshot: InteropSnapshot) -> Bool {
        guard canAccessSharedContainer() else { return false }
        // The author the peer stamped into the file must be the expected sibling.
        // (An attacker can't write into our team's App Group without same-team
        // provisioning, so this is a consistency check, not the security boundary.)
        guard snapshot.authorBundleId == InteropContract.peerBundleId else { return false }
        // Schema we don't understand → don't trust its contents.
        guard snapshot.version <= InteropSnapshot.currentVersion else { return false }
        return true
    }

    /// Whether a trusted peer snapshot is *available* to read right now (peer has
    /// published into the shared container). Mirrors Android
    /// `InteropClient.isPeerShareAvailable()` and is used by the sync manager to
    /// decide who owns reminders.
    ///
    /// - Parameter peerSnapshotExists: whether the peer's snapshot file is present.
    static func isPeerShareAvailable(peerSnapshotExists: Bool) -> Bool {
        canAccessSharedContainer() && peerSnapshotExists
    }

    // MARK: - Export gate (Android: PeerVerifier.requireTrusted on each query)

    /// Whether *we* should publish our snapshot into the shared container. Android
    /// only served data to a pinned caller; on iOS we only ever write into the
    /// container when we can actually access it (i.e. the App Group is configured),
    /// since the container itself is the access-controlled boundary.
    static func mayExport() -> Bool {
        canAccessSharedContainer()
    }

    // MARK: - Optional App Attest (hardware-backed peer authenticity)

    /// Whether App Attest is available on this device. Opt-in: callers that want
    /// hardware-backed proof of the peer's binary can require a valid assertion in
    /// addition to App Group membership. Not required for baseline trust.
    ///
    /// VERIFY: `DCAppAttestService.isSupported` — stable since iOS 14.
    static var isAppAttestSupported: Bool {
        #if canImport(DeviceCheck)
        return DCAppAttestService.shared.isSupported
        #else
        return false
        #endif
    }
}
