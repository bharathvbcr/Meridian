package com.example.core.time

/**
 * Helpers for merging local working / DND windows on the 24-hour clock, including ranges that
 * wrap past midnight (e.g. 22:00–06:00). Encoding matches [FindOverlapUseCase.inWindow]:
 * [start, end) with wrap when start > end, and start == end meaning "no window at all".
 *
 * A single arc cannot represent every set of hours (an intersection of two overnight windows can
 * be two disjoint arcs), so when a merge yields multiple islands the helpers keep the **largest
 * contiguous arc** — a conservative subset — and never fabricate coverage for hours outside the
 * true result.
 */
internal object WorkHourWindows {

    fun workWindowToHours(start: Int, end: Int): Set<Int> = when {
        start < 0 || end < 0 || start == end -> emptySet()
        start < end -> (start until end).toSet()
        else -> ((start until 24) + (0 until end)).toSet()
    }

    /**
     * Encodes [hours] as the largest contiguous arc on the clock. An empty set encodes "no window"
     * (start == end), never a fabricated default; multi-island sets degrade to their biggest arc.
     */
    fun hoursToWorkWindow(hours: Set<Int>): Pair<Int, Int> {
        if (hours.isEmpty()) return 0 to 0
        if (hours.size == 24) return 0 to 24
        return largestContiguousArc(hours)
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

    /**
     * Union of DND hours — a slot is blocked if any participant is in DND. When the union is
     * several arcs, the largest one is kept so blocking is under-approximated (a slot nobody's
     * DND blocks is never penalized as blocked, and no non-DND hour is ever reported as DND).
     */
    fun unionDndWindows(windows: List<Pair<Int, Int>>): Pair<Int, Int> {
        val active = windows.filter { it.first in 0..23 && it.second in 0..23 }
        if (active.isEmpty()) return -1 to -1
        val hours = active
            .map { workWindowToHours(it.first, it.second) }
            .reduce { acc, next -> acc union next }
        if (hours.isEmpty()) return -1 to -1
        return largestContiguousArc(hours)
    }

    /**
     * Finds the longest run of consecutive hours on the 24-hour circle (wrapping through
     * midnight counts as consecutive) and encodes it as a `[start, end)` window. Ties resolve
     * to the earliest clock-hour start, keeping results deterministic.
     */
    private fun largestContiguousArc(hours: Set<Int>): Pair<Int, Int> {
        val sorted = hours.sorted()
        // Rotate so the scan starts right after a break in circular consecutiveness; any break
        // exists because hours.size < 24 here.
        var pivot = 0
        for (i in sorted.indices) {
            val prev = sorted[(i - 1 + sorted.size) % sorted.size]
            val cur = sorted[i]
            if ((prev + 1) % 24 != cur) {
                pivot = i
                break
            }
        }
        val rotated = sorted.drop(pivot) + sorted.take(pivot)

        var bestStart = rotated[0]
        var bestLength = 1
        var runStart = rotated[0]
        var runLength = 1
        for (i in 1 until rotated.size) {
            if ((rotated[i - 1] + 1) % 24 == rotated[i]) {
                runLength++
            } else {
                runStart = rotated[i]
                runLength = 1
            }
            // Strictly greater keeps the earliest-start arc on ties (rotation is ascending).
            if (runLength > bestLength) {
                bestLength = runLength
                bestStart = runStart
            }
        }
        val end = (bestStart + bestLength) % 24
        return bestStart to end
    }
}
