"""C3 CML rain retrieval on SYNTHETIC links. The k-R coefficients here (A_TEST, B_TEST) are test values chosen for these tests, not
ITU-R P.838 values for any frequency; the tests check that the chain inverts its own forward model and handles the hard cases."""

from __future__ import annotations

import numpy as np
import pytest

from ml.cml_rain.retrieval import (
    Link,
    NeighbourRule,
    RetrievalConfig,
    SingleLinkRule,
    baseline,
    rain_rate,
    wet_neighbours,
    wet_single,
)

A_TEST, B_TEST = 0.1, 1.0  # test values only


def _link(i: int = 0, lat: float = 13.05, length: float = 3.0) -> Link:
    return Link(f"L{i}", length, A_TEST, B_TEST, lat, 80.20 + 0.001 * i, lat + 0.02, 80.21 + 0.001 * i)


def _series(rain: np.ndarray, link: Link, *, seed: int, wet_antenna: float = 0.0, noise: float = 0.1) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = len(rain)
    base = 50.0 + 0.3 * np.sin(np.arange(n) * 2 * np.pi / 1440)  # slow daily wander
    att = link.a * np.power(rain, link.b) * link.length_km
    return base + att + np.where(rain > 0, wet_antenna, 0.0) + rng.normal(0, noise, n)


def _event(n: int = 1440, start: int = 600, length: int = 120, peak: float = 40.0) -> np.ndarray:
    r = np.zeros(n)
    t = np.arange(length)
    r[start : start + length] = peak * np.sin(np.pi * t / length) ** 2
    return r


CFG = RetrievalConfig(baseline_window=240, wet_antenna_db=0.0)
SINGLE = SingleLinkRule(std_window=15, std_threshold_db=0.4)


def test_a_dry_day_gives_no_rain() -> None:
    link = _link()
    loss = _series(np.zeros(1440), link, seed=1)
    wet = wet_single(loss, SINGLE)
    assert wet.mean() < 0.01
    assert np.nansum(rain_rate(link, loss, wet, CFG)) / 60 < 0.5  # under half a millimetre over the day


def test_a_rain_event_is_recovered_when_wet_dry_is_known() -> None:
    link, rain = _link(), _event()
    loss = _series(rain, link, seed=2)
    r = rain_rate(link, loss, rain > 0.5, CFG)
    total_true = rain.sum() / 60
    total_est = np.nansum(r) / 60
    assert total_est == pytest.approx(total_true, rel=0.1)
    assert np.nanmax(r) == pytest.approx(40, rel=0.15)


def test_single_link_rule_finds_most_of_the_event_but_not_its_steady_middle() -> None:
    link, rain = _link(), _event()
    wet = wet_single(_series(rain, link, seed=3), SINGLE)
    assert wet[600:720].mean() > 0.75  # most of the two-hour event
    assert wet[:500].mean() < 0.02
    # Known weakness of the variance rule: near the peak the loss is high but changes slowly, so some minutes there read as dry
    # (and give zero rain). The neighbour rule, which looks at the level rather than its variance, does not have this problem.
    assert wet[640:680].mean() < 1.0


def test_ignoring_the_wet_antenna_overestimates_rain() -> None:
    link, rain = _link(), _event(peak=10.0)
    loss = _series(rain, link, seed=4, wet_antenna=2.0)
    wet = rain > 0.5
    naive = np.nansum(rain_rate(link, loss, wet, CFG))
    corrected = np.nansum(rain_rate(link, loss, wet, RetrievalConfig(240, 2.0)))
    true = rain.sum()
    assert naive > 1.3 * true
    assert corrected == pytest.approx(true, rel=0.15)


def test_neighbours_reject_a_fade_only_one_link_sees() -> None:
    links = [_link(i) for i in range(4)]
    n = 1440
    losses = [_series(np.zeros(n), lk, seed=10 + i) for i, lk in enumerate(links)]
    losses[0][700:760] += 6.0  # a non-rain fade on link 0 only
    rule = NeighbourRule(radius_km=10, own_excess_db=1.0, neighbour_excess_db=0.7, reference_window=240)
    wet = wet_neighbours(links, losses, rule)
    assert wet[0][700:760].mean() == 0.0
    # Real rain over all four links is found on each.
    rain = _event()
    losses = [_series(rain, lk, seed=20 + i) for i, lk in enumerate(links)]
    wet = wet_neighbours(links, losses, rule)
    for w in wet:
        assert w[660:680].mean() > 0.8


def test_a_link_without_neighbours_is_not_guessed_wet() -> None:
    lonely = [_link(0), Link("far", 3.0, A_TEST, B_TEST, 13.9, 80.2, 13.92, 80.21)]
    rain = _event()
    losses = [_series(rain, lk, seed=30) for lk in lonely]
    wet = wet_neighbours(lonely, losses, NeighbourRule(5, 1.0, 0.7, 240))
    assert not wet[0].any()


def test_gaps_stay_gaps_and_the_baseline_waits_for_dry_data() -> None:
    link = _link()
    loss = _series(np.zeros(100), link, seed=5)
    loss[10:20] = np.nan
    r = rain_rate(link, loss, np.zeros(100, dtype=bool), CFG)
    assert np.isnan(r[10:20]).all()
    assert np.isnan(baseline(loss, np.ones(100, dtype=bool), 10)).all()


def test_coefficients_are_required_and_positive() -> None:
    with pytest.raises(ValueError):
        Link("bad", 3.0, 0.0, 1.0, 13, 80, 13.01, 80.01)
    with pytest.raises(TypeError):
        Link("missing", 3.0)  # type: ignore[call-arg]
