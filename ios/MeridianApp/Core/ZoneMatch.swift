// ZoneMatch.swift
// Meridian — iOS 27+ / Swift 6
//
// Ported from app/src/main/java/com/example/core/time/ZoneMatch.kt

import Foundation

/// A resolved time-zone candidate surfaced by location search: the IANA (or fixed-offset)
/// ``zoneId`` to save, plus the human ``displayName`` to show and store on the `SavedZone`.
///
/// Produced by ``OffsetZones`` (UTC/GMT offsets) and ``GeoPlaceRepository`` (cities & airports),
/// merged alongside ``PlaceIndex`` hits in the view model.
public struct ZoneMatch: Identifiable, Hashable, Sendable {
    /// IANA zone id or fixed-offset id (e.g. `"Asia/Tokyo"`, `"+05:30"`, `"UTC"`).
    public let zoneId: String
    /// Human-readable label to show and persist.
    public let displayName: String

    /// Stable identity for SwiftUI lists. Two matches with the same zone + label are equal,
    /// but we disambiguate on both fields so e.g. "Tokyo" the city and "Tokyo (HND)" the airport
    /// (same zone, different label) can coexist in a result list.
    public var id: String { "\(zoneId)\u{001F}\(displayName)" }

    public init(zoneId: String, displayName: String) {
        self.zoneId = zoneId
        self.displayName = displayName
    }
}

public extension ZoneMatch {
    /// Adapter from a curated ``PlaceEntry`` so all search layers can merge as `[ZoneMatch]`.
    /// The display name follows Android's `SavedZone` convention: the city name.
    init(_ place: PlaceEntry) {
        self.init(zoneId: place.tzId, displayName: place.displayName)
    }
}
