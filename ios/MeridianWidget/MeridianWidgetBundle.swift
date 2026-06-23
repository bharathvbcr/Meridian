// MeridianWidgetBundle.swift
// Meridian — iOS 27 / Swift 6 — WidgetKit extension target
//
// Entry point for the widget extension. Bundles together every widget surface this app
// vends: the home-screen World Clock widget (port of Android `MeridianWidget` Glance
// widget), the Control Center / Lock Screen "World times" control (port of Android
// `WorldClockTileService` quick-settings tile), and the EventCountdown Live Activity
// (port of the Android ongoing-countdown notification).
//
// All members reference only App-Group-safe shared code (`SharedZoneStore`,
// `EventCountdownAttributes`, `TimeFormats`); the SwiftData `@Model` types and the app's
// `@MainActor` view-model are intentionally NOT linked into this target.

import WidgetKit
import SwiftUI

@main
struct MeridianWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Home-screen world clock.
        WorldClockWidget()

        // Control Center / Lock Screen quick control.
        // ControlWidget shipped in iOS 18; this target deploys to iOS 27, so it is
        // always available with no availability gate.
        WorldClockControlWidget()

        // Live Activity (lock screen + Dynamic Island).
        EventCountdownLiveActivity()
    }
}
