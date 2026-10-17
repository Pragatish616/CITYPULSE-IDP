"""C5 conformal flags on SYNTHETIC scores: the guarantee holds when calibration and test are exchangeable, and the edge cases are safe."""

from __future__ import annotations

import math

import numpy as np
import pytest

from ml.conformal.flags import fit_thresholds, flag, positive_threshold, rates


def test_threshold_is_the_k_th_smallest_positive() -> None:
    # n = 19, alpha = 0.1: k = floor(0.1 * 20) = 2, so the second smallest.
    assert positive_threshold(list(range(19, 0, -1)), 0.1) == 2.0


def test_too_few_positives_flag_everything() -> None:
    assert positive_threshold([0.3, 0.9], 0.1) == -math.inf
    assert positive_threshold([], 0.1) == -math.inf


def test_bad_alpha_or_scores_are_rejected() -> None:
    with pytest.raises(ValueError):
        positive_threshold([0.5], 0.0)
    with pytest.raises(ValueError):
        positive_threshold([float("nan")], 0.1)


def test_coverage_meets_nominal_on_exchangeable_synthetic_data() -> None:
    rng = np.random.default_rng(0)
    covs = []
    for _ in range(300):
        n = 400
        labels = rng.random(n) < 0.2
        scores = np.where(labels, rng.beta(3, 2, n), rng.beta(2, 3, n))
        groups = rng.choice(["flood", "waterlogging"], n)
        half = rng.permutation(n)
        cal, test = half[: n // 2], half[n // 2 :]
        th = fit_thresholds(scores[cal], labels[cal].astype(int), groups[cal], 0.1)
        f = flag(scores[test], groups[test], th)
        covs.append(rates(f, labels[test].astype(int)).coverage)
    # Marginal guarantee: the mean over splits is at least 1 - alpha (up to Monte Carlo noise).
    assert np.mean(covs) >= 0.89


def test_unseen_group_is_flagged_and_rates_count() -> None:
    f = flag([0.1, 0.9], ["new", "flood"], {"flood": 0.5})
    assert f.tolist() == [True, True]
    r = rates(np.array([True, False, True]), [1, 1, 0])
    assert (r.coverage, r.false_flag, r.positives, r.negatives) == (0.5, 1.0, 2, 1)
