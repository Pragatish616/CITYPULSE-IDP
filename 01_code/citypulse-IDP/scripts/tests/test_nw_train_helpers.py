"""Checks on the numeric helpers behind the nationwide model (ADR-025): the rolling features and the weighted average precision."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

pytest.importorskip("sklearn")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import nw_train as nw  # noqa: E402
from sklearn.metrics import average_precision_score  # noqa: E402


def test_rolling_sum_matches_a_plain_loop_including_the_first_days():
    rng = np.random.default_rng(1)
    P = rng.random((3, 40)).astype(np.float32) * 20
    for k in (3, 7, 30):
        got = nw.rolling_sum(P, k)
        for d in range(3):
            for t in range(40):
                assert got[d, t] == pytest.approx(P[d, max(0, t - k + 1) : t + 1].sum(), rel=1e-5), (k, d, t)


def test_rolling_max_matches_a_plain_loop_including_the_first_days():
    rng = np.random.default_rng(2)
    P = rng.random((2, 30)).astype(np.float32)
    got = nw.rolling_max(P, 7)
    for d in range(2):
        for t in range(30):
            assert got[d, t] == P[d, max(0, t - 6) : t + 1].max()


def test_a_days_features_never_use_future_rain():
    P = np.zeros((1, 30), dtype=np.float32)
    before = nw.rolling_sum(P, 7).copy()
    P[0, 15] = 99.0
    after = nw.rolling_sum(P, 7)
    assert np.array_equal(before[0, :15], after[0, :15]), "rain on day 15 changed a feature of an earlier day"
    # the 7-day sum ending on days 15 to 21 holds that rain; the sum ending on day 22 no longer does
    assert np.all(after[0, 15:22] == 99.0) and after[0, 22] == 0.0


def test_weighted_average_precision_with_unit_weights_equals_sklearn():
    rng = np.random.default_rng(3)
    y = rng.random(500) < 0.1
    s = rng.random(500)
    order = np.argsort(-s)
    assert nw.weighted_ap(y[order].astype(float), np.ones(500)) == pytest.approx(average_precision_score(y, s), abs=1e-9)


def test_doubling_a_rows_weight_is_the_same_as_repeating_the_row():
    y = np.array([1, 0, 1, 0, 0, 1], dtype=float)  # already in descending score order
    w = np.array([2, 1, 1, 3, 1, 1], dtype=float)
    repeated_y = np.repeat(y, w.astype(int))
    assert nw.weighted_ap(y, w) == pytest.approx(nw.weighted_ap(repeated_y, np.ones(len(repeated_y))), abs=1e-12)
