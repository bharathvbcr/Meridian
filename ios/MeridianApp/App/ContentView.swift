// ContentView.swift
// Meridian — iOS 27  Swift 6  SwiftUI
//
// Adaptive root container — the SwiftUI counterpart to Android `MainAppHost`:
//   • A gradient + time-of-day `CelestialBackdrop` sit behind everything, inside a single
//     `GlassEffectContainer`, so every glass surface refracts the same coloured backdrop
//     (Android: the Haze source layer).
//   • Compact (iPhone) → floating glass pill tab bar at the bottom, AI center-prominent,
//     with a "next event" bottom accessory above it and minimize-on-scroll.
//   • Regular (iPad)   → `GlassNavRail` on the leading edge.
//
// Tab order is now / world / ai / plan / settings, AI in the center slot (§6).

import SwiftUI
import SwiftData

// MARK: - ContentView

struct ContentView: View {

    // MARK: Input

    @Bindable var viewModel: MainViewModel

    /// The selected tab is owned by the app shell (so deep links can drive it).
    @Binding var selectedTab: MeridianTab

    // MARK: Environment

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(SettingsRepository.self) private var settingsRepo

    private var settings: MeridianSettings { settingsRepo.settings }
    private var isRegular: Bool { horizontalSizeClass == .regular }

    // MARK: Local state

    /// Drives minimize-on-scroll: the floating pill collapses to icons when content scrolls
    /// down and re-expands on scroll up (Android `barCollapsed` via nested-scroll deltas).
    @State private var barCollapsed: Bool = false
    @State private var lastScrollOffset: CGFloat = 0

    /// The presentation order of the tabs — AI deliberately in the center slot.
    private static let tabOrder: [MeridianTab] = [.now, .world, .ai, .plan, .settings]

    /// The accessory pill is suppressed on the scroll-heavy / full-bleed tabs and while scrubbing,
    /// matching Android (`currentRoute !in {world, plan, ai} && scrubInstant == null`).
    private var accessoryEnabled: Bool {
        !(selectedTab == .world || selectedTab == .plan || selectedTab == .ai)
            && TimeEngine.shared.scrubInstant == nil
    }

    // MARK: Body

    var body: some View {
        ZStack {
            // The gradient + celestial backdrop, captured behind one glass container so all
            // glass elements refract the same source layer.
            backdrop

            // VERIFY: GlassEffectContainer — iOS 26+ Liquid Glass grouping container; current on iOS 27.
            GlassEffectContainer {
                if isRegular {
                    regularLayout
                } else {
                    compactLayout
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Backdrop

    @ViewBuilder
    private var backdrop: some View {
        ZStack {
            // Vertical surface→background gradient (Android `Brush.verticalGradient`).
            LinearGradient(
                colors: [MeridianColors.surface, MeridianColors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if settings.backdropEnabled {
                CelestialBackdrop(intensity: settings.backdropIntensity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Compact layout (iPhone)

    private var compactLayout: some View {
        screenForTab(selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Inset content above the floating pill so it is never occluded (§4 safeAreaInset).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: barCollapsed ? 72 : 96)
            }
            // The "next event" accessory sits above the bar on the same glass layer.
            .overlay(alignment: .bottom) {
                BottomAccessoryPill(
                    tasks: viewModel.plannedTasks,
                    enabled: accessoryEnabled
                )
                .padding(.bottom, (barCollapsed ? 72 : 96) + 8)
                .padding(.horizontal, 24)
            }
            // The floating glass tab bar, AI center-prominent.
            .overlay(alignment: .bottom) {
                MeridianTabBar(
                    tabs: Self.tabOrder,
                    selectedTab: $selectedTab,
                    collapsed: barCollapsed
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            // Observe scroll to drive minimize-on-scroll. The preference action is delivered on
            // the main actor; `assumeIsolated` lets us mutate `@State` from the (Sendable) closure
            // under Swift 6 strict concurrency. Screens publish `ScrollOffsetKey` from their lists;
            // when none is published this is simply never invoked and the bar stays expanded.
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                MainActor.assumeIsolated {
                    updateBarCollapse(forOffset: offset)
                }
            }
    }

    /// Collapses the bar when content scrolls down (offset decreasing) and expands it on scroll up,
    /// matching Android's nested-scroll `barCollapsed` threshold (±3 pt).
    @MainActor
    private func updateBarCollapse(forOffset offset: CGFloat) {
        let delta = offset - lastScrollOffset
        lastScrollOffset = offset
        if delta < -3, !barCollapsed {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { barCollapsed = true }
        } else if delta > 3, barCollapsed {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { barCollapsed = false }
        }
    }

    // MARK: - Regular layout (iPad)

    private var regularLayout: some View {
        HStack(spacing: 0) {
            GlassNavRail(selectedTab: $selectedTab)

            screenForTab(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    // MARK: - Tab routing

    @ViewBuilder
    func screenForTab(_ tab: MeridianTab) -> some View {
        switch tab {
        case .now:      NowScreen()
        case .world:    WorldClockScreen()
        case .plan:     PlanScreen()
        case .ai:       AiScreen()
        case .settings: SettingsScreen()
        }
    }
}

// MARK: - ScrollOffsetKey

/// Preference key screens emit (via a background `GeometryReader`) to report their scroll offset,
/// so the shell can collapse / expand the floating bar. Screens already in the project drive their
/// own scrolling; those that opt in publish this key. Absent the key, the bar simply never collapses.
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - MeridianTabBar (compact — floating pill, AI center-prominent)

/// Floating glass pill that honours the explicit `now / world / ai / plan / settings` order and
/// renders the AI slot as a raised, accented launcher (Android `GlassNavBar` + `AiNavButton`).
/// Collapses to icon-only when `collapsed` (minimize-on-scroll).
private struct MeridianTabBar: View {
    let tabs: [MeridianTab]
    @Binding var selectedTab: MeridianTab
    var collapsed: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                if tab == .ai {
                    AiTabButton(isActive: selectedTab == .ai) { select(.ai) }
                } else {
                    TabItem(
                        tab: tab,
                        isActive: selectedTab == tab,
                        showLabel: !collapsed
                    ) { select(tab) }
                }
            }
        }
        .padding(.horizontal, collapsed ? 8 : 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())   // VERIFY: glassEffect(_:in:) iOS 26+, current iOS 27.
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: collapsed)
    }

    private func select(_ tab: MeridianTab) {
        guard selectedTab != tab else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = tab }
    }
}

// MARK: - TabItem

private struct TabItem: View {
    let tab: MeridianTab
    let isActive: Bool
    let showLabel: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? tab.activeIcon : tab.icon)
                    .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)

                if isActive && showLabel {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(isActive ? MeridianColors.onPrimary : MeridianColors.onSurfaceVariant)
            .padding(.horizontal, isActive && showLabel ? 14 : 12)
            .padding(.vertical, 10)
            .background {
                if isActive {
                    Capsule().fill(MeridianColors.primary)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isActive)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel("\(tab.title) tab")
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isActive)
    }
}

// MARK: - AiTabButton (center-prominent launcher)

private struct AiTabButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? MeridianColors.onPrimary : MeridianColors.primary)
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(isActive ? MeridianColors.primary : MeridianColors.primary.opacity(0.16))
                }
                .overlay {
                    Circle().strokeBorder(MeridianColors.primary.opacity(0.5), lineWidth: 1)
                }
                .scaleEffect(isActive ? 1.06 : 1.0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isActive)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel("AI Assistant tab")
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
    }
}

// MARK: - BottomAccessoryPill

/// "Now playing"-style slim strip surfacing the next upcoming event with a live countdown.
/// Materializes only when the next event is within one hour (Android `BottomAccessory` +
/// `Reminders.ACCESSORY_WINDOW_MILLIS`). The countdown uses the shared `CountdownFormatter` so it
/// reads identically to the Live Activity.
private struct BottomAccessoryPill: View {
    let tasks: [PlannedTask]
    var enabled: Bool

    var body: some View {
        // Tick once a second so the countdown stays fresh (Android `LaunchedEffect { delay(1000) }`).
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let next = tasks
                .filter { $0.timestamp > now }
                .min { $0.timestamp < $1.timestamp }
            let remaining = next.map { $0.timestamp.timeIntervalSince(now) }
            let withinWindow = (remaining ?? .infinity) < CountdownFormatter.accessoryWindow

            if enabled, let task = next, withinWindow {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MeridianColors.primary)

                    Text(task.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MeridianColors.onSurface)
                        .lineLimit(1)

                    Text("in \(CountdownFormatter.countdown(to: task.timestamp, now: now))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#FF6B6B"))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())   // VERIFY: glassEffect iOS 26+, current iOS 27.
                .overlay(Capsule().strokeBorder(MeridianColors.primary.opacity(0.4), lineWidth: 1))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: enabled)
    }
}
// MARK: - Preview

#if DEBUG
#Preview("ContentView — compact") {
    let container = try! ModelContainer(
        for: SavedZone.self, Person.self, PlannedTask.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let settingsRepo = SettingsRepository()

    @Previewable @State var viewModel = MainViewModel(
        modelContext: container.mainContext,
        settingsRepo: settingsRepo
    )
    @Previewable @State var tab: MeridianTab = .now

    return ContentView(viewModel: viewModel, selectedTab: $tab)
        .modelContainer(container)
        .environment(settingsRepo)
        .environment(TimeEngine.shared)
        .preferredColorScheme(.dark)
}
#endif
