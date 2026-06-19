package com.example.core.time

import com.example.core.time.FindOverlapUseCase.OverlapSlot

/**
 * Builds a *rotating* series for a standing cross-zone meeting so the inconvenient hour moves
 * between regions week to week (§5.8). Greedy: each week picks the fairest remaining slot while
 * penalizing reuse of the region that has most recently borne the worst hour.
 */
object RotationPlanner {

    private const val REUSE_PENALTY = 50.0

    fun rotatingSeries(slots: List<OverlapSlot>, count: Int): List<OverlapSlot> {
        if (slots.isEmpty() || count <= 0) return emptyList()
        val used = mutableSetOf<Long>()
        val burden = mutableMapOf<String, Int>()
        val picks = mutableListOf<OverlapSlot>()

        repeat(count) {
            val candidate = slots
                .filter { it.utcStartInstant.toEpochMilliseconds() !in used }
                .minByOrNull { slot -> slot.rankScore + (burden[worstZone(slot)] ?: 0) * REUSE_PENALTY }
                ?: return picks

            picks.add(candidate)
            used.add(candidate.utcStartInstant.toEpochMilliseconds())
            worstZone(candidate)?.let { zone -> burden[zone] = (burden[zone] ?: 0) + 1 }
        }
        return picks
    }

    /** The zone bearing the worst local view in a slot (ASLEEP is worst → lowest enum ordinal). */
    private fun worstZone(slot: OverlapSlot): String? =
        slot.localViews.entries.minByOrNull { it.value.ordinal }?.key
}
