package com.example

import com.example.core.time.IcsGenerator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class IcsGeneratorTest {

    @Test
    fun emitsZoneAwareDtStartForHalfHourOffsetZone() {
        // 07:30 UTC in Asia/Kolkata (+5:30) is 13:00 local.
        val start = Instant.parse("2026-06-20T07:30:00Z")
        val ics = IcsGenerator.generateEventIcs(
            title = "Lunch with Priya",
            startInstant = start,
            durationMinutes = 60,
            zoneId = "Asia/Kolkata",
        )

        assertTrue(ics.contains("BEGIN:VEVENT"))
        assertTrue(ics.contains("END:VEVENT"))
        assertTrue(ics.contains("DTSTART;TZID=Asia/Kolkata:20260620T130000"))
        assertTrue(ics.contains("DTEND;TZID=Asia/Kolkata:20260620T140000"))
        assertTrue(ics.contains("DTSTAMP:"))
        assertTrue(ics.contains("UID:"))
    }

    @Test
    fun escapesSpecialCharactersInSummary() {
        val ics = IcsGenerator.generateEventIcs(
            title = "Sync; review, plan",
            startInstant = Instant.parse("2026-06-20T07:30:00Z"),
            durationMinutes = 30,
            zoneId = "UTC",
        )
        assertTrue(ics.contains("SUMMARY:Sync\\; review\\, plan"))
    }

    @Test
    fun linesAreCrLfTerminatedAndNeverBareLf() {
        val ics = IcsGenerator.generateEventIcs(
            title = "Long planning session",
            startInstant = Instant.parse("2026-06-20T07:30:00Z"),
            zoneId = "Asia/Kolkata",
        )
        // RFC 5545 §3.1: content lines are delimited by CRLF.
        assertTrue(ics.contains("\r\n"))
        assertEquals("bare LF found", 0, Regex("(?<!\r)\n").findAll(ics).count())
    }

    @Test
    fun longTextFieldsAreFoldedToMax75Octets() {
        val longTitle = "Quarterly alignment sync with the platform infrastructure team across regions"
        val ics = IcsGenerator.generateEventIcs(
            title = longTitle,
            description = "Agenda: " + "roadmap deep dive, incident review, capacity planning, open Q&A. ".repeat(4),
            startInstant = Instant.parse("2026-06-20T07:30:00Z"),
            zoneId = "Europe/London",
        )
        for (line in ics.split("\r\n")) {
            assertTrue("line exceeds 75 octets (${line.toByteArray(Charsets.UTF_8).size}): $line",
                line.toByteArray(Charsets.UTF_8).size <= 75)
        }
    }

    @Test
    fun carriageReturnsInTextFieldsDoNotBreakContentLines() {
        val ics = IcsGenerator.generateEventIcs(
            title = "Kickoff\r\nfollow-up",
            startInstant = Instant.parse("2026-06-20T07:30:00Z"),
            zoneId = "UTC",
        )
        assertTrue(ics.contains("SUMMARY:Kickoff\\nfollow-up"))
        assertTrue(ics.contains("\r\n"))
    }

    @Test
    fun fixedOffsetZoneEmitsUtcTimesNotInvalidTzid() {
        // "+05:30" is a legal ZoneId here but an illegal unquoted TZID param-value per §3.1/§3.2.
        // Fixed offsets must be expressed as UTC DATE-TIME instead.
        val start = Instant.parse("2026-06-20T07:30:00Z")
        val ics = IcsGenerator.generateEventIcs(
            title = "Offset zone sync", startInstant = start, durationMinutes = 60, zoneId = "+05:30",
        )
        assertTrue(ics.contains("DTSTART:20260620T073000Z"))
        assertTrue(ics.contains("DTEND:20260620T083000Z"))
        assertFalse(ics.contains(";TZID=+"))
        assertFalse(ics.contains(";TZID=-"))
    }

    @Test
    fun uidsAreUniqueEvenForIdenticalInputs() {
        val first = IcsGenerator.generateEventIcs(
            title = "Weekly sync", startInstant = Instant.parse("2026-06-20T09:00:00Z"), zoneId = "Europe/London",
        )
        val second = IcsGenerator.generateEventIcs(
            title = "Weekly sync", startInstant = Instant.parse("2026-06-20T09:00:00Z"), zoneId = "Europe/London",
        )
        val uidOf = { s: String -> s.lineSequence().first { it.startsWith("UID:") } }
        assertTrue(uidOf(first) != uidOf(second))
    }
}
