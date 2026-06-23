// Provider.swift
// Meridian — iOS 27 / Swift 6 — WidgetKit extension target
//
// TimelineProvider for the World Clock home-screen widget. Reads the pinned-zone
// snapshot the app writes into the App Group via `SharedZoneStore`, mirroring the
// Android `MeridianWidget.provideGlance` flow that reads pinned zones from Room.
//
// Android renders a static "hh:mm a" string per zone at refresh time. We do the same per
// timeline entry, but additionally schedule the timeline to refresh at the top of each
// minute so the displayed wall-clock time stays roughly current between system reloads.

import WidgetKit
import Foundation

// MARK: - Entry

/// A single rendered point in the widget timeline.
///
/// Captures the instant the entry represents plus the pinned zones to display. The view
/// computes each zone's local wall-clock time from `date` + `tzId` (the snapshot stores
/// only primitives — it never bakes a formatted time string, matching the parity rule that
/// rendering to a zone's local time is the view layer's job).
struct WorldClockEntry: TimelineEntry {
    /// The instant this entry is valid for / rendered at.
    let date: Date
    /// Pinned zones in display order (already sorted by the app).
    let zones: [SharedZone]
    /// When the backing snapshot was last written by the app (for optional staleness UI).
    let updatedAt: Date

    /// Placeholder content used for redacted previews and the gallery.
    static let placeholder = WorldClockEntry(
        date: .now,
        zones: [
            SharedZone(id: "America/New_York",   tzId: "America/New_York",   displayName: "New York", isHome: true,  orderIndex: 0),
            SharedZone(id: "Europe/London",      tzId: "Europe/London",      displayName: "London",   isHome: false, orderIndex: 1),
            SharedZone(id: "Asia/Tokyo",         tzId: "Asia/Tokyo",         displayName: "Tokyo",    isHome: false, orderIndex: 2)
        ],
        updatedAt: .now
    )
}

// MARK: - Provider

/// Supplies timeline entries from the App Group snapshot.
struct WorldClockProvider: TimelineProvider {

    func placeholder(in context: Context) -> WorldClockEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WorldClockEntry) -> Void) {
        // In the gallery / redacted preview, show representative placeholder content;
        // otherwise reflect the user's real pinned zones.
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(makeEntry(at: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorldClockEntry>) -> Void) {
        let now = Date.now
        let entry = makeEntry(at: now)

        // Refresh at the start of the next minute so displayed minute values stay current.
        // WidgetKit may coalesce reloads under budget, but this expresses our intent.
        let calendar = Calendar.current
        let nextMinute = calendar.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)

        let timeline = Timeline(entries: [entry], policy: .after(nextMinute))
        completion(timeline)
    }

    // MARK: - Helpers

    /// Builds an entry from the current App Group snapshot.
    private func makeEntry(at date: Date) -> WorldClockEntry {
        let snapshot = SharedZoneStore.loadSnapshot()
        let zones = snapshot.zones.sorted { $0.orderIndex < $1.orderIndex }
        return WorldClockEntry(date: date, zones: zones, updatedAt: snapshot.updatedAt)
    }
}
