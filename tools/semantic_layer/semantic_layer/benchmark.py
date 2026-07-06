"""Latency and hit-rate benchmarking harness."""

from __future__ import annotations

import argparse
import statistics
import time
from typing import Iterable

import numpy as np

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
    """pairs: (original, paraphrase) expected to hit."""
    config = PipelineConfig(similarity_threshold=0.86, cache_max_entries=500)
    pipe = SemanticPipeline(config)

    hits = 0
    total = 0
    for original, paraphrase in pairs:
        pipe.process(original, llm_fn=_mock_llm)
        result = pipe.process(paraphrase, llm_fn=_mock_llm)
        total += 1
        if result.cache_hit:
            hits += 1
    return {"hit_rate": hits / max(total, 1), "pairs": total}


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


if __name__ == "__main__":
    main()
