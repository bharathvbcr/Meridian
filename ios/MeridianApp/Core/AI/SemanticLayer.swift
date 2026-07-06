// SemanticLayer.swift
// Meridian — iOS 27 / Swift 6
//
// Lightweight on-device semantic layer: embedding + cache lookup, intent routing,
// and grounding compression. Mirrors Android `SemanticLayer.kt`. Target <15 ms overhead.

import Foundation
import NaturalLanguage

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
    static func shouldBypass(intent: AiQueryIntent, prompt: String) -> Bool {
        if intent == .currentTime { return true }
        if intent == .convert && prompt.lowercased().contains("now") { return true }
        return false
    }

    static func groundingKey(epochMs: Int64, homeZoneId: String) -> Int64 {
        let epochMinute = epochMs / 60_000
        return epochMinute ^ Int64(truncatingIfNeeded: homeZoneId.hashValue)
    }
}

enum SemanticEmbedder: Sendable {
    private static let nlEmbedding: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)

    /// Character trigram hash embedding with optional NaturalLanguage sentence vectors.
    static func embed(_ text: String) -> [Float] {
        if let nl = nlEmbedding {
            let vec = nl.vector(for: text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
            if !vec.isEmpty {
                return normalize(vec.map { Float($0) })
            }
        }
        return trigramEmbed(text)
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
            let bucket = abs(gram.hashValue) % embedDim
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
    static func emitProgressive(_ text: String, onPartial: @Sendable (String) async -> Void) async {
        guard !text.isEmpty else { return }
        var built = ""
        for word in text.split(separator: " ") {
            built = built.isEmpty ? String(word) : "\(built) \(word)"
            await onPartial(built)
            try? await Task.sleep(for: .milliseconds(18))
        }
    }
}
