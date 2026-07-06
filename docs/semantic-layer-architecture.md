# Semantic Layer — Production Architecture & Implementation Guide

> Reference architecture for low-latency semantic caching, routing, and context compression.
> Meridian's mobile clients (`SemanticLayer.kt` / `SemanticLayer.swift`) implement a lightweight
> trigram variant of this design; the Python package in `tools/semantic_layer/` is the
> server/edge reference with FAISS and sentence-transformers.

---

## System Architecture & Data Flow

### End-to-end pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER QUERY (+ optional RAG context)               │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────┐
                    │   1. EMBED QUERY  (<5 ms)       │
                    │   MiniLM-L6-v2 / trigram        │
                    └─────────────────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              ▼                       ▼                       ▼
   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────────┐
   │ 2a. SEMANTIC     │   │ 2b. SEMANTIC     │   │ 2c. SEMANTIC         │
   │     CACHE        │   │     ROUTER       │   │     COMPRESSOR       │
   │ FAISS + cosine   │   │ complexity score │   │ chunk filter + rank  │
   │ threshold τ      │   │ → model tier     │   │ → reduced context    │
   └────────┬─────────┘   └────────┬─────────┘   └──────────┬───────────┘
            │                      │                          │
     sim ≥ τ │                      │                          │
            ▼                      │                          │
   ┌──────────────────┐            │                          │
   │ CACHE HIT        │            │                          │
   │ return cached    │            │                          │
   │ response (~0 ms) │            │                          │
   └──────────────────┘            │                          │
            │ miss                 │                          │
            └──────────────────────┴──────────────────────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────┐
                    │ 3. LLM INFERENCE ENGINE         │
                    │ SMALL (1–3B) │ LARGE (8–70B)    │
                    └─────────────────────────────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────┐
                    │ 4. STORE IN CACHE (async)       │
                    │ TTL + LRU eviction              │
                    └─────────────────────────────────┘
```

### Latency budget (target: semantic layer < 15 ms P95)

| Stage              | P50    | P95    | Notes                                      |
|--------------------|--------|--------|--------------------------------------------|
| Query embedding    | 2–4 ms | 6 ms   | MiniLM on CPU INT8; batch=1                  |
| FAISS search       | 0.1 ms | 1 ms   | IndexFlatIP up to ~10k entries               |
| Router classify    | 0.5 ms | 2 ms   | Heuristic + optional tiny classifier         |
| Context compress   | 3 ms   | 8 ms   | Only when RAG context > threshold            |
| **Total overhead** | **6 ms** | **12 ms** | Excludes LLM inference                  |

### Integration with Meridian mobile pipeline

The Kotlin/Swift layers mirror stages 2a–2c before `GeminiRepository` / `AiAssistant` inference:

1. **Cache lookup** → instant replay (`AiProvenance.CACHED`)
2. **Compressor** → trim grounding blocks > 1,200 chars
3. **Router** → `SemanticRoute.RULES` bypasses LLM when grounding is sufficient
4. **LLM** → on-device Nano, else cloud Gemini

---

## Mathematical Optimization & Thresholding Logic

### Cosine similarity (L2-normalized vectors)

For query embedding **q** and cached prompt embedding **c** (both unit vectors):

\[
\text{sim}(q, c) = q \cdot c = \cos(\theta)
\]

Cache hit when \(\text{sim}(q, c^*) \geq \tau\), where \(c^* = \arg\max_c \text{sim}(q, c)\).

### Dynamic threshold τ

**Problem:** Fixed τ trades off false positives (hallucinated cache hits) vs miss rate.

**Offline calibration** (validation set \(\{(q_i, c_i, y_i)\}\) where \(y_i \in \{0,1\}\) = same intent/answer):

```
For each candidate τ in linspace(0.70, 0.98, 29):
    predictions = [sim(q_i, c_i) >= τ for i]
    FPR(τ) = FP / (FP + TN)
    TPR(τ) = TP / (TP + FN)
Select τ* = max τ such that FPR(τ) ≤ ε   (e.g. ε = 0.02)
```

**Online auto-tuning** (production):

```
On cache hit with user feedback signal f ∈ {-1, 0, +1}:
    if f == -1:  τ ← min(τ + δ_up, τ_max)     # false positive → raise bar
    if f == +1:  τ ← max(τ - δ_down, τ_min)   # confirmed good hit → lower bar

δ_up   = 0.005,  δ_down = 0.002  (asymmetric: penalize FP harder)
τ ∈ [0.78, 0.95]
```

**Margin guard:** Reject hit if \(\text{sim}(q, c^*) - \text{sim}(q, c^{(2)})\) < margin_m (e.g. 0.04) — ambiguous neighborhood.

### Router complexity score

\[
S = w_1 \cdot \frac{|prompt|}{L_{max}} + w_2 \cdot \mathbb{1}_{WH} + w_3 \cdot \mathbb{1}_{multi\_step} + w_4 \cdot (1 - \max_c \text{sim}(q, centroid_c))
\]

Route to **SMALL** if \(S < \theta_{route}\), else **LARGE**.

### Context compression ratio

Given query **q** and chunks \(\{d_j\}\):

1. Score \(s_j = \text{sim}(\text{embed}(q), \text{embed}(d_j))\)
2. Keep top-\(k\) where \(\sum_j |d_j| \leq B_{token}\) (knapsack by relevance)
3. Target compression: retain ≥ 90% answer recall on held-out QA pairs

---

## Edge Cases & Failure Modes

| Scenario | Detection | Mitigation |
|----------|-----------|------------|
| **OOD query** | Embedding norm drift, low max-sim across cache (< 0.5), language mismatch | Bypass cache; route to LARGE; log for re-indexing |
| **Cold start** | `cache.size == 0` | Skip lookup; always infer; warm cache asynchronously |
| **Resource contention** | GPU memory pressure, embedder queue depth | Run embedder on dedicated CPU thread; INT8 quantize; cap concurrent embeds |
| **Stale cache** | TTL expired or grounding timestamp changed | Invalidate entries where `grounding_hash` differs |
| **Ambiguous hit** | Top-2 sim gap < margin_m | Force miss → full inference |
| **Embedding failure** | Model OOM / timeout | Fallback to trigram hash embedder (Meridian mobile pattern) |

---

## Resource Management & Benchmarking Strategy

### VRAM / RAM layout

```
┌─────────────────────────────────────────┐
│ GPU VRAM                                │
│  ├─ Primary LLM (quantized)   4–24 GB  │
│  └─ (optional) embedder GPU    ~200 MB │
├─────────────────────────────────────────┤
│ CPU RAM                                 │
│  ├─ FAISS index (FlatIP)        ~6 MB   │  (10k × 384-dim × 4 bytes)
│  ├─ MiniLM INT8 (CPU)          ~80 MB   │
│  └─ Cache metadata + responses  ~50 MB  │
└─────────────────────────────────────────┘
```

**Rule:** Prefer CPU embedding when LLM occupies GPU; never share GPU between 8B+ LLM and embedder without explicit memory budget.

### Benchmark harness

Run `python -m semantic_layer.benchmark` (see `tools/semantic_layer/`):

- **Latency:** P50/P95/P99 for embed, search, full pipeline (no LLM)
- **Cache hit rate:** vs threshold sweep on labeled near-duplicate pairs
- **Compression:** token reduction % vs QA F1 on RAG eval set
- **Contention:** embed latency under synthetic LLM GPU load

### Cache invalidation

1. **TTL:** Default 3600 s; time-sensitive queries (e.g. "what time is it") → TTL = 60 s or skip cache
2. **LRU:** Evict oldest when `max_entries` exceeded (default 10,000 server / 64 mobile)
3. **Version key:** Invalidate all entries when `model_version` or `grounding_schema_version` changes
4. **Explicit flush:** Admin API or `/cache/invalidate?prefix=...`

---

## Python Reference Implementation

See `tools/semantic_layer/`:

```
semantic_layer/
├── __init__.py       # Public API
├── types.py          # Dataclasses, enums
├── embedder.py       # SentenceTransformer + trigram fallback
├── cache.py          # FAISS semantic cache (TTL, LRU)
├── router.py         # Complexity-based model routing
├── compressor.py     # RAG context semantic filter
├── threshold.py      # Offline calibration + online tuner
├── pipeline.py       # Orchestrator
├── benchmark.py      # Latency / hit-rate harness
└── requirements.txt
```

Quick start:

```bash
cd tools/semantic_layer
pip install -r requirements.txt
python -m semantic_layer.benchmark --queries 1000
```

Example:

```python
from semantic_layer import SemanticPipeline, PipelineConfig

pipe = SemanticPipeline(PipelineConfig(
    cache_max_entries=10_000,
    similarity_threshold=0.86,
    small_model_id="phi-3-mini",
    large_model_id="llama-3-8b",
))

result = pipe.process(
    query="Convert 3pm NYC to London time",
    context_chunks=["User home: America/New_York", "..."],
    llm_fn=lambda prompt, tier: my_llm.generate(prompt, model=tier),
)
print(result.text, result.route, result.cache_hit, result.latency_ms)
```

---

## Deployment checklist

- [ ] Calibrate τ on domain-specific near-duplicate pairs (target FPR ≤ 2%)
- [ ] Set TTL per intent class (time-sensitive vs static FAQ)
- [ ] Pin embedder to CPU if LLM uses GPU
- [ ] Export Prometheus metrics: `semantic_cache_hits`, `semantic_latency_ms`, `router_tier`
- [ ] Log cache misses with max-sim for threshold drift monitoring
- [ ] A/B test compression ratio vs answer quality before production cutover
