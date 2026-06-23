// ScheduleTimeParser.swift
// Meridian — iOS 27 / Swift 6
//
// Deterministically resolves a natural-language date/time phrase to a `Date`
// in a given zone, anchored at "now". Ported 1:1 from Android's
// `core/time/ScheduleTimeParser.kt`.
//
// This is the app's own time math — the LLM only *extracts* the phrase
// ("next Monday 2pm", "tomorrow", "2026-06-22 14:00") and this parser turns it
// into an exact instant, so a weak on-device model can never pick the wrong time.
//
// Supported, case-insensitive:
//  - absolute ISO dates `yyyy-MM-dd` (optionally with a time);
//  - relative days: today/tonight, tomorrow, day after tomorrow, yesterday;
//  - weekdays with optional `this`/`next` (e.g. "next friday"), and "next week";
//  - month-day: "June 22", "22 Jun" (year optional; rolls to next year if past);
//  - durations from now: "in 30 minutes", "in 2 hours", "in a week";
//  - times: "2pm", "2:30 pm", 24-hour "14:00", noon/midnight/morning/etc.
//
// Conventions: a bare or "this" weekday is the soonest occurrence *including
// today*; "next" weekday skips today. A date with no time defaults to 09:00; a
// time with no date is today if still ahead, otherwise tomorrow. Returns nil if
// nothing parses.

import Foundation

enum ScheduleTimeParser {

    /// Default time-of-day applied to a date that arrives without one (09:00).
    static let defaultHour = 9
    static let defaultMinute = 0

    /// Relative durations beyond this many years out are treated as unparseable.
    private static let maxFutureYears = 200

    // MARK: - Public entry point

    /// Resolves `phrase` to an absolute `Date` in `zone`, anchored at `now`.
    static func parse(_ phrase: String, zone: TimeZone, now: Date) -> Date? {
        let text = phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let time = parseTimeOfDay(text)

        // "in N <unit>" sets a full instant; for day/week units an explicit
        // time-of-day still applies.
        if let relative = parseRelativeDuration(text, calendar: calendar, now: now, time: time) {
            return relative
        }

        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let todayDate = calendar.date(from: today) else { return nil }
        let date = parseDate(text, today: todayDate, calendar: calendar)

        // Build the local wall-clock date/time, then convert to an absolute Date.
        if let date {
            let t = time ?? (hour: defaultHour, minute: defaultMinute)
            return makeDate(date: date, hour: t.hour, minute: t.minute, calendar: calendar)
        }
        if let time {
            // Today at `time` if still ahead of `now`, otherwise tomorrow.
            guard let todayAt = makeDate(date: todayDate, hour: time.hour, minute: time.minute, calendar: calendar)
            else { return nil }
            if todayAt > now { return todayAt }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayDate) else { return nil }
            return makeDate(date: tomorrow, hour: time.hour, minute: time.minute, calendar: calendar)
        }
        return nil
    }

    // MARK: - Relative durations

    private static func parseRelativeDuration(
        _ text: String,
        calendar: Calendar,
        now: Date,
        time: (hour: Int, minute: Int)?
    ) -> Date? {
        guard let match = firstMatch(relativeDurationPattern, in: text) else { return nil }
        let countRaw = match[1]
        let unit = match[2]

        let n: Int
        if countRaw == "a" || countRaw == "an" {
            n = 1
        } else if let parsed = Int(countRaw) {
            n = parsed
        } else {
            return nil
        }

        let result: Date?
        if unit.hasPrefix("min") {
            // Minutes/hours are absolute offsets from now; a stray time-of-day doesn't apply.
            result = calendar.date(byAdding: .minute, value: n, to: now)
        } else if unit.hasPrefix("h") {
            result = calendar.date(byAdding: .hour, value: n, to: now)
        } else if unit.hasPrefix("day") {
            result = applyTime(calendar.date(byAdding: .day, value: n, to: now), time, calendar: calendar)
        } else if unit.hasPrefix("w") {
            result = applyTime(calendar.date(byAdding: .day, value: n * 7, to: now), time, calendar: calendar)
        } else {
            return nil
        }

        guard let result else { return nil }
        // Treat anything past a sane horizon as unparseable rather than scheduling it.
        let resultYear = calendar.component(.year, from: result)
        let nowYear = calendar.component(.year, from: now)
        if resultYear > nowYear + maxFutureYears { return nil }
        return result
    }

    /// Replaces the time-of-day of `date` with `time` (keeping its calendar day), or returns `date`.
    private static func applyTime(
        _ date: Date?,
        _ time: (hour: Int, minute: Int)?,
        calendar: Calendar
    ) -> Date? {
        guard let date else { return nil }
        guard let time else { return date }
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = time.hour
        comps.minute = time.minute
        comps.second = 0
        return calendar.date(from: comps)
    }

    // MARK: - Time of day

    private static func parseTimeOfDay(_ text: String) -> (hour: Int, minute: Int)? {
        if let m = firstMatch(amPmTimePattern, in: text) {
            var h = Int(m[1]) ?? 0
            let min = Int(m[2]) ?? 0
            let pm = m[3].replacingOccurrences(of: ".", with: "") == "pm"
            if (1...12).contains(h) && (0...59).contains(min) {
                if h == 12 { h = 0 }
                if pm { h += 12 }
                return (h, min)
            }
        }
        if let m = firstMatch(twentyFourHourPattern, in: text) {
            let h = Int(m[1]) ?? -1
            let min = Int(m[2]) ?? -1
            if (0...23).contains(h) && (0...59).contains(min) { return (h, min) }
        }
        if text.contains("midnight") { return (0, 0) }
        // Word-boundary match: "noon" must not fire inside "afternoon".
        if containsMatch(noonPattern, in: text) { return (12, 0) }
        if text.contains("afternoon") { return (14, 0) }
        if text.contains("morning") { return (9, 0) }
        if text.contains("evening") { return (18, 0) }
        if text.contains("tonight") || text.contains("night") { return (20, 0) }
        return nil
    }

    // MARK: - Date

    private static func parseDate(_ text: String, today: Date, calendar: Calendar) -> Date? {
        if let m = firstMatch(isoDatePattern, in: text),
           let year = Int(m[1]), let month = Int(m[2]), let day = Int(m[3]) {
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day
            comps.hour = 0; comps.minute = 0; comps.second = 0
            if let d = calendar.date(from: comps),
               calendar.component(.month, from: d) == month,
               calendar.component(.day, from: d) == day {
                return d
            }
        }

        if text.contains("day after tomorrow") { return calendar.date(byAdding: .day, value: 2, to: today) }
        if text.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: today) }
        if text.contains("today") || text.contains("tonight") { return today }
        if text.contains("yesterday") { return calendar.date(byAdding: .day, value: -1, to: today) }

        // "next week [monday]" anchors the weekday search a week ahead.
        let nextWeek = containsMatch(nextWeekPattern, in: text)
        let anchor = nextWeek ? (calendar.date(byAdding: .day, value: 7, to: today) ?? today) : today
        if let weekday = parseWeekday(text, anchor: anchor, calendar: calendar) { return weekday }
        if nextWeek { return anchor }
        if let monthDay = parseMonthDay(text, today: today, calendar: calendar) { return monthDay }
        return nil
    }

    private static func parseWeekday(_ text: String, anchor: Date, calendar: Calendar) -> Date? {
        for (name, dow) in weekdays {
            guard containsMatch("\\b\(name)\\b", in: text) else { continue }
            let isNext = containsMatch("\\bnext\\s+\(name)\\b", in: text)
            // Gregorian: Calendar weekday 1 = Sunday ... 7 = Saturday.
            // `dow` here is 1 = Monday ... 7 = Sunday (java.time semantics); convert.
            let anchorWeekday = isoWeekday(of: anchor, calendar: calendar)
            var days = ((dow - anchorWeekday) % 7 + 7) % 7
            if isNext && days == 0 { days = 7 }
            return calendar.date(byAdding: .day, value: days, to: anchor)
        }
        return nil
    }

    private static func parseMonthDay(_ text: String, today: Date, calendar: Calendar) -> Date? {
        for (name, month) in months {
            let after = firstMatch("\\b\(name)\\b\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?\\b", in: text)
            let before = firstMatch("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+\(name)\\b(?:,?\\s+(\\d{4}))?", in: text)
            guard let match = after ?? before else { continue }
            guard let day = Int(match[1]) else { continue }
            let year = match.count > 2 ? Int(match[2]) : nil

            let todayYear = calendar.component(.year, from: today)
            var comps = DateComponents()
            comps.year = year ?? todayYear
            comps.month = month
            comps.day = day
            comps.hour = 0; comps.minute = 0; comps.second = 0
            guard var date = calendar.date(from: comps),
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day
            else { continue }
            // No explicit year and the date already passed this year → next year.
            if year == nil && date < today {
                date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
            }
            return date
        }
        return nil
    }

    // MARK: - Helpers

    /// Builds an absolute `Date` from a calendar-day `date` plus an explicit hour/minute.
    private static func makeDate(date: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)
    }

    /// ISO weekday number for `date`: 1 = Monday ... 7 = Sunday (matches `weekdays` table).
    private static func isoWeekday(of date: Date, calendar: Calendar) -> Int {
        // Calendar.weekday: 1 = Sunday ... 7 = Saturday. Convert to ISO Monday=1.
        let w = calendar.component(.weekday, from: date)
        return ((w + 5) % 7) + 1
    }

    // MARK: - Lookup tables (ISO weekday: Monday = 1 ... Sunday = 7)

    private static let weekdays: [(String, Int)] = [
        ("monday", 1), ("tuesday", 2), ("wednesday", 3),
        ("thursday", 4), ("friday", 5), ("saturday", 6), ("sunday", 7),
        ("mon", 1), ("tue", 2), ("wed", 3),
        ("thu", 4), ("fri", 5), ("sat", 6), ("sun", 7),
    ]

    private static let months: [(String, Int)] = [
        ("january", 1), ("february", 2), ("march", 3), ("april", 4),
        ("may", 5), ("june", 6), ("july", 7), ("august", 8),
        ("september", 9), ("october", 10), ("november", 11), ("december", 12),
        ("jan", 1), ("feb", 2), ("mar", 3), ("apr", 4),
        ("jun", 6), ("jul", 7), ("aug", 8), ("sep", 9),
        ("sept", 9), ("oct", 10), ("nov", 11), ("dec", 12),
    ]

    // MARK: - Regex patterns

    private static let relativeDurationPattern =
        "\\bin\\s+(\\d+|an?)\\s+(minutes?|mins?|hours?|hrs?|days?|weeks?)\\b"
    private static let amPmTimePattern =
        "(?<!\\d)(\\d{1,2})(?::(\\d{2}))?\\s*(a\\.?m\\.?|p\\.?m\\.?)(?![a-z])"
    // Digit lookarounds (not \b) so an ISO "…-22T14:00" still yields the 14:00 time.
    private static let twentyFourHourPattern = "(?<![\\d:])(\\d{1,2}):(\\d{2})(?!\\d)"
    private static let isoDatePattern = "(?<!\\d)(\\d{4})-(\\d{1,2})-(\\d{1,2})(?!\\d)"
    private static let nextWeekPattern = "\\bnext\\s+week\\b"
    private static let noonPattern = "\\b(noon|midday)\\b"

    // MARK: - Regex utilities

    /// Returns the capture groups of the first match (index 0 = whole match, 1.. = groups).
    /// Missing optional groups are returned as empty strings.
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    private static func containsMatch(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
