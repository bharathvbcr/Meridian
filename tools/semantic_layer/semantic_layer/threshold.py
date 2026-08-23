"""Threshold calibration and online auto-tuning for semantic cache."""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np




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
        Select τ* = the smallest τ such that FPR(τ) ≤ max_fpr.

        Because TPR is monotone non-decreasing as τ decreases, the *most permissive*
        feasible threshold maximizes recall subject to the false-positive budget.
        (Picking the largest feasible τ would silently trade away every hit.)

        Args:
            query_vecs: (N, D) normalized query embeddings
            cache_vecs: (N, D) paired cache prompt embeddings
            labels: (N,) 1 if semantically equivalent, 0 otherwise
            max_fpr: maximum allowed false-positive rate
        """
        if grid is None:
            # Span the full plausible range: embedding spaces differ wildly in their
            # similarity distributions, so the whole point of calibration is to find
            # where this space's positives actually live.
            grid = np.linspace(0.05, 0.98, 94)

        sims = np.sum(query_vecs * cache_vecs, axis=1)
        positives = labels.astype(bool)
        negatives = ~positives

        best_tau: float | None = None
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
                # Ascending scan: the first feasible τ already maximizes TPR.
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
                break

        if best_tau is None:
            # No grid point meets the budget: report the conservative ceiling with its real
            # stats instead of an empty success dict.
            tau = float(grid[-1])
            preds = sims >= tau
            tp = int(np.sum(preds & positives))
            fp = int(np.sum(preds & negatives))
            tn = int(np.sum(~preds & negatives))
            fn = int(np.sum(~preds & positives))
            best_tau = tau
            best_stats = {
                "tau": best_tau,
                "fpr": fp / max(fp + tn, 1),
                "tpr": tp / max(tp + fn, 1),
                "tp": tp,
                "fp": fp,
                "tn": tn,
                "fn": fn,
            }

        return best_tau, best_stats

    def should_hit(
        self,
        best_sim: float,
        second_best_sim: float,
        margin: float = 0.04,
    ) -> bool:
        """Apply threshold + ambiguity margin guard."""
        if best_sim < self.threshold:
            return False
        if best_sim - second_best_sim < margin:
            return False
        return True
