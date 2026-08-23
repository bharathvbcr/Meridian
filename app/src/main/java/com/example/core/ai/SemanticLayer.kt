package com.example.core.ai

import java.util.concurrent.ConcurrentLinkedDeque
import kotlin.math.sqrt

// Lightweight on-device semantic layer: embedding + cache lookup, intent routing,
// and grounding compression. No network, no heavy ML deps — target <15 ms overhead.

private const val EMBED_DIM = 384
private const val CACHE_MAX = 64
private const val CACHE_THRESHOLD = 0.86f
/** Reject a cache hit when the top-two matches are too close — avoids ambiguous replays. */
private const val CACHE_MARGIN = 0.04f
private const val GROUNDING_COMPRESS_AT = 1_200

// Streaming cadence for progressive partials: 18 ms per step, capped so even a very long reply
// finishes streaming in well under a second (32 steps ≈ 576 ms).
internal const val PARTIAL_STEP_DELAY_MS = 18L
internal const val MAX_PARTIAL_STEPS = 32

// Answers here are time-valued (live clock, conversions, meeting windows), so a cache hit must be
// recent or it replays a stale reading — "9:41 PM" served an hour later. The TTL bounds staleness to
// the cache's real purpose: collapsing rapid re-asks, retries, and double-submits. Keep it short.
private const val CACHE_TTL_MS = 30_000L

enum class SemanticRoute {
    /** Answer from the deterministic rules engine — skip the LLM. */
    RULES,
    /** Normal on-device → cloud inference path. */
    STANDARD,
}

/** One prior chat turn for multi-turn prompt context. */
data class ChatTurn(val role: String, val text: String)

object SemanticCachePolicy {
    /**
     * Skip the cache for intents that must never be replayed: time-sensitive reads
     * (CURRENT_TIME, and CONVERT referencing "now") whose answer goes stale, and SCHEDULE — a
     * side-effecting action, where a near-duplicate prompt ("…at 1pm" vs "…at 2pm") would
     * otherwise return the first booking's JSON and schedule the wrong time.
     */
    fun shouldBypass(intent: AiQueryIntent, prompt: String): Boolean {
        if (intent == AiQueryIntent.CURRENT_TIME || intent == AiQueryIntent.SCHEDULE) return true
        if (intent == AiQueryIntent.CONVERT && prompt.lowercase().contains("now")) return true
        return false
    }

    /** Epoch-minute + home zone — invalidates cached time readings when the clock advances. */
    fun groundingKey(epochMs: Long, homeZoneId: String): Long {
        val epochMinute = epochMs / 60_000L
        return epochMinute xor homeZoneId.hashCode().toLong()
    }
}

object SemanticEmbedder {
    /** Character trigram hash embedding, L2-normalized. Fast and stable across platforms. */
    fun embed(text: String): FloatArray {
        val normalized = text.lowercase().trim().replace(Regex("\\s+"), " ")
        val vec = FloatArray(EMBED_DIM)
        if (normalized.isEmpty()) return vec
        val padded = "  $normalized "
        for (i in 0 until padded.length - 2) {
            val gram = padded.substring(i, i + 3)
            val bucket = (gram.hashCode() and Int.MAX_VALUE) % EMBED_DIM
            vec[bucket] += 1f
        }
        val norm = sqrt(vec.sumOf { (it * it).toDouble() }).toFloat().coerceAtLeast(1e-6f)
        for (i in vec.indices) vec[i] /= norm
        return vec
    }

    fun cosine(a: FloatArray, b: FloatArray): Float {
        var dot = 0f
        val n = minOf(a.size, b.size)
        for (i in 0 until n) dot += a[i] * b[i]
        return dot
    }
}

class SemanticCache(
    private val maxEntries: Int = CACHE_MAX,
    private val threshold: Float = CACHE_THRESHOLD,
    private val ttlMs: Long = CACHE_TTL_MS,
    private val margin: Float = CACHE_MARGIN,
    private val nowMs: () -> Long = System::currentTimeMillis,
) {
    data class Hit(val response: String, val provenance: AiProvenance)

    private data class Entry(
        val prompt: String,
        val vector: FloatArray,
        val response: String,
        val provenance: AiProvenance,
        val storedAt: Long,
        val groundingKey: Long,
    )

    private val entries = ConcurrentLinkedDeque<Entry>()

    fun lookup(
        query: String,
        groundingKey: Long,
    ): Hit? {
        val qVec = SemanticEmbedder.embed(query)
        val now = nowMs()
        var best: Entry? = null
        var top1 = threshold
        var top2 = threshold
        for (entry in entries) {
            // Expired entries hold stale time readings — never replay them.
            if (now - entry.storedAt > ttlMs) {
                entries.remove(entry)
                continue
            }
            if (entry.groundingKey != groundingKey) continue
            val score = SemanticEmbedder.cosine(qVec, entry.vector)
            if (score > top1) {
                top2 = top1
                top1 = score
                best = entry
            } else if (score > top2) {
                top2 = score
            }
        }
        if (best == null) return null
        // Ambiguous top-two match — prefer a fresh answer over a wrong replay.
        if (top1 - top2 < margin) return null
        return Hit(best.response, AiProvenance.CACHED)
    }

    fun store(
        prompt: String,
        response: String,
        provenance: AiProvenance,
        groundingKey: Long,
    ) {
        if (response.isBlank()) return
        entries.addFirst(
            Entry(
                prompt = prompt,
                vector = SemanticEmbedder.embed(prompt),
                response = response,
                provenance = provenance,
                storedAt = nowMs(),
                groundingKey = groundingKey,
            ),
        )
        while (entries.size > maxEntries) entries.pollLast()
    }
}

object SemanticRouter {
    /** Route simple, fact-resolved queries to the rules engine; complex ones to the LLM. */
    fun route(intent: AiQueryIntent, prompt: String, groundingBlock: String): SemanticRoute {
        if (groundingBlock.isEmpty()) return SemanticRoute.STANDARD
        return when (intent) {
            AiQueryIntent.CURRENT_TIME -> SemanticRoute.RULES
            AiQueryIntent.CONVERT -> if (prompt.length <= 200) SemanticRoute.RULES else SemanticRoute.STANDARD
            AiQueryIntent.MEETING ->
                if (groundingBlock.contains("MEETING SLOTS") && prompt.length <= 280) SemanticRoute.RULES
                else SemanticRoute.STANDARD
            AiQueryIntent.SCHEDULE -> SemanticRoute.STANDARD
            AiQueryIntent.GENERAL ->
                if (prompt.length <= 100 && groundingBlock.contains("LIVE CLOCK")) SemanticRoute.RULES
                else SemanticRoute.STANDARD
        }
    }
}

object SemanticCompressor {
    /** Keeps section headers and caps bullet lines so long grounding blocks fit tighter prompts. */
    fun compress(block: String, maxBulletsPerSection: Int = 5): String {
        if (block.length <= GROUNDING_COMPRESS_AT) return block
        val lines = block.lines()
        val out = StringBuilder()
        var bulletsInSection = 0
        for (line in lines) {
            when {
                line.isBlank() -> {
                    out.appendLine()
                    bulletsInSection = 0
                }
                !line.startsWith("• ") -> {
                    out.appendLine(line)
                    bulletsInSection = 0
                }
                bulletsInSection < maxBulletsPerSection -> {
                    out.appendLine(line.take(160))
                    bulletsInSection++
                }
            }
        }
        return out.toString().trimEnd()
    }
}

/**
 * Text safe to show while a candidate is still being interpreted: schedule-JSON payloads are
 * replaced with a friendly placeholder instead of flashing machine output at the user.
 */
fun displayableCandidate(text: String): String =
    if (ScheduleParser.extractScheduleJson(text) != null) "Scheduling your event…" else text

/**
 * Progressive partial text for rules/cache paths — improves perceived latency in the UI.
 * Schedule-JSON payloads are never streamed raw (the user would watch machine output flash by
 * right before the confirm card takes over); a friendly placeholder streams instead.
 */
suspend fun emitProgressivePartial(text: String, onPartial: suspend (String) -> Unit) {
    if (text.isBlank()) return
    val chunks = partialChunks(displayableCandidate(text), maxChunks = MAX_PARTIAL_STEPS)
    for (chunk in chunks) {
        onPartial(chunk)
        kotlinx.coroutines.delay(PARTIAL_STEP_DELAY_MS)
    }
}

/**
 * Splits [text] into at most [maxChunks] monotonically growing prefixes ending with the full
 * text. One callback per word made long replies re-render the bubble dozens of times per second
 * and added ~18 ms of artificial latency per word; bounding the step count caps both.
 */
internal fun partialChunks(text: String, maxChunks: Int): List<String> {
    val words = text.split(' ')
    if (words.size <= maxChunks) {
        return List(words.size) { i -> words.take(i + 1).joinToString(" ") }
    }
    // Emit every k-th word so each chunk boundary lands on a word edge.
    val stride = (words.size + maxChunks - 1) / maxChunks
    val chunks = mutableListOf<String>()
    var end = 0
    while (end < words.size) {
        end = minOf(end + stride, words.size)
        chunks.add(words.take(end).joinToString(" "))
    }
    return chunks
}
