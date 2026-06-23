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

struct WorldVisualization: View {

    /// Shared display instant (scrub-aware).
    let instant: Date
    /// Saved-zone ids to plot on both the map and the globe.
    let zoneIds: [String]
    /// Selected map rendering style.
    let mapStyle: MapStyle

    // MARK: State

    @State private var globeMode = false

    // MARK: Degrade detection

    /// Force 2D when the device is battery- or memory-constrained (evaluated once).
    private static let constrained: Bool = {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        // < 3 GB physical memory ≈ Android's `isLowRamDevice` heuristic.
        let threeGB: UInt64 = 3 * 1024 * 1024 * 1024
        let lowRam = ProcessInfo.processInfo.physicalMemory < threeGB
        return lowPower || lowRam
    }()

    /// Performance style keeps frames cheap, so the 3D globe is disabled there too.
    private var performanceMode: Bool { mapStyle == .performance }
    private var twoDOnly: Bool { Self.constrained || performanceMode }
    private var showGlobe: Bool { globeMode && !twoDOnly }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Spacer()
                if !twoDOnly {
                    Picker("View", selection: $globeMode) {
                        Text("2D").tag(false)
                        Text("3D").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .sensoryFeedback(.selection, trigger: globeMode)
                } else {
                    Text(performanceMode ? "3D off (Performance style)" : "3D off (Low Power Mode)")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
                }
            }

            ZStack {
                if showGlobe {
                    DayNightGlobe(
                        zoneIds: zoneIds,
                        effectiveDate: instant,
                        style: mapStyle
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .transition(.opacity)
                } else {
                    DayNightMap(
                        instant: instant,
                        zoneIds: zoneIds,
                        style: mapStyle
                    )
                    .transition(.opacity)
                }
            }
            .animation(Motion.smooth(), value: showGlobe)
        }
    }
}
