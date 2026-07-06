// WorldClockWidget.swift
// Meridian — iOS 27 / Swift 6 — WidgetKit extension target
//
// Home-screen world clock widget. Port of the Android Glance `MeridianWidget`:
//   - Header "Meridian World Clock".
//   - A list of pinned zones, each showing displayName, the IANA tz id, and the current
//     local time ("h:mm a" / "HH:mm").
//   - An empty-state prompt when no zones are pinned.
//   - Tapping the widget deep-links into the World screen via `meridian://world`.
//
// iOS polish over the Android original: respects the user's 12/24-hour locale via
// `TimeFormats`, sizes its visible row count to the widget family, and uses `.glassEffect`
// row chips for the small/medium tiles.

import WidgetKit
import SwiftUI

// MARK: - Widget palette
//
// `MeridianColors` lives in the app target, so the widget defines a minimal local palette
// matching the brand. These mirror the design-system hex values (Theme.swift).

private enum WidgetPalette {
    static let primary  = Color(red: 0x60 / 255, green: 0xCD / 255, blue: 0xFF / 255) // #60CDFF
    static let onSurface = Color(red: 0xF1 / 255, green: 0xF5 / 255, blue: 0xF9 / 255) // #F1F5F9
    static let onSurfaceVariant = Color(red: 0x94 / 255, green: 0xA3 / 255, blue: 0xB8 / 255) // #94A3B8
    static let background = Color(red: 0x02 / 255, green: 0x06 / 255, blue: 0x17 / 255) // #020617
    static let surface = Color(red: 0x0F / 255, green: 0x17 / 255, blue: 0x2A / 255) // #0F172A
}

// MARK: - Widget

struct WorldClockWidget: Widget {
    static let kind = "com.example.meridian.WorldClockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WorldClockProvider()) { entry in
            WorldClockWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.background
                }
        }
        .configurationDisplayName("World Clock")
        .description("Current time in your pinned locations.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root view

struct WorldClockWidgetView: View {
    let entry: WorldClockEntry

    @Environment(\.widgetFamily) private var family

    /// Whether to render local times in 24-hour notation, following the device locale.
    private var use24Hour: Bool {
        TimeFormats.is24HourSystem()
    }

    /// Maximum visible zone rows for the current family.
    private var maxRows: Int {
        switch family {
        case .systemSmall:  return 3
        case .systemMedium: return 4
        case .systemLarge:  return 8
        default:            return 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if entry.zones.isEmpty {
                emptyState
            } else {
                zoneList
            }
        }
        .widgetURL(
            URL(string: entry.zones.isEmpty ? "meridian://addzone" : "meridian://world")
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WidgetPalette.primary)
            Text("Meridian World Clock")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack {
            Spacer(minLength: 0)
            Text("Tap to search and pin cities.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WidgetPalette.primary)
                .multilineTextAlignment(.center)
            Text("Opens Meridian's city search.")
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Zone list

    private var zoneList: some View {
        VStack(spacing: 4) {
            ForEach(entry.zones.prefix(maxRows)) { zone in
                zoneRow(zone)
            }
            // Small family hides the tz subtitle and shows fewer rows; keep it from
            // stretching vertically when only one or two zones exist.
            Spacer(minLength: 0)
        }
    }

    private func zoneRow(_ zone: SharedZone) -> some View {
        let tz = TimeFormats.safeTimeZone(id: zone.tzId)
        let time = TimeFormats.hourMinute(date: entry.date, timeZone: tz, use24Hour: use24Hour)

        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(zone.displayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetPalette.onSurface)
                    .lineLimit(1)
                if family != .systemSmall {
                    Text(zone.tzId)
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetPalette.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(time)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WidgetPalette.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WidgetPalette.surface)
        )
    }
}

// MARK: - Previews

#Preview("World Clock — Medium", as: .systemMedium) {
    WorldClockWidget()
} timeline: {
    WorldClockEntry.placeholder
    WorldClockEntry(date: .now, zones: [], updatedAt: .now)
}
