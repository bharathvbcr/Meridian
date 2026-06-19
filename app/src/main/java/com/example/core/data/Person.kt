package com.example.core.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * A person you plan meetings with, carrying their time zone (§5.8, §13). Stored locally;
 * a String zone id keeps Android types out of the domain layer.
 */
@Entity(tableName = "people")
data class Person(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val name: String,
    val zoneId: String,
    /** City or place label (e.g. "El Paso") — distinct from the IANA zone id (e.g. America/Denver). */
    val locationName: String = "",
    /** Local working window [workStartHour, workEndHour) used by the fairness ranker (§5.8). */
    val workStartHour: Int = 9,
    val workEndHour: Int = 17,
    /** Optional do-not-disturb window; -1/-1 means none. Wraps midnight if start > end. */
    val dndStartHour: Int = -1,
    val dndEndHour: Int = -1,
    val isFavorite: Boolean = false,
) {
    /** Human place name for chips; falls back to the zone segment when legacy rows lack [locationName]. */
    fun displayLocation(): String =
        locationName.ifBlank { zoneId.substringAfterLast('/').replace('_', ' ') }

    /** True when this contact belongs on [zone]'s location row (city + IANA id). */
    fun matchesZone(zone: SavedZone): Boolean =
        zoneId == zone.id &&
            (locationName.isBlank() || locationName.equals(zone.displayName, ignoreCase = true))

    fun isAssignedToAny(savedZones: List<SavedZone>): Boolean =
        savedZones.any { matchesZone(it) }

    /** Same IANA zone as a pinned row — used to attach orphan-city contacts to that row. */
    fun sharesTimeZoneWith(zone: SavedZone): Boolean = zoneId == zone.id

    fun appearsOnZoneRow(zone: SavedZone, savedZones: List<SavedZone>): Boolean =
        isFavorite && (
            matchesZone(zone) ||
                (sharesTimeZoneWith(zone) && zone.isFavorite && !isAssignedToAny(savedZones))
            )
}
