"""Shared types for the semantic layer pipeline."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, Literal


class ModelTier(str, Enum):
    """Target inference backend selected by the semantic router."""

    SMALL = "small"  # 1B–3B — admin, FAQ, simple lookups
    LARGE = "large"  # 8B–70B — multi-step reasoning, open-ended


class CacheProvenance(str, Enum):
    CACHED = "cached"
    RULES = "rules"
    SMALL_LLM = "small_llm"
    LARGE_LLM = "large_llm"


@dataclass(frozen=True)
class PipelineConfig:
    """Tunable knobs for the semantic layer."""

    embed_model: str = "sentence-transformers/all-MiniLM-L6-v2"
    embed_dim: int = 384
    use_gpu_embedder: bool = False
    cache_max_entries: int = 10_000
    similarity_threshold: float = 0.86
    similarity_margin: float = 0.04  # min gap between top-1 and top-2
    cache_ttl_seconds: float = 3600.0
    compress_min_chars: int = 1200
    compress_top_k: int = 8
    compress_max_chunk_chars: int = 512
    router_threshold: float = 0.45
    threshold_min: float = 0.78
    threshold_max: float = 0.95
    threshold_fp_delta: float = 0.005
    threshold_hit_delta: float = 0.002
    ood_max_sim_floor: float = 0.50


@dataclass
class CacheHit:
    response: str
    similarity: float
    provenance: CacheProvenance = CacheProvenance.CACHED
    entry_id: int | None = None


@dataclass
class PipelineResult:
    text: str
    route: ModelTier
    cache_hit: bool
    provenance: CacheProvenance
    latency_ms: float
    tokens_saved: int = 0
    metadata: dict = field(default_factory=dict)


# LLM callback: (prompt, tier) -> response text
LlmFn = Callable[[str, ModelTier], str]
