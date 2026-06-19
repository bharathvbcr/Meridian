package com.example

import com.example.core.time.IcsGenerator
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
}
