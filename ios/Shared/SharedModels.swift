// SharedModels.swift
// Meridian — iOS 27 / watchOS 27 / Swift 6
//
// Lightweight, Sendable + Codable value types shared between the phone app and the
// watchOS companion over WatchConnectivity. These are deliberately decoupled from the
// SwiftData `@Model` types (`SavedZone`, `PlannedTask`) — those are not Sendable and are
// not available to the watch target. The phone serialises a snapshot of its domain state
// into a `WatchSyncPayload`, transfers it via `WCSession.updateApplicationContext`, and
// the watch decodes it for display.
//
// Behavioral port of Android `WearSyncManager.kt`, which pushed a `DataMap` of
// home/second-zone strings over the Wearable Data Layer. The iOS payload is broader: it
// carries the full ordered watchlist plus the next upcoming event, which is more idiomatic
// for a SwiftUI watch app (a list + a countdown), while still preserving the Android
// home-zone semantics via `WatchZone.isHome`.
//
// This file lives in `ios/Shared` so both the app target and the watch app target compile
// the exact same definitions — keeping the wire format trivially in sync.

import Foundation

// MARK: - WatchZone

/// A single time zone as displayed on the watch. Mirrors the primitive fields of the
/// phone's `SavedZone` that the watch needs; the watch computes local wall-clock time
/// itself from `tzId`, so no formatted strings are baked into the wire format.
public struct WatchZone: Codable, Sendable, Identifiable, Hashable {
    /// IANA identifier, e.g. `"America/Los_Angeles"`. Also the stable list identity.
    public let id: String
    /// IANA zone id used for time computation (usually equal to `id`).
    public let tzId: String
    /// Friendly label, e.g. `"San Francisco"`.
    public let displayName: String
    /// `true` for the user's residence/home anchor (Android `SavedZone.isHome`).
    public let isHome: Bool
    /// Display order (ascending), matching the phone's `sortOrder`.
    public let orderIndex: Int

    public init(
        id: String,
        tzId: String,
        displayName: String,
        isHome: Bool,
        orderIndex: Int
    ) {
        self.id = id
        self.tzId = tzId
        self.displayName = displayName
        self.isHome = isHome
        self.orderIndex = orderIndex
    }
}

// MARK: - WatchEvent

/// The next upcoming planned event, shown as a countdown on the watch. Carries only the
/// absolute instant and a title; the watch renders the countdown locally via
/// `Text(timerInterval:)`, so no per-second updates need to cross the wire.
public struct WatchEvent: Codable, Sendable, Identifiable, Hashable {
    /// Originating `PlannedTask.id`.
    public let id: String
    /// Event title (mirrors `PlannedTask.title`).
    public let title: String
    /// Absolute start instant of the event.
    public let date: Date
    /// IANA zone the event is anchored to (for optional "in <city>" labelling).
    public let tzId: String

    public init(id: String, title: String, date: Date, tzId: String) {
        self.id = id
        self.title = title
        self.date = date
        self.tzId = tzId
    }
}

// MARK: - WatchSyncPayload

/// The full snapshot transferred phone → watch via `updateApplicationContext`.
///
/// `updateApplicationContext` keeps only the *latest* value (older queued contexts are
/// replaced), which is exactly the semantics we want: the watch always sees the current
/// world-clock list and next event. The payload is versioned so a newer phone build can
/// evolve the shape and an older watch build can safely ignore an incompatible snapshot.
public struct WatchSyncPayload: Codable, Sendable, Hashable {
    /// Schema version. Bump when the shape of any field changes.
    public let version: Int
    /// Pinned zones in display order.
    public let zones: [WatchZone]
    /// The next upcoming event, or `nil` when there is none scheduled ahead.
    public let nextEvent: WatchEvent?
    /// When the phone produced this snapshot (used by the watch for staleness display).
    public let updatedAt: Date

    public static let currentVersion = 1

    /// An empty placeholder shown before the first sync arrives.
    public static let empty = WatchSyncPayload(
        version: currentVersion,
        zones: [],
        nextEvent: nil,
        updatedAt: .distantPast
    )

    public init(
        version: Int = WatchSyncPayload.currentVersion,
        zones: [WatchZone],
        nextEvent: WatchEvent?,
        updatedAt: Date
    ) {
        self.version = version
        self.zones = zones
        self.nextEvent = nextEvent
        self.updatedAt = updatedAt
    }
}

// MARK: - Dictionary bridging

/// `WCSession.updateApplicationContext` requires a property-list-compatible
/// `[String: Any]` dictionary. We encode the strongly-typed payload to JSON `Data` and
/// carry it under a single key, which sidesteps plist type restrictions (e.g. `Date`,
/// optionals, nested arrays) and keeps the wire format identical to what `Codable` emits.
public enum WatchSyncEncoding {

    /// The single dictionary key under which the encoded payload travels.
    public static let payloadKey = "meridian.watchSyncPayload"

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

    /// Encodes a payload into a plist-safe application-context dictionary.
    public static func encode(_ payload: WatchSyncPayload) throws -> [String: Any] {
        let data = try encoder.encode(payload)
        return [payloadKey: data]
    }

    /// Decodes a payload from a received application-context dictionary, returning `nil`
    /// when the dictionary does not contain a valid (compatible) payload.
    public static func decode(_ context: [String: Any]) -> WatchSyncPayload? {
        guard
            let data = context[payloadKey] as? Data,
            let payload = try? decoder.decode(WatchSyncPayload.self, from: data),
            payload.version <= WatchSyncPayload.currentVersion
        else {
            return nil
        }
        return payload
    }
}
