package com.example.core.time

import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toJavaInstant
import kotlinx.datetime.toKotlinInstant
import java.time.temporal.ChronoUnit
import kotlin.math.min
import kotlin.math.sqrt

/**
 * A participant in a meeting search: a time zone plus that person's working window and an optional
 * do-not-disturb window (§5.8). Defaults model a 9–5 worker with no DND.
 */
data class MeetingParticipant(
    val zoneId: String,
    val workStartHour: Int = 9,
    val workEndHour: Int = 17,
    val dndStartHour: Int = -1,
    val dndEndHour: Int = -1,
)

class FindOverlapUseCase(
    private val timeEngine: TimeEngine
) {

    data class OverlapSlot(
        val utcStartInstant: Instant,
        val localHours: Map<String, Int>,       // ZoneId -> local hour (0-23)
        val localViews: Map<String, LocalView>, // ZoneId -> awake/working/asleep tag
        val totalDiscomfort: Double,
        val standardDeviation: Double,
        val hasDnd: Boolean,
        val ratingLabel: String,                 // "Optimal", "Fair", "Difficult"
        val rankScore: Double                    // Lower is fairer & better
    )

    /** Zone-only convenience: ranks slots treating every zone as a default 9–5 worker. */
    fun calculateBestOverlapSlots(
        baseDateInstant: Instant,
        participantZones: List<TimeZone>
    ): List<OverlapSlot> =
        rankParticipantSlots(baseDateInstant, participantZones.map { MeetingParticipant(it.id) })

    /**
     * Finds and ranks 24 hourly meeting slots over the day starting at [baseDateInstant], scoring
     * each participant against their own working/DND window (§5.8). Lower rankScore = fairer.
     */
    fun rankParticipantSlots(
        baseDateInstant: Instant,
        participants: List<MeetingParticipant>
    ): List<OverlapSlot> {
        if (participants.isEmpty()) return emptyList()

        val startOfWindow = baseDateInstant.toJavaInstant().truncatedTo(ChronoUnit.HOURS)

        val results = mutableListOf<OverlapSlot>()

        for (hourOffset in 0 until 24) {
            val slotInstant = startOfWindow.plusSeconds(hourOffset * 3600L).toKotlinInstant()

            val localHours = mutableMapOf<String, Int>()
            val localViews = mutableMapOf<String, LocalView>()
            val distressList = mutableListOf<Double>()
            var isAnyDnd = false

            for (participant in participants) {
                val zone = TimeZone.of(participant.zoneId)
                val hour = timeEngine.toZonedDateTime(slotInstant, zone).hour
                val distress = discomfortFor(hour, participant)
                distressList.add(distress)
                if (inDndWindow(hour, participant)) isAnyDnd = true

                // Representative view per zone (first participant seen for that zone wins).
                if (participant.zoneId !in localViews) {
                    localHours[participant.zoneId] = hour
                    localViews[participant.zoneId] = viewFor(hour, participant)
                }
            }

            val n = distressList.size
            val sum = distressList.sum()
            val mean = sum / n
            val stdDev = sqrt(distressList.sumOf { (it - mean) * (it - mean) } / n)

            val ratingLabel = when {
                isAnyDnd -> "Difficult"
                sum <= n * 1.5 -> "Optimal"
                else -> "Fair"
            }
            val dndPenalty = if (isAnyDnd) 1000.0 else 0.0
            val rankScore = sum * 10.0 + stdDev + dndPenalty

            results.add(
                OverlapSlot(
                    utcStartInstant = slotInstant,
                    localHours = localHours,
                    localViews = localViews,
                    totalDiscomfort = sum,
                    standardDeviation = stdDev,
                    hasDnd = isAnyDnd,
                    ratingLabel = ratingLabel,
                    rankScore = rankScore
                )
            )
        }

        return results.sortedBy { it.rankScore }
    }

    /** Discomfort cost of a local [hour] for [p]: 0 inside the working window, rising with distance. */
    private fun discomfortFor(hour: Int, p: MeetingParticipant): Double {
        if (inDndWindow(hour, p)) return 8.0
        if (inWindow(hour, p.workStartHour, p.workEndHour)) return 0.0
        return when (hoursOutsideWindow(hour, p.workStartHour, p.workEndHour)) {
            in 0..2 -> 1.5
            in 3..4 -> 3.0
            else -> 6.0
        }
    }

    private fun viewFor(hour: Int, p: MeetingParticipant): LocalView = when {
        inDndWindow(hour, p) -> LocalView.ASLEEP
        inWindow(hour, p.workStartHour, p.workEndHour) -> LocalView.WORKING
        hoursOutsideWindow(hour, p.workStartHour, p.workEndHour) <= 2 -> LocalView.AWAKE
        hoursOutsideWindow(hour, p.workStartHour, p.workEndHour) <= 4 -> LocalView.OUTSIDE_HOURS
        else -> LocalView.ASLEEP
    }

    private fun inDndWindow(hour: Int, p: MeetingParticipant): Boolean =
        p.dndStartHour in 0..23 && p.dndEndHour in 0..23 && inWindow(hour, p.dndStartHour, p.dndEndHour)

    /** True if [hour] falls in [start, end); supports windows that wrap past midnight. */
    private fun inWindow(hour: Int, start: Int, end: Int): Boolean {
        if (start < 0 || end < 0 || start == end) return false
        return if (start < end) hour in start until end else hour >= start || hour < end
    }

    /** Circular distance in hours from [hour] to the nearest edge of the working window. */
    private fun hoursOutsideWindow(hour: Int, start: Int, end: Int): Int {
        if (inWindow(hour, start, end)) return 0
        val lastWorkingHour = (end + 23) % 24 // end is exclusive
        return min(circularDistance(hour, start), circularDistance(hour, lastWorkingHour))
    }

    private fun circularDistance(a: Int, b: Int): Int {
        val diff = ((a - b) % 24 + 24) % 24
        return min(diff, 24 - diff)
    }
}
