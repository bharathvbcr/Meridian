package com.example

import com.example.core.time.WorkHourWindows
import com.example.feature.planner.buildMeetingParticipants
import com.example.core.data.Person
import com.example.core.data.SavedZone
import com.example.feature.planner.buildParticipantLocationGroups
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkHourWindowsTest {

    @Test
    fun intersectNormalWindowsUsesLatestStartAndEarliestEnd() {
        val merged = WorkHourWindows.intersectWorkWindows(listOf(9 to 17, 10 to 18, 8 to 16))
        assertEquals(10 to 16, merged)
    }

    @Test
    fun intersectOvernightWindowsKeepsNightHours() {
        val merged = WorkHourWindows.intersectWorkWindows(listOf(22 to 6, 23 to 7))
        assertEquals(23 to 6, merged)
    }

    @Test
    fun intersectMixedDayAndNightFindsOverlap() {
        val merged = WorkHourWindows.intersectWorkWindows(listOf(20 to 4, 22 to 6))
        assertEquals(22 to 4, merged)
    }

    @Test
    fun meetingParticipantsMergeOvernightShifts() {
        val nightOwl = Person(
            id = 1,
            name = "Night",
            zoneId = "America/Denver",
            locationName = "Denver",
            isFavorite = true,
            workStartHour = 22,
            workEndHour = 6,
        )
        val lateNight = Person(
            id = 2,
            name = "Late",
            zoneId = "America/Denver",
            locationName = "Denver",
            isFavorite = true,
            workStartHour = 23,
            workEndHour = 7,
        )
        val groups = buildParticipantLocationGroups(
            listOf(SavedZone(id = "America/Denver", displayName = "Denver", isFavorite = true)),
            listOf(nightOwl, lateNight),
        )

        val participants = buildMeetingParticipants(
            localZoneId = "America/Chicago",
            groups = groups,
            selectedZones = mapOf("America/Denver" to true),
            selectedPeople = mapOf(1 to true, 2 to true),
        )

        val mountain = participants.single { it.zoneId == "America/Denver" }
        assertEquals(23, mountain.workStartHour)
        assertEquals(6, mountain.workEndHour)
    }

    @Test
    fun unionDndWindowsBlocksEitherParticipantSleep() {
        val merged = WorkHourWindows.unionDndWindows(listOf(22 to 7, 0 to 8))
        assertTrue(WorkHourWindows.workWindowToHours(merged.first, merged.second).contains(23))
        assertTrue(WorkHourWindows.workWindowToHours(merged.first, merged.second).contains(7))
    }
}
