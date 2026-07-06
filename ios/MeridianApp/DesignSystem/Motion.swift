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

    // MARK: - Reduce Motion

    /// Near-instant animation used as the Reduce-Motion substitute. Not fully
    /// instant (a hair of duration) so SwiftUI still coalesces the state change
    /// into a single frame transition rather than a hard, un-animated snap,
    /// which keeps `withAnimation` completion callbacks and transitions intact.
    static let instant: Animation = .linear(duration: 0.01)

    /// Reduce-Motion-aware wrapper for any base animation. Pass the value read
    /// from `@Environment(\.accessibilityReduceMotion)`. Returns `nil` when
    /// Reduce Motion is on so callers can use `.animation(nil, value:)` /
    /// `withAnimation(nil)` to opt out of motion entirely, while still driving
    /// the same state change. When motion is allowed, the base spring is
    /// returned unchanged.
    ///
    /// Usage:
    /// ```swift
    /// @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// withAnimation(Motion.reduced(Motion.snappy(), reduceMotion: reduceMotion)) { … }
    /// ```
    static func reduced(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }

    /// Reduce-Motion-aware variant that always yields a concrete `Animation`
    /// (never `nil`), collapsing to a near-instant curve when Reduce Motion is
    /// on. Prefer this when a call site needs a non-optional animation — e.g.
    /// `.animation(Motion.reducedOrInstant(Motion.smooth(), reduceMotion: rm), value:)`.
    static func reducedOrInstant(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? instant : base
    }

    /// Reduce-Motion-aware size-morph spring for the scrubber. Collapses the
    /// pill ↔ dial resize to a near-instant curve when Reduce Motion is on;
    /// otherwise defers to `scrubberExpandCollapse(expanding:)`.
    static func scrubberExpandCollapse(expanding: Bool, reduceMotion: Bool) -> Animation {
        reduceMotion ? instant : scrubberExpandCollapse(expanding: expanding)
    }

    /// Reduce-Motion-aware content transition for the scrubber pill ↔ dial swap.
    /// Under Reduce Motion this drops the scale/move choreography and cross-fades
    /// with opacity only (the WCAG-recommended fallback for large motion), while
    /// still honouring the user's request to avoid movement. Otherwise it returns
    /// the full `scrubberContentTransition`.
    static func scrubberContentTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : scrubberContentTransition
    }
}

// MARK: - Reduce-Motion View Helpers

extension View {
    /// One-line Reduce-Motion-aware animation. Equivalent to
    /// `.animation(Motion.reduced(base, reduceMotion:), value:)` but reads the
    /// environment for you, so consumers never need to thread the flag manually.
    ///
    /// Usage: `someView.meridianAnimation(Motion.snappy(), value: isSelected)`
    func meridianAnimation<V: Equatable>(_ base: Animation, value: V) -> some View {
        modifier(ReduceMotionAnimationModifier(base: base, value: value))
    }

    /// One-line Reduce-Motion-aware transition. Applies `full` when motion is
    /// allowed and collapses to a plain cross-fade when Reduce Motion is on,
    /// reading `\.accessibilityReduceMotion` for the consumer so no call site
    /// has to thread the flag. `.opacity` is the WCAG-recommended substitute for
    /// scale/move choreography under Reduce Motion.
    ///
    /// Usage: `subview.meridianTransition(Motion.scrubberContentTransition)`
    func meridianTransition(_ full: AnyTransition) -> some View {
        modifier(ReduceMotionTransitionModifier(full: full))
    }
}

/// Runs `body` inside `withAnimation`, honouring Reduce Motion by passing `nil`
/// (no motion) when the flag is set. This is the imperative sibling of
/// `View.meridianAnimation(_:value:)` for state mutations that live outside a
/// view body (button actions, gesture handlers). The caller supplies the flag
/// read from `@Environment(\.accessibilityReduceMotion)`, keeping the call site
/// a single line while preserving `withAnimation`'s completion semantics.
///
/// Usage:
/// ```swift
/// @Environment(\.accessibilityReduceMotion) private var reduceMotion
/// Button("Expand") { withMeridianAnimation(Motion.bouncy(), reduceMotion: reduceMotion) { expanded.toggle() } }
/// ```
@discardableResult
func withMeridianAnimation<Result>(
    _ base: Animation,
    reduceMotion: Bool,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(Motion.reduced(base, reduceMotion: reduceMotion), body)
}

/// Backing modifier for `View.meridianAnimation(_:value:)`. Reads
/// `\.accessibilityReduceMotion` and applies `nil` animation when Reduce Motion
/// is enabled, letting the value change apply without motion.
private struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
    let base: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.reduced(base, reduceMotion: reduceMotion), value: value)
    }
}

/// Backing modifier for `View.meridianTransition(_:)`. Reads
/// `\.accessibilityReduceMotion` and substitutes a plain `.opacity` cross-fade
/// for the supplied transition when Reduce Motion is enabled.
private struct ReduceMotionTransitionModifier: ViewModifier {
    let full: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : full)
    }
}
