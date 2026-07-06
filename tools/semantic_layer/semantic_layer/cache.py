"""FAISS-backed semantic cache with TTL and LRU eviction."""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from typing import Protocol

import numpy as np

try:
    import faiss

    _HAS_FAISS = True
except ImportError:
    faiss = None  # type: ignore[assignment]
    _HAS_FAISS = False

from semantic_layer.embedder import Embedder
from semantic_layer.threshold import ThresholdTuner
from semantic_layer.types import CacheHit, CacheProvenance, PipelineConfig


class _VectorIndex(Protocol):
    def search(self, query: np.ndarray, k: int) -> tuple[np.ndarray, np.ndarray]: ...
    def rebuild(self, matrix: np.ndarray) -> None: ...


class _FaissIndex:
    def __init__(self, dim: int) -> None:
        self._dim = dim
        self._index: faiss.IndexFlatIP | None = None

    def rebuild(self, matrix: np.ndarray) -> None:
        index = faiss.IndexFlatIP(self._dim)
        if matrix.size:
            index.add(matrix.astype(np.float32))
        self._index = index

    def search(self, query: np.ndarray, k: int) -> tuple[np.ndarray, np.ndarray]:
        assert self._index is not None
        return self._index.search(query.reshape(1, -1).astype(np.float32), k)


class _NumpyIndex:
    """Brute-force fallback when FAISS is unavailable — fine up to ~5k entries."""

    def __init__(self) -> None:
        self._matrix: np.ndarray | None = None

    def rebuild(self, matrix: np.ndarray) -> None:
        self._matrix = matrix.astype(np.float32) if matrix.size else None

    def search(self, query: np.ndarray, k: int) -> tuple[np.ndarray, np.ndarray]:
        if self._matrix is None or len(self._matrix) == 0:
            return np.zeros((1, k), dtype=np.float32), -np.ones((1, k), dtype=np.int64)
        sims = self._matrix @ query.astype(np.float32)
        k = min(k, len(sims))
        top_idx = np.argpartition(-sims, k - 1)[:k]
        top_idx = top_idx[np.argsort(-sims[top_idx])]
        return sims[top_idx].reshape(1, -1), top_idx.reshape(1, -1)


@dataclass
class _CacheEntry:
    prompt: str
    response: str
    vector: np.ndarray
    created_at: float
    last_accessed: float
    provenance: CacheProvenance
    grounding_hash: str = ""
    ttl_seconds: float = 3600.0

    def is_expired(self, now: float) -> bool:
        return (now - self.created_at) > self.ttl_seconds


class SemanticCache:
    """
    Low-latency semantic cache using FAISS IndexFlatIP (inner product = cosine on unit vectors).

    - O(n) rebuild on eviction is acceptable up to ~10k entries (<2 ms)
    - Thread-safe via re-entrant lock
    - LRU eviction when max_entries exceeded
    """

    def __init__(
        self,
        embedder: Embedder,
        config: PipelineConfig,
        tuner: ThresholdTuner | None = None,
    ) -> None:
        self._embedder = embedder
        self._config = config
        self._tuner = tuner or ThresholdTuner(threshold=config.similarity_threshold)
        self._dim = config.embed_dim
        self._max = config.cache_max_entries
        self._default_ttl = config.cache_ttl_seconds
        self._margin = config.similarity_margin

        self._entries: list[_CacheEntry] = []
        self._index: _VectorIndex = _FaissIndex(self._dim) if _HAS_FAISS else _NumpyIndex()
        self._lock = threading.RLock()

    @property
    def size(self) -> int:
        with self._lock:
            return len(self._entries)

    @property
    def threshold(self) -> float:
        return self._tuner.threshold

    def lookup(self, query: str) -> CacheHit | None:
        """Return cached response if cosine similarity exceeds dynamic threshold."""
        with self._lock:
            self._purge_expired()
            if not self._entries:
                return None

            q_vec = self._embedder.embed(query).astype(np.float32)

            # Search top-2 for ambiguity margin
            k = min(2, len(self._entries))
            sims, indices = self._index.search(q_vec, k)
            best_sim = float(sims[0, 0])
            second_sim = float(sims[0, 1]) if k > 1 else 0.0
            best_idx = int(indices[0, 0])

            if best_idx < 0 or best_idx >= len(self._entries):
                return None

            entry = self._entries[best_idx]

            # OOD guard: if nothing in cache is even remotely similar, skip
            if best_sim < self._config.ood_max_sim_floor:
                return None

            if not self._tuner.should_hit(
                q_vec, entry.vector, best_sim, second_sim, self._margin
            ):
                return None

            now = time.monotonic()
            entry.last_accessed = now
            return CacheHit(
                response=entry.response,
                similarity=best_sim,
                provenance=CacheProvenance.CACHED,
                entry_id=best_idx,
            )

    def store(
        self,
        prompt: str,
        response: str,
        provenance: CacheProvenance = CacheProvenance.LARGE_LLM,
        grounding_hash: str = "",
        ttl_seconds: float | None = None,
    ) -> None:
        if not response.strip():
            return

        vec = self._embedder.embed(prompt).astype(np.float32)
        now = time.monotonic()

        with self._lock:
            self._entries.insert(
                0,
                _CacheEntry(
                    prompt=prompt,
                    response=response.strip(),
                    vector=vec,
                    created_at=now,
                    last_accessed=now,
                    provenance=provenance,
                    grounding_hash=grounding_hash,
                    ttl_seconds=ttl_seconds or self._default_ttl,
                ),
            )
            self._evict_lru()
            self._rebuild_index()

    def invalidate_by_grounding(self, grounding_hash: str) -> int:
        """Remove entries tied to stale grounding context."""
        with self._lock:
            before = len(self._entries)
            self._entries = [e for e in self._entries if e.grounding_hash != grounding_hash]
            removed = before - len(self._entries)
            if removed:
                self._rebuild_index()
            return removed

    def flush(self) -> None:
        with self._lock:
            self._entries.clear()
            self._index.rebuild(np.empty((0, self._dim)))

    def on_feedback(self, hit: CacheHit, positive: bool) -> None:
        self._tuner.on_feedback(positive)

    def _purge_expired(self) -> None:
        now = time.monotonic()
        before = len(self._entries)
        self._entries = [e for e in self._entries if not e.is_expired(now)]
        if len(self._entries) != before:
            self._rebuild_index()

    def _evict_lru(self) -> None:
        while len(self._entries) > self._max:
            self._entries.pop()

    def _rebuild_index(self) -> None:
        if not self._entries:
            self._index.rebuild(np.empty((0, self._dim)))
            return
        matrix = np.vstack([e.vector for e in self._entries]).astype(np.float32)
        self._index.rebuild(matrix)
