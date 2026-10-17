"""Path-averaged rain rate from a commercial microwave link's signal level (C3).

Rain between the two antennas of a backhaul link (roughly 10 to 40 GHz) weakens the received signal. Overeem et al. turned operators'
link power logs into city and country rain maps (Water Resources Research 2011 and 2016; research notes N7, N8). This module is the
standard processing chain, written from that literature; the specific rules below are the common textbook forms, recalled rather than
copied from the papers [UNVERIFIED: check each against N7 and pycomlink before use on real data]:

1. **Wet or dry.** Either (a) one link alone: the rolling standard deviation of the loss over ``std_window`` samples above
   ``std_threshold_db`` means wet; or (b) with neighbours: wet when this link's excess loss is at least ``own_excess_db`` and the median
   excess loss of links whose midpoints lie within ``radius_km`` is at least ``neighbour_excess_db``. (b) rejects fades that only one
   link sees (multipath, equipment).
2. **Baseline.** The loss the link would have without rain: the median of the last ``baseline_window`` dry samples, held through wet
   periods.
3. **Rain attenuation.** A = loss - baseline - wet_antenna_db while wet, never below 0; 0 while dry. Water on the antenna covers adds
   loss that is not rain along the path; ``wet_antenna_db`` is subtracted (0 is allowed, and biases rain high).
4. **Rain rate.** Specific attenuation k = A / length_km (dB/km) and R = (k / a) ** (1 / b) mm/h, with a and b for the link's frequency
   and polarisation. **There are no default coefficients**: take them from ITU-R Recommendation P.838 for each link; nothing here
   invents them.

Inputs are loss series in dB (transmitted minus received power, or minus received power when the transmit level is constant), one value
per regular time step, NaN for gaps.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Link:
    link_id: str
    length_km: float
    a: float  # k-R coefficient for this frequency and polarisation (ITU-R P.838); no default
    b: float  # k-R exponent; no default
    lat1: float
    lon1: float
    lat2: float
    lon2: float

    def __post_init__(self) -> None:
        if not (self.length_km > 0 and self.a > 0 and self.b > 0):
            raise ValueError(f"{self.link_id}: length, a and b must be positive")

    @property
    def midpoint(self) -> tuple[float, float]:
        return ((self.lat1 + self.lat2) / 2, (self.lon1 + self.lon2) / 2)


@dataclass(frozen=True)
class SingleLinkRule:
    std_window: int
    std_threshold_db: float


@dataclass(frozen=True)
class NeighbourRule:
    radius_km: float
    own_excess_db: float
    neighbour_excess_db: float
    reference_window: int  # samples for the reference level used for "excess" (median over the window)


@dataclass(frozen=True)
class RetrievalConfig:
    baseline_window: int
    wet_antenna_db: float


def km_between(p: tuple[float, float], q: tuple[float, float]) -> float:
    lat = math.radians((p[0] + q[0]) / 2)
    dx = (q[1] - p[1]) * 111.32 * math.cos(lat)
    dy = (q[0] - p[0]) * 111.32
    return math.hypot(dx, dy)


def _rolling(x: np.ndarray, n: int, fn) -> np.ndarray:
    out = np.full(len(x), np.nan)
    for i in range(len(x)):
        w = x[max(0, i - n + 1) : i + 1]
        w = w[~np.isnan(w)]
        if len(w) >= max(2, n // 2):
            out[i] = fn(w)
    return out


def wet_single(loss_db: np.ndarray, rule: SingleLinkRule) -> np.ndarray:
    """Wet where the rolling standard deviation is above the threshold."""
    sd = _rolling(np.asarray(loss_db, dtype=float), rule.std_window, np.std)
    return np.nan_to_num(sd, nan=0.0) > rule.std_threshold_db


def excess(loss_db: np.ndarray, window: int) -> np.ndarray:
    """Loss above its rolling median over the previous ``window`` samples."""
    x = np.asarray(loss_db, dtype=float)
    ref = _rolling(x, window, np.median)
    return x - ref


def wet_neighbours(links: Sequence[Link], losses: Sequence[np.ndarray], rule: NeighbourRule) -> list[np.ndarray]:
    """Wet/dry for each link from its own excess loss and its neighbours' median excess loss."""
    ex = [np.nan_to_num(excess(lo, rule.reference_window), nan=0.0) for lo in losses]
    out = []
    for i, li in enumerate(links):
        nb = [j for j, lj in enumerate(links) if j != i and km_between(li.midpoint, lj.midpoint) <= rule.radius_km]
        if not nb:
            # No neighbours: this rule cannot judge; say dry rather than guess.
            out.append(np.zeros(len(ex[i]), dtype=bool))
            continue
        med = np.median(np.vstack([ex[j] for j in nb]), axis=0)
        out.append((ex[i] >= rule.own_excess_db) & (med >= rule.neighbour_excess_db))
    return out


def baseline(loss_db: np.ndarray, wet: np.ndarray, window: int) -> np.ndarray:
    """Median of the last ``window`` dry samples, held through wet periods; NaN until there is any dry sample."""
    x = np.asarray(loss_db, dtype=float)
    out = np.full(len(x), np.nan)
    dry: list[float] = []
    for i in range(len(x)):
        if not wet[i] and not math.isnan(x[i]):
            dry.append(float(x[i]))
            if len(dry) > window:
                dry.pop(0)
        if dry:
            out[i] = float(np.median(dry))
    return out


def rain_rate(link: Link, loss_db: np.ndarray, wet: np.ndarray, cfg: RetrievalConfig) -> np.ndarray:
    """Path-averaged rain rate (mm/h) at each step; NaN where the loss or the baseline is missing."""
    x = np.asarray(loss_db, dtype=float)
    base = baseline(x, wet, cfg.baseline_window)
    att = np.where(wet, np.maximum(x - base - cfg.wet_antenna_db, 0.0), 0.0)
    k = att / link.length_km
    r = np.power(k / link.a, 1.0 / link.b)
    r[np.isnan(x) | np.isnan(base)] = np.nan
    return r
