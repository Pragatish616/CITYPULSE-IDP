"""C8 signal-timing learner, on SIMULATED passes only (ml/signal_timing/simulate.py). These check the method recovers what was put in;
they say nothing about real Chennai signals."""

from __future__ import annotations

import numpy as np
import pytest

from ml.signal_timing.learner import LearnerConfig, default_bin, estimate_cycle, find_stop, learn, learn_bin, pass_delay
from ml.signal_timing.simulate import SignalSpec, simulate_passes, simulate_random_signal


@pytest.mark.parametrize(("cycle", "red"), [(60, 30), (90, 45), (120, 70), (150, 90)])
def test_cycle_and_red_are_recovered(cycle: float, red: float) -> None:
    r = learn_bin("sim", simulate_passes(SignalSpec(cycle, red, offset_s=13.0), 200, seed=1))
    assert r.cycle is not None
    # The largest well-fitting candidate, not a sub-multiple (60 s fits a 120 s signal just as tightly).
    assert r.cycle.cycle_s == pytest.approx(cycle, abs=1.0)
    assert r.cycle.resultant > 0.9
    # Red is biased low by design (quantile / q, brief queue stops); within 12 %.
    assert r.red_s is not None
    assert red * 0.88 <= r.red_s <= red * 1.02


def test_a_sparse_sample_still_finds_the_cycle() -> None:
    # One car in five carries a recording phone.
    passes = simulate_passes(SignalSpec(120, 60), 400, seed=7, sampled_fraction=0.2)
    r = learn_bin("sim", passes)
    assert r.cycle is not None and r.cycle.cycle_s == pytest.approx(120, abs=1.0)


def test_a_signal_without_a_fixed_cycle_is_not_given_one() -> None:
    r = learn_bin("sim", simulate_random_signal(200, seed=2))
    assert r.cycle is None
    assert any("no fixed cycle" in n for n in r.notes)


def test_too_few_passes_say_so_instead_of_guessing() -> None:
    r = learn_bin("sim", simulate_passes(SignalSpec(90, 45), 6, seed=3))
    assert r.cycle is None
    assert r.delay is None
    assert any("no delay estimate" in n for n in r.notes)


def test_delay_from_noisy_gps_matches_the_noise_free_delay() -> None:
    spec = SignalSpec(120, 70, offset_s=5.0)
    noisy = learn_bin("sim", simulate_passes(spec, 200, seed=11)).delay
    clean = learn_bin("sim", simulate_passes(spec, 200, seed=11, gps_noise_m=0.0)).delay
    assert noisy is not None and clean is not None
    assert noisy.passes == clean.passes == 200
    assert noisy.median_s == pytest.approx(clean.median_s, abs=2.0)
    assert noisy.p85_s == pytest.approx(clean.p85_s, abs=3.0)


def test_a_car_that_never_stops_loses_almost_no_time() -> None:
    t = np.arange(0, 40, 1.0)
    s = -250 + 10 * t
    assert find_stop((t, s)) is None
    d = pass_delay((t, s))
    assert d is not None and d < 0.5


def test_a_stop_and_its_departure_are_found() -> None:
    t = np.arange(0, 80, 1.0)
    s = np.where(t < 20, -250 + 10 * t, np.where(t < 50, -50.0, -50 + 10 * (t - 50)))
    st = find_stop((t, s))
    assert st is not None
    assert st.s == pytest.approx(-50, abs=1)
    assert st.end == pytest.approx(50, abs=3)
    assert st.duration == pytest.approx(30, abs=6)


def test_sub_multiples_are_not_chosen() -> None:
    # Exact green starts of a 150 s signal: 50 and 75 s fit perfectly too; the estimate must be 150.
    est = estimate_cycle([1000 + 150 * k for k in range(20)], LearnerConfig())
    assert est is not None and est.cycle_s == pytest.approx(150, abs=0.5)


def test_bins_are_in_indian_time() -> None:
    # 2026-10-12 is a Monday. 03:00 UTC is 08:30 IST (morning peak); 13:00 UTC is 18:30 IST (evening peak).
    assert default_bin(1_791_774_000 - 1_791_774_000 % 86400 + 3 * 3600) == "weekday_am_peak"
    assert default_bin(1_791_774_000 - 1_791_774_000 % 86400 + 13 * 3600) == "weekday_pm_peak"


def test_learn_groups_by_bin() -> None:
    passes = simulate_passes(SignalSpec(90, 40), 120, seed=5)
    out = learn(passes, bin_of=lambda t: "a" if int(t) % 2 else "b")
    assert set(out) <= {"a", "b"}
    assert sum(r.passes for r in out.values()) == len(passes)


def test_bad_input_is_rejected() -> None:
    with pytest.raises(ValueError):
        find_stop(([0, 1, 1, 2, 3, 4], [-10, -9, -8, -7, -6, -5]))
