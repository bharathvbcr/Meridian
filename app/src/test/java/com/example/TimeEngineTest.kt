package com.example

import com.example.core.time.TimeEngine
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.ZoneId

class TimeEngineTest {

    // A deterministic Clock implementation for test stability
    private class TestClock(private var currentInstant: Instant) : Clock {
        override fun now(): Instant = currentInstant
    }

    @Test
    fun testCurrentInstantAndScrubbing() {
        val initialInstant = Instant.parse("2026-06-16T12:00:00Z")
        val testClock = TestClock(initialInstant)
        val engine = TimeEngine(testClock)

        // Verifies default scrub instant starts as null
        assertNull(engine.scrubInstant.value)

        // Verifies the now() bridging yields the correct instant
        assertEquals(initialInstant.toEpochMilliseconds(), engine.now().toEpochMilli())

        // Update scrub and verify the change
        val scrubbedValue = java.time.Instant.parse("2026-06-16T15:30:00Z")
        engine.updateScrub(scrubbedValue)
        assertEquals(scrubbedValue, engine.scrubInstant.value)

        // Clearing scrub
        engine.updateScrub(null)
        assertNull(engine.scrubInstant.value)
    }

    @Test
    fun testZonedDateTimeConversionsWithoutManualOffset() {
        val clockInstant = Instant.parse("2026-06-16T12:00:00Z")
        val testClock = TestClock(clockInstant)
        val engine = TimeEngine(testClock)

        // Resolves to India Standard Time (UTC+5:30)
        val jZoneId = ZoneId.of("Asia/Kolkata")
        val zonedDateTime = engine.getScrubbedZonedDateTime(jZoneId)

        assertEquals(2026, zonedDateTime.year)
        assertEquals(6, zonedDateTime.monthValue)
        assertEquals(16, zonedDateTime.dayOfMonth)
        assertEquals(17, zonedDateTime.hour)
        assertEquals(30, zonedDateTime.minute)

        // Update the scrubber reference instant
        val scrubbedValue = java.time.Instant.parse("2026-06-16T04:00:00Z")
        engine.updateScrub(scrubbedValue)

        // Resolves to America/New_York (UTC-4 in Daylight Saving Time)
        val zoneIdNewYork = ZoneId.of("America/New_York")
        val zonedDateTimeNY = engine.getScrubbedZonedDateTime(zoneIdNewYork)

        assertEquals(0, zonedDateTimeNY.hour)
        assertEquals(0, zonedDateTimeNY.minute)
    }

    @Test
    fun testKotlinToJavaBridges() {
        val initialInstant = Instant.parse("2026-06-16T12:00:00Z")
        val testClock = TestClock(initialInstant)
        val engine = TimeEngine(testClock)

        val javaInst = java.time.Instant.ofEpochMilli(1718541978000L)
        val kotlinInst = engine.javaToKotlinInstant(javaInst)
        assertEquals(1718541978000L, kotlinInst.toEpochMilliseconds())

        val backToJava = engine.kotlinToJavaInstant(kotlinInst)
        assertEquals(javaInst, backToJava)
    }
}
