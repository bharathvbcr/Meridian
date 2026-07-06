//  WorldVisualization.swift
//  Meridian — iOS 27 / Swift 6
//
//  Ported from the `WorldVisualization` composable in WorldClockScreen.kt (§5.2, §16).
//
//  Hosts the world day/night terminator with a 2D map ⇄ 3D globe toggle and a graceful
//  low-power degrade: on Low Power Mode or a low-RAM device — or whenever the Performance
//  map style is selected — the heavier 3D globe is disabled, the toggle hides, and the view
//  is forced to the flat 2D map (parity with Android's PowerManager.isPowerSaveMode /
//  ActivityManager.isLowRamDevice check).

import SwiftUI
import Combine

struct WorldVisualization: View {

    /// Shared display instant (scrub-aware).
    let instant: Date
    /// Saved-zone ids to plot on both the map and the globe.
    let zoneIds: [String]
    /// Selected map rendering style.
    let mapStyle: MapStyle
    /// The home zone's id + the device's vetted location, forwarded to the map and globe so
    /// the home pin marks the user's actual location instead of the zone's city.
    var homeZoneId: String? = nil
    var homeLocation: GeoPoint? = nil

    // MARK: State

    @State private var globeMode = false
    /// Re-evaluated on appear and whenever the power state changes, so toggling Low Power
    /// Mode mid-session re-gates 3D live (Android reads isPowerSaveMode per composition).
    @State private var constrained = Self.evaluateConstrained()

    // MARK: Degrade detection

    /// Force 2D when the device is battery- or memory-constrained.
    private static func evaluateConstrained() -> Bool {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        // < 3 GB physical memory ≈ Android's `isLowRamDevice` heuristic.
        let threeGB: UInt64 = 3 * 1024 * 1024 * 1024
        let lowRam = ProcessInfo.processInfo.physicalMemory < threeGB
        return lowPower || lowRam
    }

    /// Performance style keeps frames cheap, so the 3D globe is disabled there too.
    private var performanceMode: Bool { mapStyle == .performance }
    private var twoDOnly: Bool { constrained || performanceMode }
    private var showGlobe: Bool { globeMode && !twoDOnly }

    // MARK: - Degrade copy

    /// SF Symbol + full VoiceOver sentence explaining why the 3D globe is unavailable.
    private var degradeIcon: String { performanceMode ? "cube.transparent" : "bolt.slash" }
    private var degradeLabel: String {
        performanceMode
            ? "3D off (Performance style)"
            : "3D off (Low Power Mode)"
    }
    private var degradeAccessibilityLabel: String {
        performanceMode
            ? "3D globe unavailable with Performance map style"
            : "3D globe unavailable in Low Power Mode"
    }

    // MARK: - Body

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: MeridianSpacing.sm.rawValue) {
            HStack {
                Spacer()
                if !twoDOnly {
                    Picker("View", selection: $globeMode) {
                        Text("2D")
                            .tag(false)
                            .accessibilityLabel("Flat map")
                        Text("3D")
                            .tag(true)
                            .accessibilityLabel("Globe")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .sensoryFeedback(.selection, trigger: globeMode)
                    .accessibilityLabel("World visualization")
                    .accessibilityValue(globeMode ? "Globe" : "Flat map")
                    .accessibilityHint("Switches between a flat map and a 3D globe")
                } else {
                    HStack(spacing: MeridianSpacing.xs.rawValue) {
                        Image(systemName: degradeIcon)
                            .font(.bodyMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                            .accessibilityHidden(true)
                        Text(degradeLabel)
                            .font(.bodyMedium)
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(degradeAccessibilityLabel)
                }
            }

            ZStack {
                if showGlobe {
                    DayNightGlobe(
                        zoneIds: zoneIds,
                        effectiveDate: instant,
                        style: mapStyle,
                        homeZoneId: homeZoneId,
                        homeLocation: homeLocation
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .transition(.opacity)
                } else {
                    DayNightMap(
                        instant: instant,
                        zoneIds: zoneIds,
                        style: mapStyle,
                        homeZoneId: homeZoneId,
                        homeLocation: homeLocation
                    )
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Motion.smooth(), value: showGlobe)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(showGlobe ? "World globe" : "World map")
        }
        .onAppear { constrained = Self.evaluateConstrained() }
        // NSProcessInfoPowerStateDidChange arrives on an arbitrary queue; hop to main.
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            withAnimation(reduceMotion ? nil : Motion.smooth()) {
                constrained = Self.evaluateConstrained()
            }
        }
    }
}
