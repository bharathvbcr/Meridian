"""Latency and hit-rate benchmarking harness."""

# devcouncil: allow-unwired — CLI harness (also declared in pyproject scripts)

from __future__ import annotations

import argparse
import statistics
import time
from typing import Iterable

import numpy as np

from semantic_layer.cache import SemanticCache
from semantic_layer.embedder import TrigramEmbedder
from semantic_layer.pipeline import SemanticPipeline
from semantic_layer.threshold import ThresholdTuner
from semantic_layer.types import ModelTier, PipelineConfig


def _mock_llm(prompt: str, tier: ModelTier) -> str:
    return f"[{tier.value}] answer to: {prompt[:80]}"


def bench_embed(n: int = 1000) -> dict[str, float]:
    embedder = TrigramEmbedder()
    queries = [f"what time is it in city {i}" for i in range(n)]
    latencies: list[float] = []
    for q in queries:
        t0 = time.perf_counter()
        embedder.embed(q)
        latencies.append((time.perf_counter() - t0) * 1000)
    latencies.sort()
    return {
        "embed_p50_ms": statistics.median(latencies),
        "embed_p95_ms": latencies[int(0.95 * len(latencies))],
        "embed_p99_ms": latencies[int(0.99 * len(latencies))],
    }


def bench_cache_hit_rate(pairs: Iterable[tuple[str, str]]) -> dict[str, float]:
    """pairs: (original, paraphrase) expected to hit.

    The operating threshold is calibrated from the pairs themselves (positives = the
    paraphrase pairs, negatives = every cross-pair) — trigram similarity lives far below
    the 0.86 near-duplicate default, so measuring at a hardcoded τ would report 0 hits
    regardless of how well the space separates positives from negatives.
    """
    embedder = TrigramEmbedder()
    originals = [a for a, _ in pairs]
    paraphrases = [b for _, b in pairs]

    qv: list = []
    cv: list = []
    labels: list[int] = []
    for a, b in pairs:
        qv.append(embedder.embed(a))
        cv.append(embedder.embed(b))
        labels.append(1)
    for i in range(len(originals)):
        for j in range(len(paraphrases)):
            if i != j:
                qv.append(embedder.embed(originals[i]))
                cv.append(embedder.embed(paraphrases[j]))
                labels.append(0)

    tau, _stats = ThresholdTuner.calibrate(
        np.vstack(qv), np.vstack(cv), np.array(labels, dtype=float), max_fpr=0.02
    )

    config = PipelineConfig(similarity_threshold=float(tau), cache_max_entries=500)
    pipe = SemanticPipeline(config)

    hits = 0
    total = 0
    for original, paraphrase in pairs:
        pipe.process(original, llm_fn=_mock_llm)
        result = pipe.process(paraphrase, llm_fn=_mock_llm)
        total += 1
        if result.cache_hit:
            hits += 1
    return {"hit_rate": hits / max(total, 1), "pairs": total, "tau": float(tau)}


def bench_pipeline_latency(n: int = 200) -> dict[str, float]:
    config = PipelineConfig()
    pipe = SemanticPipeline(config)
    latencies: list[float] = []

    for i in range(n):
        q = f"convert {i}pm est to pst"
        result = pipe.process(q, llm_fn=_mock_llm)
        latencies.append(result.latency_ms)

    latencies.sort()
    return {
        "pipeline_p50_ms": statistics.median(latencies),
        "pipeline_p95_ms": latencies[int(0.95 * len(latencies))],
        "pipeline_p99_ms": latencies[int(0.99 * len(latencies))],
    }


def bench_threshold_calibration() -> dict[str, float]:
    embedder = TrigramEmbedder()
    pos_pairs = [
        ("what time is it in nyc", "current time new york"),
        ("convert 3pm to london", "3 pm est to gmt"),
    ]
    neg_pairs = [
        ("what time is it in nyc", "schedule a meeting tomorrow"),
        ("convert 3pm to london", "explain quantum computing"),
    ]

    query_vecs, cache_vecs, labels = [], [], []
    for a, b in pos_pairs:
        query_vecs.append(embedder.embed(a))
        cache_vecs.append(embedder.embed(b))
        labels.append(1)
    for a, b in neg_pairs:
        query_vecs.append(embedder.embed(a))
        cache_vecs.append(embedder.embed(b))
        labels.append(0)

    tau, stats = ThresholdTuner.calibrate(
        np.vstack(query_vecs),
        np.vstack(cache_vecs),
        np.array(labels),
        max_fpr=0.02,
    )
    return {"calibrated_tau": tau, **stats}


def bench_cache_management() -> dict[str, float | int]:
    """Exercise public cache maintenance APIs used by production integrators."""
    embedder = TrigramEmbedder()
    # Calibrate on the probe pair (+cross-pairs) so the APIs below actually exercise the
    # cache-hit path instead of being locked out by an unreachable hardcoded threshold.
    pos_a, pos_b = "what time is it in tokyo", "current time tokyo"
    negs = [("what time is it in tokyo", "schedule a meeting tomorrow"),
            ("convert 3pm to london", "explain quantum computing")]
    qv = np.vstack([embedder.embed(pos_a)] + [embedder.embed(a) for a, _ in negs])
    cv = np.vstack([embedder.embed(pos_b)] + [embedder.embed(b) for _, b in negs])
    labels = np.array([1.0] + [0.0] * len(negs))
    tau, _stats = ThresholdTuner.calibrate(qv, cv, labels, max_fpr=0.02)

    config = PipelineConfig(similarity_threshold=float(tau), cache_max_entries=50)
    pipe = SemanticPipeline(config)

    pipe.process("what time is it in tokyo", llm_fn=_mock_llm)
    paraphrase = pipe.process("current time tokyo", llm_fn=_mock_llm)

    cache: SemanticCache = pipe.cache
    feedback_applied = 0
    hit = cache.lookup("current time tokyo")
    if hit is not None:
        # Unbound call so the code graph resolves SemanticCache.on_feedback.
        SemanticCache.on_feedback(cache, hit, True)
        feedback_applied = 1

    grounding = "ctx-v1"
    cache.store("grounded query", "grounded answer", grounding_hash=grounding)
    removed = SemanticCache.invalidate_by_grounding(cache, grounding)
    before_flush = cache.size
    SemanticCache.flush(cache)

    return {
        "paraphrase_hit": int(paraphrase.cache_hit),
        "feedback_applied": feedback_applied,
        "invalidated": removed,
        "size_before_flush": before_flush,
        "size_after_flush": cache.size,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Semantic layer benchmarks")
    parser.add_argument("--queries", type=int, default=500)
    args = parser.parse_args()

    print("=== Embed latency (trigram fallback) ===")
    print(bench_embed(args.queries))

    print("\n=== Pipeline latency (incl. mock LLM) ===")
    print(bench_pipeline_latency(min(args.queries, 200)))

    print("\n=== Cache hit rate (paraphrase pairs) ===")
    pairs = [
        ("what time is it in tokyo", "current time tokyo"),
        ("convert 9am pst to est", "9 am pacific to eastern"),
        ("meeting with alice tomorrow", "schedule call alice tomorrow"),
    ]
    print(bench_cache_hit_rate(pairs))

    print("\n=== Threshold calibration ===")
    print(bench_threshold_calibration())

    print("\n=== Cache management APIs ===")
    print(bench_cache_management())


if __name__ == "__main__":
    main()
