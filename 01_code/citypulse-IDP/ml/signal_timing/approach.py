"""From raw GPS traces to learner passes (C8): the approaches of a signal on the road graph, and matching traces to them.

An approach is a polyline along one incoming road: ``upstream_m`` metres before the signal node, through it, and ``downstream_m`` metres
beyond (continuing straight). Distance along it is negative before the signal node (the stop line is taken as the node) and positive
after. A trace is matched to an approach where its points stay within ``corridor_m`` of the polyline and move forward along it; a pass
is a matched run that covers the learner's window.

The road graph comes from ``data/graph/2026-09-14`` (OpenStreetMap, ODbL): node coordinates from the prior file, directed edges from the
CLI graph. Map matching is deliberately simple (nearest polyline within a corridor, forward motion); it is not a general map matcher.
"""

from __future__ import annotations

import json
import math
from collections import defaultdict
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

import numpy as np

M_PER_DEG = 111_320.0
GRAPH_DIR = Path(__file__).resolve().parents[2] / "data" / "graph" / "2026-09-14"


@dataclass(frozen=True)
class Approach:
    site_id: str
    approach_id: str
    points: tuple[tuple[float, float], ...]  # (lat, lon), upstream end first
    stop_index: int  # index of the signal node in points
    heading_deg: float  # direction of travel at the stop line

    def to_json(self) -> dict:
        return {
            "site_id": self.site_id,
            "approach_id": self.approach_id,
            "points": [list(p) for p in self.points],
            "stop_index": self.stop_index,
            "heading_deg": round(self.heading_deg, 1),
        }

    @staticmethod
    def from_json(d: dict) -> Approach:
        return Approach(d["site_id"], d["approach_id"], tuple(tuple(p) for p in d["points"]), d["stop_index"], d["heading_deg"])


class RoadGraph:
    """Node coordinates and directed adjacency (both directions)."""

    def __init__(
        self,
        lat: np.ndarray,
        lon: np.ndarray,
        edges: Sequence[tuple[int, int]],
        names: dict[int, dict[str, str]] | None = None,
    ) -> None:
        self.lat, self.lon = lat, lon
        self.out: dict[int, list[int]] = defaultdict(list)
        self.inc: dict[int, list[int]] = defaultdict(list)
        for a, b in edges:
            self.out[a].append(b)
            self.inc[b].append(a)
        # node -> {street name: highway class} of the edges touching it (empty when not loaded)
        self.names: dict[int, dict[str, str]] = names or {}

    @staticmethod
    def load(graph_dir: Path = GRAPH_DIR) -> RoadGraph:
        prior = json.loads((graph_dir / "chennai_prior_ell0.json").read_text(encoding="utf-8"))
        edges = json.loads((graph_dir / "chennai_graph_cli.json").read_text(encoding="utf-8"))["edges"]
        names: dict[int, dict[str, str]] = defaultdict(dict)
        for e in prior["edges"]:
            name = e.get("street_name") or ""
            for n in (e["from"], e["to"]):
                names[n][name] = e.get("highway") or ""
        nodes = prior["nodes"]
        return RoadGraph(
            np.array([n["lat"] for n in nodes]),
            np.array([n["lon"] for n in nodes]),
            [(e["from"], e["to"]) for e in edges],
            names,
        )

    def xy(self, n: int, lat0: float) -> tuple[float, float]:
        return ((self.lon[n]) * M_PER_DEG * math.cos(math.radians(lat0)), self.lat[n] * M_PER_DEG)

    def dist(self, a: int, b: int) -> float:
        lat0 = float(self.lat[a])
        ax, ay = self.xy(a, lat0)
        bx, by = self.xy(b, lat0)
        return math.hypot(bx - ax, by - ay)

    def bearing(self, a: int, b: int) -> float:
        lat0 = float(self.lat[a])
        ax, ay = self.xy(a, lat0)
        bx, by = self.xy(b, lat0)
        return math.degrees(math.atan2(bx - ax, by - ay)) % 360

    def nearest(self, lat: float, lon: float, max_m: float = 30.0) -> int | None:
        d = np.hypot((self.lat - lat) * M_PER_DEG, (self.lon - lon) * M_PER_DEG * math.cos(math.radians(lat)))
        i = int(np.argmin(d))
        return i if d[i] <= max_m else None


def _turn(a: float, b: float) -> float:
    return abs((b - a + 180) % 360 - 180)


def _straightest(graph: RoadGraph, options: list[int], here: int, heading: float, backwards: bool) -> int | None:
    best, best_turn = None, 45.0  # never follow a turn sharper than 45 degrees
    for o in options:
        h = graph.bearing(o, here) if backwards else graph.bearing(here, o)
        t = _turn(heading, h)
        if t < best_turn:
            best, best_turn = o, t
    return best


def approaches(graph: RoadGraph, site_id: str, signal_node: int, upstream_m: float = 250.0, downstream_m: float = 80.0) -> list[Approach]:
    """One approach per distinct incoming road of the signal node."""
    out = []
    for k, prev in enumerate(sorted(set(graph.inc[signal_node]))):
        heading = graph.bearing(prev, signal_node)
        up = [signal_node, prev]
        length = graph.dist(prev, signal_node)
        while length < upstream_m:
            h = graph.bearing(up[-1], up[-2])
            nxt = _straightest(graph, [n for n in graph.inc[up[-1]] if n not in up], up[-1], h, backwards=True)
            if nxt is None:
                break
            length += graph.dist(nxt, up[-1])
            up.append(nxt)
        down = [signal_node]
        dlen = 0.0
        h = heading
        while dlen < downstream_m:
            nxt = _straightest(graph, [n for n in graph.out[down[-1]] if n not in down and n not in up], down[-1], h, backwards=False)
            if nxt is None:
                break
            dlen += graph.dist(down[-1], nxt)
            h = graph.bearing(down[-1], nxt)
            down.append(nxt)
        if length < 0.6 * upstream_m or dlen < 0.5 * downstream_m:
            continue  # too short to measure a queue and a departure
        nodes = list(reversed(up)) + down[1:]
        out.append(
            Approach(
                site_id,
                f"{site_id}-a{k}",
                tuple((float(graph.lat[n]), float(graph.lon[n])) for n in nodes),
                len(up) - 1,
                heading,
            )
        )
    return out


def _project(lat: np.ndarray, lon: np.ndarray, ap: Approach) -> tuple[np.ndarray, np.ndarray]:
    """Distance along the approach (0 at the stop line) and distance from it, metres."""
    lat0 = ap.points[0][0]
    kx = M_PER_DEG * math.cos(math.radians(lat0))
    px = np.array([p[1] * kx for p in ap.points])
    py = np.array([p[0] * M_PER_DEG for p in ap.points])
    x, y = lon * kx, lat * M_PER_DEG
    seg = np.hypot(np.diff(px), np.diff(py))
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    best_s = np.full(len(x), np.nan)
    best_d = np.full(len(x), np.inf)
    for k in range(len(seg)):
        if seg[k] == 0:
            continue
        ux, uy = (px[k + 1] - px[k]) / seg[k], (py[k + 1] - py[k]) / seg[k]
        along = np.clip((x - px[k]) * ux + (y - py[k]) * uy, 0, seg[k])
        d = np.hypot(x - (px[k] + along * ux), y - (py[k] + along * uy))
        better = d < best_d
        best_d[better] = d[better]
        best_s[better] = cum[k] + along[better]
    return best_s - cum[ap.stop_index], best_d


def match_passes(
    t: np.ndarray,
    lat: np.ndarray,
    lon: np.ndarray,
    ap: Approach,
    *,
    corridor_m: float = 20.0,
    window_before: float = 150.0,
    window_after: float = 30.0,
) -> list[tuple[np.ndarray, np.ndarray]]:
    """Passes (t, s) of one trace along one approach: runs inside the corridor that cover the window and move forward overall."""
    t = np.asarray(t, dtype=float)
    s, d = _project(np.asarray(lat, dtype=float), np.asarray(lon, dtype=float), ap)
    inside = d <= corridor_m
    out = []
    i = 0
    while i < len(t):
        if not inside[i]:
            i += 1
            continue
        j = i
        while j + 1 < len(t) and inside[j + 1]:
            j += 1
        ts, ss = t[i : j + 1], s[i : j + 1]
        if len(ts) >= 5 and ss[0] <= -window_before and ss[-1] >= window_after and ss[-1] > ss[0]:
            out.append((ts, ss))
        i = j + 1
    return out
