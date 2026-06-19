package com.example.core.data

import java.time.ZonedDateTime

/** Slots pinned on the Now card alongside local device time. */
object ZoneAnchorRole {
    const val NONE = ""
    /** Origin country — e.g. India for family calls while studying abroad. */
    const val HOME_COUNTRY = "home_country"
    /** Usual base — e.g. campus city or apartment. */
    const val RESIDENCE = "residence"
}

fun SavedZone.isNowAnchor(): Boolean = anchorRole.isNotEmpty() || isHome

fun List<SavedZone>.homeCountryZone(): SavedZone? =
    find { it.anchorRole == ZoneAnchorRole.HOME_COUNTRY }

fun List<SavedZone>.residenceZone(): SavedZone? =
    find { it.anchorRole == ZoneAnchorRole.RESIDENCE }
        ?: find { it.isHome && it.anchorRole.isEmpty() }

/** City label for the local user — home/residence name, not the IANA segment. */
fun List<SavedZone>.localLocationLabel(localZoneId: String): String =
    residenceZone()?.displayName
        ?: find { it.isHome }?.displayName
        ?: localZoneId.substringAfterLast('/').replace('_', ' ')

fun wallClockKey(zdt: ZonedDateTime): String =
    "${zdt.offset}|${zdt.toLocalTime().withNano(0)}"

fun offsetDiffLabel(local: ZonedDateTime, other: ZonedDateTime): String {
    val diffHours = (other.offset.totalSeconds - local.offset.totalSeconds) / 3600.0
    return when {
        diffHours > 0 -> "+${if (diffHours % 1.0 == 0.0) diffHours.toInt() else diffHours}h ahead"
        diffHours < 0 -> "${if (diffHours % 1.0 == 0.0) diffHours.toInt() else diffHours}h behind"
        else -> "Same time as local"
    }
}
