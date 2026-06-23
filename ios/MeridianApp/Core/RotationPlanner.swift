import Foundation

/// Builds a *rotating* series for a standing cross-zone meeting so the inconvenient hour moves
/// between regions week to week. Greedy: each week picks the fairest remaining slot while
/// penalizing reuse of the region that has most recently borne the worst hour.
///
/// Direct behavioral port of Android `RotationPlanner`. Stateless / `Sendable`.
enum RotationPlanner {

    private static let reusePenalty = 50.0

    /// Picks `count` slots from `slots` (expected pre-sorted ascending by rankScore), rotating the
    /// burden of the worst local view across zones. Mirrors Android `rotatingSeries`.
    ///
    /// - Parameter participantOrder: zone ids in the SAME order participants were first encountered
    ///   when `FindOverlapUseCase` built each slot's `localViews` (Android: the LinkedHashMap
    ///   insertion order). `worstZone` resolves ties on the worst view by this order to match
    ///   Kotlin's `minByOrNull` over a LinkedHashMap. When empty (legacy callers), ties fall back
    ///   to the dictionary's own iteration of distinct keys — never to zone-id sort order.
    static func rotatingSeries(
        slots: [MeetingSlot],
        count: Int,
        participantOrder: [String] = []
    ) -> [MeetingSlot] {
        guard !slots.isEmpty, count > 0 else { return [] }

        var used = Set<Date>()
        var burden: [String: Int] = [:]
        var picks: [MeetingSlot] = []

        for _ in 0..<count {
            var best: MeetingSlot? = nil
            var bestCost = Double.greatestFiniteMagnitude

            // Preserve input iteration order so ties resolve to the first (fairest) candidate,
            // matching Kotlin's `minByOrNull`.
            for slot in slots where !used.contains(slot.start) {
                let reuse = Double(worstZone(slot, order: participantOrder).flatMap { burden[$0] } ?? 0) * reusePenalty
                let cost = slot.rankScore + reuse
                if cost < bestCost {
                    bestCost = cost
                    best = slot
                }
            }

            guard let candidate = best else { return picks }

            picks.append(candidate)
            used.insert(candidate.start)
            if let zone = worstZone(candidate, order: participantOrder) {
                burden[zone, default: 0] += 1
            }
        }

        return picks
    }

    /// The zone bearing the worst local view in a slot (asleep is worst → lowest enum value).
    ///
    /// Android: `slot.localViews.entries.minByOrNull { it.value.ordinal }`. `localViews` is a
    /// LinkedHashMap whose insertion order is the participant list order; `minByOrNull` returns the
    /// FIRST entry at the minimum ordinal in that order — i.e. the first PARTICIPANT bearing the
    /// worst view. We reconstruct that participant order via `order` (the zone ids in
    /// first-encountered order) and pick the first zone present at the minimum view. Ties are
    /// broken ONLY by participant order, never by zone-id sort order.
    private static func worstZone(_ slot: MeetingSlot, order: [String]) -> String? {
        guard !slot.localViews.isEmpty else { return nil }

        // Iterate zones in participant insertion order; any zone in the slot but absent from
        // `order` (shouldn't happen) is appended afterward, preserving determinism without
        // resorting to lexicographic zone-id ordering.
        var ordered: [String] = []
        ordered.reserveCapacity(slot.localViews.count)
        var seen = Set<String>()
        for zone in order where slot.localViews[zone] != nil && seen.insert(zone).inserted {
            ordered.append(zone)
        }
        for zone in slot.localViews.keys where seen.insert(zone).inserted {
            ordered.append(zone)
        }

        var bestZone: String? = nil
        var bestView: LocalView? = nil
        for zone in ordered {
            guard let view = slot.localViews[zone] else { continue }
            // Strict `<` keeps the FIRST entry on a tie, exactly like Kotlin `minByOrNull`.
            if bestView == nil || view < bestView! {
                bestView = view
                bestZone = zone
            }
        }
        return bestZone
    }
}
