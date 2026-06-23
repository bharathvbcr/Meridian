// MeridianWatchApp.swift
// Meridian — watchOS 27 / Swift 6
//
// Minimal SwiftUI watch companion: a list of the phone's pinned world-clock zones (each with
// its live local time) and a countdown to the next planned event. State arrives from the phone
// via `WatchSessionManager` (WatchConnectivity `applicationContext`).
//
// This replaces the Android Wear face data from `WearSyncManager.kt` with a richer, idiomatic
// watchOS list + countdown, while preserving the home-zone semantics (the home zone is badged).

import SwiftUI

// MARK: - App entry

@main
struct MeridianWatchApp: App {

    /// Lives for the app's lifetime; activates WatchConnectivity on appear.
    @State private var session = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(session)
                .task {
                    // Activate once the UI exists so received contexts can be applied.
                    session.activate()
                }
        }
    }
}

// MARK: - Root view

private struct WatchRootView: View {
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        NavigationStack {
            List {
                if let event = session.nextEvent {
                    Section("Next Event") {
                        NextEventRow(event: event)
                    }
                }

                Section("World Clock") {
                    if session.zones.isEmpty {
                        ContentUnavailableView(
                            "No Zones",
                            systemImage: "globe",
                            description: Text(
                                session.hasReceivedData
                                    ? "Add zones on your iPhone to see them here."
                                    : "Open Meridian on your iPhone to sync."
                            )
                        )
                    } else {
                        ForEach(session.zones) { zone in
                            ZoneRow(zone: zone)
                        }
                    }
                }
            }
            .navigationTitle("Meridian")
        }
    }
}

// MARK: - Zone row

/// One world-clock entry. Uses a `TimelineView` so the displayed local time ticks every minute
/// without manual timers.
private struct ZoneRow: View {
    let zone: WatchZone

    var body: some View {
        // Update at the start of each minute (seconds are not shown).
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(zone.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        if zone.isHome {
                            Image(systemName: "house.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(zoneSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(localTime(at: context.date))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
    }

    /// Local wall-clock time in this zone, formatted via the Sendable `Date.FormatStyle`
    /// (no `DateFormatter`), honoring the user's locale 12/24-hour preference.
    private func localTime(at instant: Date) -> String {
        guard let tz = TimeZone(identifier: zone.tzId) else { return "--:--" }
        // The target zone is set via the FormatStyle's `timeZone` *property* (initializer
        // argument). The `.timeZone(_:)` modifier only controls the time-zone display symbol
        // (e.g. "PST"), not which zone the date is rendered in.
        return instant.formatted(
            Date.FormatStyle(timeZone: tz)
                .hour(.defaultDigits)
                .minute(.twoDigits)
        )
    }

    /// A short UTC-offset / abbreviation subtitle, e.g. "GMT+9".
    private var zoneSubtitle: String {
        guard let tz = TimeZone(identifier: zone.tzId) else { return zone.tzId }
        let seconds = tz.secondsFromGMT(for: .now)
        if seconds == 0 { return "GMT" }
        let sign = seconds > 0 ? "+" : "-"
        let absMinutes = abs(seconds) / 60
        let hours = absMinutes / 60
        let minutes = absMinutes % 60
        return minutes == 0
            ? "GMT\(sign)\(hours)"
            : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }
}

// MARK: - Next-event row

/// Countdown to the next planned event. The system renders the live countdown via
/// `Text(timerInterval:)`, so no manual ticking is needed.
private struct NextEventRow: View {
    let event: WatchEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
                .lineLimit(2)

            if event.date > .now {
                // VERIFY: `Text(timerInterval:countsDown:)` — SwiftUI, available watchOS 8+.
                Text(timerInterval: Date.now...event.date, countsDown: true)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.tint)
            } else {
                Text("Now")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }

            Text(eventWhen)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Absolute event time in the event's own zone, e.g. "Mon 14:30".
    private var eventWhen: String {
        let tz = TimeZone(identifier: event.tzId) ?? .current
        return event.date.formatted(
            Date.FormatStyle(timeZone: tz)
                .weekday(.abbreviated)
                .hour(.defaultDigits)
                .minute(.twoDigits)
        )
    }
}
