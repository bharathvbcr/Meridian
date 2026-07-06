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

    /// The accessory pill is suppressed on the scroll-heavy / full-bleed tabs and while scrubbing,
    /// matching Android (`currentRoute !in {world, plan, ai} && scrubInstant == null`).
    private var accessoryEnabled: Bool {
        !(selectedTab == .world || selectedTab == .plan || selectedTab == .ai)
            && TimeEngine.shared.scrubInstant == nil
    }

    private var tabBarHeight: CGFloat { barCollapsed ? 72 : 96 }

    // MARK: Body

    var body: some View {
        ZStack {
            backdrop

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
            .id(selectedTab)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: tabBarHeight)
            }
            .overlay(alignment: .bottom) {
                BottomAccessory(
                    tasks: viewModel.plannedTasks,
                    tab: selectedTab,
                    enabled: accessoryEnabled,
                    embedded: true,
                    onTap: {
                        withAnimation(Motion.snappy()) { selectedTab = .plan }
                    }
                )
                .padding(.bottom, tabBarHeight + 8)
                .padding(.horizontal, 24)
            }
            .overlay(alignment: .bottom) {
                GlassCompactNavBar(
                    selectedTab: $selectedTab,
                    collapsed: barCollapsed
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                MainActor.assumeIsolated {
                    updateBarCollapse(forOffset: offset)
                }
            }
            .onChange(of: selectedTab) { _, _ in
                barCollapsed = false
                lastScrollOffset = 0
            }
            .environment(\.tabBarInsetHeight, tabBarHeight)
            .animation(Motion.smooth(), value: selectedTab)
    }

    /// Collapses the bar when content scrolls down (offset decreasing) and expands it on scroll up,
    /// matching Android's nested-scroll `barCollapsed` threshold (±3 pt).
    @MainActor
    private func updateBarCollapse(forOffset offset: CGFloat) {
        let delta = offset - lastScrollOffset
        lastScrollOffset = offset
        if delta < -3, !barCollapsed {
            withAnimation(Motion.snappy()) { barCollapsed = true }
        } else if delta > 3, barCollapsed {
            withAnimation(Motion.snappy()) { barCollapsed = false }
        }
    }

    // MARK: - Regular layout (iPad)

    private var regularLayout: some View {
        HStack(spacing: 0) {
            GlassNavRail(selectedTab: $selectedTab)

            screenForTab(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selectedTab)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .overlay(alignment: .bottom) {
                    BottomAccessory(
                        tasks: viewModel.plannedTasks,
                        tab: selectedTab,
                        enabled: accessoryEnabled,
                        embedded: true,
                        onTap: {
                            withAnimation(Motion.snappy()) { selectedTab = .plan }
                        }
                    )
                    .padding(.bottom, 20)
                    .padding(.horizontal, 32)
                }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .animation(Motion.smooth(), value: selectedTab)
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

// MARK: - Preview

#if DEBUG
#Preview("ContentView — compact") {
    let container = try! ModelContainer(
        for: SavedZone.self, Person.self, PlannedTask.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let settingsRepo = SettingsRepository()
    let viewModel = MainViewModel(
        modelContext: container.mainContext,
        settingsRepo: settingsRepo
    )

    return ContentView(viewModel: viewModel, selectedTab: .constant(.now))
        .modelContainer(container)
        .environment(settingsRepo)
        .environment(TimeEngine.shared)
        .preferredColorScheme(.dark)
}
#endif
