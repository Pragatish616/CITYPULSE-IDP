"""Signal-timing study commands (C8). Run from 01_code/citypulse-IDP:

    python -m ml.signal_timing candidates --out ml/signal_timing/sites/candidates.json
    python -m ml.signal_timing approaches --site S01 --lat 13.04 --lon 80.23 --out ml/signal_timing/sites/S01.json
    python -m ml.signal_timing learn --site ml/signal_timing/sites/S01.json --traces field/S01/ --out field/S01/learned.json [--start-epoch 1760000000]
    python -m ml.signal_timing evaluate --learned field/ --stopwatch field/stopwatch.csv --out field/evaluation.json

`candidates` only proposes junctions; the owner chooses the 10 sites and writes them in the data log before the first drive
(README.md, study protocol).
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from dataclasses import asdict
from pathlib import Path

import numpy as np

from ml.signal_timing.approach import Approach, RoadGraph, approaches, match_passes
from ml.signal_timing.ingest import read_any
from ml.signal_timing.learner import LearnerConfig, learn

REPO = Path(__file__).resolve().parents[2]
POI = REPO / "data" / "places" / "chennai-poi-2026-10-15" / "poi.json"
KILL_MEDIAN_ERROR_S = 15.0
CENTRE = (13.0418, 80.2341)  # cities.yaml centre for Chennai
FIXED_STOPWATCH_SD_S = 5.0


def signal_points() -> list[tuple[float, float, str]]:
    doc = json.loads(POI.read_text(encoding="utf-8"))
    sig = next(i for i, c in enumerate(doc["categories"]) if c["id"] == "signal")
    return [(r[0], r[1], r[3]) for r in doc["places"] if r[2] == sig]


def cmd_candidates(a: argparse.Namespace) -> int:
    g = RoadGraph.load()
    # Eligible: snaps to the graph, at least two measurable approaches, on a main road, within 10 km of the city centre (reachable by
    # the team). OpenStreetMap usually tags the signal on the node just before the junction, which has two approaches (both directions).
    main = {"trunk", "primary", "secondary", "trunk_link", "primary_link", "secondary_link"}
    rows = []
    for lat, lon, name in signal_points():
        if math.hypot((lat - CENTRE[0]) * 111.32, (lon - CENTRE[1]) * 108.4) > 10.0:
            continue
        n = g.nearest(lat, lon)
        if n is None:
            continue
        roads = {k: v for k, v in g.names.get(n, {}).items() if k and not k.startswith("edge ")}
        if not any(v in main for v in g.names.get(n, {}).values()):
            continue
        aps = approaches(g, "x", n)
        if len(aps) >= 2:
            rows.append(
                {
                    "lat": round(lat, 6),
                    "lon": round(lon, 6),
                    "node": n,
                    "approaches": len(aps),
                    "streets": sorted(roads),
                    "osm_name": name,
                }
            )
    # Spread across the city: greedy farthest-point choice, starting from the junction with most approaches.
    rows.sort(key=lambda r: -r["approaches"])
    chosen = [rows[0]] if rows else []
    while len(chosen) < min(a.n, len(rows)):
        def gap(r: dict) -> float:
            return min(math.hypot(r["lat"] - c["lat"], (r["lon"] - c["lon"]) * 0.974) for c in chosen)

        chosen.append(max((r for r in rows if r not in chosen), key=gap))
    for i, c in enumerate(chosen, 1):
        c["candidate_id"] = f"C{i:02d}"
    out = {
        "note": "Candidates only. The owner chooses 10 sites and records them in the data log before the first drive.",
        "eligible_junctions": len(rows),
        "candidates": chosen,
    }
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{len(rows)} eligible junctions; wrote {len(chosen)} candidates to {a.out}")
    return 0


def cmd_approaches(a: argparse.Namespace) -> int:
    g = RoadGraph.load()
    n = g.nearest(a.lat, a.lon)
    if n is None:
        print("no graph node within 30 m", file=sys.stderr)
        return 1
    aps = approaches(g, a.site, n)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps({"site_id": a.site, "node": n, "approaches": [x.to_json() for x in aps]}, indent=1) + "\n")
    print(f"{a.site}: {len(aps)} approaches written to {a.out}")
    return 0


def cmd_learn(a: argparse.Namespace) -> int:
    site = json.loads(Path(a.site).read_text(encoding="utf-8"))
    aps = [Approach.from_json(x) for x in site["approaches"]]
    cfg = LearnerConfig()
    passes: dict[str, list] = {ap.approach_id: [] for ap in aps}
    files = sorted(p for p in Path(a.traces).iterdir() if p.suffix.lower() in (".gpx", ".csv"))
    for f in files:
        t, la, lo = read_any(f, start_epoch=a.start_epoch)
        for ap in aps:
            passes[ap.approach_id] += match_passes(t, la, lo, ap, window_before=cfg.window_before, window_after=cfg.window_after)
    out = {"site_id": site["site_id"], "trace_files": len(files), "config": asdict(cfg), "approaches": {}}
    for aid, ps in passes.items():
        res = learn(ps, cfg)
        out["approaches"][aid] = {"passes": len(ps), "bins": {k: _bin_json(v) for k, v in res.items()}}
    Path(a.out).write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({k: v["passes"] for k, v in out["approaches"].items()}))
    return 0


def _bin_json(b) -> dict:
    return {
        "passes": b.passes,
        "stops": b.stops,
        "cycle_s": None if b.cycle is None else round(b.cycle.cycle_s, 2),
        "resultant": None if b.cycle is None else round(b.cycle.resultant, 3),
        "red_s": None if b.red_s is None else round(b.red_s, 1),
        "delay_median_s": None if b.delay is None else round(b.delay.median_s, 1),
        "delay_p85_s": None if b.delay is None else round(b.delay.p85_s, 1),
        "notes": b.notes,
    }


def evaluate(learned: list[dict], stopwatch_rows: list[dict]) -> dict:
    """Primary outcome of the pre-registered study. Reading of the protocol fixed here, before any data: a site 'has a fixed cycle' if
    its stopwatch cycles have SD <= 5 s; its error is |learned - stopwatch median| for the approach and bin with the most passes among
    those the stopwatch covers; a fixed-cycle site where the learner finds no cycle counts as a failure (infinite error)."""
    by_site: dict[str, list[dict]] = {}
    for r in stopwatch_rows:
        by_site.setdefault(r["site_id"], []).append(r)
    sites = []
    for site_id, rows in sorted(by_site.items()):
        cycles = [float(r["cycle_s"]) for r in rows if r.get("cycle_s")]
        sw_median = statistics.median(cycles) if cycles else None
        sw_sd = statistics.stdev(cycles) if len(cycles) > 1 else None
        fixed = sw_sd is not None and sw_sd <= FIXED_STOPWATCH_SD_S
        bins = {r.get("bin") for r in rows}
        lr = next((x for x in learned if x["site_id"] == site_id), None)
        best = None
        if lr:
            for aid, ap in lr["approaches"].items():
                for b, v in ap["bins"].items():
                    if (not bins - {None, ""} or b in bins) and (best is None or v["passes"] > best[2]["passes"]):
                        best = (aid, b, v)
        learned_cycle = best[2]["cycle_s"] if best else None
        err = None if sw_median is None else (abs(learned_cycle - sw_median) if learned_cycle is not None else math.inf)
        sites.append(
            {
                "site_id": site_id,
                "stopwatch_cycles": len(cycles),
                "stopwatch_median_s": sw_median,
                "stopwatch_sd_s": None if sw_sd is None else round(sw_sd, 2),
                "fixed_cycle_by_stopwatch": fixed,
                "approach": best[0] if best else None,
                "bin": best[1] if best else None,
                "passes": best[2]["passes"] if best else 0,
                "learned_cycle_s": learned_cycle,
                "abs_error_s": None if err is None or math.isinf(err) else round(err, 2),
                "learner_found_no_cycle": learned_cycle is None,
            }
        )
    fixed_errs = [
        (math.inf if s["learner_found_no_cycle"] else s["abs_error_s"]) for s in sites if s["fixed_cycle_by_stopwatch"]
    ]
    med = float(np.median(fixed_errs)) if fixed_errs else None
    return {
        "sites": sites,
        "fixed_cycle_sites": len(fixed_errs),
        "median_abs_error_s_fixed_sites": None if med is None or math.isinf(med) else round(med, 2),
        "median_is_a_failure": med is not None and math.isinf(med),
        "killed": med is None or med > KILL_MEDIAN_ERROR_S,
        "kill_rule": f"median error over fixed-cycle sites > {KILL_MEDIAN_ERROR_S} s",
        "no_fixed_cycle_agreement": {
            "learner_none_and_stopwatch_not_fixed": sum(
                1 for s in sites if s["learner_found_no_cycle"] and not s["fixed_cycle_by_stopwatch"]
            ),
            "learner_none_but_stopwatch_fixed": sum(1 for s in sites if s["learner_found_no_cycle"] and s["fixed_cycle_by_stopwatch"]),
        },
    }


def cmd_evaluate(a: argparse.Namespace) -> int:
    import csv

    learned = [json.loads(p.read_text(encoding="utf-8")) for p in Path(a.learned).rglob("learned.json")]
    with open(a.stopwatch, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    res = evaluate(learned, rows)
    Path(a.out).write_text(json.dumps(res, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({k: res[k] for k in ("fixed_cycle_sites", "median_abs_error_s_fixed_sites", "killed")}))
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="python -m ml.signal_timing")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("candidates")
    c.add_argument("--out", required=True)
    c.add_argument("--n", type=int, default=20)
    c = sub.add_parser("approaches")
    c.add_argument("--site", required=True)
    c.add_argument("--lat", type=float, required=True)
    c.add_argument("--lon", type=float, required=True)
    c.add_argument("--out", required=True)
    c = sub.add_parser("learn")
    c.add_argument("--site", required=True)
    c.add_argument("--traces", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--start-epoch", type=float, default=None)
    c = sub.add_parser("evaluate")
    c.add_argument("--learned", required=True)
    c.add_argument("--stopwatch", required=True)
    c.add_argument("--out", required=True)
    a = p.parse_args()
    return {"candidates": cmd_candidates, "approaches": cmd_approaches, "learn": cmd_learn, "evaluate": cmd_evaluate}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
