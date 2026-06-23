// AiGrounding.swift
// Meridian — iOS 27 / Swift 6
//
// Pre-resolved semantic context injected ahead of the user's message so the
// on-device Foundation Models session can answer without tool calls. Ported from
// Android's `core/ai/AiGrounding.kt` + the grounding half of `MeridianAiTools.kt`.
//
// `block` is the full LIVE CLOCK / TIME CONVERSIONS / MEETING SLOTS text;
// `intent` drives lean prompt assembly (see `AiAssistant`). The LLM never does
// time math — every fact here is computed by the app's own engine.

import Foundation

// MARK: - AiQueryIntent

/// Classified intent of a user prompt, mirroring Android's `AiQueryIntent`.
enum AiQueryIntent: Sendable {
    case currentTime
    case convert
    case meeting
    case schedule
    case general

    /// Short hint appended to the grounding block (mirrors Android `promptHint`).
    var promptHint: String {
        switch self {
        case .currentTime: return "current time lookup — answer from LIVE CLOCK"
        case .convert:     return "time conversion — answer from TIME CONVERSIONS if present, else convert it"
        case .meeting:     return "meeting time — answer from MEETING SLOTS if present, else find a fair time"
        case .schedule:    return "schedule an event — reply with schedule JSON only"
        case .general:     return "general time question — use LIVE CLOCK as needed"
        }
    }
}

// MARK: - AiGrounding

/// The pre-resolved context (text block + intent) for a single prompt.
struct AiGrounding: Sendable {
    let block: String
    let intent: AiQueryIntent

    static let empty = AiGrounding(block: "", intent: .general)
}

// MARK: - AiGroundingBuilder

/// Builds the LIVE CLOCK grounding block for a prompt: the user's home zone, their
/// saved zones, any people named in the prompt, and any places named in the prompt.
///
/// `@MainActor` because it reads `PlaceIndex.shared` (a `@MainActor` type) and the
/// assistant always runs on the main actor.
@MainActor
struct AiGroundingBuilder {

    private let findOverlap: FindOverlapUseCase
    private let now: @Sendable () -> Date

    init(findOverlap: FindOverlapUseCase, now: @escaping @Sendable () -> Date = { Date() }) {
        self.findOverlap = findOverlap
        self.now = now
    }

    // MARK: - Public API

    /// Convenience returning only the text block (matches Android `groundingFacts`).
    func groundingFacts(
        prompt: String,
        homeZoneId: String,
        savedZones: [SavedZone],
        people: [Person] = []
    ) -> String {
        build(prompt: prompt, homeZoneId: homeZoneId, savedZones: savedZones, people: people).block
    }

    /// Builds the full grounding (block + intent) for `prompt`.
    func build(
        prompt: String,
        homeZoneId: String,
        savedZones: [SavedZone],
        people: [Person] = []
    ) -> AiGrounding {
        let instant = now()

        // Ordered, de-duplicated set of "Name — Fri 14:30, 22 Jun 2026" lines.
        var lineKeys: [String] = []
        var lineValues: [String: String] = [:]

        func addZone(_ zoneId: String, _ name: String) {
            if lineValues[zoneId] != nil { return }
            guard let tz = TimeZone(identifier: zoneId) else { return }
            lineKeys.append(zoneId)
            lineValues[zoneId] = "\(name) — \(groundingTimeString(instant, tz: tz))"
        }

        func addPersonLine(_ person: Person, label: String) {
            let key = "\(person.tzId)\u{0000}\(person.displayLocation())"
            if lineValues[key] != nil { return }
            guard let tz = TimeZone(identifier: person.tzId) else { return }
            let hour = hourOf(instant, tz: tz)
            let tag = scheduleTag(hour: hour, person: person)
            lineKeys.append(key)
            lineValues[key] = "\(label) — \(groundingTimeString(instant, tz: tz))\(tag)"
        }

        // Home zone first.
        let homeName = "You · \(localLocationLabel(savedZones, homeZoneId))"
        addZone(homeZoneId, homeName)

        // Saved zones (bounded).
        for zone in savedZones.prefix(Self.maxSavedZones) {
            addZone(zone.id, zone.displayName)
        }

        // Saved zones explicitly named in the prompt.
        for zone in savedZonesMentioned(prompt, savedZones) {
            addZone(zone.id, zone.displayName)
        }

        // People named in the prompt.
        let mentionedPeople = peopleMentioned(prompt, people)
        for person in mentionedPeople {
            let label = person.name.trimmingCharacters(in: .whitespaces).isEmpty
                ? person.displayLocation()
                : "\(person.name) · \(person.displayLocation())"
            addPersonLine(person, label: label)
        }

        // Places explicitly named in the prompt (resolved via PlaceIndex / UTC offsets).
        let promptPlaces = resolvePromptPlaces(prompt)
        for place in promptPlaces {
            addZone(place.zoneId, place.name)
        }

        if lineKeys.isEmpty { return .empty }

        let intent = detectIntent(prompt)
        let conversions = buildConversions(prompt, promptPlaces: promptPlaces, homeZoneId: homeZoneId, instant: instant)
        let participants = meetingParticipants(promptPlaces: promptPlaces, mentionedPeople: mentionedPeople)
        let withinDays = parseMeetingWithinDays(prompt)
        let meetingSlots = (intent == .meeting && participants.count >= 2)
            ? buildMeetingSlots(participants, withinDays: withinDays, instant: instant)
            : []

        var block = ""
        block += "LIVE CLOCK — authoritative real-world times, current as of this request. "
        block += "Use these directly and never say you lack real-time information:\n"
        for key in lineKeys {
            if let line = lineValues[key] { block += "• \(line)\n" }
        }
        if !conversions.isEmpty {
            block += "TIME CONVERSIONS (already computed — use these exact values, do not recompute):\n"
            for c in conversions { block += "• \(c)\n" }
        }
        if !meetingSlots.isEmpty {
            block += "MEETING SLOTS (already ranked — use these exact values, do not recompute):\n"
            for s in meetingSlots { block += "• \(s)\n" }
        }
        block += "QUERY INTENT: \(intent.promptHint)\n"

        return AiGrounding(
            block: block.trimmingCharacters(in: .whitespacesAndNewlines),
            intent: intent
        )
    }

    // MARK: - Place resolution

    /// A resolved place: IANA id, display name, and TimeZone.
    struct ResolvedPlace: Sendable {
        let zoneId: String
        let name: String
    }

    /// Resolves places named in `prompt`: UTC/GMT offset phrases first, then word
    /// n-grams (longest first), de-duplicated by zone id, bounded.
    private func resolvePromptPlaces(_ prompt: String) -> [ResolvedPlace] {
        var out: [ResolvedPlace] = []
        var seen = Set<String>()

        func append(_ zoneId: String, _ name: String) {
            guard !seen.contains(zoneId), TimeZone(identifier: zoneId) != nil else { return }
            seen.insert(zoneId)
            out.append(ResolvedPlace(zoneId: zoneId, name: name))
        }

        // UTC/GMT offset phrases first (e.g. "UTC+9", "GMT-5:30").
        for offsetText in offsetPhrases(in: prompt) {
            if let match = OffsetZones.parse(offsetText).first, let id = Self.normalizedZoneId(match.zoneId) {
                append(id, match.displayName)
            }
        }

        let tokens = tokenize(prompt)
        guard !tokens.isEmpty else { return Array(out.prefix(Self.maxPromptPlaces)) }

        var claimed = [Bool](repeating: false, count: tokens.count)

        // Try longest n-grams first, never re-using a claimed token.
        for size in stride(from: Self.maxNgram, through: 1, by: -1) {
            if size > tokens.count { continue }
            for start in 0...(tokens.count - size) {
                if out.count >= Self.maxPromptPlaces { break }
                let end = start + size
                if (start..<end).contains(where: { claimed[$0] }) { continue }
                let slice = Array(tokens[start..<end])

                if size == 1 {
                    let t = slice[0].lowercased()
                    if t.count < Self.minTokenLen || Self.stopwords.contains(t) { continue }
                } else {
                    if Self.stopwords.contains(slice.first!.lowercased()) { continue }
                    if Self.stopwords.contains(slice.last!.lowercased()) { continue }
                }

                let candidate = slice.joined(separator: " ")
                guard let resolved = resolveCandidate(candidate) else { continue }
                if seen.contains(resolved.zoneId) { continue }
                append(resolved.zoneId, resolved.name)
                for i in start..<end { claimed[i] = true }
            }
            if out.count >= Self.maxPromptPlaces { break }
        }

        return Array(out.prefix(Self.maxPromptPlaces))
    }

    /// Resolves a single candidate phrase, mirroring Android `resolveZoneFast`:
    /// abbreviations, UTC/GMT offsets, curated index, then a confident fuzzy match.
    private func resolveCandidate(_ candidate: String) -> ResolvedPlace? {
        // Abbreviation / phrase hint (e.g. "JST", "Pacific Time").
        if let match = TzAbbreviations.resolve(candidate), let id = Self.normalizedZoneId(match.zoneId) {
            return ResolvedPlace(zoneId: id, name: match.displayName)
        }
        // UTC/GMT offset token (e.g. "UTC+9").
        if let match = OffsetZones.parse(candidate).first, let id = Self.normalizedZoneId(match.zoneId) {
            return ResolvedPlace(zoneId: id, name: match.displayName)
        }
        // Curated city index — confident hit only when a city/country/alias is
        // exactly equal to or starts with the query (no substring/contains hits),
        // mirroring Android `PlaceIndex.resolveConfident`.
        guard let entry = PlaceIndex.shared.resolveConfident(query: candidate) else { return nil }
        return ResolvedPlace(zoneId: entry.tzId, name: entry.displayName)
    }

    // MARK: - Conversions

    /// When `prompt` names a clock time, converts that time (today, in each named place)
    /// to the home zone — or between the first two named places when the user asks A→B.
    private func buildConversions(
        _ prompt: String,
        promptPlaces: [ResolvedPlace],
        homeZoneId: String,
        instant: Date
    ) -> [String] {
        guard !promptPlaces.isEmpty else { return [] }
        guard let time = parseClockTime(prompt) else { return [] }

        let lower = prompt.lowercased()
        let ordered = promptPlaces.sorted { a, b in
            let ia = lower.range(of: a.name.lowercased()).map { lower.distance(from: lower.startIndex, to: $0.lowerBound) } ?? Int.max
            let ib = lower.range(of: b.name.lowercased()).map { lower.distance(from: lower.startIndex, to: $0.lowerBound) } ?? Int.max
            return ia < ib
        }

        if ordered.count >= 2 && !wantsHomeTime(prompt) {
            return [formatConversion(from: ordered[0], to: ordered[1], time: time, instant: instant)]
        }

        guard TimeZone(identifier: homeZoneId) != nil else { return [] }
        let homeName = shortZoneName(homeZoneId)
        let home = ResolvedPlace(zoneId: homeZoneId, name: homeName)
        return ordered
            .filter { $0.zoneId != homeZoneId }
            .map { formatConversion(from: $0, to: home, time: time, instant: instant) }
    }

    private func formatConversion(
        from: ResolvedPlace,
        to: ResolvedPlace,
        time: (hour: Int, minute: Int),
        instant: Date
    ) -> String {
        guard let fromTz = TimeZone(identifier: from.zoneId),
              let toTz = TimeZone(identifier: to.zoneId) else { return "" }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = fromTz
        var comps = cal.dateComponents([.year, .month, .day], from: instant)
        comps.hour = time.hour; comps.minute = time.minute; comps.second = 0
        guard let src = cal.date(from: comps) else { return "" }

        let srcStr = clockString(src, tz: fromTz)
        let dstStr = clockString(src, tz: toTz)

        let srcDay = dayNumber(src, tz: fromTz)
        let dstDay = dayNumber(src, tz: toTz)
        let shift = dstDay - srcDay
        let shiftLabel = shift > 0 ? " (the next day)" : (shift < 0 ? " (the previous day)" : "")

        return "\(srcStr) in \(from.name) = \(dstStr) in \(to.name)\(shiftLabel)"
    }

    // MARK: - Meeting slots

    private struct ParticipantLabel: Sendable {
        let displayName: String
        let participant: MeetingParticipant
    }

    private func meetingParticipants(
        promptPlaces: [ResolvedPlace],
        mentionedPeople: [Person]
    ) -> [ParticipantLabel] {
        var out: [String: ParticipantLabel] = [:]
        var order: [String] = []
        let settings = SettingsRepository.shared.settings

        for place in promptPlaces where out[place.zoneId] == nil {
            order.append(place.zoneId)
            out[place.zoneId] = ParticipantLabel(
                displayName: place.name,
                participant: MeetingParticipant(
                    name: place.name,
                    zoneId: place.zoneId,
                    workStartHour: settings.defaultWorkStartHour,
                    workEndHour: settings.defaultWorkEndHour
                )
            )
        }
        for person in mentionedPeople {
            let key = "\(person.tzId)\u{0000}\(person.displayLocation())"
            if out[key] != nil { continue }
            order.append(key)
            out[key] = ParticipantLabel(
                displayName: person.name.isEmpty ? person.displayLocation() : person.name,
                participant: MeetingParticipant(
                    name: person.name.isEmpty ? person.displayLocation() : person.name,
                    zoneId: person.tzId,
                    workStartHour: person.workStartHour,
                    workEndHour: person.workEndHour,
                    dndStartHour: person.dndStartHour,
                    dndEndHour: person.dndEndHour
                )
            )
        }
        return order.compactMap { out[$0] }
    }

    private func buildMeetingSlots(
        _ participants: [ParticipantLabel],
        withinDays: Int,
        instant: Date
    ) -> [String] {
        guard participants.count >= 2 else { return [] }
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let startOfDay = utcCal.startOfDay(for: instant)
        let baseDate = utcCal.date(byAdding: .day, value: min(max(withinDays, 0), 365), to: startOfDay) ?? startOfDay

        let slots = findOverlap.rankParticipantSlots(
            baseDate: baseDate,
            participants: participants.map(\.participant)
        ).prefix(3)

        return slots.map { slot in
            let locals = participants.compactMap { label -> String? in
                guard let tz = TimeZone(identifier: label.participant.zoneId) else { return nil }
                let hour = hourOf(slot.start, tz: tz)
                let tag = (slot.localViews[label.participant.zoneId] == .working) ? " (working)" : ""
                return "\(label.displayName) \(String(format: "%02d:00", hour))\(tag)"
            }.joined(separator: ", ")
            return "\(slot.label.displayName): \(locals)"
        }
    }

    // MARK: - Mentions

    private func savedZonesMentioned(_ prompt: String, _ savedZones: [SavedZone]) -> [SavedZone] {
        guard !savedZones.isEmpty else { return [] }
        let lower = prompt.lowercased()
        return savedZones
            .filter { zone in
                let name = zone.displayName.trimmingCharacters(in: .whitespaces).lowercased()
                return name.count >= Self.minTokenLen && lower.contains(name)
            }
            .sorted { $0.displayName.count > $1.displayName.count }
    }

    private func peopleMentioned(_ prompt: String, _ people: [Person]) -> [Person] {
        guard !people.isEmpty else { return [] }
        let lower = prompt.lowercased()
        var seenZones = Set<String>()
        return people
            .filter { person in
                let name = person.name.trimmingCharacters(in: .whitespaces).lowercased()
                return name.count >= Self.minPersonNameLen && lower.contains(name)
            }
            .sorted { $0.name.count > $1.name.count }
            .filter { seenZones.insert($0.tzId).inserted }
            .prefix(Self.maxMentionedPeople)
            .map { $0 }
    }

    // MARK: - Intent detection

    private func detectIntent(_ prompt: String) -> AiQueryIntent {
        let p = prompt.lowercased()
        if Self.scheduleHints.contains(where: { p.contains($0) }) { return .schedule }
        if Self.meetingHints.contains(where: { p.contains($0) }) { return .meeting }
        if Self.convertHints.contains(where: { p.contains($0) })
            || (parseClockTime(prompt) != nil && p.contains(" to ")) { return .convert }
        if Self.currentTimeHints.contains(where: { p.contains($0) }) { return .currentTime }
        return .general
    }

    private func parseMeetingWithinDays(_ prompt: String) -> Int {
        let p = prompt.lowercased()
        if p.contains("day after tomorrow") { return 2 }
        if p.contains("tomorrow") { return 1 }
        return 0
    }

    private func wantsHomeTime(_ prompt: String) -> Bool {
        let p = prompt.lowercased()
        return Self.homeTimeHints.contains { p.contains($0) }
    }

    // MARK: - Schedule tags (people)

    private func scheduleTag(hour: Int, person: Person) -> String {
        if inDndWindow(hour, person.dndStartHour, person.dndEndHour) { return " (do not disturb)" }
        if inWindow(hour, person.workStartHour, person.workEndHour) { return " (working)" }
        let outside = hoursOutsideWindow(hour, person.workStartHour, person.workEndHour)
        if outside <= 2 { return " (awake, off-hours)" }
        if outside <= 4 { return " (off-hours)" }
        return " (likely asleep)"
    }

    private func inDndWindow(_ hour: Int, _ start: Int, _ end: Int) -> Bool {
        (0...23).contains(start) && (0...23).contains(end) && inWindow(hour, start, end)
    }

    private func inWindow(_ hour: Int, _ start: Int, _ end: Int) -> Bool {
        if start < 0 || end < 0 || start == end { return false }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    private func hoursOutsideWindow(_ hour: Int, _ start: Int, _ end: Int) -> Int {
        if inWindow(hour, start, end) { return 0 }
        let lastWorkingHour = (end + 23) % 24
        return min(circularDistance(hour, start), circularDistance(hour, lastWorkingHour))
    }

    private func circularDistance(_ a: Int, _ b: Int) -> Int {
        let diff = ((a - b) % 24 + 24) % 24
        return min(diff, 24 - diff)
    }

    // MARK: - Clock time parsing (lenient)

    /// Lenient time-of-day so "9:00" / "9am" / "2:30 pm" works.
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

    // MARK: - UTC offset parsing

    /// Finds "UTC+9" / "GMT-5:30" style phrases in `prompt`.
    private func offsetPhrases(in prompt: String) -> [String] {
        var out: [String] = []
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)\\b(?:utc|gmt)\\s*[+-]\\s*\\d{1,2}(?::?\\d{2})?\\b",
            options: []
        ) else { return out }
        let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
        regex.enumerateMatches(in: prompt, options: [], range: range) { match, _, _ in
            if let match, let r = Range(match.range, in: prompt) {
                out.append(String(prompt[r]).replacingOccurrences(of: " ", with: ""))
            }
        }
        return out
    }

    // MARK: - Formatting helpers

    private func groundingTimeString(_ date: Date, tz: TimeZone) -> String {
        // "EEE HH:mm, d MMM yyyy" — e.g. "Fri 14:30, 22 Jun 2026".
        format(date, tz: tz, pattern: "EEE HH:mm, d MMM yyyy")
    }

    private func clockString(_ date: Date, tz: TimeZone) -> String {
        format(date, tz: tz, pattern: "HH:mm")
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
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return (comps.year ?? 0) * 372 + (comps.month ?? 0) * 31 + (comps.day ?? 0)
    }

    private func shortZoneName(_ zoneId: String) -> String {
        (zoneId.split(separator: "/").last.map(String.init) ?? zoneId).replacingOccurrences(of: "_", with: " ")
    }

    /// Mirrors Android `savedZones.localLocationLabel(homeZoneId)`.
    private func localLocationLabel(_ savedZones: [SavedZone], _ homeZoneId: String) -> String {
        if let match = savedZones.first(where: { $0.id == homeZoneId }) { return match.displayName }
        return shortZoneName(homeZoneId)
    }

    private func tokenize(_ prompt: String) -> [String] {
        // Android splits on `[^\p{L}\p{Nd}+]+` — keep letters, digits, and '+'.
        let keep = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "+"))
        let separators = keep.inverted
        return prompt
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .prefix(Self.maxPromptTokens)
            .map { $0 }
    }

    // MARK: - Zone id normalization

    /// Returns an iOS-acceptable IANA/offset identifier for `rawId`, or nil if it can't be
    /// resolved to a `TimeZone`. Handles `OffsetZones`' JVM-style ids ("+05:30", "UTC")
    /// which Foundation does not accept verbatim, by converting them to "GMT±HHMM".
    static func normalizedZoneId(_ rawId: String) -> String? {
        if TimeZone(identifier: rawId) != nil { return rawId }
        if rawId == "UTC" || rawId == "Z" { return "UTC" }
        // "+05:30" / "-08:00" → GMT-anchored id Foundation understands.
        if let regex = try? NSRegularExpression(pattern: "^([+-])(\\d{2}):?(\\d{2})$"),
           let m = regex.firstMatch(in: rawId, range: NSRange(rawId.startIndex..., in: rawId)),
           let signR = Range(m.range(at: 1), in: rawId),
           let hR = Range(m.range(at: 2), in: rawId),
           let mnR = Range(m.range(at: 3), in: rawId) {
            let candidate = "GMT\(rawId[signR])\(rawId[hR])\(rawId[mnR])"
            if TimeZone(identifier: candidate) != nil { return candidate }
            // Last resort: build a fixed-offset TimeZone and use its canonical identifier.
            let sign = rawId[signR] == "-" ? -1 : 1
            let seconds = sign * ((Int(rawId[hR]) ?? 0) * 3600 + (Int(rawId[mnR]) ?? 0) * 60)
            return TimeZone(secondsFromGMT: seconds)?.identifier
        }
        return nil
    }

    // MARK: - Regex utility

    private func matchGroups(_ pattern: String, in text: String) -> [String]? {
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

    // MARK: - Constants

    private static let maxNgram = 3
    private static let minTokenLen = 3
    private static let maxPromptPlaces = 4
    private static let maxSavedZones = 6
    private static let maxPromptTokens = 40
    private static let maxMentionedPeople = 4
    private static let minPersonNameLen = 2

    private static let scheduleHints = ["schedule", "add event", "add meeting", "set up", "book", "create event"]
    private static let meetingHints = [
        "meeting", "meet with", "best time", "good time", "fair time", "overlap",
        "call with", "schedule a call", "find a time", "when can we", "time to meet",
    ]
    private static let convertHints = ["convert", "what is", "what's", "equals", "equivalent"]
    private static let currentTimeHints = [
        "what time", "current time", "time is it", "time in", "time now", "right now",
    ]
    private static let homeTimeHints = ["my time", "my local", "local time", "my timezone", "here at home"]

    private static let stopwords: Set<String> = [
        "the", "what", "whats", "what's", "is", "are", "was", "time", "times", "now", "right",
        "current", "currently", "today", "tonight", "tomorrow", "yesterday", "for", "and", "with",
        "between", "vs", "versus", "from", "into", "convert", "schedule", "plan", "add", "set",
        "meeting", "meet", "call", "best", "when", "whens", "when's", "tell", "give", "show", "get",
        "please", "local", "zone", "clock", "date", "day", "you", "your", "can", "could", "would",
        "about", "here", "there", "this", "that", "over", "city", "country",
        "in", "it", "at", "on", "to", "of", "as", "by", "an", "do", "does", "me", "my", "we", "us",
        "or", "if", "so", "am", "pm",
    ]
}
