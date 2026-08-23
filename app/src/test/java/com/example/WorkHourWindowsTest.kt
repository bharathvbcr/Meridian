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

    @Test
    fun disjointWorkIntersectionNeverOverCovers() {
        // 08–20 ∩ overnight 18–10 = {8,9,18,19}: two arcs on the circle. The merged window must
        // never claim hours outside the true intersection — 10:00–17:00 belongs to neither person.
        val merged = WorkHourWindows.intersectWorkWindows(listOf(8 to 20, 18 to 10))
        val claimed = WorkHourWindows.workWindowToHours(merged.first, merged.second)
        val truth = WorkHourWindows.workWindowToHours(8, 20)
            .intersect(WorkHourWindows.workWindowToHours(18, 10))
        assertTrue("claimed $claimed must be a subset of true intersection $truth", claimed.all { it in truth })
    }

    @Test
    fun emptyWorkIntersectionIsNotFabricatedAsNineToFive() {
        // Day worker 9–17 and night worker 18–02 share no working hour. The merge must not
        // silently invent the default 9–5 window (start == end encodes "no window").
        val merged = WorkHourWindows.intersectWorkWindows(listOf(9 to 17, 18 to 2))
        assertTrue("empty intersection must not fabricate coverage (got $merged)", merged.first == merged.second)
        assertTrue(WorkHourWindows.workWindowToHours(merged.first, merged.second).isEmpty())
    }

    @Test
    fun disjointDndUnionNeverOverBlocks() {
        // DND 22–06 ∪ DND 12–14 is two arcs. The merged window must never block hours that are
        // in neither window (6–11 were wrongly blocked as DND before).
        val merged = WorkHourWindows.unionDndWindows(listOf(22 to 6, 12 to 14))
        val claimed = WorkHourWindows.workWindowToHours(merged.first, merged.second)
        val truth = WorkHourWindows.workWindowToHours(22, 6).union(WorkHourWindows.workWindowToHours(12, 14))
        assertTrue("claimed DND $claimed must be a subset of union $truth", claimed.all { it in truth })
    }

    @Test
    fun disjointWorkIntersectionKeepsTheLargestSharedArc() {
        // Of {8,9} and {18,19}, either arc is honest — but one of them must be kept, not dropped.
        val merged = WorkHourWindows.intersectWorkWindows(listOf(8 to 20, 18 to 10))
        val claimed = WorkHourWindows.workWindowToHours(merged.first, merged.second)
        assertTrue(
            "largest shared arc must be preserved (got $merged → $claimed)",
            claimed.containsAll(setOf(8, 9)) || claimed.containsAll(setOf(18, 19)),
        )
    }
}
