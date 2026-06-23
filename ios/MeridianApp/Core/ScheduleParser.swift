// ScheduleParser.swift
// Meridian — iOS 27 / Swift 6
//
// Turns the assistant's reply into a concrete scheduling action. Ported from
// Android's `core/ai/ScheduleParser.kt`. Kept free of any model dependency so it
// can be tested directly: the assistant only calls these after it has the text.
//
// The model never computes a timestamp — it emits a plain-words `when` and a
// place, and this resolves the exact instant in-app via `ScheduleTimeParser`,
// with fallbacks so a fumbled `when` still works: the model's `when` → the
// user's original prompt → any legacy numeric `timestamp`.
//
// Hardened against fumbling models: a field that arrives as the wrong JSON type
// (object/array instead of a primitive) is treated as absent rather than
// throwing, and extraction tolerates nested objects and `}` inside string values.

import Foundation

enum ScheduleParser {

    // MARK: - Schedule JSON extraction

    /// The schedule-action JSON object embedded in `text`, or nil.
    ///
    /// Scans brace-balanced objects (respecting string literals), so it works for
    /// a clean lone object, one inside ```fences```, one wrapped in prose, several
    /// side by side, and objects containing nested objects or a literal `}` inside
    /// a string. Returns the first whose action is "schedule".
    static func extractScheduleJson(_ text: String) -> String? {
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "{" {
                if let obj = balancedObject(chars, from: i) {
                    if containsScheduleAction(obj) { return obj }
                    i += obj.count
                    continue
                }
            }
            i += 1
        }
        return nil
    }

    /// The `title` field in a schedule block (for a clarifying reply), or nil.
    static func titleOf(_ jsonStr: String) -> String? {
        guard let obj = parse(jsonStr) else { return nil }
        guard let title = stringValue(obj, "title"), !title.isEmpty else { return nil }
        return title
    }

    // MARK: - PlannedTask construction

    /// Builds a `PlannedTask` from a schedule block, computing the instant in-app.
    ///
    /// - Parameters:
    ///   - jsonStr: A schedule-action JSON object (as returned by `extractScheduleJson`).
    ///   - originalPrompt: The user's original message, used as a `when` fallback.
    ///   - now: The reference instant.
    ///   - homeZoneId: The IANA zone used when no zone is given or resolvable.
    ///   - resolveZoneId: Maps a place name to an IANA id (the model may send either).
    /// - Returns: nil if it isn't a schedule action or no date/time can be resolved.
    ///
    /// `@MainActor`-isolated: it builds and returns a non-`Sendable` `PlannedTask`
    /// to its `@MainActor` caller (`AiAssistant.interpret`), so the whole call stays
    /// on the main actor with no isolation crossing. The `resolveZoneId` closure is
    /// likewise `@MainActor` so it can invoke the `@MainActor` `MeridianAiTools.resolveZoneId`.
    @MainActor
    static func buildScheduledTask(
        jsonStr: String,
        originalPrompt: String,
        now: Date,
        homeZoneId: String,
        resolveZoneId: @MainActor (String) async -> String?
    ) async -> PlannedTask? {
        guard let obj = parse(jsonStr) else { return nil }
        guard stringValue(obj, "action") == "schedule" else { return nil }

        let title = stringValue(obj, "title").flatMap { $0.isEmpty ? nil : $0 } ?? "New event"
        let rawZone = (stringValue(obj, "zoneId") ?? stringValue(obj, "zone")) ?? ""
        let resolvedZoneId = await resolveScheduleZone(rawZone, homeZoneId: homeZoneId, resolveZoneId: resolveZoneId)
        let zone = TimeZone(identifier: resolvedZoneId) ?? .current

        let whenPhrase = stringValue(obj, "when") ?? ""
        let legacyTimestamp = longValue(obj, "timestamp").flatMap { $0 > 0 ? $0 : nil }

        let instant: Date? =
            ScheduleTimeParser.parse(whenPhrase, zone: zone, now: now)
            ?? ScheduleTimeParser.parse(originalPrompt, zone: zone, now: now)
            ?? legacyTimestamp.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }

        guard let instant else { return nil }

        return PlannedTask(
            title: title,
            timestamp: instant,
            tzId: zone.identifier,
            origin: "ai"
        )
    }

    /// An IANA id is used as-is; a place name is resolved via `resolveZoneId`; else the home zone.
    @MainActor
    private static func resolveScheduleZone(
        _ raw: String,
        homeZoneId: String,
        resolveZoneId: @MainActor (String) async -> String?
    ) async -> String {
        if raw.trimmingCharacters(in: .whitespaces).isEmpty { return homeZoneId }
        if let tz = TimeZone(identifier: raw) { return tz.identifier }
        return await resolveZoneId(raw) ?? homeZoneId
    }

    // MARK: - JSON helpers

    /// Parses a JSON object string into `[String: Any]`, or nil. Lenient by tolerating failure.
    private static func parse(_ jsonStr: String) -> [String: Any]? {
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return object as? [String: Any]
    }

    /// Field value as a string, or nil if absent or a non-primitive (object/array).
    /// A bool or number is coerced to its string form (mirrors lenient Kotlin behavior).
    private static func stringValue(_ obj: [String: Any], _ key: String) -> String? {
        guard let value = obj[key] else { return nil }
        if value is [Any] || value is [String: Any] { return nil }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    /// Field value as an integer (epoch milliseconds), or nil if absent or non-numeric.
    private static func longValue(_ obj: [String: Any], _ key: String) -> Int64? {
        guard let value = obj[key] else { return nil }
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }

    private static func containsScheduleAction(_ obj: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "\"action\"\\s*:\\s*\"schedule\"",
            options: []
        ) else { return false }
        let range = NSRange(obj.startIndex..<obj.endIndex, in: obj)
        return regex.firstMatch(in: obj, options: [], range: range) != nil
    }

    /// The complete `{...}` starting at `start`, honoring string literals/escapes; nil if unbalanced.
    private static func balancedObject(_ chars: [Character], from start: Int) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < chars.count {
            let c = chars[i]
            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
            } else {
                switch c {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return String(chars[start...i]) }
                default: break
                }
            }
            i += 1
        }
        return nil
    }
}
