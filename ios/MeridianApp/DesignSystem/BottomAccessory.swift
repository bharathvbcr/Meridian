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

    @Environment(\.glassOpacity) private var glassOpacity
    @Environment(\.glassEnabled) private var glassEnabled
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: visible)
    }

    @ViewBuilder
    private func pill(for task: PlannedTask, now: Date) -> some View {
        let alphas = ScrubberGlass.alphas(opacity: glassOpacity)
        let countdown = CountdownFormatter.countdown(to: task.timestamp, now: now)

        HStack(spacing: 0) {
            Image(systemName: "clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MeridianColors.primary)

            Spacer().frame(width: 10)

            Text(task.title)
                .font(.system(size: 12, weight: .bold))   // labelMedium + Bold
                .foregroundStyle(MeridianColors.onSurface)
                .lineLimit(1)

            Spacer().frame(width: 8)

            Text("in \(countdown)")
                .font(.system(size: 12, weight: .semibold))   // labelMedium
                .foregroundStyle(Color(hex: "FF6B6B"))         // error / countdown red
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            // Solid scrim over the glass so the title + countdown stay legible,
            // matching the time-scrubber pills.
            Capsule(style: .continuous)
                .fill(MeridianColors.surface.opacity(alphas.pillTint))
        }
        .background {
            // Frosted glass backing (or the milkier material per the frosted flag).
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
        .padding(.horizontal, 24)
        .padding(.bottom, 96)
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
