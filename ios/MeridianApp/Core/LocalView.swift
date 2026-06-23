import Foundation

/// How a wall-clock hour reads for a participant, used to annotate meeting slots.
///
/// Carried as an explicit enum (never color alone) so each state pairs with an icon + label.
/// Ordering matches Android's enum ordinals so "worst" comparisons stay identical:
/// `asleep (0) < outsideHours (1) < working (2) < awake (3)`.
/// A LOWER value is a WORSE local view (asleep is the worst burden).
enum LocalView: Int, Comparable, Sendable, CaseIterable {
    case asleep        = 0
    case outsideHours  = 1
    case working       = 2
    case awake         = 3

    static func < (lhs: LocalView, rhs: LocalView) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
