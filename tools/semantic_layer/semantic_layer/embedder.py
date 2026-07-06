"""Low-latency embedding with sentence-transformers and trigram fallback."""

from __future__ import annotations

import hashlib
import re
import time
from typing import Protocol

import numpy as np

_WHITESPACE = re.compile(r"\s+")


class Embedder(Protocol):
    def embed(self, text: str) -> np.ndarray: ...
    def embed_batch(self, texts: list[str]) -> np.ndarray: ...


class TrigramEmbedder:
    """
    Character trigram hash embedding — mirrors Meridian mobile `SemanticEmbedder`.
    Zero ML deps, ~0.1 ms per query, stable across platforms.
    """

    def __init__(self, dim: int = 384) -> None:
        self.dim = dim

    def embed(self, text: str) -> np.ndarray:
        return self.embed_batch([text])[0]

    def embed_batch(self, texts: list[str]) -> np.ndarray:
        out = np.zeros((len(texts), self.dim), dtype=np.float32)
        for i, raw in enumerate(texts):
            normalized = _WHITESPACE.sub(" ", raw.lower().strip())
            if not normalized:
                continue
            padded = f"  {normalized} "
            for j in range(len(padded) - 2):
                gram = padded[j : j + 3]
                bucket = int(hashlib.md5(gram.encode()).hexdigest(), 16) % self.dim
                out[i, bucket] += 1.0
            norm = max(float(np.linalg.norm(out[i])), 1e-6)
            out[i] /= norm
        return out


class SentenceTransformerEmbedder:
    """
    Production embedder using all-MiniLM-L6-v2 (384-dim).
    Prefer CPU when GPU is occupied by the primary LLM.
    """

    def __init__(
        self,
        model_name: str = "sentence-transformers/all-MiniLM-L6-v2",
        device: str = "cpu",
    ) -> None:
        from sentence_transformers import SentenceTransformer

        self._model = SentenceTransformer(model_name, device=device)
        self._device = device

    def embed(self, text: str) -> np.ndarray:
        return self.embed_batch([text])[0]

    def embed_batch(self, texts: list[str]) -> np.ndarray:
        vecs = self._model.encode(
            texts,
            convert_to_numpy=True,
            normalize_embeddings=True,
            show_progress_bar=False,
            batch_size=min(32, max(1, len(texts))),
        )
        return np.asarray(vecs, dtype=np.float32)


class ResilientEmbedder:
    """Primary embedder with automatic fallback on failure or timeout."""

    def __init__(
        self,
        primary: Embedder,
        fallback: Embedder | None = None,
        timeout_ms: float = 50.0,
    ) -> None:
        self._primary = primary
        self._fallback = fallback or TrigramEmbedder()
        self._timeout_ms = timeout_ms

    def embed(self, text: str) -> np.ndarray:
        return self.embed_batch([text])[0]

    def embed_batch(self, texts: list[str]) -> np.ndarray:
        t0 = time.perf_counter()
        try:
            vecs = self._primary.embed_batch(texts)
            elapsed_ms = (time.perf_counter() - t0) * 1000
            if elapsed_ms > self._timeout_ms:
                return self._fallback.embed_batch(texts)
            return vecs
        except Exception:
            return self._fallback.embed_batch(texts)


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    """Dot product of L2-normalized vectors."""
    return float(np.dot(a, b))
