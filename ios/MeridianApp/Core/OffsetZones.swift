// OffsetZones.swift
// Meridian — iOS 27+ / Swift 6
//
// Ported from app/src/main/java/com/example/core/time/OffsetZones.kt

import Foundation

/// Resolves raw UTC/GMT offset queries to addable zones, so users can search by offset
/// ("UTC", "GMT+1", "utc+5:30", "-0800", "+09:00") and not just by place. Fixed-offset ids
/// like "+05:30" are valid IANA/`TimeZone` ids, so they save and render like any other zone.
///
/// An offset must be anchored by a `utc`/`gmt` prefix or an explicit sign, so plain text or a
/// bare number ("5", "london") never masquerades as an offset.
public enum OffsetZones {

    /// `(utc|gmt|z|zulu)?  sign?  HH?  (:?MM)?`
    /// Anchored to the whole (already-trimmed, lower-cased) string.
    // VERIFY: Swift `Regex` literal — anchors `^…$` match start/end of the input; we additionally
    // require a full match via `wholeMatch`. The `(?::?(\d{2}))?` group makes the colon optional.
    nonisolated(unsafe) private static let pattern = /^(utc|gmt|z|zulu)?\s*([+-])?\s*(\d{1,2})?(?::?(\d{2}))?$/

    /// `java.time` caps offsets at ±18:00.
    private static let maxOffsetMinutes = 18 * 60

    private static let utc = ZoneMatch(zoneId: "UTC", displayName: "UTC")

    /// Parse `query` as a UTC/GMT offset. Returns a single-element list on success, `[]` otherwise.
    public static func parse(_ query: String) -> [ZoneMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return [] }
        guard let match = try? pattern.wholeMatch(in: q) else { return [] }

        // Optional capture groups; absent groups are nil → treat as "".
        let prefix = match.1.map(String.init) ?? ""
        let sign = match.2.map(String.init) ?? ""
        let hoursStr = match.3.map(String.init) ?? ""
        let minutesStr = match.4.map(String.init) ?? ""

        let hasPrefix = !prefix.isEmpty
        let hasDigits = !hoursStr.isEmpty

        // Bare "utc"/"gmt"/"z"/"zulu" -> UTC.
        if !hasDigits && sign.isEmpty {
            return hasPrefix ? [utc] : []
        }
        // Anchor requirement + "z"/"zulu" are bare-UTC only (no numeric offset).
        if !hasPrefix && sign.isEmpty { return [] }
        if prefix == "z" || prefix == "zulu" { return [] }
        if !hasDigits { return [] }

        guard let hours = Int(hoursStr) else { return [] }
        let minutes: Int
        if minutesStr.isEmpty {
            minutes = 0
        } else {
            guard let m = Int(minutesStr) else { return [] }
            minutes = m
        }
        if minutes > 59 { return [] }
        let totalMinutes = hours * 60 + minutes
        if totalMinutes > maxOffsetMinutes { return [] }

        let signed = (sign == "-" ? -1 : 1) * totalMinutes * 60
        if signed == 0 { return [utc] }

        // Present like Java's `ZoneOffset.id`: "+05:30" / "-08:00", labeled "UTC+05:30".
        let offsetId = formatOffsetId(totalSeconds: signed)
        return [ZoneMatch(zoneId: offsetId, displayName: "UTC\(offsetId)")]
    }

    /// Format a signed second-offset as a fixed-offset zone id matching `java.time.ZoneOffset.id`:
    /// sign + zero-padded `HH:MM` (and `:SS` only when non-zero, which never happens here).
    private static func formatOffsetId(totalSeconds: Int) -> String {
        let sign = totalSeconds < 0 ? "-" : "+"
        let abs = Swift.abs(totalSeconds)
        let hours = abs / 3600
        let minutes = (abs % 3600) / 60
        return String(format: "%@%02d:%02d", sign, hours, minutes)
    }
}
