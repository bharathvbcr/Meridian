"""Threshold calibration and online auto-tuning for semantic cache."""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from semantic_layer.embedder import cosine


@dataclass
class ThresholdTuner:
    """
    Maintains dynamic similarity threshold τ to balance hit rate vs false positives.

    Offline: use `calibrate()` with labeled pairs.
    Online: call `on_feedback()` after user thumbs-up/down on cached answers.
    """

    threshold: float = 0.86
    tau_min: float = 0.78
    tau_max: float = 0.95
    fp_delta: float = 0.005
    hit_delta: float = 0.002
    false_positives: int = 0
    confirmed_hits: int = 0
    _history: list[float] = field(default_factory=list)

    def on_feedback(self, positive: bool) -> None:
        if positive:
            self.confirmed_hits += 1
            self.threshold = max(self.tau_min, self.threshold - self.hit_delta)
        else:
            self.false_positives += 1
            self.threshold = min(self.tau_max, self.threshold + self.fp_delta)
        self._history.append(self.threshold)

    @staticmethod
    def calibrate(
        query_vecs: np.ndarray,
        cache_vecs: np.ndarray,
        labels: np.ndarray,
        max_fpr: float = 0.02,
        grid: np.ndarray | None = None,
    ) -> tuple[float, dict[str, float]]:
        """
        Select τ* = max τ such that FPR(τ) ≤ max_fpr.

        Args:
            query_vecs: (N, D) normalized query embeddings
            cache_vecs: (N, D) paired cache prompt embeddings
            labels: (N,) 1 if semantically equivalent, 0 otherwise
            max_fpr: maximum allowed false-positive rate
        """
        if grid is None:
            grid = np.linspace(0.70, 0.98, 29)

        sims = np.sum(query_vecs * cache_vecs, axis=1)
        positives = labels.astype(bool)
        negatives = ~positives

        best_tau = grid[0]
        best_stats: dict[str, float] = {}

        for tau in grid:
            preds = sims >= tau
            tp = int(np.sum(preds & positives))
            fp = int(np.sum(preds & negatives))
            tn = int(np.sum(~preds & negatives))
            fn = int(np.sum(~preds & positives))
            fpr = fp / max(fp + tn, 1)
            tpr = tp / max(tp + fn, 1)
            if fpr <= max_fpr:
                best_tau = float(tau)
                best_stats = {
                    "tau": best_tau,
                    "fpr": fpr,
                    "tpr": tpr,
                    "tp": tp,
                    "fp": fp,
                    "tn": tn,
                    "fn": fn,
                }

        return best_tau, best_stats

    def should_hit(
        self,
        query_vec: np.ndarray,
        best_vec: np.ndarray,
        best_sim: float,
        second_best_sim: float,
        margin: float = 0.04,
    ) -> bool:
        """Apply threshold + ambiguity margin guard."""
        if best_sim < self.threshold:
            return False
        if best_sim - second_best_sim < margin:
            return False
        # redundant cosine check for non-FAISS paths
        _ = cosine(query_vec, best_vec)
        return True
