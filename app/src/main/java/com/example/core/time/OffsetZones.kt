package com.example.core.time

import java.time.ZoneOffset
import java.util.Locale

/**
 * Resolves raw UTC/GMT offset queries to addable zones, so users can search by offset
 * ("UTC", "GMT+1", "utc+5:30", "-0800", "+09:00") and not just by place. Fixed-offset ids
 * like "+05:30" are valid [java.time.ZoneId]s, so they save and render like any other zone.
 *
 * An offset must be anchored by a `utc`/`gmt` prefix or an explicit sign, so plain text or a
 * bare number ("5", "london") never masquerades as an offset.
 */
object OffsetZones {

    // (utc|gmt|z|zulu)?  sign?  HH?  (:?MM)?
    private val PATTERN = Regex("^(utc|gmt|z|zulu)?\\s*([+-])?\\s*(\\d{1,2})?(?::?(\\d{2}))?$")

    private const val MAX_OFFSET_MINUTES = 18 * 60 // java.time caps offsets at +/-18:00

    fun parse(query: String): List<ZoneMatch> {
        val q = query.trim().lowercase(Locale.ROOT)
        if (q.isEmpty()) return emptyList()
        val match = PATTERN.matchEntire(q) ?: return emptyList()
        val (prefix, sign, hoursStr, minutesStr) = match.destructured

        val hasPrefix = prefix.isNotEmpty()
        val hasDigits = hoursStr.isNotEmpty()

        // Bare "utc"/"gmt"/"z"/"zulu" -> UTC.
        if (!hasDigits && sign.isEmpty()) {
            return if (hasPrefix) listOf(UTC) else emptyList()
        }
        // Anchor requirement + "z"/"zulu" are bare-UTC only (no numeric offset).
        if (!hasPrefix && sign.isEmpty()) return emptyList()
        if (prefix == "z" || prefix == "zulu") return emptyList()
        if (!hasDigits) return emptyList()

        val hours = hoursStr.toIntOrNull() ?: return emptyList()
        val minutes = if (minutesStr.isEmpty()) 0 else (minutesStr.toIntOrNull() ?: return emptyList())
        if (minutes > 59) return emptyList()
        val totalMinutes = hours * 60 + minutes
        if (totalMinutes > MAX_OFFSET_MINUTES) return emptyList()

        val signed = (if (sign == "-") -1 else 1) * totalMinutes * 60
        val offset = runCatching { ZoneOffset.ofTotalSeconds(signed) }.getOrNull() ?: return emptyList()
        if (offset.totalSeconds == 0) return listOf(UTC)
        // ZoneOffset.id is "+05:30" / "-08:00"; present it as "UTC+05:30".
        return listOf(ZoneMatch(offset.id, "UTC${offset.id}"))
    }

    private val UTC = ZoneMatch("UTC", "UTC")
}
