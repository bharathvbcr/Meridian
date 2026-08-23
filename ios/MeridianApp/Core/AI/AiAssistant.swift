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
//    gated by `SystemLanguageModel.availability`. Falls back to cloud (if API key
//    present) when on-device is unavailable or inference fails — provenance stays
//    honest (CLOUD badge). Then rules engine as last resort.
//  - `.cloud`: Gemini (network + API key). Falls back to rules if no key or failure.
//
// The LLM never computes a timestamp: a scheduling request is resolved locally
// by `ScheduleParser` + `ScheduleTimeParser` into a concrete `PlannedTask`.

import Foundation
import FoundationModels

// MARK: - AiInferenceActor

/// Runs Foundation Models inference off the main actor; MainActor only updates UI state.
actor AiInferenceActor {
    private var session: LanguageModelSession?
    private let findOverlap: FindOverlapUseCase
    private let now: @Sendable () -> Date

    init(findOverlap: FindOverlapUseCase, now: @escaping @Sendable () -> Date) {
        self.findOverlap = findOverlap
        self.now = now
    }

    func prewarm(available: Bool) {
        guard available else { return }
        ensureSession()?.prewarm()
    }

    func respond(to prompt: String, available: Bool) async -> String? {
        guard available, let session = ensureSession() else { return nil }
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            self.session = nil
            return nil
        }
    }

    func invalidateSession() {
        session = nil
    }

    private func ensureSession() -> LanguageModelSession? {
        if let session { return session }
        let created = LanguageModelSession(
            tools: [
                GetCurrentTimeTool(findOverlap: findOverlap, now: now),
                ConvertTimeTool(findOverlap: findOverlap, now: now),
                FindMeetingTimeTool(findOverlap: findOverlap, now: now),
            ],
            instructions: { AiAssistant.systemInstruction }
        )
        session = created
        return created
    }
}

// MARK: - AiAssistant

@MainActor
final class AiAssistant {

    // MARK: Dependencies

    private let settings: SettingsRepository
    private let tools: MeridianAiTools
    private let grounding: AiGroundingBuilder
    private let findOverlap: FindOverlapUseCase
    private let now: @Sendable () -> Date
    private let resourcePolicy: AiResourcePolicy

    /// Optional cloud client. Nil unless a Gemini API key is configured.
    private let cloud: GeminiCloudClient?

    /// On-device semantic cache — near-duplicate prompts replay instantly.
    private let semanticCache = SemanticCache()

    /// Off-main-actor inference for Foundation Models.
    private let inferenceActor: AiInferenceActor

    // MARK: Init

    init(
        settings: SettingsRepository = .shared,
        findOverlap: FindOverlapUseCase = FindOverlapUseCase(),
        cloud: GeminiCloudClient? = GeminiCloudClient.makeFromEnvironment(),
        resourcePolicy: AiResourcePolicy = AiResourcePolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.now = now
        self.findOverlap = findOverlap
        self.resourcePolicy = resourcePolicy
        self.tools = MeridianAiTools(findOverlap: findOverlap, now: now)
        self.grounding = AiGroundingBuilder(findOverlap: findOverlap, now: now)
        self.cloud = cloud
        self.inferenceActor = AiInferenceActor(findOverlap: findOverlap, now: now)
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
        guard settings.settings.aiEngine == .onDevice,
              isOnDeviceAvailable,
              !resourcePolicy.skipPrewarm() else { return }
        Task { await inferenceActor.prewarm(available: isOnDeviceAvailable) }
    }

    /// Releases the on-device session — call on background / memory pressure.
    func releaseOnDeviceSession() {
        Task { await inferenceActor.invalidateSession() }
    }

    // MARK: - Public entry point

    /// Processes a single user prompt and returns an `AiResult`.
    func process(
        prompt: String,
        homeZoneId: String = TimeZone.current.identifier,
        savedZones: [SavedZone] = [],
        people: [Person] = [],
        recentTurns: [ChatTurn] = [],
        onPartial: @Sendable (String) async -> Void = { _ in }
    ) async -> AiResult {
        let startedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let zone = TimeZone(identifier: homeZoneId) ?? .current
        let instant = now()
        let epochMs = Int64(instant.timeIntervalSince1970 * 1000)
        let groundingKey = SemanticCachePolicy.groundingKey(epochMs: epochMs, homeZoneId: zone.identifier)

        let ground = grounding.build(
            prompt: prompt,
            homeZoneId: zone.identifier,
            savedZones: savedZones,
            people: people
        )

        // Semantic cache — instant replay for near-duplicate prompts.
        if !SemanticCachePolicy.shouldBypass(intent: ground.intent, prompt: prompt),
           let hit = semanticCache.lookup(prompt, groundingKey: groundingKey) {
            await onPartial(hit.response)
            let result = await interpret(
                text: hit.response,
                source: hit.source,
                originalPrompt: prompt,
                homeZoneId: zone.identifier,
                instant: instant,
                groundingKey: groundingKey
            )
            logResult(path: "cache", result: result, startedAt: startedAt)
            return result
        }

        let compressedBlock = SemanticCompressor.compress(ground.block)
        let routedGround = AiGrounding(block: compressedBlock, intent: ground.intent)

        // Semantic router — skip the LLM when grounding already holds the answer.
        let routeToRules = SemanticRouter.route(intent: ground.intent, prompt: prompt, groundingBlock: compressedBlock) == .rules
            || resourcePolicy.preferRulesOnly()
        if routeToRules {
            let ruleText = RulesEngine.answer(
                prompt: prompt,
                grounding: routedGround,
                zone: zone,
                instant: instant
            )
            await SemanticPartialEmitter.emitProgressive(ruleText, onPartial: onPartial)
            let result = await interpret(
                text: ruleText,
                source: .rules,
                originalPrompt: prompt,
                homeZoneId: zone.identifier,
                instant: instant,
                storeInCache: !SemanticCachePolicy.shouldBypass(intent: ground.intent, prompt: prompt),
                groundingKey: groundingKey
            )
            logResult(path: "rules", result: result, startedAt: startedAt)
            return result
        }

        if resourcePolicy.skipLlm() {
            let ruleText = RulesEngine.answer(
                prompt: prompt,
                grounding: routedGround,
                zone: zone,
                instant: instant
            )
            await SemanticPartialEmitter.emitProgressive(ruleText, onPartial: onPartial)
            let result = await interpret(
                text: ruleText,
                source: .rules,
                originalPrompt: prompt,
                homeZoneId: zone.identifier,
                instant: instant,
                storeInCache: false,
                groundingKey: groundingKey
            )
            logResult(path: "rules-degraded", result: result, startedAt: startedAt)
            return result
        }

        let contextualPrompt = buildContextualPrompt(
            grounding: routedGround, zone: zone, instant: instant, prompt: prompt, recentTurns: recentTurns
        )

        // Engine selection with silent cloud fallback on the on-device path.
        let engine = settings.settings.aiEngine
        let candidate: (text: String, source: InferenceSource)?
        switch engine {
        case .onDevice:
            if let onDevice = await runOnDevice(contextualPrompt) {
                candidate = onDevice
            } else if let cloudResult = await runCloud(contextualPrompt) {
                candidate = cloudResult
            } else {
                candidate = nil
            }
        case .cloud:
            candidate = await runCloud(contextualPrompt)
        }

        // Engine produced text → interpret it (schedule JSON or plain answer).
        if let candidate {
            await onPartial(SemanticPartialEmitter.displayableCandidate(candidate.text))
            let result = await interpret(
                text: candidate.text,
                source: candidate.source,
                originalPrompt: prompt,
                homeZoneId: zone.identifier,
                instant: instant,
                storeInCache: !SemanticCachePolicy.shouldBypass(intent: ground.intent, prompt: prompt),
                groundingKey: groundingKey
            )
            logResult(path: "llm", result: result, startedAt: startedAt)
            return result
        }

        // Fall back to the deterministic rules engine (never fails, no network).
        let ruleText = RulesEngine.answer(
            prompt: prompt,
            grounding: routedGround,
            zone: zone,
            instant: instant
        )
        await SemanticPartialEmitter.emitProgressive(ruleText, onPartial: onPartial)
        let result = await interpret(
            text: ruleText,
            source: .rules,
            originalPrompt: prompt,
            homeZoneId: zone.identifier,
            instant: instant,
            storeInCache: !SemanticCachePolicy.shouldBypass(intent: ground.intent, prompt: prompt),
            groundingKey: groundingKey
        )
        logResult(path: "rules-fallback", result: result, startedAt: startedAt)
        return result
    }

    private func logResult(path: String, result: AiResult, startedAt: Int64) {
        let elapsed = Int64(Date().timeIntervalSince1970 * 1000) - startedAt
        switch result {
        case let .success(_, source):
            AiTelemetry.logInference(path: path, source: source, latencyMs: elapsed)
        case let .scheduled(_, source):
            AiTelemetry.logInference(path: path, source: source, latencyMs: elapsed)
        case .error:
            break
        }
    }

    // MARK: - Result interpretation

    /// A schedule request comes back as JSON; the app resolves its date/time itself
    /// (§12.7). Otherwise it's a plain answer.
    private func interpret(
        text: String,
        source: InferenceSource,
        originalPrompt: String,
        homeZoneId: String,
        instant: Date,
        storeInCache: Bool = false,
        groundingKey: Int64 = 0
    ) async -> AiResult {
        if let scheduleJson = ScheduleParser.extractScheduleJson(text) {
            // A booking is an action, never a replayable answer: even if `storeInCache` was set
            // by an intent misclassification, schedule JSON must not enter the cache (a
            // near-duplicate later prompt would re-book the first request's time).
            if let task = await ScheduleParser.buildScheduledTask(
                jsonStr: scheduleJson,
                originalPrompt: originalPrompt,
                now: instant,
                homeZoneId: homeZoneId,
                resolveZoneId: { [tools] query in tools.resolveZoneId(query) }
            ) {
                return .scheduled(task: task, source: source)
            }
            let title = ScheduleParser.titleOf(scheduleJson)
            let suffix = title.map { " for \"\($0)\"" } ?? ""
            let ask = "Sure — what date and time should I set\(suffix)?"
            if storeInCache {
                semanticCache.store(prompt: originalPrompt, response: ask, source: source, groundingKey: groundingKey)
            }
            return .success(text: ask, source: source)
        }
        if storeInCache {
            semanticCache.store(prompt: originalPrompt, response: text, source: source, groundingKey: groundingKey)
        }
        return .success(text: text, source: source)
    }

    // MARK: - On-device path

    private func runOnDevice(_ prompt: String) async -> (text: String, source: InferenceSource)? {
        guard let text = await inferenceActor.respond(to: prompt, available: isOnDeviceAvailable) else {
            return nil
        }
        return (text, .onDevice)
    }

    // MARK: - Cloud path

    /// Runs the cloud model with function calling: the client services every round
    /// of tool calls (up to `maxToolTurns`, mirroring Android `runWithTools`) via
    /// the dispatcher below, so the cloud model can fetch any live fact the
    /// grounding block didn't pre-resolve.
    private func runCloud(_ prompt: String) async -> (text: String, source: InferenceSource)? {
        guard let cloud else { return nil }
        let (findOverlap, now) = (self.findOverlap, self.now)
        do {
            let text = try await cloud.generate(
                systemInstruction: Self.systemInstruction,
                prompt: prompt,
                toolDispatcher: { name, argumentsJSON in
                    await MainActor.run {
                        Self.dispatchCloudTool(
                            tools: MeridianAiTools(findOverlap: findOverlap, now: now),
                            name: name,
                            argumentsJSON: argumentsJSON
                        )
                    }
                }
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (trimmed, .cloud)
        } catch {
            return nil
        }
    }

    /// Routes one cloud `functionCall` to the deterministic tool layer.
    /// Mirrors Android `MeridianAiTools.dispatch(call)`.
    @MainActor
    private static func dispatchCloudTool(
        tools: MeridianAiTools,
        name: String,
        argumentsJSON: Data
    ) -> String {
        let args = (try? JSONSerialization.jsonObject(with: argumentsJSON) as? [String: Any]) ?? [:]
        switch name {
        case "get_current_time":
            return tools.getCurrentTime(location: args["location"] as? String)
        case "convert_time":
            return tools.convertTime(
                time: args["time"] as? String,
                from: args["from_location"] as? String,
                to: args["to_location"] as? String
            )
        case "find_meeting_time":
            let locations = (args["locations"] as? [Any])?.compactMap { $0 as? String } ?? []
            let withinDays = (args["within_days"] as? Int)
                ?? (args["within_days"] as? Double).map(Int.init)
                ?? 0
            return tools.findMeetingTime(locations: locations, withinDays: withinDays)
        default:
            return "Error: unknown tool \"\(name)\"."
        }
    }

    // MARK: - Prompt assembly

    /// Front-loads the live-clock facts and the current date/time into the message
    /// itself, then the user's question — mirrors Android `buildContextualPrompt`.
    private func buildContextualPrompt(
        grounding: AiGrounding,
        zone: TimeZone,
        instant: Date,
        prompt: String,
        recentTurns: [ChatTurn]
    ) -> String {
        var out = ""
        if !recentTurns.isEmpty {
            out += "RECENT CONVERSATION (for context only — answer the latest user message):\n"
            for turn in recentTurns {
                out += "\(turn.role): \(turn.text)\n"
            }
            out += "\n"
        }
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

    // nonisolated: an immutable String is safe to read from any actor — without this,
    // the static inherits @MainActor isolation and AiInferenceActor can't reference it.
    nonisolated static let systemInstruction: String = """
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

    typealias ToolDispatcher = @Sendable (_ name: String, _ argumentsJSON: Data) async -> String

    static let maxToolTurns = 5

    func generate(
        systemInstruction: String,
        prompt: String,
        toolDispatcher: ToolDispatcher? = nil
    ) async throws -> String {
        var contents: [[String: Any]] = [
            ["role": "user", "parts": [["text": prompt]]]
        ]

        var turn = 0
        while true {
            let content = try await generateTurn(systemInstruction: systemInstruction, contents: contents, withTools: toolDispatcher != nil)
            let calls = Self.functionCalls(in: content)
            guard let toolDispatcher, !calls.isEmpty, turn < Self.maxToolTurns else {
                return Self.text(in: content)
            }
            turn += 1

            contents.append(content)
            var responseParts: [[String: Any]] = []
            for call in calls {
                let result = await toolDispatcher(call.name, call.argumentsJSON)
                responseParts.append([
                    "functionResponse": [
                        "name": call.name,
                        "response": ["result": result],
                    ],
                ])
            }
            contents.append(["role": "function", "parts": responseParts])
        }
    }

    private func generateTurn(
        systemInstruction: String,
        contents: [[String: Any]],
        withTools: Bool
    ) async throws -> [String: Any] {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: endpoint) else { throw CloudError.badURL }

        var body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": contents,
        ]
        if withTools {
            body["tools"] = [["functionDeclarations": Self.functionDeclarations]]
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Key goes in a header, not a query param — URLs leak into logs and proxies.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CloudError.httpError
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any] else {
            throw CloudError.badPayload
        }
        return content
    }

    private static func functionCalls(in content: [String: Any]) -> [(name: String, argumentsJSON: Data)] {
        let parts = content["parts"] as? [[String: Any]] ?? []
        return parts.compactMap { part in
            guard let call = part["functionCall"] as? [String: Any],
                  let name = call["name"] as? String else { return nil }
            let args = call["args"] as? [String: Any] ?? [:]
            let data = (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8)
            return (name, data)
        }
    }

    private static func text(in content: [String: Any]) -> String {
        let parts = content["parts"] as? [[String: Any]] ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    private static var functionDeclarations: [[String: Any]] { [
        [
            "name": "get_current_time",
            "description": "Get the current real-world local date and time at a city, place, airport code, or UTC offset — e.g. \"Tokyo\", \"New York\", \"LHR\", or \"UTC+9\".",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "location": [
                        "type": "STRING",
                        "description": "A city, place, airport code, or UTC offset.",
                    ],
                ],
                "required": ["location"],
            ],
        ],
        [
            "name": "convert_time",
            "description": "Convert a clock time from one place to the equivalent local time in another place.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "time": [
                        "type": "STRING",
                        "description": "The time to convert — 24-hour \"HH:mm\" or ISO \"yyyy-MM-ddTHH:mm\". A bare time of day means today in the source place.",
                    ],
                    "from_location": [
                        "type": "STRING",
                        "description": "The place the given time is in.",
                    ],
                    "to_location": [
                        "type": "STRING",
                        "description": "The place to convert the time into.",
                    ],
                ],
                "required": ["time", "from_location", "to_location"],
            ],
        ],
        [
            "name": "find_meeting_time",
            "description": "Find the fairest meeting hours shared across two or more places, ranked best-first.",
            "parameters": [
                "type": "OBJECT",
                "properties": [
                    "locations": [
                        "type": "ARRAY",
                        "items": ["type": "STRING"],
                        "description": "Two or more cities, places, or time zones that need to meet.",
                    ],
                    "within_days": [
                        "type": "INTEGER",
                        "description": "How many days from today to search (0 = today, 1 = tomorrow).",
                    ],
                ],
                "required": ["locations"],
            ],
        ],
    ] }

    enum CloudError: Error, Sendable {
        case badURL
        case httpError
        case badPayload
    }
}

// MARK: - RulesEngine

/// Deterministic, network-free fallback. When no LLM is available it answers
/// directly from the already-computed grounding block, which contains the LIVE
/// CLOCK / TIME CONVERSIONS / MEETING SLOTS facts the model would otherwise use.
enum RulesEngine {

    static func answer(prompt: String, grounding: AiGrounding, zone: TimeZone, instant: Date) -> String {
        if grounding.intent == .schedule {
            let title = inferTitle(from: prompt)
            let when = prompt
            return "{\"action\":\"schedule\",\"title\":\"\(escape(title))\",\"when\":\"\(escape(when))\",\"zoneId\":\"\(zone.identifier)\"}"
        }

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

    private static func liveClockSummary(_ block: String) -> String {
        let bullets = block
            .split(separator: "\n")
            .filter { $0.hasPrefix("• ") }
            .map { String($0.dropFirst(2)) }
        guard !bullets.isEmpty else { return block }
        return bullets.joined(separator: "\n")
    }

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
