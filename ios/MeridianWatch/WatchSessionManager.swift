// WatchSessionManager.swift
// Meridian — watchOS 27 / Swift 6 (watch side)
//
// Receives the phone's world-clock + next-event snapshot over WatchConnectivity and exposes
// it as observable state for `MeridianWatchApp`'s SwiftUI views. This is the watch counterpart
// to the phone's `WatchSyncManager`; together they replace Android's Wearable Data Layer sync
// from `WearSyncManager.kt`.
//
// `updateApplicationContext` delivers the latest snapshot to `didReceiveApplicationContext`,
// and the most recent context is also available as `session.receivedApplicationContext` after
// activation — so a freshly-launched watch app gets the last known state immediately.

import Foundation
import Observation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - WatchSessionManager

/// Observable store of the latest payload pushed from the phone.
///
/// `@MainActor`-isolated observable state with a `nonisolated` `WCSessionDelegate`
/// conformance whose callbacks hop back to the main actor.
@Observable
@MainActor
final class WatchSessionManager: NSObject {

    /// The most recently received snapshot. Starts empty until the first context arrives.
    private(set) var payload: WatchSyncPayload = .empty

    /// `true` once at least one snapshot (or a non-empty restored context) has been applied.
    private(set) var hasReceivedData = false

    override init() {
        super.init()
    }

    // MARK: - Convenience views over the payload

    /// Pinned zones in display order.
    var zones: [WatchZone] {
        payload.zones.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// The next upcoming event, if any.
    var nextEvent: WatchEvent? {
        payload.nextEvent
    }

    // MARK: - Activation

    /// Activates the session and restores any context already buffered by the system.
    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // The system may already hold the last application context from a previous run.
        apply(context: session.receivedApplicationContext)
        #endif
    }

    /// Decodes and stores a received context, ignoring incompatible/empty payloads.
    private func apply(context: [String: Any]) {
        applyPayload(WatchSyncEncoding.decode(context))
    }

    /// Stores an already-decoded payload, ignoring incompatible/empty (`nil`) payloads.
    ///
    /// Takes the `Sendable` `WatchSyncPayload?` so callers can decode the non-`Sendable`
    /// `[String: Any]` context *before* hopping to the main actor.
    private func applyPayload(_ decoded: WatchSyncPayload?) {
        guard let decoded else { return }
        payload = decoded
        hasReceivedData = true
    }
}

// MARK: - WCSessionDelegate

#if canImport(WatchConnectivity)
extension WatchSessionManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        // `receivedApplicationContext` is `[String: Any]`, which is NOT Sendable, so it must
        // not cross the actor hop. Decode here, then capture only the Sendable payload.
        let restored = WatchSyncEncoding.decode(session.receivedApplicationContext)
        Task { @MainActor in
            self.applyPayload(restored)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        // `[String: Any]` is NOT Sendable; decode to the Sendable payload before the hop.
        let decoded = WatchSyncEncoding.decode(applicationContext)
        Task { @MainActor in
            self.applyPayload(decoded)
        }
    }
}
#endif
