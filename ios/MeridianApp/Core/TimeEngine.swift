// TimeEngine.swift
// Meridian — iOS 27 / Swift 6
//
// Drives the timeline scrubber and all time-display helpers across the app.
//
// Ported from `TimeEngine.kt`: the engine owns an optional *absolute* scrub instant
// (not a relative offset) plus an injectable `now` closure for deterministic tests.
// `displayDate` resolves to the scrub instant when scrubbing, otherwise to `now()`.

import Foundation
import Observation

// MARK: - TimeEngine

/// Central observable that owns the scrub instant and provides time helpers for
/// every time zone the app displays.
///
/// - The `@Observable` macro generates per-property tracking so SwiftUI views only
///   re-render when values they actually read change.
/// - `@MainActor` confines all mutable state to the main actor, satisfying Swift 6
///   strict concurrency without `@unchecked Sendable`. Formatting uses the `Sendable`
///   `Date.FormatStyle` API instead of a shared `DateFormatter` (which was the source
///   of a data race under strict concurrency).
@Observable
@MainActor
final class TimeEngine {

    // MARK: Singleton

    static let shared = TimeEngine()

    // MARK: Observed state

    /// Absolute instant the scrubber is pinned to, or `nil` when tracking live time.
    /// Mirrors `TimeEngine.scrubInstant` (a `StateFlow<Instant?>`) on Android.
    var scrubInstant: Date?

    // MARK: Injectable clock

    /// Source of "now". Defaults to the system clock; tests can inject a fixed value.
    /// Not observed — swapping the clock should not invalidate views by itself.
    @ObservationIgnored
    var now: () -> Date

    // MARK: Init

    init(now: @escaping () -> Date = { Date() }, scrubInstant: Date? = nil) {
        self.now = now
        self.scrubInstant = scrubInstant
    }

    // MARK: - Computed properties

    /// The instant the whole app should render: the scrub instant while scrubbing,
    /// otherwise live `now()`. This is the single source of truth for displayed time.
    var displayDate: Date {
        scrubInstant ?? now()
    }

    /// `true` while the user is pinned to a scrubbed instant (i.e. not live).
    var isScrubbing: Bool {
        scrubInstant != nil
    }

    // MARK: - Scrub control

    /// Pins the timeline to an absolute instant. Pass `nil` to return to live time.
    func setScrubInstant(_ instant: Date?) {
        scrubInstant = instant
    }

    /// Resets the scrubber to live time.
    func resetScrub() {
        scrubInstant = nil
    }

    // MARK: - Label

    /// Human-readable scrub label: `"Live"` when tracking now, otherwise a signed
    /// h/m delta from live time such as `"+3h 15m"` or `"-30m"`.
    var offsetLabel: String {
        guard let instant = scrubInstant else { return "Live" }

        let delta = instant.timeIntervalSince(now())
        // Snap sub-minute jitter so the label does not flicker around "Live".
        let totalMinutes = Int((abs(delta) / 60.0).rounded())
        if totalMinutes == 0 { return "Live" }

        let sign    = delta >= 0 ? "+" : "-"
        let hours   = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 { return "\(sign)\(minutes)m" }
        if minutes == 0 { return "\(sign)\(hours)h" }
        return "\(sign)\(hours)h \(minutes)m"
    }

    // MARK: - Display helpers

    /// Formatted time string for the display date in the given time zone.
    ///
    /// Uses the `Sendable` `Date.FormatStyle` API; no shared mutable formatter.
    ///
    /// - Parameters:
    ///   - tzId: IANA time-zone identifier (e.g. `"America/New_York"`).
    ///   - use24Hour: When `true` uses 24-hour format; otherwise 12-hour with AM/PM.
    /// - Returns: Formatted time string, or `"--:--"` if the time zone is invalid.
    func formattedTime(in tzId: String, use24Hour: Bool) -> String {
        guard let tz = TimeZone(identifier: tzId) else { return "--:--" }
        return TimeFormats.hourMinute(date: displayDate, timeZone: tz, use24Hour: use24Hour)
    }

    /// UTC offset for the given time zone, in seconds, at the display date.
    /// - Parameter tzId: IANA time-zone identifier.
    /// - Returns: Offset in seconds (e.g. `-18000` for UTC-5), or `nil` for an unknown zone.
    func utcOffset(for tzId: String) -> Int? {
        TimeZone(identifier: tzId)?.secondsFromGMT(for: displayDate)
    }

    /// Local hour of day (0–23) in the given time zone at the display date.
    /// - Parameter tzId: IANA time-zone identifier.
    /// - Returns: Hour component (0–23), or `0` if the time zone identifier is invalid.
    func hourOfDay(in tzId: String) -> Int {
        guard let tz = TimeZone(identifier: tzId) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar.component(.hour, from: displayDate)
    }

    /// Whether the sun is up in the given time zone at the display date, using true
    /// solar geometry when coordinates are known and falling back to a simple
    /// hour-of-day window (06:00–20:00) otherwise.
    /// - Parameter tzId: IANA time-zone identifier.
    func isDaytime(in tzId: String) -> Bool {
        if let c = ZoneCoordinates.coordinates(for: tzId) {
            return SolarMath.isDaylight(latitude: c.lat, longitude: c.lon, date: displayDate)
        }
        let hour = hourOfDay(in: tzId)
        return hour >= 6 && hour < 20
    }
}
