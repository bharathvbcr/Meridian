import SwiftUI

// MARK: - Motion

/// Namespace for Meridian's standard animation curves, ported from Android's `Motion`
/// (Motion.kt). All animations use spring physics for a natural, fluid feel.
enum Motion {

    /// Smooth, critically-damped spring — no overshoot. Android: dampingRatio 1.0, stiffness 300.
    /// Great for expanding panels and large transitions.
    static func smooth() -> Animation {
        .spring(response: 0.5, dampingFraction: 1.0)
    }

    /// Bouncy spring — playful overshoot for cards, badges, FABs.
    /// Android: dampingRatio 0.7, stiffness 300.
    static func bouncy() -> Animation {
        .spring(response: 0.5, dampingFraction: 0.7)
    }

    /// Snappy spring — tight, confident feel for toggles and selections.
    /// Android: dampingRatio 0.85, stiffness 400.
    static func snappy() -> Animation {
        .spring(response: 0.35, dampingFraction: 0.85)
    }

    /// Quick spring — fast micro-interactions, icon presses, haptic confirmations.
    static func quick() -> Animation {
        .spring(response: 0.2, dampingFraction: 0.85)
    }

    /// Bouncy expand / smooth tuck-away for scrubber pill ↔ dial transitions.
    /// Mirrors Android's `scrubberExpandCollapseTransform`: the size morph never overshoots
    /// (a bouncy size spring can yield negative interim padding), while the content
    /// fades/scales with a gentle bounce on expand and a smooth settle on collapse.
    static func scrubberExpandCollapse(expanding: Bool) -> Animation {
        expanding
            ? .spring(response: 0.45, dampingFraction: 1.0)   // StiffnessMediumLow, no bounce
            : .spring(response: 0.35, dampingFraction: 1.0)   // StiffnessMedium, no bounce
    }

    /// Content transition pairing for the scrubber pill ↔ dial swap. Use with
    /// `.transition(Motion.scrubberContentTransition)` on the swapped subviews.
    static var scrubberContentTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity)
                .combined(with: .move(edge: .bottom)),
            removal: .scale(scale: 0.94).combined(with: .opacity)
        )
    }
}
