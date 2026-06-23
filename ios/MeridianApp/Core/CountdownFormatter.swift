// CountdownFormatter.swift
// Meridian — iOS 27 / Swift 6
//
// Mirrors the Android `Reminders.formatCountdown` helper (§5.7) byte-for-byte so
// the bottom accessory pill and the Live Activity countdown read identically on
// both platforms. The source of truth is the Kotlin object
// `com.example.core.notify.Reminders`.

import Foundation

/// Stateless namespace that formats a remaining-time interval into the compact
/// countdown string shared by the accessory pill and the Live Activity.
///
/// Output grammar (matching Android exactly):
/// - `> 0` days  → `"2d 3h"`
/// - `> 0` hours → `"3h 45m"`
/// - `> 0` mins  → `"45m"`
/// - otherwise   → `"<1m"`
enum CountdownFormatter {

    // MARK: - Reminder / Live-Update windows (mirror Reminders.kt)

    /// Window before an event during which the live countdown is shown (24 h).
    static let liveWindow: TimeInterval = 24 * 60 * 60

    /// Window before an event during which the bottom accessory pill is shown (1 h).
    static let accessoryWindow: TimeInterval = 60 * 60

    // MARK: - Formatting

    /// Compact `"2d 3h"` / `"45m"` / `"<1m"` countdown string.
    ///
    /// - Parameter millis: Remaining time in milliseconds. Negative values are
    ///   clamped to zero, matching `coerceAtLeast(0)` on the Android side.
    /// - Returns: The formatted countdown string.
    static func formatCountdown(millis: Int64) -> String {
        let totalMinutes = max(millis / 60_000, 0)
        let days    = totalMinutes / (60 * 24)
        let hours   = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    /// Convenience overload taking a `TimeInterval` (seconds) — the natural unit
    /// for Swift `Date` arithmetic. Converts to milliseconds and delegates to the
    /// canonical implementation so behaviour stays identical to Android.
    ///
    /// - Parameter remaining: Seconds until the event. Negative is clamped to zero.
    /// - Returns: The formatted countdown string.
    static func formatCountdown(remaining: TimeInterval) -> String {
        formatCountdown(millis: Int64((remaining * 1000).rounded()))
    }

    /// Countdown from `now` until `target`. Returns `"<1m"` once the target has
    /// passed (negative interval clamps to zero).
    ///
    /// - Parameters:
    ///   - target: The event instant.
    ///   - now:    Reference instant; defaults to `Date()`.
    /// - Returns: The formatted countdown string.
    static func countdown(to target: Date, now: Date = Date()) -> String {
        formatCountdown(remaining: target.timeIntervalSince(now))
    }
}
