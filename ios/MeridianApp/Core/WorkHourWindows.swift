import Foundation

/// Helpers for merging local working / DND windows on the 24-hour clock, including ranges
/// that wrap past midnight (e.g. 22:00–06:00). Encoding matches `FindOverlapUseCase.inWindow`:
/// `[start, end)` with wrap when `start > end`.
///
/// Pure value-type math — `Sendable` by construction. Direct port of Android `WorkHourWindows`.
enum WorkHourWindows {

    /// Expand a `[start, end)` window into the set of hours it covers (handles midnight wrap).
    static func workWindowToHours(start: Int, end: Int) -> Set<Int> {
        if start < 0 || end < 0 || start == end { return [] }
        if start < end {
            return Set(start..<end)
        } else {
            return Set(start..<24).union(Set(0..<end))
        }
    }

    /// Encodes `hours` as a single contiguous arc on the clock; falls back to 9–17 when empty.
    static func hoursToWorkWindow(_ hours: Set<Int>) -> (start: Int, end: Int) {
        if hours.isEmpty { return (9, 17) }
        if hours.count == 24 { return (0, 24) }

        let complement = (0..<24).filter { !hours.contains($0) }
        if complement.isEmpty { return (0, 24) }

        // One contiguous work arc <=> complement is one contiguous gap on the circle.
        let gapStart = complement.min()!
        let gapEnd = complement.max()!
        let gapContiguous: Bool = (gapStart <= gapEnd)
            ? (complement.count == gapEnd - gapStart + 1)
            : false

        if !gapContiguous {
            // Should not happen for intersections; pick the tightest span as a safe fallback.
            let sorted = hours.sorted()
            let last = sorted.last! + 1
            return (sorted.first!, last == 24 ? 24 : last)
        }

        let start = (gapEnd + 1) % 24
        let end = gapStart
        return (start, end)
    }

    /// Latest start / earliest end overlap across all windows (may wrap).
    static func intersectWorkWindows(_ windows: [(start: Int, end: Int)]) -> (start: Int, end: Int) {
        guard let first = windows.first else { return (9, 17) }
        var hours = workWindowToHours(start: first.start, end: first.end)
        for window in windows.dropFirst() {
            hours = hours.intersection(workWindowToHours(start: window.start, end: window.end))
            if hours.isEmpty { break }
        }
        return hoursToWorkWindow(hours)
    }

    /// Union of DND hours — a slot is blocked if any participant is in DND.
    static func unionDndWindows(_ windows: [(start: Int, end: Int)]) -> (start: Int, end: Int) {
        let active = windows.filter { (0...23).contains($0.start) && (0...23).contains($0.end) }
        if active.isEmpty { return (-1, -1) }
        var hours = Set<Int>()
        for window in active {
            hours.formUnion(workWindowToHours(start: window.start, end: window.end))
        }
        if hours.isEmpty { return (-1, -1) }
        return hoursToWorkWindow(hours)
    }
}
