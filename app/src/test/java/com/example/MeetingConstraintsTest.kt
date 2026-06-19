package com.example

import com.example.core.time.FindOverlapUseCase
import com.example.core.time.LocalView
import com.example.core.time.MeetingParticipant
import com.example.core.time.RotationPlanner
import com.example.core.time.TimeEngine
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MeetingConstraintsTest {

    private class TestClock(private val fixed: Instant) : Clock {
        override fun now(): Instant = fixed
    }

    private val useCase = FindOverlapUseCase(TimeEngine(TestClock(Instant.parse("2026-06-16T00:00:00Z"))))
    private val base = Instant.parse("2026-06-16T00:00:00Z")

    @Test
    fun customWorkingWindowShiftsTheBestSlot() {
        // A single UTC participant who works 0-8 should get a best slot inside that window.
        val slots = useCase.rankParticipantSlots(
            base,
            listOf(MeetingParticipant("UTC", workStartHour = 0, workEndHour = 8)),
        )
        val bestHour = slots.first().localHours.getValue("UTC")
        assertTrue("best hour $bestHour", bestHour in 0..7)
        assertEquals(LocalView.WORKING, slots.first().localViews.getValue("UTC"))
    }

    @Test
    fun dndWindowIsTreatedAsUnavailable() {
        // Working 0-23 but DND 9-17: the 9-17 hours must rank worse than the rest.
        val slots = useCase.rankParticipantSlots(
            base,
            listOf(MeetingParticipant("UTC", workStartHour = 0, workEndHour = 24, dndStartHour = 9, dndEndHour = 17)),
        )
        val worst = slots.last().localHours.getValue("UTC")
        assertTrue("worst hour $worst should be inside DND 9..16", worst in 9..16)
        assertTrue(slots.any { it.hasDnd })
    }

    @Test
    fun rotatingSeriesSpreadsTheBurdenAcrossWeeks() {
        // Two far-apart zones: the rotation should not pick the same time every week.
        val slots = useCase.calculateBestOverlapSlots(
            base,
            listOf(kotlinx.datetime.TimeZone.of("America/Los_Angeles"), kotlinx.datetime.TimeZone.of("Asia/Tokyo")),
        )
        val series = RotationPlanner.rotatingSeries(slots, 4)
        assertEquals(4, series.size)
        val distinctTimes = series.map { it.utcStartInstant }.distinct()
        assertEquals(4, distinctTimes.size)
    }
}
