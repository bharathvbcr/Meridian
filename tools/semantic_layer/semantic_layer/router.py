"""Intent/complexity-based semantic router for model tier selection."""

from __future__ import annotations

import re
from dataclasses import dataclass

import numpy as np

from semantic_layer.embedder import Embedder
from semantic_layer.types import ModelTier, PipelineConfig

_WH_WORDS = re.compile(
    r"\b(why|how|explain|analyze|compare|evaluate|design|implement|debug|optimize)\b",
    re.I,
)
_MULTI_STEP = re.compile(
    r"\b(then|after that|step|first|second|finally|additionally)\b",
    re.I,
)
_CODE_BLOCK = re.compile(r"```|def |class |function |import ")


@dataclass(frozen=True)
class RouteDecision:
    tier: ModelTier
    complexity_score: float
    reasons: tuple[str, ...]


class SemanticRouter:
    """
    Routes prompts to SMALL (1–3B) or LARGE (8–70B) models.

    Combines cheap heuristics with optional embedding distance to
    pre-computed simple/complex centroids for domain adaptation.
    """

    def __init__(
        self,
        embedder: Embedder,
        config: PipelineConfig,
        simple_centroid: np.ndarray | None = None,
        complex_centroid: np.ndarray | None = None,
    ) -> None:
        self._embedder = embedder
        self._config = config
        self._threshold = config.router_threshold
        self._simple = simple_centroid
        self._complex = complex_centroid

        # Default centroids from canonical examples (computed lazily)
        self._centroids_ready = simple_centroid is not None and complex_centroid is not None

    def _ensure_centroids(self) -> None:
        if self._centroids_ready:
            return
        simple_prompts = [
            "what time is it",
            "convert 3pm to utc",
            "list my meetings today",
            "timezone for tokyo",
        ]
        complex_prompts = [
            "explain why dst transitions cause scheduling bugs across zones",
            "design a distributed cache invalidation strategy",
            "compare fair meeting slot algorithms and recommend one",
        ]
        self._simple = self._embedder.embed_batch(simple_prompts).mean(axis=0)
        self._complex = self._embedder.embed_batch(complex_prompts).mean(axis=0)
        self._centroids_ready = True

    def route(self, prompt: str, has_rag_context: bool = False) -> RouteDecision:
        reasons: list[str] = []
        score = 0.0

        # Length signal
        length_norm = min(len(prompt) / 500.0, 1.0)
        score += 0.25 * length_norm
        if length_norm > 0.5:
            reasons.append("long_prompt")

        # WH / reasoning verbs
        if _WH_WORDS.search(prompt):
            score += 0.25
            reasons.append("reasoning_verb")

        # Multi-step instructions
        if _MULTI_STEP.search(prompt):
            score += 0.20
            reasons.append("multi_step")

        # Code / technical content
        if _CODE_BLOCK.search(prompt):
            score += 0.20
            reasons.append("technical")

        # RAG context increases effective complexity
        if has_rag_context:
            score += 0.10
            reasons.append("rag_context")

        # Embedding distance to centroids
        self._ensure_centroids()
        assert self._simple is not None and self._complex is not None
        vec = self._embedder.embed(prompt)
        sim_simple = float(np.dot(vec, self._simple))
        sim_complex = float(np.dot(vec, self._complex))
        centroid_signal = max(0.0, sim_complex - sim_simple)
        score += 0.30 * centroid_signal
        if centroid_signal > 0.15:
            reasons.append("complex_embedding")

        tier = ModelTier.SMALL if score < self._threshold else ModelTier.LARGE
        return RouteDecision(tier=tier, complexity_score=score, reasons=tuple(reasons))
