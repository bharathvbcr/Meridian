// TzAbbreviations.swift
// Meridian — iOS 27+ / Swift 6
//
// Ported from app/src/main/java/com/example/core/time/TzAbbreviations.kt

import Foundation

/// Common time-zone abbreviations → IANA ids for AI grounding and zone search.
///
/// Abbreviations are inherently ambiguous (CST = US Central vs China). This table maps the
/// unambiguous travel/planner cases; ambiguous ones need a phrase hint (see ``phrases``) or fall
/// through to ``PlaceIndex`` and the full search stack.
public enum TzAbbreviations {

    private static let aliases: [String: String] = [
        // Americas (US — unambiguous 3-letter daylight forms)
        "EST": "America/New_York",
        "EDT": "America/New_York",
        "ET": "America/New_York",
        "CDT": "America/Chicago",
        "MDT": "America/Denver",
        "MST": "America/Denver",
        "MT": "America/Denver",
        "PDT": "America/Los_Angeles",
        "PST": "America/Los_Angeles",
        "PT": "America/Los_Angeles",
        "AKST": "America/Anchorage",
        "AKDT": "America/Anchorage",
        "HST": "Pacific/Honolulu",
        "BRT": "America/Sao_Paulo",
        "ART": "America/Argentina/Buenos_Aires",
        // Europe / Africa
        "GMT": "UTC",
        "UTC": "UTC",
        "WET": "Europe/Lisbon",
        "CET": "Europe/Paris",
        "CEST": "Europe/Paris",
        "EET": "Europe/Helsinki",
        "EEST": "Europe/Helsinki",
        "MSK": "Europe/Moscow",
        "TRT": "Europe/Istanbul",
        "SAST": "Africa/Johannesburg",
        "EAT": "Africa/Nairobi",
        "WAT": "Africa/Lagos",
        // Asia / Pacific
        "IST": "Asia/Kolkata",
        "PKT": "Asia/Karachi",
        "ICT": "Asia/Bangkok",
        "SGT": "Asia/Singapore",
        "HKT": "Asia/Hong_Kong",
        "JST": "Asia/Tokyo",
        "KST": "Asia/Seoul",
        "AEST": "Australia/Sydney",
        "AEDT": "Australia/Sydney",
        "AWST": "Australia/Perth",
        "NZST": "Pacific/Auckland",
        "NZDT": "Pacific/Auckland",
        "GST": "Asia/Dubai",
        "IRST": "Asia/Tehran",
    ]

    /// Ambiguous abbreviations disambiguated by a surrounding phrase. Order matters: first match wins.
    /// Each entry is a case-insensitive, whole-word-anchored regex → IANA id.
    nonisolated(unsafe) private static let phrases: [(Regex<Substring>, String)] = [
        (try! Regex(#"(?i)\bchina\s+cst\b"#), "Asia/Shanghai"),
        (try! Regex(#"(?i)\bcn\s+cst\b"#), "Asia/Shanghai"),
        (try! Regex(#"(?i)\bus\s+cst\b"#), "America/Chicago"),
        (try! Regex(#"(?i)\bcentral\s+time\b"#), "America/Chicago"),
        (try! Regex(#"(?i)\beastern\s+time\b"#), "America/New_York"),
        (try! Regex(#"(?i)\bpacific\s+time\b"#), "America/Los_Angeles"),
        (try! Regex(#"(?i)\bmountain\s+time\b"#), "America/Denver"),
        (try! Regex(#"(?i)\bbangladesh\s+time\b"#), "Asia/Dhaka"),
        (try! Regex(#"(?i)\bbritish\s+summer\s+time\b"#), "Europe/London"),
        (try! Regex(#"(?i)\bbst\b"#), "Europe/London"),
    ]

    /// Resolve `query` to a zone via phrase hints first, then the exact abbreviation table.
    public static func resolve(_ query: String) -> ZoneMatch? {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        for (regex, zoneId) in phrases where (try? regex.firstMatch(in: raw)) != nil {
            return ZoneMatch(zoneId: zoneId, displayName: raw)
        }
        let key = raw.uppercased()
        guard let zoneId = aliases[key] else { return nil }
        return ZoneMatch(zoneId: zoneId, displayName: key)
    }

    /// True when `token` looks like a bare abbreviation (2–5 letters).
    public static func looksLikeAbbreviation(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return (2...5).contains(t.count) && t.allSatisfy(\.isLetter)
    }
}
