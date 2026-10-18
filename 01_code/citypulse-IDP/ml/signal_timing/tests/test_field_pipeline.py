"""C8 field pipeline on SYNTHETIC data: approaches on a made-up junction, matching GPS traces to them, GPX reading, and the
pre-registered stopwatch evaluation (kill rule)."""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import pytest

from ml.signal_timing.__main__ import evaluate
from ml.signal_timing.approach import M_PER_DEG, RoadGraph, approaches, match_passes
from ml.signal_timing.ingest import read_any, read_gpx
from ml.signal_timing.learner import learn_bin
from ml.signal_timing.simulate import SignalSpec, simulate_passes

LAT0, LON0 = 13.05, 80.23
KX = M_PER_DEG * math.cos(math.radians(LAT0))


def _cross() -> tuple[RoadGraph, int]:
    """A two-way cross street: nodes every 50 m, 500 m each side of the centre node 0, in four arms."""
    lat, lon, edges = [LAT0], [LON0], []
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        prev = 0
        for k in range(1, 11):
            lat.append(LAT0 + dy * 50 * k / M_PER_DEG)
            lon.append(LON0 + dx * 50 * k / KX)
            n = len(lat) - 1
            edges += [(prev, n), (n, prev)]
            prev = n
    return RoadGraph(np.array(lat), np.array(lon), edges), 0


def test_a_cross_has_four_straight_approaches() -> None:
    g, c = _cross()
    aps = approaches(g, "S", c)
    assert len(aps) == 4
    for ap in aps:
        # Straight through: the far ends are on opposite arms, 250+ m before and 80+ m after.
        (la0, lo0), (la1, lo1) = ap.points[0], ap.points[-1]
        assert math.hypot((la1 - la0) * M_PER_DEG, (lo1 - lo0) * KX) >= 330


def test_a_simulated_trace_is_matched_to_its_approach_and_learned() -> None:
    g, c = _cross()
    ap = next(a for a in approaches(g, "S", c) if abs(a.heading_deg - 90) < 1)  # driving east
    passes = simulate_passes(SignalSpec(90, 45, 7.0), 80, seed=3)
    matched = []
    for t, s in passes:
        s = np.asarray(s)
        lat = LAT0 + np.random.default_rng(1).normal(0, 2, len(s)) / M_PER_DEG
        lon = LON0 + s / KX
        got = match_passes(np.asarray(t), lat, lon, ap)
        assert len(got) == 1
        inner = (s > -245) & (s < 75)  # projection is clipped at the approach's ends, by design
        assert np.allclose(got[0][1][inner], s[inner], atol=0.5)
        matched += got
    r = learn_bin("x", matched)
    assert r.cycle is not None and r.cycle.cycle_s == pytest.approx(90, abs=1)


def test_a_trace_on_the_cross_street_or_going_the_other_way_is_not_matched() -> None:
    g, c = _cross()
    ap = next(a for a in approaches(g, "S", c) if abs(a.heading_deg - 90) < 1)
    t = np.arange(0, 60.0)
    north = (LAT0 + (-250 + 10 * t) / M_PER_DEG, np.full(len(t), LON0))
    west = (np.full(len(t), LAT0), LON0 + (250 - 10 * t) / KX)
    assert match_passes(t, *north, ap) == []
    assert match_passes(t, *west, ap) == []


def test_gpx_and_csv_are_read(tmp_path: Path) -> None:
    (tmp_path / "a.gpx").write_text(
        '<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>'
        '<trkpt lat="13.05" lon="80.23"><time>2026-10-20T03:00:01Z</time></trkpt>'
        '<trkpt lat="13.0501" lon="80.23"><time>2026-10-20T03:00:00Z</time></trkpt>'
        "</trkseg></trk></gpx>",
        encoding="utf-8",
    )
    t, la, _ = read_gpx(tmp_path / "a.gpx")
    assert list(np.diff(t)) == [1.0] and la[0] == 13.0501  # sorted by time
    (tmp_path / "b.csv").write_text('"Time (s)","Latitude (°)","Longitude (°)"\n0.0,13.05,80.23\n1.0,13.0501,80.23\n', encoding="utf-8")
    t, _, _ = read_any(tmp_path / "b.csv", start_epoch=1000.0)
    assert list(t) == [1000.0, 1001.0]


def _learned(site: str, cycle: float | None, passes: int = 40) -> dict:
    return {"site_id": site, "approaches": {f"{site}-a0": {"passes": passes, "bins": {"weekday_am_peak": {"passes": passes, "cycle_s": cycle}}}}}


def _sw(site: str, cycles: list[float]) -> list[dict]:
    return [{"site_id": site, "bin": "weekday_am_peak", "cycle_s": str(c)} for c in cycles]


def test_evaluation_applies_the_kill_rule() -> None:
    good = evaluate([_learned("S1", 92.0), _learned("S2", 118.0), _learned("S3", 60.0)],
                    _sw("S1", [90, 91, 89]) + _sw("S2", [120, 121, 119]) + _sw("S3", [61, 60, 59]))
    assert good["median_abs_error_s_fixed_sites"] == 2.0 and not good["killed"]
    bad = evaluate([_learned("S1", 45.0), _learned("S2", 60.0), _learned("S3", None)],
                   _sw("S1", [90, 91, 89]) + _sw("S2", [120, 121, 119]) + _sw("S3", [61, 60, 59]))
    assert bad["killed"]
    # A police-run junction (stopwatch cycles all over the place) is not a fixed-cycle site and does not count against the learner.
    mixed = evaluate([_learned("S1", 90.0), _learned("S4", None)], _sw("S1", [90, 90, 91]) + _sw("S4", [40, 95, 150]))
    assert mixed["fixed_cycle_sites"] == 1 and not mixed["killed"]
    assert mixed["no_fixed_cycle_agreement"]["learner_none_and_stopwatch_not_fixed"] == 1
