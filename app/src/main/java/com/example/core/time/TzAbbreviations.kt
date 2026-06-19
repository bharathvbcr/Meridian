package com.example.core.time

import java.util.Locale

/**
 * Common time-zone abbreviations → IANA ids for AI grounding and zone search.
 *
 * Abbreviations are inherently ambiguous (CST = US Central vs China). This table maps the
 * unambiguous travel/planner cases; ambiguous ones need a phrase hint (see [PHRASES]) or fall
 * through to [PlaceIndex] and the full search stack.
 */
object TzAbbreviations {

    private val ALIASES: Map<String, String> = mapOf(
        // Americas (US — unambiguous 3-letter daylight forms)
        "EST" to "America/New_York",
        "EDT" to "America/New_York",
        "ET" to "America/New_York",
        "CDT" to "America/Chicago",
        "MDT" to "America/Denver",
        "MST" to "America/Denver",
        "MT" to "America/Denver",
        "PDT" to "America/Los_Angeles",
        "PST" to "America/Los_Angeles",
        "PT" to "America/Los_Angeles",
        "AKST" to "America/Anchorage",
        "AKDT" to "America/Anchorage",
        "HST" to "Pacific/Honolulu",
        "BRT" to "America/Sao_Paulo",
        "ART" to "America/Argentina/Buenos_Aires",
        // Europe / Africa
        "GMT" to "UTC",
        "UTC" to "UTC",
        "WET" to "Europe/Lisbon",
        "CET" to "Europe/Paris",
        "CEST" to "Europe/Paris",
        "EET" to "Europe/Helsinki",
        "EEST" to "Europe/Helsinki",
        "MSK" to "Europe/Moscow",
        "TRT" to "Europe/Istanbul",
        "SAST" to "Africa/Johannesburg",
        "EAT" to "Africa/Nairobi",
        "WAT" to "Africa/Lagos",
        // Asia / Pacific
        "IST" to "Asia/Kolkata",
        "PKT" to "Asia/Karachi",
        "ICT" to "Asia/Bangkok",
        "SGT" to "Asia/Singapore",
        "HKT" to "Asia/Hong_Kong",
        "JST" to "Asia/Tokyo",
        "KST" to "Asia/Seoul",
        "AEST" to "Australia/Sydney",
        "AEDT" to "Australia/Sydney",
        "AWST" to "Australia/Perth",
        "NZST" to "Pacific/Auckland",
        "NZDT" to "Pacific/Auckland",
        "GST" to "Asia/Dubai",
        "IRST" to "Asia/Tehran",
    )

    private val PHRASES: List<Pair<Regex, String>> = listOf(
        Regex("(?i)\\bchina\\s+cst\\b") to "Asia/Shanghai",
        Regex("(?i)\\bcn\\s+cst\\b") to "Asia/Shanghai",
        Regex("(?i)\\bus\\s+cst\\b") to "America/Chicago",
        Regex("(?i)\\bcentral\\s+time\\b") to "America/Chicago",
        Regex("(?i)\\beastern\\s+time\\b") to "America/New_York",
        Regex("(?i)\\bpacific\\s+time\\b") to "America/Los_Angeles",
        Regex("(?i)\\bmountain\\s+time\\b") to "America/Denver",
        Regex("(?i)\\bbangladesh\\s+time\\b") to "Asia/Dhaka",
        Regex("(?i)\\bbritish\\s+summer\\s+time\\b") to "Europe/London",
        Regex("(?i)\\bbst\\b") to "Europe/London",
    )

    fun resolve(query: String): ZoneMatch? {
        val raw = query.trim()
        if (raw.isEmpty()) return null
        PHRASES.firstOrNull { it.first.containsMatchIn(raw) }?.let { return ZoneMatch(it.second, raw) }
        val key = raw.uppercase(Locale.ROOT)
        val zoneId = ALIASES[key] ?: return null
        return ZoneMatch(zoneId, key)
    }

    /** True when [token] looks like a bare abbreviation (2–5 letters). */
    fun looksLikeAbbreviation(token: String): Boolean {
        val t = token.trim()
        return t.length in 2..5 && t.all { it.isLetter() }
    }
}
