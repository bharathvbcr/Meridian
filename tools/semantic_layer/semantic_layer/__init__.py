"""
Semantic Layer — production reference implementation.

Low-latency semantic caching, routing, and context compression for LLM pipelines.
"""

from semantic_layer.cache import SemanticCache
from semantic_layer.compressor import CompressionResult, SemanticCompressor
from semantic_layer.embedder import (
    ResilientEmbedder,
    SentenceTransformerEmbedder,
    TrigramEmbedder,
    cosine,
)
from semantic_layer.pipeline import SemanticPipeline
from semantic_layer.router import RouteDecision, SemanticRouter
from semantic_layer.threshold import ThresholdTuner
from semantic_layer.types import (
    CacheHit,
    CacheProvenance,
    LlmFn,
    ModelTier,
    PipelineConfig,
    PipelineResult,
)

__all__ = [
    "SemanticPipeline",
    "SemanticCache",
    "SemanticRouter",
    "SemanticCompressor",
    "ThresholdTuner",
    "ResilientEmbedder",
    "SentenceTransformerEmbedder",
    "TrigramEmbedder",
    "PipelineConfig",
    "PipelineResult",
    "CacheHit",
    "CacheProvenance",
    "ModelTier",
    "LlmFn",
    "RouteDecision",
    "CompressionResult",
    "cosine",
]
