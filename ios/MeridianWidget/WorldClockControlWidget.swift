// WorldClockControlWidget.swift
// Meridian — iOS 27 / Swift 6 — WidgetKit extension target
//
// Control Center / Lock Screen control. Port of the Android `WorldClockTileService`
// quick-settings tile (§5.4):
//   - Label "World times".
//   - Value = the home (or, failing that, first pinned) zone's current local time,
//     prefixed by its display name — e.g. "New York · 9:05 AM".
//   - Tapping it opens the World screen (`meridian://world`).
//
// ControlWidget shipped in iOS 18; this target deploys to iOS 27 so it is used
// unconditionally. The primary-zone selection (home else first) is computed from the same
// App Group snapshot the home-screen widget reads, via a `ControlValueProvider`.

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Control value

/// The resolved primary zone (or `nil`) plus the instant it was resolved at.
struct WorldClockControlValue {
    let zone: SharedZone?
    let date: Date
}

// MARK: - Value provider

/// Resolves the primary pinned zone for the control from the App Group snapshot.
///
/// Mirrors Android `WorldClockTileService.loadPrimaryZone()`:
/// `zones.firstOrNull { it.isHome } ?: zones.firstOrNull()`.
struct WorldClockControlValueProvider: ControlValueProvider {

    /// Placeholder shown in the gallery before the real value loads.
    var previewValue: WorldClockControlValue {
        WorldClockControlValue(
            zone: SharedZone(
                id: "America/New_York",
                tzId: "America/New_York",
                displayName: "New York",
                isHome: true,
                orderIndex: 0
            ),
            date: .now
        )
    }

    func currentValue() async throws -> WorldClockControlValue {
        let zones = SharedZoneStore.loadZones().sorted { $0.orderIndex < $1.orderIndex }
        let primary = zones.first(where: { $0.isHome }) ?? zones.first
        return WorldClockControlValue(zone: primary, date: .now)
    }
}

// MARK: - Control widget

struct WorldClockControlWidget: ControlWidget {
    static let kind = "com.example.meridian.WorldClockControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: WorldClockControlValueProvider()
        ) { value in
            ControlWidgetButton(action: OpenWorldClockIntent()) {
                Label {
                    Text(Self.subtitle(for: value))
                } icon: {
                    Image(systemName: "globe")
                }
                // Secondary line: the primary zone name (Android shows "name · time").
                if let zone = value.zone {
                    Text(zone.displayName)
                }
            }
        }
        .displayName("World times")
        .description("Peek at your primary location's current time.")
    }

    /// The control's primary value text — the primary zone's current local time, or a
    /// prompt when nothing is pinned.
    private static func subtitle(for value: WorldClockControlValue) -> String {
        guard let zone = value.zone else { return "No locations" }
        let tz = TimeFormats.safeTimeZone(id: zone.tzId)
        return TimeFormats.hourMinute(
            date: value.date,
            timeZone: tz,
            use24Hour: TimeFormats.is24HourSystem()
        )
    }
}

// MARK: - Open intent

/// Opens the Meridian app at the World screen when the control is tapped.
///
/// Returns `OpenURLIntent` from `perform()` so the system performs the navigation. A freshly
/// constructed `EnvironmentValues().openURL` is the default no-op action (it is not bound to any
/// live scene), so it cannot drive a deep link from a control's intent — it would at most bring
/// the app forward without navigating. `OpenURLIntent(_:)` accepts any `URL`, including custom
/// schemes such as `meridian://`, so the `World` screen is reached deterministically, matching the
/// Android `WorldClockTileService` tile's deep link.
struct OpenWorldClockIntent: AppIntent {
    static let title: LocalizedStringResource = "Open World Clock"

    /// Bring the host app to the foreground when this intent runs; the returned `OpenURLIntent`
    /// then performs the `meridian://world` deep link.
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "meridian://world")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
