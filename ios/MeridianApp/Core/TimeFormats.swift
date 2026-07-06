// TimeFormats.swift
// Meridian — iOS 27 / Swift 6
//
// Stateless, locale-aware formatting utilities used throughout the app.
//
// Ported from `TimeFormats.kt`. Every formatter is built from the `Sendable`
// `Date.FormatStyle` API (no `DateFormatter`), so these helpers are safe to call from
// any actor context with no synchronisation — this removes the shared-formatter data
// race that Swift 6 strict concurrency would otherwise flag.

import Foundation

// HourCycle is defined in Models.swift (canonical): .system / .twelve / .twentyFour.

// MARK: - TimeFormats

/// Namespace for all time / date formatting helpers used by Meridian views.
enum TimeFormats {

    // MARK: - Locale hour-cycle override

    /// Returns a copy of `base` whose hour cycle is forced to 12- or 24-hour.
    ///
    /// `Date.FormatStyle` has no direct "force 24-hour" switch — the rendered hour
    /// cycle follows the locale. We therefore override the locale's `hourCycle`, which
    /// is the supported way to control 12/24-hour output.
    static func locale(_ base: Locale = .current, use24Hour: Bool) -> Locale {
        var components = Locale.Components(locale: base)
        components.hourCycle = use24Hour ? .zeroToTwentyThree : .oneToTwelve
        return Locale(components: components)
    }

    // MARK: - Core formatters (Date.FormatStyle)

    /// A `Sendable` `Date.FormatStyle` rendering hour + minute, e.g. "9:05 AM" or "09:05".
    ///
    /// - Parameters:
    ///   - timeZone: The zone the wall-clock time is rendered in.
    ///   - use24Hour: When `true`, forces 24-hour notation.
    static func hourMinuteStyle(timeZone: TimeZone, use24Hour: Bool) -> Date.FormatStyle {
        var style = Date.FormatStyle()
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
            .locale(locale(use24Hour: use24Hour))
        style.timeZone = timeZone
        return style
    }

    /// A `Sendable` `Date.FormatStyle` rendering hour + minute + second,
    /// e.g. "9:05:42 AM" or "09:05:42".
    static func hourMinuteSecondStyle(timeZone: TimeZone, use24Hour: Bool) -> Date.FormatStyle {
        var style = Date.FormatStyle()
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
            .second(.twoDigits)
            .locale(locale(use24Hour: use24Hour))
        style.timeZone = timeZone
        return style
    }

    /// A `Sendable` `Date.FormatStyle` rendering a short weekday + date, e.g. "Mon, Jun 20".
    static func shortDateStyle(timeZone: TimeZone) -> Date.FormatStyle {
        var style = Date.FormatStyle()
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day(.defaultDigits)
            .locale(.current)
        style.timeZone = timeZone
        return style
    }

    /// A `Sendable` `Date.FormatStyle` rendering weekday, date, and time,
    /// e.g. "Mon, Jun 20, 9:05 AM" or "Mon, Jun 20, 09:05".
    static func fullDateTimeStyle(timeZone: TimeZone, use24Hour: Bool) -> Date.FormatStyle {
        var style = Date.FormatStyle()
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day(.defaultDigits)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
            .locale(locale(use24Hour: use24Hour))
        style.timeZone = timeZone
        return style
    }

    // MARK: - String convenience wrappers

    /// Returns a localised "h:mm a" / "HH:mm" string for `date` in the given zone.
    static func hourMinute(date: Date, timeZone: TimeZone, use24Hour: Bool) -> String {
        date.formatted(hourMinuteStyle(timeZone: timeZone, use24Hour: use24Hour))
    }

    /// Convenience overload taking an IANA timezone identifier.
    static func hourMinute(date: Date, timeZoneId: String, use24Hour: Bool) -> String {
        hourMinute(date: date, timeZone: safeTimeZone(id: timeZoneId), use24Hour: use24Hour)
    }

    /// Returns a localised "h:mm:ss a" / "HH:mm:ss" string for `date` in the given zone.
    static func hourMinuteSecond(date: Date, timeZone: TimeZone, use24Hour: Bool) -> String {
        date.formatted(hourMinuteSecondStyle(timeZone: timeZone, use24Hour: use24Hour))
    }

    /// Convenience overload taking an IANA timezone identifier.
    static func hourMinuteSecond(date: Date, timeZoneId: String, use24Hour: Bool) -> String {
        hourMinuteSecond(date: date, timeZone: safeTimeZone(id: timeZoneId), use24Hour: use24Hour)
    }

    /// Returns a short date string such as "Mon, Jun 20" for `date` in the given zone.
    static func shortDate(date: Date, timeZoneId: String) -> String {
        date.formatted(shortDateStyle(timeZone: safeTimeZone(id: timeZoneId)))
    }

    /// Returns a full date-and-time string such as "Mon, Jun 20, 9:05 AM".
    static func fullDateTime(date: Date, timeZoneId: String, use24Hour: Bool) -> String {
        date.formatted(fullDateTimeStyle(timeZone: safeTimeZone(id: timeZoneId), use24Hour: use24Hour))
    }

    // MARK: - UTC offset

    /// Returns a human-readable UTC offset string such as "UTC+5:30" or "UTC-8"
    /// for the given IANA timezone identifier at the specified instant (DST-aware).
    static func utcOffset(for tzId: String, at date: Date) -> String {
        let totalSeconds = offsetSeconds(for: tzId, at: date)
        let sign         = totalSeconds >= 0 ? "+" : "-"
        let absVal       = abs(totalSeconds)
        let hours        = absVal / 3600
        let minutes      = (absVal % 3600) / 60

        if minutes == 0 {
            return "UTC\(sign)\(hours)"
        } else {
            return String(format: "UTC%@%d:%02d", sign, hours, minutes)
        }
    }

    // MARK: - Locale helpers

    /// Returns `true` when the device's current locale uses a 24-hour clock by default.
    static func is24HourSystem() -> Bool {
        switch Locale.current.hourCycle {
        case .zeroToTwentyThree, .oneToTwentyFour:
            return true
        default:
            return false
        }
    }

    /// Maps a ``HourCycle`` preference to a concrete boolean, resolving `.system` by
    /// checking the current locale.
    ///
    /// - Parameter cycle: The user's saved hour-cycle preference.
    /// - Returns: `true` for 24-hour display, `false` for 12-hour.
    static func uses24Hour(cycle: HourCycle) -> Bool {
        switch cycle {
        case .system:     return is24HourSystem()
        case .twelve:     return false
        case .twentyFour: return true
        }
    }

    // MARK: - Timezone helpers

    /// Returns a `TimeZone` for the given IANA identifier, or UTC / `.current` as a
    /// fallback when the identifier is unrecognised.
    static func safeTimeZone(id: String) -> TimeZone {
        TimeZone(identifier: id) ?? TimeZone(identifier: "UTC") ?? .current
    }

    /// Returns the total UTC offset in seconds for the given IANA timezone identifier
    /// at the specified instant (DST-aware). Positive = ahead of UTC.
    static func offsetSeconds(for tzId: String, at date: Date) -> Int {
        safeTimeZone(id: tzId).secondsFromGMT(for: date)
    }
}

// MARK: - Date + startOfDay

extension Date {

    /// The beginning of the calendar day (midnight) in the device's current calendar
    /// and timezone for this `Date` value.
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
