// AiAssistant.swift
// Meridian — iOS 27 / Swift 6
//
// Dual-engine orchestrator for the Meridian assistant. Ported from Android's
// `core/ai/GeminiRepository.kt` (hybrid Gemini Nano + cloud), adapted to Apple's
// on-device Foundation Models with an optional Gemini cloud fallback and a
// deterministic rules fallback.
//
// Engine selection (driven by `MeridianSettings.aiEngine`):
//  - `.onDevice` (default): Apple Foundation Models via `LanguageModelSession`,
//    gated by `SystemLanguageModel.availability`. Tools (`get_current_time`,
//    `convert_time`, `find_meeting_time`) are attached so the model can act on
//    time. Live facts are also pre-resolved into the prompt by `AiGroundingBuilder`
//    (mirrors the Android "facts ride in the prompt, not the system instruction"
//    fix). Falls back to the rules engine when the model is unavailable.
//  - `.cloud`: Gemini (network + API key). Only this branch ever touches the
//    network. Falls back to the rules engine if no key is configured or the
//    request fails.
//
// The LLM never computes a timestamp: a scheduling request is resolved locally
// by `ScheduleParser` + `ScheduleTimeParser` into a concrete `PlannedTask`.

import Foundation
import FoundationModels

// MARK: - AiAssistant

@MainActor
final class AiAssistant {

    // MARK: Dependencies

    private let settings: SettingsRepository
    private let tools: MeridianAiTools
    private let grounding: AiGroundingBuilder
    private let findOverlap: FindOverlapUseCase
    private let now: @Sendable () -> Date

    /// Optional cloud client. Nil unless a Gemini API key is configured.
    private let cloud: GeminiCloudClient?

    // MARK: On-device session (lazy, reused for prefix caching)

    private var session: LanguageModelSession?

    // MARK: Init

    init(
        settings: SettingsRepository = .shared,
        findOverlap: FindOverlapUseCase = FindOverlapUseCase(),
        cloud: GeminiCloudClient? = GeminiCloudClient.makeFromEnvironment(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.now = now
        self.findOverlap = findOverlap
        self.tools = MeridianAiTools(findOverlap: findOverlap, now: now)
        self.grounding = AiGroundingBuilder(findOverlap: findOverlap, now: now)
        self.cloud = cloud
    }

    // MARK: - Availability

    /// Whether the on-device Foundation Models model is ready to serve requests.
    var isOnDeviceAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        case .unavailable: return false
        @unknown default: return false
        }
    }

    /// Precomputes the key-value cache for the static instructions so the first
    /// real request is faster. Safe to call repeatedly; a no-op off-device.
    func prewarm() {
        guard settings.settings.aiEngine == .onDevice, isOnDeviceAvailable else { return }
        ensureSession()?.prewarm()
    }

    // MARK: - Public entry point

    /// Processes a single user prompt and returns an `AiResult`.
    func process(
        prompt: String,
        homeZoneId: String = TimeZone.current.identifier,
        savedZones: [SavedZone] = [],
        people: [Person] = []
    ) async -> AiResult {
        let zone = TimeZone(identifier: homeZoneId) ?? .current
        let instant = now()

        let ground = grounding.build(
            prompt: prompt,
            homeZoneId: zone.identifier,
            savedZones: savedZones,
            people: people
        )
        let contextualPrompt = buildContextualPrompt(grounding: ground, zone: zone, instant: instant, prompt: prompt)

        // Engine selection.
        let engine = settings.settings.aiEngine
        let candidate: (text: String, onDevice: Bool)?
        switch engine {
        case .onDevice:
            candidate = await runOnDevice(contextualPrompt)
        case .cloud:
            candidate = await runCloud(contextualPrompt)
        }

        // Engine produced text → interpret it (schedule JSON or plain answer).
        if let candidate {
            return await interpret(
                text: candidate.text,
                onDevice: candidate.onDevice,
                originalPrompt: prompt,
                homeZoneId: zone.identifier,
                instant: instant
            )
        }

        // Fall back to the deterministic rules engine (never fails, no network).
        let ruleText = RulesEngine.answer(
            prompt: prompt,
            grounding: ground,
            zone: zone,
            instant: instant
        )
        return await interpret(
            text: ruleText,
            onDevice: false,
            originalPrompt: prompt,
            homeZoneId: zone.identifier,
            instant: instant
        )
    }

    // MARK: - Result interpretation

    /// A schedule request comes back as JSON; the app resolves its date/time itself
    /// (§12.7). Otherwise it's a plain answer.
    private func interpret(
        text: String,
        onDevice: Bool,
        originalPrompt: String,
        homeZoneId: String,
        instant: Date
    ) async -> AiResult {
        if let scheduleJson = ScheduleParser.extractScheduleJson(text) {
            if let task = await ScheduleParser.buildScheduledTask(
                jsonStr: scheduleJson,
                originalPrompt: originalPrompt,
                now: instant,
                homeZoneId: homeZoneId,
                resolveZoneId: { [tools] query in tools.resolveZoneId(query) }
            ) {
                return .scheduled(task: task, onDevice: onDevice)
            }
            // It was a scheduling request but no date/time could be resolved.
            let title = ScheduleParser.titleOf(scheduleJson)
            let suffix = title.map { " for \"\($0)\"" } ?? ""
            return .success(text: "Sure — what date and time should I set\(suffix)?", onDevice: onDevice)
        }
        return .success(text: text, onDevice: onDevice)
    }

    // MARK: - On-device path

    private func runOnDevice(_ prompt: String) async -> (text: String, onDevice: Bool)? {
        guard isOnDeviceAvailable, let session = ensureSession() else { return nil }
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (text, true)
        } catch {
            // Any model error (context window, guardrails, etc.) → fall through.
            // Discard the session so a poisoned transcript doesn't break later turns;
            // a fresh one is built on the next request.
            self.session = nil
            return nil
        }
    }

    /// Lazily builds the reused session. Reuse is what enables `prewarm` caching.
    @discardableResult
    private func ensureSession() -> LanguageModelSession? {
        if let session { return session }
        guard isOnDeviceAvailable else { return nil }
        let created = LanguageModelSession(
            tools: [
                GetCurrentTimeTool(findOverlap: findOverlap, now: now),
                ConvertTimeTool(findOverlap: findOverlap, now: now),
                FindMeetingTimeTool(findOverlap: findOverlap, now: now),
            ],
            instructions: { Self.systemInstruction }
        )
        session = created
        return created
    }

    // MARK: - Cloud path

    private func runCloud(_ prompt: String) async -> (text: String, onDevice: Bool)? {
        guard let cloud else { return nil }
        do {
            let text = try await cloud.generate(systemInstruction: Self.systemInstruction, prompt: prompt)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (trimmed, false)
        } catch {
            return nil
        }
    }

    // MARK: - Prompt assembly

    /// Front-loads the live-clock facts and the current date/time into the message
    /// itself, then the user's question — mirrors Android `buildContextualPrompt`.
    private func buildContextualPrompt(
        grounding: AiGrounding,
        zone: TimeZone,
        instant: Date,
        prompt: String
    ) -> String {
        var out = ""
        if !grounding.block.isEmpty {
            out += grounding.block
            out += "\n\n"
        }
        let dateStr = Self.rfcFormatter(zone: zone).string(from: instant)
        let epochMs = Int64(instant.timeIntervalSince1970 * 1000)
        out += "Current local date/time: \(dateStr) (\(zone.identifier)). Unix epoch now: \(epochMs) ms.\n\n"

        switch grounding.intent {
        case .schedule:
            out += Self.scheduleRule + "\n"
        case .meeting:
            out += "Answer from MEETING SLOTS when present. Otherwise use LIVE CLOCK and tools. Reply in plain, friendly text — never say you lack real-time information.\n"
        case .convert:
            out += "Answer from TIME CONVERSIONS when present. Otherwise use LIVE CLOCK and tools. Reply in plain, friendly text — never say you lack real-time information.\n"
        case .currentTime:
            out += "Answer directly from LIVE CLOCK. Reply in one or two short sentences — never say you lack real-time information.\n"
        case .general:
            out += Self.generalRule + "\n"
        }
        out += "\n"
        out += prompt
        return out
    }

    // MARK: - Static instruction text (ported from Android buildSystemInstruction)

    static let systemInstruction: String = """
        You are Meridian, an elegant world-clock and calendar assistant.
        You help with world times, time-zone conversions, fair meeting windows, and scheduling.

        Each message may begin with a LIVE CLOCK block of authoritative, up-to-the-second \
        real-world times. Treat those as ground truth and answer from them — never reply \
        that you don't have access to real-time information.

        TOOLS — call these for any live fact not already given in the message:
        • get_current_time(location) — the real current time at any place.
        • convert_time(time, from_location, to_location) — convert a time between places.
        • find_meeting_time(locations, within_days) — the fairest shared meeting hours.

        To SCHEDULE or ADD an event, reply with ONLY a JSON object — no prose, no code fences:
        {"action":"schedule","title":"...","when":"<date & time in plain words>","zoneId":"<place>"}
        Give the date/time in WORDS (e.g. "tomorrow 1pm"); do NOT compute a timestamp — the app resolves it exactly.
        Example: {"action":"schedule","title":"Lunch with Emma","when":"tomorrow 1pm","zoneId":"Europe/London"}

        Otherwise, answer in plain, friendly, accurate text without markdown code fences.
        """

    private static let scheduleRule =
        "If the request is to schedule or add an event/meeting, reply with ONLY this JSON and " +
        "nothing else: {\"action\":\"schedule\",\"title\":\"…\",\"when\":\"<date and time in " +
        "plain words exactly as the user said, e.g. 'next Monday 2pm' or '2026-06-22 14:00'>\"," +
        "\"zoneId\":\"<the place, e.g. 'Europe/London' or 'Tokyo'>\"}. Do NOT compute a numeric timestamp."

    private static let generalRule =
        "Answer in plain, friendly text using the times above. To schedule, reply with ONLY the " +
        "schedule JSON (no prose). Never say you lack real-time information."

    private static func rfcFormatter(zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        // RFC 1123-style, e.g. "Mon, 22 Jun 2026 14:30:00".
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
        return f
    }
}

// MARK: - GeminiCloudClient

/// Minimal Gemini cloud client. Only constructed (and only touches the network)
/// when an API key is configured via `MERIDIAN_GEMINI_API_KEY`. Mirrors the cloud
/// fallback model used on Android (`gemini-2.5-flash-lite`).
struct GeminiCloudClient: Sendable {

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gemini-2.5-flash-lite") {
        self.apiKey = apiKey
        self.model = model
    }

    /// Reads the API key from the environment / Info.plist. Returns nil when absent
    /// so the assistant silently falls back to the rules engine.
    static func makeFromEnvironment() -> GeminiCloudClient? {
        if let key = ProcessInfo.processInfo.environment["MERIDIAN_GEMINI_API_KEY"], !key.isEmpty {
            return GeminiCloudClient(apiKey: key)
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "MeridianGeminiApiKey") as? String, !key.isEmpty {
            return GeminiCloudClient(apiKey: key)
        }
        return nil
    }

    /// Single-shot generation via the Gemini `generateContent` REST endpoint.
    func generate(systemInstruction: String, prompt: String) async throws -> String {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard var components = URLComponents(string: endpoint) else { throw CloudError.badURL }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw CloudError.badURL }

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CloudError.httpError
        }
        return Self.extractText(from: data)
    }

    /// Extracts `candidates[0].content.parts[*].text` from a Gemini response payload.
    private static func extractText(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return ""
        }
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    enum CloudError: Error, Sendable {
        case badURL
        case httpError
    }
}

// MARK: - RulesEngine

/// Deterministic, network-free fallback. When no LLM is available it answers
/// directly from the already-computed grounding block, which contains the LIVE
/// CLOCK / TIME CONVERSIONS / MEETING SLOTS facts the model would otherwise use.
enum RulesEngine {

    static func answer(prompt: String, grounding: AiGrounding, zone: TimeZone, instant: Date) -> String {
        // Schedule intent → emit the schedule JSON so the orchestrator resolves it.
        if grounding.intent == .schedule {
            let title = inferTitle(from: prompt)
            // `when` echoes the user's own words; `ScheduleTimeParser` resolves it.
            let when = prompt
            return "{\"action\":\"schedule\",\"title\":\"\(escape(title))\",\"when\":\"\(escape(when))\",\"zoneId\":\"\(zone.identifier)\"}"
        }

        // For every other intent, the grounding block already holds the facts.
        if !grounding.block.isEmpty {
            switch grounding.intent {
            case .currentTime:
                return liveClockSummary(grounding.block)
            case .convert:
                return section(grounding.block, header: "TIME CONVERSIONS") ?? liveClockSummary(grounding.block)
            case .meeting:
                return section(grounding.block, header: "MEETING SLOTS") ?? liveClockSummary(grounding.block)
            default:
                return liveClockSummary(grounding.block)
            }
        }

        return """
            I can help with world times, time-zone conversions, meeting windows, and scheduling. \
            Try "What time is it in Tokyo?", "Convert 3 PM New York to London", or \
            "Best meeting time for NYC, London, and Singapore".
            """
    }

    /// Returns the bullet lines under the LIVE CLOCK header as a short answer.
    private static func liveClockSummary(_ block: String) -> String {
        let bullets = block
            .split(separator: "\n")
            .filter { $0.hasPrefix("• ") }
            .map { String($0.dropFirst(2)) }
        guard !bullets.isEmpty else { return block }
        return bullets.joined(separator: "\n")
    }

    /// Returns the bullet lines that follow a given header in the grounding block.
    private static func section(_ block: String, header: String) -> String? {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let headerIdx = lines.firstIndex(where: { $0.hasPrefix(header) }) else { return nil }
        var out: [String] = []
        for line in lines[(headerIdx + 1)...] {
            if line.hasPrefix("• ") {
                out.append(String(line.dropFirst(2)))
            } else if !out.isEmpty {
                break
            }
        }
        return out.isEmpty ? nil : out.joined(separator: "\n")
    }

    private static func inferTitle(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New event" : trimmed
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
