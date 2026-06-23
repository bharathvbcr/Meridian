// MeridianAiTools.swift
// Meridian — iOS 27 / Swift 6
//
// The assistant's deterministic capability layer — the bridge that lets the
// model answer real-world "what time is it in Tokyo?" questions and act on time
// instead of replying that it has no live data. Ported from Android's
// `core/ai/MeridianAiTools.kt` (the callable-tool half; the grounding half lives
// in `AiGrounding.swift`).
//
// Every fact here is computed by the app's own time engine and zone search — the
// LLM never does time math (§12.7). Surfaced two complementary ways:
//
//  - Foundation Models `Tool` types (`GetCurrentTimeTool`, `ConvertTimeTool`,
//    `FindMeetingTimeTool`) for the on-device / cloud function-calling path.
//  - `AiGroundingBuilder` pre-resolves the live clock as plain text for prompts
//    where the model can't call tools.
//
// Zone resolution is delegated to `PlaceIndex` plus UTC-offset parsing — the same
// resolution the grounding builder uses.

import Foundation
import FoundationModels

// MARK: - MeridianAiTools

/// Deterministic time computations shared by the Foundation Models tools and the
/// cloud function-calling dispatcher. `@MainActor` because it reads
/// `PlaceIndex.shared`.
@MainActor
final class MeridianAiTools {

    private let findOverlap: FindOverlapUseCase
    private let now: @Sendable () -> Date

    init(findOverlap: FindOverlapUseCase, now: @escaping @Sendable () -> Date = { Date() }) {
        self.findOverlap = findOverlap
        self.now = now
    }

    // MARK: - Resolved place

    struct Resolved: Sendable {
        let id: String
        let name: String
    }

    /// Resolves a place name or zone query to a validated IANA zone id, or nil.
    /// Used by `ScheduleParser` to map a model-provided place to a zone.
    func resolveZoneId(_ query: String) -> String? {
        resolveZone(query)?.id
    }

    /// Resolves a query to a place, mirroring Android `resolveZoneFast` →
    /// abbreviations, curated `PlaceIndex`, UTC/GMT offsets, then exact IANA id.
    func resolveZone(_ query: String) -> Resolved? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Time-zone abbreviation / phrase hint (e.g. "JST", "Pacific Time").
        if let match = TzAbbreviations.resolve(trimmed), let id = AiGroundingBuilder.normalizedZoneId(match.zoneId) {
            return Resolved(id: id, name: match.displayName)
        }
        // Curated city index (one indexed lookup before any fuzzy match).
        if let entry = PlaceIndex.shared.entry(for: trimmed) {
            return Resolved(id: entry.tzId, name: entry.displayName)
        }
        // UTC/GMT offset ("UTC+9", "GMT-5:30", "+05:30").
        if let match = OffsetZones.parse(trimmed).first, let id = AiGroundingBuilder.normalizedZoneId(match.zoneId) {
            return Resolved(id: id, name: match.displayName)
        }
        // Exact IANA identifier.
        if let tz = TimeZone(identifier: trimmed), tz.identifier == trimmed {
            return Resolved(id: trimmed, name: shortZoneName(trimmed))
        }
        // Fuzzy place search.
        if let entry = PlaceIndex.shared.search(query: trimmed, limit: 1).first {
            return Resolved(id: entry.tzId, name: entry.displayName)
        }
        return nil
    }

    // MARK: - get_current_time

    /// The real current local date and time at a place. Returns a human-readable
    /// summary (also suitable as a tool output the model reasons over).
    func getCurrentTime(location: String?) -> String {
        guard let location, !location.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Error: no location was provided."
        }
        guard let zone = resolveZone(location), let tz = TimeZone(identifier: zone.id) else {
            return "Error: couldn't find a place matching \"\(location)\"."
        }
        let instant = now()
        let time = format(instant, tz: tz, pattern: "HH:mm")
        let date = format(instant, tz: tz, pattern: "EEEE, d MMMM yyyy")
        let offset = TimeFormats.utcOffset(for: zone.id, at: instant)
        return "\(zone.name) (\(zone.id)): \(time) on \(date), \(offset)."
    }

    // MARK: - convert_time

    /// Converts a clock time from one place to the equivalent local time in another.
    func convertTime(time: String?, from: String?, to: String?) -> String {
        guard let time, !time.isEmpty, let from, !from.isEmpty, let to, !to.isEmpty else {
            return "Error: convert_time needs a time, a from_location, and a to_location."
        }
        guard let fromZone = resolveZone(from), let fromTz = TimeZone(identifier: fromZone.id) else {
            return "Error: couldn't find a place matching \"\(from)\"."
        }
        guard let toZone = resolveZone(to), let toTz = TimeZone(identifier: toZone.id) else {
            return "Error: couldn't find a place matching \"\(to)\"."
        }
        guard let source = parseWallClock(time, tz: fromTz) else {
            return "Error: couldn't understand the time \"\(time)\". Use \"HH:mm\" or \"yyyy-MM-ddTHH:mm\"."
        }

        let srcStr = "\(fromZone.name): \(format(source, tz: fromTz, pattern: "HH:mm")) \(format(source, tz: fromTz, pattern: "EEEE, d MMMM yyyy"))"
        let dstStr = "\(toZone.name): \(format(source, tz: toTz, pattern: "HH:mm")) \(format(source, tz: toTz, pattern: "EEEE, d MMMM yyyy"))"

        let shift = dayNumber(source, tz: toTz) - dayNumber(source, tz: fromTz)
        let dayDiff = shift > 0 ? "the next day" : (shift < 0 ? "the previous day" : "the same day")

        return "\(srcStr) = \(dstStr) (\(dayDiff))."
    }

    // MARK: - find_meeting_time

    /// The fairest meeting hours shared across two or more places, ranked best-first.
    func findMeetingTime(locations: [String], withinDays: Int) -> String {
        var resolved: [Resolved] = []
        var seen = Set<String>()
        for raw in locations {
            guard let zone = resolveZone(raw), !seen.contains(zone.id) else { continue }
            seen.insert(zone.id)
            resolved.append(zone)
        }
        if resolved.count < 2 {
            return "Error: need at least two recognizable places to compare; resolved \(resolved.count)."
        }

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let startOfDay = utcCal.startOfDay(for: now())
        let baseDate = utcCal.date(byAdding: .day, value: min(max(withinDays, 0), 365), to: startOfDay) ?? startOfDay

        let settings = SettingsRepository.shared.settings
        let participants = resolved.map {
            MeetingParticipant(
                name: $0.name,
                zoneId: $0.id,
                workStartHour: settings.defaultWorkStartHour,
                workEndHour: settings.defaultWorkEndHour
            )
        }

        let slots = findOverlap.rankParticipantSlots(
            baseDate: baseDate,
            participants: participants
        ).prefix(3)

        let places = resolved.map(\.name).joined(separator: ", ")
        var lines: [String] = []
        for slot in slots {
            let locals = resolved.compactMap { r -> String? in
                guard let tz = TimeZone(identifier: r.id) else { return nil }
                let hour = hourOf(slot.start, tz: tz)
                return "\(r.name) \(String(format: "%02d:00", hour))"
            }.joined(separator: ", ")
            lines.append("\(slot.label.displayName): \(locals)")
        }
        return "Fair meeting times for \(places):\n" + lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Parses a time-of-day (today in `tz`) or a full ISO "yyyy-MM-ddTHH:mm".
    private func parseWallClock(_ raw: String, tz: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        // Tolerate a space between date and time as well as the ISO "T".
        let text = raw.trimmingCharacters(in: .whitespaces)
        let isoText = replaceFirstDateTimeSpace(text)

        // Full ISO local date-time.
        if let m = matchGroups("^(\\d{4})-(\\d{1,2})-(\\d{1,2})[T ](\\d{1,2}):(\\d{2})", in: isoText),
           let y = Int(m[1]), let mo = Int(m[2]), let d = Int(m[3]), let h = Int(m[4]), let mi = Int(m[5]) {
            var comps = DateComponents()
            comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi; comps.second = 0
            if let date = cal.date(from: comps) { return date }
        }

        // Time-of-day only → today in `tz`.
        if let time = parseClockTime(text) {
            var comps = cal.dateComponents([.year, .month, .day], from: now())
            comps.hour = time.hour; comps.minute = time.minute; comps.second = 0
            return cal.date(from: comps)
        }
        return nil
    }

    private func parseClockTime(_ raw: String) -> (hour: Int, minute: Int)? {
        let t = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let m = matchGroups("(?<!\\d)(\\d{1,2})(?::(\\d{2}))?\\s*(a\\.?m\\.?|p\\.?m\\.?)", in: t) {
            var h = Int(m[1]) ?? 0
            let min = Int(m[2]) ?? 0
            if (1...12).contains(h) && (0...59).contains(min) {
                if h == 12 { h = 0 }
                if m[3].replacingOccurrences(of: ".", with: "") == "pm" { h += 12 }
                return (h, min)
            }
        }
        if let m = matchGroups("(?<![\\d:])(\\d{1,2}):(\\d{2})(?!\\d)", in: t) {
            let h = Int(m[1]) ?? -1
            let min = Int(m[2]) ?? -1
            if (0...23).contains(h) && (0...59).contains(min) { return (h, min) }
        }
        return nil
    }

    private func replaceFirstDateTimeSpace(_ text: String) -> String {
        // Replace the single space between an ISO date and time with "T".
        guard let regex = try? NSRegularExpression(pattern: "(?<=\\d) (?=\\d)", options: []) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "T")
    }

    private func shortZoneName(_ zoneId: String) -> String {
        (zoneId.split(separator: "/").last.map(String.init) ?? zoneId).replacingOccurrences(of: "_", with: " ")
    }

    private func format(_ date: Date, tz: TimeZone, pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = pattern
        return f.string(from: date)
    }

    private func hourOf(_ date: Date, tz: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.hour, from: date)
    }

    private func dayNumber(_ date: Date, tz: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 372 + (c.month ?? 0) * 31 + (c.day ?? 0)
    }

    private func matchGroups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
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
}

// MARK: - Foundation Models Tools
//
// The Foundation Models `Tool.call(arguments:)` requirement is nonisolated
// (`@concurrent`), so these conform as `Sendable` structs holding only Sendable
// inputs (`FindOverlapUseCase` is Sendable, plus a `@Sendable now` closure). Each
// `call` hops to the main actor to build a `MeridianAiTools` (which reads the
// `@MainActor` `PlaceIndex`) and run the deterministic computation.

/// `get_current_time(location)` — the real current time at any place.
struct GetCurrentTimeTool: Tool {
    let name = "get_current_time"
    let description = """
        Get the current real-world local date and time at a city, place, airport code, \
        or UTC offset — e.g. "Tokyo", "New York", "LHR", or "UTC+9". Call this whenever \
        the user asks what time it is somewhere.
        """

    let findOverlap: FindOverlapUseCase
    let now: @Sendable () -> Date

    @Generable
    struct Arguments {
        @Guide(description: "A city, place, airport code, or UTC offset — e.g. \"Tokyo\", \"New York\", \"LHR\", or \"UTC+9\".")
        var location: String
    }

    func call(arguments: Arguments) async throws -> String {
        let (findOverlap, now) = (self.findOverlap, self.now)
        let location = arguments.location
        return await MainActor.run {
            MeridianAiTools(findOverlap: findOverlap, now: now).getCurrentTime(location: location)
        }
    }
}

/// `convert_time(time, from_location, to_location)` — convert a time between places.
struct ConvertTimeTool: Tool {
    let name = "convert_time"
    let description = "Convert a clock time from one place to the equivalent local time in another place."

    let findOverlap: FindOverlapUseCase
    let now: @Sendable () -> Date

    @Generable
    struct Arguments {
        @Guide(description: "The time to convert — 24-hour \"HH:mm\" or ISO \"yyyy-MM-ddTHH:mm\". If only a time of day is given, today's date in the source place is assumed.")
        var time: String
        @Guide(description: "The place the given time is in.")
        var fromLocation: String
        @Guide(description: "The place to convert the time into.")
        var toLocation: String
    }

    func call(arguments: Arguments) async throws -> String {
        let (findOverlap, now) = (self.findOverlap, self.now)
        let (time, from, to) = (arguments.time, arguments.fromLocation, arguments.toLocation)
        return await MainActor.run {
            MeridianAiTools(findOverlap: findOverlap, now: now).convertTime(time: time, from: from, to: to)
        }
    }
}

/// `find_meeting_time(locations, within_days)` — the fairest shared meeting hours.
struct FindMeetingTimeTool: Tool {
    let name = "find_meeting_time"
    let description = """
        Find the fairest meeting hours shared across two or more places, ranked best-first — \
        for questions like "best time to meet for New York, Berlin and Singapore?".
        """

    let findOverlap: FindOverlapUseCase
    let now: @Sendable () -> Date

    @Generable
    struct Arguments {
        @Guide(description: "Two or more cities, places, or time zones that need to meet.")
        var locations: [String]
        @Guide(description: "How many days from today to search (0 = today, 1 = tomorrow). Defaults to today.")
        var withinDays: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let (findOverlap, now) = (self.findOverlap, self.now)
        let (locations, withinDays) = (arguments.locations, arguments.withinDays)
        return await MainActor.run {
            MeridianAiTools(findOverlap: findOverlap, now: now).findMeetingTime(locations: locations, withinDays: withinDays)
        }
    }
}
