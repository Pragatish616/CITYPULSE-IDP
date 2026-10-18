"""Label-conditional (Mondrian) split conformal thresholds for flagging edges (C5, PREREGISTRATION.md).

For each group, the threshold is set on the calibration positives so that, under exchangeability, at least 1 - alpha of positives in the
same group score at or above it. It is a statement about how often a score covered a label, not about any road's condition.
"""

from __future__ import annotations

import math
from collections.abc import Hashable, Sequence
from dataclasses import dataclass

import numpy as np


def positive_threshold(positive_scores: Sequence[float], alpha: float) -> float:
    """tau = the k-th smallest positive score, k = floor(alpha * (n + 1)); -inf when k = 0 (too few positives: flag everything)."""
    if not 0 < alpha < 1:
        raise ValueError("alpha must be in (0, 1)")
    s = np.sort(np.asarray(positive_scores, dtype=float))
    if np.any(~np.isfinite(s)):
        raise ValueError("scores must be finite")
    k = math.floor(alpha * (len(s) + 1))
    return -math.inf if k == 0 else float(s[k - 1])


def fit_thresholds(
    scores: Sequence[float], labels: Sequence[int], groups: Sequence[Hashable], alpha: float
) -> dict[Hashable, float]:
    """One threshold per group, from that group's positives."""
    sc = np.asarray(scores, dtype=float)
    lb = np.asarray(labels)
    gr = np.asarray(groups, dtype=object)
    return {g: positive_threshold(sc[(gr == g) & (lb == 1)], alpha) for g in dict.fromkeys(groups)}


def flag(scores: Sequence[float], groups: Sequence[Hashable], thresholds: dict[Hashable, float]) -> np.ndarray:
    """Flag each edge whose score reaches its group's threshold. A group with no threshold (unseen in calibration) is flagged."""
    return np.array([s >= thresholds.get(g, -math.inf) for s, g in zip(scores, groups, strict=True)], dtype=bool)


@dataclass(frozen=True)
class Rates:
    coverage: float  # flagged share of positives (nan if none)
    false_flag: float  # flagged share of negatives (nan if none)
    positives: int
    negatives: int


def rates(flags: np.ndarray, labels: Sequence[int]) -> Rates:
    lb = np.asarray(labels)
    pos, neg = lb == 1, lb == 0
    return Rates(
        coverage=float(flags[pos].mean()) if pos.any() else math.nan,
        false_flag=float(flags[neg].mean()) if neg.any() else math.nan,
        positives=int(pos.sum()),
        negatives=int(neg.sum()),
    )


def route_scores(routes: Sequence[Sequence[int]], score: dict[int, float], positive: set[int]) -> list[float]:
    """C5b route nonconformity: for each route with at least one positive edge, the lowest score among its positive edges (routes
    without a positive edge have nothing to cover and are left out)."""
    return [min(score.get(e, 0.0) for e in r if e in positive) for r in routes if any(e in positive for e in r)]


def route_threshold(routes: Sequence[Sequence[int]], score: dict[int, float], positive: set[int], alpha: float) -> float:
    """tau such that, for exchangeable routes, P(every positive edge on a route scores >= tau | it has one) >= 1 - alpha."""
    return positive_threshold(route_scores(routes, score, positive), alpha)


def route_covered(route: Sequence[int], score: dict[int, float], positive: set[int], tau: float) -> bool | None:
    """Whether every positive edge on the route is flagged; ``None`` when the route has no positive edge."""
    pos = [e for e in route if e in positive]
    if not pos:
        return None
    return all(score.get(e, 0.0) >= tau for e in pos)
