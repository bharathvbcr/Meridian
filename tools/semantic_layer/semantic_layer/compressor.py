"""Semantic context compression for RAG — filter irrelevant chunks before LLM."""

from __future__ import annotations

import re
from dataclasses import dataclass

import numpy as np

from semantic_layer.embedder import Embedder
from semantic_layer.types import PipelineConfig

_SECTION_HEADER = re.compile(r"^[A-Z][A-Z0-9 _-]{2,}$")


@dataclass(frozen=True)
class CompressionResult:
    text: str
    original_chars: int
    compressed_chars: int
    chunks_kept: int
    chunks_total: int

    @property
    def chars_saved(self) -> int:
        return self.original_chars - self.compressed_chars


def _split_chunks(text: str, max_chunk_chars: int) -> list[str]:
    """Split on blank lines; subdivide long sections."""
    raw = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    chunks: list[str] = []
    for part in raw:
        if len(part) <= max_chunk_chars:
            chunks.append(part)
        else:
            for line in part.splitlines():
                line = line.strip()
                if line:
                    chunks.append(line[:max_chunk_chars])
    return chunks


class SemanticCompressor:
    """
    Two-stage compression:
    1. Semantic ranking — keep top-k chunks by query similarity (RAG path)
    2. Structural trim — cap bullets per section (Meridian grounding path)
    """

    def __init__(self, embedder: Embedder, config: PipelineConfig) -> None:
        self._embedder = embedder
        self._min_chars = config.compress_min_chars
        self._top_k = config.compress_top_k
        self._max_chunk = config.compress_max_chunk_chars

    def compress(
        self,
        context: str,
        query: str = "",
        max_bullets_per_section: int = 5,
    ) -> CompressionResult:
        original = len(context)
        if original <= self._min_chars:
            return CompressionResult(
                text=context,
                original_chars=original,
                compressed_chars=original,
                chunks_kept=1,
                chunks_total=1,
            )

        if query.strip():
            return self._semantic_filter(context, query)

        trimmed = self._structural_trim(context, max_bullets_per_section)
        return CompressionResult(
            text=trimmed,
            original_chars=original,
            compressed_chars=len(trimmed),
            chunks_kept=0,
            chunks_total=0,
        )

    def _semantic_filter(self, context: str, query: str) -> CompressionResult:
        chunks = _split_chunks(context, self._max_chunk)
        if not chunks:
            return CompressionResult(context, len(context), len(context), 0, 0)

        q_vec = self._embedder.embed(query)
        c_vecs = self._embedder.embed_batch(chunks)
        scores = c_vecs @ q_vec

        # Always retain section headers even if low score
        header_mask = np.array(
            [bool(_SECTION_HEADER.match(c.splitlines()[0] if c else "")) for c in chunks]
        )

        ranked = np.argsort(-scores)
        kept: list[str] = []
        for idx in ranked:
            if len(kept) >= self._top_k and not header_mask[idx]:
                continue
            if scores[idx] < 0.25 and not header_mask[idx]:
                continue
            kept.append(chunks[idx])

        # Preserve original order for readability
        kept_set = set(kept)
        ordered = [c for c in chunks if c in kept_set]
        text = "\n\n".join(ordered)
        return CompressionResult(
            text=text,
            original_chars=len(context),
            compressed_chars=len(text),
            chunks_kept=len(ordered),
            chunks_total=len(chunks),
        )

    @staticmethod
    def _structural_trim(block: str, max_bullets: int) -> str:
        """Mirrors Meridian `SemanticCompressor.compress` — cap bullets per section."""
        lines = block.splitlines()
        out: list[str] = []
        bullets_in_section = 0
        for line in lines:
            if not line.strip():
                out.append("")
                bullets_in_section = 0
            elif not line.startswith("• "):
                out.append(line)
                bullets_in_section = 0
            elif bullets_in_section < max_bullets:
                out.append(line[:160])
                bullets_in_section += 1
        return "\n".join(out).rstrip()
