package com.example

import com.example.core.time.FindOverlapUseCase
import com.example.core.time.LocalView
import com.example.core.time.TimeEngine
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FindOverlapUseCaseTest {

    private class TestClock(private val fixed: Instant) : Clock {
        override fun now(): Instant = fixed
    }

    private fun useCase(now: String = "2026-06-16T00:00:00Z"): FindOverlapUseCase =
        FindOverlapUseCase(TimeEngine(TestClock(Instant.parse(now))))

    @Test
    fun returnsTwentyFourSlotsSortedByFairness() {
        val slots = useCase().calculateBestOverlapSlots(
            baseDateInstant = Instant.parse("2026-06-16T00:00:00Z"),
            participantZones = listOf(TimeZone.of("UTC"), TimeZone.of("Asia/Tokyo")),
        )
        assertEquals(24, slots.size)
        // Ranked ascending: each slot's score is <= the next.
        for (i in 0 until slots.size - 1) {
            assertTrue(slots[i].rankScore <= slots[i + 1].rankScore)
        }
    }

    @Test
    fun bestSlotForSingleZoneFallsInWorkingHours() {
        val slots = useCase().calculateBestOverlapSlots(
            baseDateInstant = Instant.parse("2026-06-16T00:00:00Z"),
            participantZones = listOf(TimeZone.of("UTC")),
        )
        val best = slots.first()
        val hour = best.localHours.getValue("UTC")
        assertTrue("best hour was $hour", hour in 9..16)
        assertEquals(LocalView.WORKING, best.localViews.getValue("UTC"))
    }

    @Test
    fun everySlotAnnotatesEveryParticipant() {
        val zones = listOf(TimeZone.of("Europe/London"), TimeZone.of("America/New_York"))
        val slots = useCase().calculateBestOverlapSlots(
            baseDateInstant = Instant.parse("2026-06-16T00:00:00Z"),
            participantZones = zones,
        )
        slots.forEach { slot ->
            zones.forEach { tz ->
                assertTrue(slot.localHours.containsKey(tz.id))
                assertTrue(slot.localViews.containsKey(tz.id))
            }
        }
    }

    @Test
    fun emptyParticipantsYieldNoSlots() {
        val slots = useCase().calculateBestOverlapSlots(
            baseDateInstant = Instant.parse("2026-06-16T00:00:00Z"),
            participantZones = emptyList(),
        )
        assertTrue(slots.isEmpty())
    }
}
