package com.example.core.time

import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID

object IcsGenerator {
    private val utcFormatter = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
    private val localFormatter = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss")

    /** RFC 5545 §3.1: content lines SHOULD NOT be longer than 75 octets, excluding the CRLF. */
    private const val MAX_LINE_OCTETS = 75

    /**
     * Generates an RFC-5545 iCalendar content string.
     *
     * Compliance notes:
     *  - Lines are CRLF-delimited and folded to [MAX_LINE_OCTETS] octets (§3.1).
     *  - Region zones (e.g. `Asia/Kolkata`) use `DTSTART;TZID=…` local times; fixed-offset zones
     *    (e.g. `+05:30`) are emitted as UTC DATE-TIME instead — an offset id is not a legal
     *    unquoted TZID param-value and no VTIMEZONE can describe it.
     *  - Text fields escape `\ ; ,` and newlines per §3.3.11.
     */
    fun generateEventIcs(
        title: String,
        description: String = "Scheduled via Meridian World Clock Planner",
        startInstant: Instant,
        durationMinutes: Int = 60,
        zoneId: String
    ): String {
        val jZoneId = try {
            ZoneId.of(zoneId)
        } catch (e: Exception) {
            ZoneId.systemDefault()
        }

        val useUtcForm = jZoneId is ZoneOffset

        val dtStamp = utcFormatter.format(ZonedDateTime.ofInstant(Instant.now(), ZoneOffset.UTC))

        val uid = UUID.randomUUID().toString()

        return buildString {
            appendIcsLine("BEGIN:VCALENDAR")
            appendIcsLine("VERSION:2.0")
            appendIcsLine("PRODID:-//Meridian//NONSGML World Clock Generator//EN")
            appendIcsLine("CALSCALE:GREGORIAN")
            appendIcsLine("BEGIN:VEVENT")
            appendIcsLine("UID:$uid")
            appendIcsLine("DTSTAMP:$dtStamp")
            appendIcsLine("SUMMARY:${normalizeIcsString(title)}")
            appendIcsLine("DESCRIPTION:${normalizeIcsString(description)}")
            if (useUtcForm) {
                val startUtc = startInstant.atZone(ZoneOffset.UTC)
                appendIcsLine("DTSTART:${utcFormatter.format(startUtc)}")
                appendIcsLine("DTEND:${utcFormatter.format(startUtc.plusMinutes(durationMinutes.toLong()))}")
            } else {
                val startZoned = ZonedDateTime.ofInstant(startInstant, jZoneId)
                val endZoned = startZoned.plusMinutes(durationMinutes.toLong())
                appendIcsLine("DTSTART;TZID=${jZoneId.id}:${localFormatter.format(startZoned)}")
                appendIcsLine("DTEND;TZID=${jZoneId.id}:${localFormatter.format(endZoned)}")
            }
            appendIcsLine("END:VEVENT")
            appendIcsLine("END:VCALENDAR")
        }
    }

    /** Appends one logical property as one or more folded physical lines joined with CRLF. */
    private fun StringBuilder.appendIcsLine(line: String) {
        foldToOctets(line).forEach { append(it).append("\r\n") }
    }

    /**
     * Folds a content line so every physical line stays within [MAX_LINE_OCTETS] UTF-8 octets
     * (§3.1). Continuation lines begin with a single space, which counts toward their budget.
     * Never splits inside a multi-byte character or a surrogate pair.
     */
    internal fun foldToOctets(line: String, maxOctets: Int = MAX_LINE_OCTETS): List<String> {
        require(maxOctets >= 4) { "folding budget too small" }
        if (line.isEmpty()) return emptyList()
        if (line.toByteArray(Charsets.UTF_8).size <= maxOctets) return listOf(line)

        val out = mutableListOf<String>()
        var idx = 0 // char index into line
        var firstChunk = true
        while (idx < line.length) {
            val budget = if (firstChunk) maxOctets else maxOctets - 1 // leading space costs 1 octet
            var octets = 0
            var take = 0
            while (idx + take < line.length) {
                val c = line[idx + take]
                val charOctets = when {
                    Character.isHighSurrogate(c) && idx + take + 1 < line.length &&
                        Character.isLowSurrogate(line[idx + take + 1]) -> 4
                    Character.isHighSurrogate(c) || Character.isLowSurrogate(c) -> 3 // lone surrogate → '?' bytes
                    c.code < 0x80 -> 1
                    c.code < 0x800 -> 2
                    else -> 3
                }
                if (octets + charOctets > budget) break
                octets += charOctets
                take += if (charOctets == 4) 2 else 1
            }
            if (take == 0) break // single code point larger than budget — cannot make progress safely
            out.add((if (firstChunk) "" else " ") + line.substring(idx, idx + take))
            idx += take
            firstChunk = false
        }
        return out
    }

    /**
     * Escapes text-field characters according to RFC-5545 §3.3.11. A CRLF becomes `\n`; a bare
     * carriage return has no escape form, so it is dropped rather than corrupting the content line.
     */
    private fun normalizeIcsString(input: String): String {
        return input
            .replace("\\", "\\\\")
            .replace("\r\n", "\n")
            .replace("\n", "\\n")
            .replace("\r", "")
            .replace(";", "\\;")
            .replace(",", "\\,")
    }
}
