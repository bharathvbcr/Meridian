package com.example.core.time

/**
 * Helpers for merging local working / DND windows on the 24-hour clock, including ranges that
 * wrap past midnight (e.g. 22:00–06:00). Encoding matches [FindOverlapUseCase.inWindow]:
 * [start, end) with wrap when start > end.
 */
internal object WorkHourWindows {

    fun workWindowToHours(start: Int, end: Int): Set<Int> = when {
        start < 0 || end < 0 || start == end -> emptySet()
        start < end -> (start until end).toSet()
        else -> ((start until 24) + (0 until end)).toSet()
    }

    /** Encodes [hours] as a single contiguous arc on the clock; falls back to 9–17 when empty. */
    fun hoursToWorkWindow(hours: Set<Int>): Pair<Int, Int> {
        if (hours.isEmpty()) return 9 to 17
        if (hours.size == 24) return 0 to 24

        val complement = (0 until 24).filter { it !in hours }
        if (complement.isEmpty()) return 0 to 24

        // One contiguous work arc <=> complement is one contiguous gap on the circle.
        val gapStart = complement.min()
        val gapEnd = complement.max()
        val gapContiguous = if (gapStart <= gapEnd) {
            complement.size == gapEnd - gapStart + 1
        } else {
            false
        }
        if (!gapContiguous) {
            // Should not happen for intersections; pick the tightest span as a safe fallback.
            val sorted = hours.sorted()
            return sorted.first() to (sorted.last() + 1).let { if (it == 24) 24 else it }
        }

        val start = (gapEnd + 1) % 24
        val end = gapStart
        return if (start < end) start to end else start to end
    }

    /** Latest start / earliest end overlap across all windows (may wrap). */
    fun intersectWorkWindows(windows: List<Pair<Int, Int>>): Pair<Int, Int> {
        if (windows.isEmpty()) return 9 to 17
        var hours = workWindowToHours(windows.first().first, windows.first().second)
        for (window in windows.drop(1)) {
            hours = hours intersect workWindowToHours(window.first, window.second)
            if (hours.isEmpty()) break
        }
        return hoursToWorkWindow(hours)
    }

    /** Union of DND hours — a slot is blocked if any participant is in DND. */
    fun unionDndWindows(windows: List<Pair<Int, Int>>): Pair<Int, Int> {
        val active = windows.filter { it.first in 0..23 && it.second in 0..23 }
        if (active.isEmpty()) return -1 to -1
        val hours = active
            .map { workWindowToHours(it.first, it.second) }
            .reduce { acc, next -> acc union next }
        if (hours.isEmpty()) return -1 to -1
        return hoursToWorkWindow(hours)
    }
}
