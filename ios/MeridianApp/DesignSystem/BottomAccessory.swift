// BottomAccessory.swift
// Meridian — iOS 27 / Swift 6
//
// Ported from app/src/main/java/com/example/ui/components/BottomAccessory.kt
//
// The glass bar's "now playing"-style bottom accessory: a slim pill that surfaces
// the next upcoming task with a live countdown. Materializes only when the next
// task is within one hour, and is additionally gated by the contract:
//   - the current tab is NOT in {world, plan, ai}, and
//   - the timeline scrubber is not active (no scrub instant).
//
// A `TimelineView(.periodic by: 1)` drives the per-second countdown, mirroring the
// Android `LaunchedEffect { delay(1000) }` loop.

import SwiftUI

/// Slim countdown pill for the next task within one hour.
struct BottomAccessory: View {

    /// Upcoming tasks (any order); the soonest future one is selected.
    let tasks: [PlannedTask]
    /// The current tab — used to gate visibility (hidden on world / plan / ai).
    let tab: MeridianTab
    /// Caller-side enable flag (e.g. accessory preference). Defaults to `true`.
    var enabled: Bool = true
    /// When `true`, the parent positions the pill (e.g. `ContentView` overlay). Skips built-in padding.
    var embedded: Bool = false
    /// Optional tap handler — e.g. jump to the Plan tab.
    var onTap: (() -> Void)? = nil

    @Environment(\.glassOpacity) private var glassOpacity
    @Environment(\.reduceTransparencyOverride) private var reduceTransparency

    /// Tabs on which the accessory is suppressed (own glass chrome / scrubber owns the space).
    private static let suppressedTabs: Set<MeridianTab> = [.world, .plan, .ai]

    var body: some View {
        // Suppressed tabs hide the accessory entirely. The scrubber-active gate is read
        // from the shared TimeEngine (no active scrub instant required to show).
        let tabAllows = !Self.suppressedTabs.contains(tab)
        let scrubbing = TimeEngine.shared.isScrubbing

        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date, visibleByGate: enabled && tabAllows && !scrubbing)
        }
    }

    @ViewBuilder
    private func content(now: Date, visibleByGate: Bool) -> some View {
        let next = tasks
            .filter { $0.timestamp > now }
            .min(by: { $0.timestamp < $1.timestamp })

        let remaining = next.map { $0.timestamp.timeIntervalSince(now) }
        let withinWindow = (remaining ?? .greatestFiniteMagnitude) < CountdownFormatter.accessoryWindow
        let visible = visibleByGate && withinWindow && next != nil

        Group {
            if visible, let task = next {
                pill(for: task, now: now)
                    // Reduce-Motion collapses the slide-up to a plain cross-fade;
                    // for a control that materializes unexpectedly, a gentle fade
                    // is the WCAG-preferred substitute for the move choreography.
                    .meridianTransition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .meridianAnimation(Motion.snappy(), value: visible)
    }

    @ViewBuilder
    private func pill(for task: PlannedTask, now: Date) -> some View {
        let alphas = ScrubberGlass.alphas(opacity: glassOpacity)
        let countdown = CountdownFormatter.countdown(to: task.timestamp, now: now)

        let content = HStack(spacing: MeridianSpacing.sm.rawValue) {
            Image(systemName: "clock")
                .font(.system(size: Self.iconSize, weight: .semibold))
                .foregroundStyle(MeridianColors.primary)
                .accessibilityHidden(true)

            // Task name reads first — larger, semibold title rung.
            Text(task.title)
                .font(.titleMedium)
                .foregroundStyle(MeridianColors.onSurface)
                .lineLimit(1)
                .layoutPriority(1)

            // Countdown is the supporting detail — a rung smaller, brand-tinted
            // (informational, not an error). Fixed monospaced digits so the
            // per-second tick doesn't jitter the layout.
            Text("in \(countdown)")
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.primary)
                .monospacedDigit()
                .accessibilityHidden(true)

            if onTap != nil {
                Image(systemName: "chevron.up")
                    .font(.labelSmall)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, MeridianSpacing.lg.rawValue)
        .padding(.vertical, MeridianSpacing.md.rawValue)
        .frame(minHeight: Self.minHeight)
        .background {
            Capsule(style: .continuous)
                .fill(MeridianColors.accessoryPillTint(opacity: glassOpacity))
        }
        .background {
            if reduceTransparency {
                Capsule(style: .continuous).fill(MeridianColors.surface)
            } else {
                Capsule(style: .continuous)
                    .fill(alphas.frosted ? AnyShapeStyle(.regularMaterial)
                                         : AnyShapeStyle(.ultraThinMaterial))
            }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1)
        }
        .clipShape(Capsule(style: .continuous))
        .contentShape(Capsule())

        Group {
            if let onTap {
                Button(action: onTap) { content }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(task.title), starting in \(countdown)")
                    .accessibilityHint("Opens the planner")
                    .accessibilityAddTraits([.isButton, .updatesFrequently])
            } else {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(task.title), starting in \(countdown)")
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .modifier(EmbeddedPaddingModifier(embedded: embedded))
    }

    // MARK: - Layout constants

    /// Icon point size, matched to the nav / scrubber pill convention (20).
    private static let iconSize: CGFloat = ScrubberPillDefaults.iconSize
    /// Minimum pill height — guarantees a >=44 pt (48 pt, matching the scrubber
    /// pill) touch target and gives scaled Dynamic Type headroom before clipping.
    private static let minHeight: CGFloat = ScrubberPillDefaults.minHeight
}

// MARK: - Embedded padding

private struct EmbeddedPaddingModifier: ViewModifier {
    let embedded: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .padding(.horizontal, MeridianSpacing.xxl.rawValue)
                // Clears the floating tab bar. Expressed on the spacing scale
                // (24 x 4 = 96) rather than a bare literal.
                .padding(.bottom, MeridianSpacing.xxl.rawValue * 4)
        }
    }
}

#if DEBUG
#Preview("BottomAccessory") {
    ZStack {
        MeridianColors.background.ignoresSafeArea()
        VStack {
            Spacer()
            BottomAccessory(
                tasks: [
                    {
                        let t = PlannedTask(title: "Standup with Berlin", timestamp: Date().addingTimeInterval(20 * 60), tzId: "Europe/Berlin")
                        return t
                    }()
                ],
                tab: .now
            )
        }
    }
    .environment(\.glassOpacity, 0.6)
}
#endif
