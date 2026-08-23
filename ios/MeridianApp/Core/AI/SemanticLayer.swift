// SemanticLayer.swift
// Meridian — iOS 27 / Swift 6
//
// Lightweight on-device semantic layer: embedding + cache lookup, intent routing,
// and grounding compression. Mirrors Android `SemanticLayer.kt`. Target <15 ms overhead.

import Foundation

private let embedDim = 384
private let cacheMax = 64
private let cacheThreshold: Float = 0.86
private let cacheMargin: Float = 0.04
private let groundingCompressAt = 1_200
private let cacheTtlMs: Int64 = 30_000

enum SemanticRoute: Sendable {
    case rules
    case standard
}

/// One prior chat turn for multi-turn prompt context.
struct ChatTurn: Sendable {
    let role: String
    let text: String
}

enum SemanticCachePolicy: Sendable {
    /// Skip the cache for intents that must never be replayed: time-sensitive reads whose
    /// answers go stale, and SCHEDULE — a side-effecting action where a near-duplicate prompt
    /// ("…at 1pm" vs "…at 2pm") would otherwise replay the first booking's JSON. Mirrors
    /// Android `SemanticCachePolicy.shouldBypass`.
    static func shouldBypass(intent: AiQueryIntent, prompt: String) -> Bool {
        if intent == .currentTime || intent == .schedule { return true }
        if intent == .convert && prompt.lowercased().contains("now") { return true }
        return false
    }

    static func groundingKey(epochMs: Int64, homeZoneId: String) -> Int64 {
        let epochMinute = epochMs / 60_000
        return epochMinute ^ Int64(truncatingIfNeeded: homeZoneId.hashValue)
    }
}

enum SemanticEmbedder: Sendable {
    /// Character trigram hash embedding, L2-normalized — deliberately the ONLY embedding space.
    /// Mirrors Android exactly; mixing in NLEmbedding sentence vectors would let stored entries
    /// and later queries come from different vector spaces (availability can change mid-session,
    /// and non-English text falls back), making cosine scores meaningless. One space, everywhere.
    static func embed(_ text: String) -> [Float] {
        trigramEmbed(text)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var dot: Float = 0
        for i in 0..<n { dot += a[i] * b[i] }
        return dot
    }

    private static func trigramEmbed(_ text: String) -> [Float] {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        var vec = [Float](repeating: 0, count: embedDim)
        guard !normalized.isEmpty else { return vec }
        let padded = "  \(normalized) "
        let chars = Array(padded)
        guard chars.count >= 3 else { return vec }
        for i in 0..<(chars.count - 2) {
            let gram = String(chars[i..<(i + 3)])
            // Mask the sign bit like Kotlin's `and Int.MAX_VALUE`; abs(Int.min) would trap.
            let bucket = (gram.hashValue & Int.max) % embedDim
            vec[bucket] += 1
        }
        return normalize(vec)
    }

    private static func normalize(_ vec: [Float]) -> [Float] {
        let norm = max(sqrt(vec.reduce(0) { $0 + $1 * $1 }), 1e-6)
        return vec.map { $0 / norm }
    }
}

final class SemanticCache: @unchecked Sendable {
    struct Hit: Sendable {
        let response: String
        let source: InferenceSource
    }

    private struct Entry {
        let prompt: String
        let vector: [Float]
        let response: String
        let source: InferenceSource
        let storedAt: Int64
        let groundingKey: Int64
    }

    private let maxEntries: Int
    private let threshold: Float
    private let margin: Float
    private let ttlMs: Int64
    private var entries: [Entry] = []
    private let lock = NSLock()
    private let nowMs: () -> Int64

    init(
        maxEntries: Int = cacheMax,
        threshold: Float = cacheThreshold,
        margin: Float = cacheMargin,
        ttlMs: Int64 = cacheTtlMs,
        nowMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.maxEntries = maxEntries
        self.threshold = threshold
        self.margin = margin
        self.ttlMs = ttlMs
        self.nowMs = nowMs
    }

    func lookup(_ query: String, groundingKey: Int64) -> Hit? {
        let qVec = SemanticEmbedder.embed(query)
        let now = nowMs()
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { now - $0.storedAt > ttlMs }
        var best: Entry?
        var top1 = threshold
        var top2 = threshold
        for entry in entries {
            guard entry.groundingKey == groundingKey else { continue }
            let score = SemanticEmbedder.cosine(qVec, entry.vector)
            if score > top1 {
                top2 = top1
                top1 = score
                best = entry
            } else if score > top2 {
                top2 = score
            }
        }
        guard let best, top1 - top2 >= margin else { return nil }
        return Hit(response: best.response, source: .cached)
    }

    func store(prompt: String, response: String, source: InferenceSource, groundingKey: Int64) {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        entries.insert(
            Entry(
                prompt: prompt,
                vector: SemanticEmbedder.embed(prompt),
                response: trimmed,
                source: source,
                storedAt: nowMs(),
                groundingKey: groundingKey
            ),
            at: 0
        )
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }
}

enum SemanticRouter: Sendable {
    static func route(intent: AiQueryIntent, prompt: String, groundingBlock: String) -> SemanticRoute {
        guard !groundingBlock.isEmpty else { return .standard }
        switch intent {
        case .currentTime:
            return .rules
        case .convert:
            return prompt.count <= 200 ? .rules : .standard
        case .meeting:
            return groundingBlock.contains("MEETING SLOTS") && prompt.count <= 280 ? .rules : .standard
        case .schedule:
            return .standard
        case .general:
            return prompt.count <= 100 && groundingBlock.contains("LIVE CLOCK") ? .rules : .standard
        }
    }
}

enum SemanticCompressor: Sendable {
    static func compress(_ block: String, maxBulletsPerSection: Int = 5) -> String {
        guard block.count > groundingCompressAt else { return block }
        var out: [String] = []
        var bulletsInSection = 0
        for line in block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.isEmpty {
                out.append("")
                bulletsInSection = 0
            } else if !line.hasPrefix("• ") {
                out.append(line)
                bulletsInSection = 0
            } else if bulletsInSection < maxBulletsPerSection {
                out.append(String(line.prefix(160)))
                bulletsInSection += 1
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SemanticPartialEmitter {
    private static let stepDelayMs: Int64 = 18
    /// Caps artificial streaming latency: 32 steps ≈ 576 ms regardless of reply length.
    private static let maxSteps = 32

    /// Text safe to show while a candidate is still being interpreted: schedule-JSON payloads
    /// are replaced with a friendly placeholder instead of flashing machine output.
    static func displayableCandidate(_ text: String) -> String {
        ScheduleParser.extractScheduleJson(text) != nil ? "Scheduling your event…" : text
    }

    static func emitProgressive(_ text: String, onPartial: @Sendable (String) async -> Void) async {
        guard !text.isEmpty else { return }
        let streamable = displayableCandidate(text)
        for chunk in partialChunks(streamable, maxChunks: maxSteps) {
            await onPartial(chunk)
            do {
                try await Task.sleep(for: .milliseconds(stepDelayMs))
            } catch {
                return // cancelled — stop streaming instead of swallowing the cancellation
            }
        }
    }

    /// Splits [text] into at most [maxChunks] monotonically growing prefixes ending with the
    /// full text. Mirrors Android `partialChunks`.
    static func partialChunks(_ text: String, maxChunks: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > maxChunks else {
            return (1...words.count).map { words.prefix($0).joined(separator: " ") }
        }
        let stride = (words.count + maxChunks - 1) / maxChunks
        var chunks: [String] = []
        var end = 0
        while end < words.count {
            end = min(end + stride, words.count)
            chunks.append(words.prefix(end).joined(separator: " "))
        }
        return chunks
    }
}
