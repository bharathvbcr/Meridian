"""End-to-end semantic layer orchestrator."""

from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass, field

from semantic_layer.cache import SemanticCache
from semantic_layer.compressor import SemanticCompressor
from semantic_layer.embedder import ResilientEmbedder, SentenceTransformerEmbedder, TrigramEmbedder
from semantic_layer.router import SemanticRouter
from semantic_layer.threshold import ThresholdTuner
from semantic_layer.types import (
    CacheProvenance,
    LlmFn,
    ModelTier,
    PipelineConfig,
    PipelineResult,
)


def _grounding_hash(context: str) -> str:
    return hashlib.sha256(context.encode()).hexdigest()[:16]


@dataclass
class SemanticPipeline:
    """
    Production orchestrator: cache → compress → route → LLM → store.

    Target semantic-layer overhead: <15 ms P95 (excluding LLM inference).
    """

    config: PipelineConfig = field(default_factory=PipelineConfig)
    _cache: SemanticCache = field(init=False)
    _router: SemanticRouter = field(init=False)
    _compressor: SemanticCompressor = field(init=False)
    _embedder: ResilientEmbedder = field(init=False)

    def __post_init__(self) -> None:
        device = "cuda" if self.config.use_gpu_embedder else "cpu"
        try:
            primary = SentenceTransformerEmbedder(self.config.embed_model, device=device)
        except Exception:
            primary = TrigramEmbedder(self.config.embed_dim)

        self._embedder = ResilientEmbedder(primary, TrigramEmbedder(self.config.embed_dim))
        tuner = ThresholdTuner(
            threshold=self.config.similarity_threshold,
            tau_min=self.config.threshold_min,
            tau_max=self.config.threshold_max,
            fp_delta=self.config.threshold_fp_delta,
            hit_delta=self.config.threshold_hit_delta,
        )
        self._cache = SemanticCache(self._embedder, self.config, tuner)
        self._router = SemanticRouter(self._embedder, self.config)
        self._compressor = SemanticCompressor(self._embedder, self.config)

    @property
    def cache(self) -> SemanticCache:
        return self._cache

    def process(
        self,
        query: str,
        context_chunks: list[str] | None = None,
        llm_fn: LlmFn | None = None,
        skip_cache: bool = False,
        time_sensitive: bool = False,
    ) -> PipelineResult:
        """
        Run the full semantic pipeline.

        Args:
            query: User prompt
            context_chunks: Optional RAG / grounding blocks
            llm_fn: Callable(prompt, tier) -> response; required on cache miss
            skip_cache: Force inference (e.g. admin override)
            time_sensitive: Use short TTL and bypass cache read
        """
        t0 = time.perf_counter()
        context = "\n\n".join(context_chunks) if context_chunks else ""
        g_hash = _grounding_hash(context) if context else ""

        # --- Stage 1: Semantic cache ---
        if not skip_cache and not time_sensitive:
            hit = self._cache.lookup(query)
            if hit is not None:
                elapsed = (time.perf_counter() - t0) * 1000
                return PipelineResult(
                    text=hit.response,
                    route=ModelTier.SMALL,
                    cache_hit=True,
                    provenance=CacheProvenance.CACHED,
                    latency_ms=elapsed,
                    metadata={"similarity": hit.similarity},
                )

        # --- Stage 2: Context compression ---
        compression = self._compressor.compress(context, query=query)
        compressed_context = compression.text

        # --- Stage 3: Semantic routing ---
        route = self._router.route(query, has_rag_context=bool(compressed_context))

        # --- Stage 4: LLM inference ---
        if llm_fn is None:
            elapsed = (time.perf_counter() - t0) * 1000
            return PipelineResult(
                text="",
                route=route.tier,
                cache_hit=False,
                provenance=CacheProvenance.LARGE_LLM,
                latency_ms=elapsed,
                tokens_saved=compression.chars_saved,
                metadata={
                    "route_score": route.complexity_score,
                    "route_reasons": route.reasons,
                    "compressed_context": compressed_context,
                },
            )

        prompt = self._build_prompt(query, compressed_context)
        response = llm_fn(prompt, route.tier)
        provenance = (
            CacheProvenance.SMALL_LLM
            if route.tier == ModelTier.SMALL
            else CacheProvenance.LARGE_LLM
        )

        # --- Stage 5: Async-style cache store (inline for simplicity) ---
        if not time_sensitive and response.strip():
            ttl = 60.0 if time_sensitive else self.config.cache_ttl_seconds
            self._cache.store(
                prompt=query,
                response=response,
                provenance=provenance,
                grounding_hash=g_hash,
                ttl_seconds=ttl,
            )

        elapsed = (time.perf_counter() - t0) * 1000
        return PipelineResult(
            text=response,
            route=route.tier,
            cache_hit=False,
            provenance=provenance,
            latency_ms=elapsed,
            tokens_saved=compression.chars_saved,
            metadata={
                "route_score": route.complexity_score,
                "route_reasons": route.reasons,
            },
        )

    @staticmethod
    def _build_prompt(query: str, context: str) -> str:
        if not context.strip():
            return query
        return f"Context:\n{context}\n\nUser: {query}"
