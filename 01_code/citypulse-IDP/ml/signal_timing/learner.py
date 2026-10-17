"""Learning a traffic signal's timing and its waiting time from vehicle passes (C8).

Input is one approach of one signal, as a list of passes. A pass is a time series (t seconds, s metres) where s is the distance along the
road relative to the stop line (negative before it, positive after). Getting from raw GPS to these series is map matching, which the
router's snapper does for nodes; it is not part of this module.

What is learned, per time-of-week bin:

* **Green starts.** A pass that stopped near the stop line (speed under ``stop_speed`` for at least ``min_stop_s``) and then left gives one
  departure time. The first car in the queue leaves soon after the light turns green; later cars leave later, so departures are a noisy,
  late-biased sample of green starts.
* **Cycle length.** For a fixed-time signal every green start is ``offset + k * C``. For each candidate C the departures are wrapped onto a
  circle of circumference C and the mean resultant length R(C) (1 = all at the same phase, near 0 = spread out) is computed. Every
  sub-multiple C/2, C/3... wraps the same times just as tightly, so the estimate is the **largest** candidate whose R is within
  ``alias_tolerance`` of the best. A signal with no candidate above ``min_resultant`` is reported as having no fixed cycle (actuated, police
  controlled, or too few passes), not given a made-up one.
* **Red time.** Cars arriving at random during the red wait roughly uniformly between 0 and the red, so the ``red_quantile`` (q) of
  stop durations divided by q estimates it. A quantile rather than the maximum, because one stalled car would otherwise set it. Cars that
  stop only briefly behind a discharging queue pull the estimate down; it is biased low, by how much is measured in the tests.
* **Delay.** For every pass (stopped or not) the time to cover the window [-``window_before``, +``window_after``] metres around the stop
  line, minus the time at the pass's own cruise speed. Reported as median and 85th percentile with the number of passes, and
  ``None`` when there are fewer than ``min_passes``.

Nothing here has been run on real Chennai traces; the tests use the simulator in ``simulate.py`` (clearly labelled synthetic data).
"""

from __future__ import annotations

import math
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass, field

import numpy as np

Pass = tuple[Sequence[float], Sequence[float]]
"""One pass: (times in seconds, distance to the stop line in metres, negative before it)."""


@dataclass(frozen=True)
class LearnerConfig:
    """Thresholds. Fixed before any real data is seen (see README.md); change them only with a new pre-registration."""

    stop_speed: float = 1.0  # m/s: slower than this counts as stopped
    min_stop_s: float = 3.0  # a stop must last this long
    stop_zone_m: float = 120.0  # the stop must be within this distance before the stop line (a queue)
    min_cycle_s: float = 40.0
    max_cycle_s: float = 180.0
    cycle_step_s: float = 0.25
    min_resultant: float = 0.5  # below this no fixed cycle is claimed
    alias_tolerance: float = 0.9  # largest candidate with R >= this * best R
    min_departures: int = 8  # fewer departures than this: no cycle estimate
    red_quantile: float = 0.9
    window_before: float = 150.0
    window_after: float = 30.0
    min_passes: int = 10  # fewer passes than this in a bin: no delay estimate


@dataclass(frozen=True)
class Stop:
    """A stop before the stop line."""

    start: float
    end: float  # the departure time
    s: float  # where the car stood (metres, negative)

    @property
    def duration(self) -> float:
        return self.end - self.start


@dataclass(frozen=True)
class CycleEstimate:
    cycle_s: float
    resultant: float  # mean resultant length at cycle_s
    offset_s: float  # phase of the departures, in [0, cycle_s)
    departures: int


@dataclass(frozen=True)
class DelayEstimate:
    median_s: float
    p85_s: float
    passes: int


@dataclass
class BinResult:
    """What was learned for one time-of-week bin. ``None`` fields mean "not enough data", never zero."""

    bin: str
    passes: int
    stops: int
    cycle: CycleEstimate | None
    red_s: float | None
    delay: DelayEstimate | None
    notes: list[str] = field(default_factory=list)


def _smoothed(t: np.ndarray, s: np.ndarray, half: int = 3) -> tuple[np.ndarray, np.ndarray]:
    """Positions smoothed by a rolling median of 2*half+1 samples, and the speed at each sample by a central difference over the
    same span. Raw 1 Hz GPS with metre-level noise gives single-step speeds too noisy to see a stop."""
    if np.any(np.diff(t) <= 0):
        raise ValueError("pass times must be strictly increasing")
    n = len(s)
    sm = np.array([np.median(s[max(0, i - half) : i + half + 1]) for i in range(n)])
    v = np.empty(n)
    for i in range(n):
        a, b = max(0, i - half), min(n - 1, i + half)
        v[i] = (sm[b] - sm[a]) / (t[b] - t[a]) if b > a else 0.0
    return sm, v


def find_stop(p: Pass, cfg: LearnerConfig = LearnerConfig()) -> Stop | None:
    """The last stop before the stop line in a pass, or ``None`` if the car did not stop in the queue zone."""
    t = np.asarray(p[0], dtype=float)
    s = np.asarray(p[1], dtype=float)
    if len(t) < 5:
        return None
    sm, v = _smoothed(t, s)
    slow = v < cfg.stop_speed
    best: Stop | None = None
    i = 0
    while i < len(v):
        if not slow[i]:
            i += 1
            continue
        j = i
        while j + 1 < len(v) and slow[j + 1]:
            j += 1
        start, end = t[i], t[j]
        where = float(np.median(sm[i : j + 1]))
        if end - start >= cfg.min_stop_s and -cfg.stop_zone_m <= where <= 5.0:
            best = Stop(start=float(start), end=float(end), s=where)
        i = j + 1
    return best


def _resultant(times: np.ndarray, cycle: float) -> tuple[float, float]:
    """Mean resultant length and mean phase (seconds in [0, cycle)) of ``times`` wrapped on a circle of circumference ``cycle``."""
    ang = 2 * math.pi * (times % cycle) / cycle
    c, s = float(np.mean(np.cos(ang))), float(np.mean(np.sin(ang)))
    r = math.hypot(c, s)
    phase = (math.atan2(s, c) % (2 * math.pi)) / (2 * math.pi) * cycle
    return r, phase


def estimate_cycle(departures: Iterable[float], cfg: LearnerConfig = LearnerConfig()) -> CycleEstimate | None:
    """The fixed cycle that best explains the departure times, or ``None`` (too few, or no candidate is periodic enough)."""
    d = np.asarray(sorted(departures), dtype=float)
    if len(d) < cfg.min_departures:
        return None
    d = d - d[0]
    cands = np.arange(cfg.min_cycle_s, cfg.max_cycle_s + 1e-9, cfg.cycle_step_s)
    rs = np.array([_resultant(d, c)[0] for c in cands])
    best = float(rs.max())
    if best < cfg.min_resultant:
        return None
    ok = np.nonzero(rs >= cfg.alias_tolerance * best)[0]
    # The largest candidate in the top group, refined to the local peak around it.
    k = int(ok.max())
    while k + 1 < len(rs) and rs[k + 1] >= rs[k]:
        k += 1
    while k - 1 >= 0 and rs[k - 1] > rs[k]:
        k -= 1
    r, phase = _resultant(d, float(cands[k]))
    return CycleEstimate(cycle_s=float(cands[k]), resultant=r, offset_s=phase, departures=len(d))


def pass_delay(p: Pass, cfg: LearnerConfig = LearnerConfig()) -> float | None:
    """Seconds lost in the window around the stop line, against the pass's own cruise speed; ``None`` if the pass does not cover it."""
    t = np.asarray(p[0], dtype=float)
    s = np.asarray(p[1], dtype=float)
    a, b = -cfg.window_before, cfg.window_after
    sm, v = _smoothed(t, s)
    # A standing car's noisy position wanders back and forth; only a real reversal (more than a few metres) disqualifies the pass.
    mono = np.maximum.accumulate(sm)
    if sm[0] > a or mono[-1] < b or np.any(mono - sm > 5.0):
        return None
    # The first time the (smoothed, never-decreasing) position reaches each end of the window.
    ta, tb = float(t[np.argmax(mono >= a)]), float(t[np.argmax(mono >= b)])
    # Cruise speed: the 90th percentile of smoothed speeds on the whole pass (a car that never stops is near it all the time).
    cruise = float(np.quantile(v, 0.9))
    if cruise <= cfg.stop_speed:
        return None
    return max(0.0, (tb - ta) - (b - a) / cruise)


def learn_bin(name: str, passes: Sequence[Pass], cfg: LearnerConfig = LearnerConfig()) -> BinResult:
    """Everything for one time-of-week bin."""
    stops = [st for st in (find_stop(p, cfg) for p in passes) if st is not None]
    cycle = estimate_cycle([st.end for st in stops], cfg)
    notes: list[str] = []
    if cycle is None:
        notes.append(
            "no fixed cycle: too few stopped passes"
            if len(stops) < cfg.min_departures
            else "no fixed cycle found (actuated or manually controlled signal, or mixed timing plans)"
        )
    # Random arrivals wait roughly uniformly between 0 and the red, so the q-quantile of waits is about q * red.
    red = (
        float(np.quantile([st.duration for st in stops], cfg.red_quantile)) / cfg.red_quantile
        if len(stops) >= cfg.min_departures
        else None
    )
    delays = [d for d in (pass_delay(p, cfg) for p in passes) if d is not None]
    delay = (
        DelayEstimate(median_s=float(np.median(delays)), p85_s=float(np.quantile(delays, 0.85)), passes=len(delays))
        if len(delays) >= cfg.min_passes
        else None
    )
    if delay is None:
        notes.append(f"no delay estimate: {len(delays)} usable passes, {cfg.min_passes} needed")
    return BinResult(bin=name, passes=len(passes), stops=len(stops), cycle=cycle, red_s=red, delay=delay, notes=notes)


def default_bin(epoch_s: float) -> str:
    """Time-of-week bin of a pass start, in Indian Standard Time: weekday or weekend, then morning peak (8-11), evening peak (17-20),
    day (11-17), night (20-8)."""
    ist = epoch_s + 5.5 * 3600
    day = int(ist // 86400 + 3) % 7  # 1970-01-01 was a Thursday; 0 = Monday
    hour = (ist % 86400) / 3600
    kind = "weekend" if day >= 5 else "weekday"
    if 8 <= hour < 11:
        part = "am_peak"
    elif 17 <= hour < 20:
        part = "pm_peak"
    elif 11 <= hour < 17:
        part = "day"
    else:
        part = "night"
    return f"{kind}_{part}"


def learn(
    passes: Sequence[Pass], cfg: LearnerConfig = LearnerConfig(), bin_of: Callable[[float], str] = default_bin
) -> dict[str, BinResult]:
    """Group passes by the bin of their first timestamp (epoch seconds) and learn each bin."""
    groups: dict[str, list[Pass]] = {}
    for p in passes:
        groups.setdefault(bin_of(float(p[0][0])), []).append(p)
    return {k: learn_bin(k, v, cfg) for k, v in sorted(groups.items())}
