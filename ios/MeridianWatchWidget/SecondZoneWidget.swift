// SecondZoneWidget.swift
// Meridian — watchOS 27 / Swift 6 — watch widget extension
//
// Accessory-family widget mirroring Android's `SecondZoneTileService` Wear Tile:
// the local time next to one synced "second zone" (the home anchor when present,
// else the first pinned zone), plus the next planned event on the rectangular
// family. Data comes from the last `WatchSyncPayload` the watch app persisted via
// `WatchWidgetStore`; timelines re-arm at the top of each minute (the Android Tile
// declares 60 s freshness).

import SwiftUI
import WidgetKit

// MARK: - Palette (self-contained; the app's MeridianColors is not linked here)

private enum WatchWidgetPalette {
    static let primary = Color(red: 0x60 / 255, green: 0xCD / 255, blue: 0xFF / 255)   // #60CDFF
    static let onSurface = Color(red: 0xF1 / 255, green: 0xF5 / 255, blue: 0xF9 / 255) // #F1F5F9
    static let onSurfaceVariant = Color(red: 0x94 / 255, green: 0xA3 / 255, blue: 0xB8 / 255) // #94A3B8
}

// MARK: - Entry

struct SecondZoneEntry: TimelineEntry {
    let date: Date
    /// The synced second zone (home anchor first, else first pinned), or `nil`
    /// before the first phone sync.
    let secondZone: WatchZone?
    /// The next upcoming event, when one is scheduled ahead of `date`.
    let nextEvent: WatchEvent?
}

// MARK: - Provider

struct SecondZoneProvider: TimelineProvider {

    func placeholder(in context: Context) -> SecondZoneEntry {
        SecondZoneEntry(
            date: Date(),
            secondZone: WatchZone(id: "Asia/Tokyo", tzId: "Asia/Tokyo", displayName: "Tokyo", isHome: false, orderIndex: 0),
            nextEvent: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SecondZoneEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SecondZoneEntry>) -> Void) {
        // One entry per minute boundary for the next 30 minutes, then re-request —
        // same cadence as the phone widget's provider.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        let nextMinute = cal.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)

        var entries = [entry(at: now)]
        for offset in 0..<30 {
            entries.append(entry(at: nextMinute.addingTimeInterval(TimeInterval(offset * 60))))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Builds one entry from the persisted payload (Android: tile reads
    /// `meridian_wear_prefs`). Second zone = home anchor, else first pinned zone.
    private func entry(at date: Date) -> SecondZoneEntry {
        let payload = WatchWidgetStore.load()
        let zones = (payload?.zones ?? []).sorted { $0.orderIndex < $1.orderIndex }
        let second = zones.first(where: \.isHome) ?? zones.first
        let event = payload?.nextEvent.flatMap { $0.date > date ? $0 : nil }
        return SecondZoneEntry(date: date, secondZone: second, nextEvent: event)
    }
}

// MARK: - Widget

struct SecondZoneWidget: Widget {

    static let kind = "MeridianSecondZoneWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SecondZoneProvider()) { entry in
            SecondZoneWidgetView(entry: entry)
                .containerBackground(.black.gradient, for: .widget)
                .widgetURL(
                    URL(string: entry.secondZone == nil ? "meridian://addzone" : "meridian://world")
                )
        }
        .configurationDisplayName("Second Zone")
        .description("Local time beside your synced zone, with the next event countdown.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
        ])
    }
}

// MARK: - View

struct SecondZoneWidgetView: View {

    @Environment(\.widgetFamily) private var family

    let entry: SecondZoneEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryInline:
            inline
        default:
            inline
        }
    }

    // Rectangular: both clocks + next-event line (the full Android Tile layout).
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                clockColumn(label: "Local", time: timeString(zoneId: TimeZone.current.identifier))
                if let zone = entry.secondZone {
                    clockColumn(label: shortName(zone), time: timeString(zoneId: zone.tzId))
                }
            }
            if let event = entry.nextEvent {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WatchWidgetPalette.primary)
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(WatchWidgetPalette.onSurface)
                    Text(event.date, style: .timer)
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(WatchWidgetPalette.primary)
                }
            } else if entry.secondZone == nil {
                Text("Open Meridian on iPhone to sync zones.")
                    .font(.system(size: 10))
                    .foregroundStyle(WatchWidgetPalette.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Circular: the second zone's time over its short name.
    private var circular: some View {
        VStack(spacing: 0) {
            Text(timeString(zoneId: entry.secondZone?.tzId ?? TimeZone.current.identifier))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text(entry.secondZone.map(shortName) ?? "Local")
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.secondary)
        }
    }

    // Corner: second-zone time as the label, its name curved along the corner.
    private var corner: some View {
        Text(timeString(zoneId: entry.secondZone?.tzId ?? TimeZone.current.identifier))
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .widgetLabel {
                Text(entry.secondZone.map(shortName) ?? "Local")
            }
    }

    // Inline: "Tokyo 21:14" one-liner.
    private var inline: some View {
        Text("\(entry.secondZone.map(shortName) ?? "Local") \(timeString(zoneId: entry.secondZone?.tzId ?? TimeZone.current.identifier))")
    }

    private func clockColumn(label: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(time)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchWidgetPalette.onSurface)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(WatchWidgetPalette.onSurfaceVariant)
        }
    }

    /// Locale-aware HH:mm in the given zone at the entry instant.
    private func timeString(zoneId: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zoneId) ?? .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: entry.date)
    }

    /// "America/New_York" → "New York" fallback; prefers the synced display name.
    private func shortName(_ zone: WatchZone) -> String {
        if !zone.displayName.isEmpty { return zone.displayName }
        return zone.tzId.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.tzId
    }
}
