// MeridianWatchWidgetBundle.swift
// Meridian — watchOS 27 / Swift 6 — watch widget extension
//
// Entry point for the watch's glanceable surfaces (accessory complications +
// Smart Stack). The iOS counterpart of Android's `SecondZoneTileService` Wear
// Tile: local time plus one synced "second zone", and the next-event countdown.

import SwiftUI
import WidgetKit

@main
struct MeridianWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        SecondZoneWidget()
    }
}
