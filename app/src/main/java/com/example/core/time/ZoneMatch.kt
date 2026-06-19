package com.example.core.time

/**
 * A resolved time-zone candidate surfaced by location search: the IANA (or fixed-offset)
 * [zoneId] to save, plus the human [displayName] to show and store on the [SavedZone].
 * Produced by [OffsetZones] (UTC/GMT offsets) and [GeoPlaceRepository] (cities & airports),
 * merged alongside [PlaceIndex] hits in the view model.
 */
data class ZoneMatch(
    val zoneId: String,
    val displayName: String,
)
