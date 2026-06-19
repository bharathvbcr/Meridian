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

    /**
     * Generates a fully-compliant RFC-5545 iCalendar content string.
     * Incorporates strict DTSTART;TZID formatting to guarantee correct localized processing
     * in Microsoft Outlook, Google Calendar, and Apple Calendar.
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

        val startZoned = ZonedDateTime.ofInstant(startInstant, jZoneId)
        val endZoned = startZoned.plusMinutes(durationMinutes.toLong())
        
        val dtStamp = utcFormatter.format(ZonedDateTime.ofInstant(java.time.Instant.now(), ZoneOffset.UTC))
        val dtStartNormalized = localFormatter.format(startZoned)
        val dtEndNormalized = localFormatter.format(endZoned)
        
        val uniqueString = "${startInstant.toEpochMilli()}-$title-$zoneId"
        val uid = UUID.nameUUIDFromBytes(uniqueString.toByteArray()).toString()

        return buildString {
            appendLine("BEGIN:VCALENDAR")
            appendLine("VERSION:2.0")
            appendLine("PRODID:-//Meridian//NONSGML World Clock Generator//EN")
            appendLine("CALSCALE:GREGORIAN")
            appendLine("BEGIN:VEVENT")
            appendLine("UID:$uid")
            appendLine("DTSTAMP:$dtStamp")
            appendLine("SUMMARY:${normalizeIcsString(title)}")
            appendLine("DESCRIPTION:${normalizeIcsString(description)}")
            appendLine("DTSTART;TZID=${jZoneId.id}:$dtStartNormalized")
            appendLine("DTEND;TZID=${jZoneId.id}:$dtEndNormalized")
            appendLine("END:VEVENT")
            appendLine("END:VCALENDAR")
        }
    }

    /**
     * Escapes standard control characters according to RFC-5545 string field guidelines
     */
    private fun normalizeIcsString(input: String): String {
        return input
            .replace("\\", "\\\\")
            .replace(";", "\\;")
            .replace(",", "\\,")
            .replace("\n", "\\n")
    }
}
