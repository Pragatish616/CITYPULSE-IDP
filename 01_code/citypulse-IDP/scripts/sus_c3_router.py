"""Part C3 step 3 (ADR-026): does the nationwide model's prior route people around the December 2015 flood better than the other priors?

Follows PREREGISTRATION_C3.md. Builds the `national` prior pack (equal prior mass, values allocated by the nationwide model's score at each edge
midpoint on the 250 m Chennai grid), routes the SAME 250 pairs as round 2 for flat and national, and merges them with round 2's routes for the other
variants. Output: data/results/2026-10-04-susceptibility-chennai-c3/router_result.json
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sus_router_eval import BASE, ROOT, SEED, allocate, cell_index, exposure_share, read_pack, write_variant  # noqa: E402

OUT = ROOT / "data" / "results" / "2026-10-04-susceptibility-chennai-c3"
RUNS = [("ped_l5", "pedestrian"), ("ped_l20", "pedestrian"), ("car_l5", "commuter")]
PAIRS = 250


def main() -> int:
    t0 = time.time()
    g = np.load(BASE / "chennai250.npz")
    sc = np.load(BASE / "chennai250_scores.npz")["model"]
    lon_g, lat_g, y15 = g["lon"], g["lat"], None
    src, dst, nlat, nlon, prior, meta = read_pack()
    mlat, mlon = (nlat[src] + nlat[dst]) / 2, (nlon[src] + nlon[dst]) / 2
    r, c, ok = cell_index(mlon, mlat, lon_g, lat_g)
    score = np.full(len(src), np.nan)
    score[ok] = sc[r[ok], c[ok]]
    values = np.sort(prior)[::-1].copy()
    variant = allocate(values, score)
    assert np.array_equal(np.sort(variant), np.sort(prior)), "the national prior must hold the same values as the current prior"
    write_variant("national", variant, meta)
    print(f"national prior written ({time.time() - t0:.0f}s); scored edges {int(np.isfinite(score).sum()):,} of {len(src):,}", flush=True)

    # exposure truth on the 90 m grid of Parts A/C (the same truth as rounds 1 and 2)
    grid90 = np.load(BASE / "grid.npz")
    lon90, lat90, y90 = grid90["lon"], grid90["lat"], grid90["y2015"]

    merged: dict[int, dict] = {}
    for label, cls in RUNS:
        out_json = BASE / f"routes_c3_{label}.json"
        env = {**os.environ, "HAZARD_CONFIG": str(BASE / f"hazard_classes_round2_{label}.yaml"), "ROUTE_CLASSES": cls}
        cmd = ["dart", "run", "tool/prior_routes.dart", str(out_json), str(PAIRS), str(SEED + 13), f"flat={BASE / 'packs' / 'flat'}", f"national={BASE / 'packs' / 'national'}"]
        p = subprocess.run(cmd, cwd=ROOT / "packages" / "pulse_router", capture_output=True, text=True, env=env, shell=(sys.platform == "win32"))
        print(label, p.stdout.strip(), p.stderr.strip()[-300:], flush=True)
        if p.returncode != 0:
            return p.returncode
        r2 = {row["pair"]: row for row in json.loads((BASE / f"routes_round2_{label}.json").read_text(encoding="utf-8"))["rows"]}
        for row in json.loads(out_json.read_text(encoding="utf-8"))["rows"]:
            old = r2.get(row["pair"])
            if old is None:
                continue
            assert abs(old["routes"][f"flat|{cls}"]["distance_m"] - row["routes"][f"flat|{cls}"]["distance_m"]) < 1e-6, "flat routes differ between runs"
            slot = merged.setdefault(row["pair"], {"routes": {}, "got": set()})
            for key, val in {**old["routes"], **row["routes"]}.items():
                slot["routes"][f"{key.split('|')[0]}|{label}"] = val
            slot["got"].add(label)
    rows = [v for v in merged.values() if v["got"] == {l for l, _ in RUNS}]
    n = len(rows)
    names = ["flat", "gcc", "model05", "base05", "random", "oracle", "national"]
    classes = [l for l, _ in RUNS]
    table = {f"{k}|{c}": np.zeros(n) for k in names for c in classes}
    added = {f"{k}|{c}": np.zeros(n) for k in names for c in classes}
    for i, row in enumerate(rows):
        for c in classes:
            ref = row["routes"][f"flat|{c}"]
            for k in names:
                rt = row["routes"][f"{k}|{c}"]
                table[f"{k}|{c}"][i] = exposure_share(rt["path"], y90, lon90, lat90)
                added[f"{k}|{c}"][i] = (rt["free_flow_s"] - ref["free_flow_s"]) / 60.0
    rng = np.random.default_rng(SEED + 51)
    idx = [rng.integers(0, n, n) for _ in range(2000)]

    def ci_mean(x):
        b = [x[i].mean() for i in idx]
        return [float(np.percentile(b, 2.5)), float(np.percentile(b, 97.5))]

    trip = {c: float(np.mean([r["routes"][f"flat|{c}"]["free_flow_s"] for r in rows]) / 60.0) for c in classes}
    summary = {}
    for c in classes:
        for k in names:
            red = table[f"flat|{c}"] - table[f"{k}|{c}"]
            summary[f"{k}|{c}"] = {"mean_exposure_share": float(table[f"{k}|{c}"].mean()), "reduction_vs_flat": float(red.mean()), "reduction_ci95": ci_mean(red),
                                   "mean_added_free_flow_min": float(added[f"{k}|{c}"].mean()), "mean_trip_min_flat": trip[c]}
        for other in ("base05", "random", "gcc", "model05"):
            diff = table[f"{other}|{c}"] - table[f"national|{c}"]
            summary[f"national_better_than_{other}|{c}"] = {"mean_exposure_difference": float(diff.mean()), "ci95": ci_mean(diff)}
    d2 = all(summary[f"national|{c}"]["reduction_ci95"][0] > 0 and summary[f"national|{c}"]["mean_added_free_flow_min"] <= 0.05 * trip[c]
             and summary[f"national_better_than_base05|{c}"]["ci95"][0] > 0 and summary[f"national_better_than_random|{c}"]["ci95"][0] > 0 for c in ("ped_l5", "ped_l20"))
    res = {"task": "ADR-026 Part C3 routing with the nationwide prior", "pairs_scored": n, "summary": summary, "decision_rule_2_nationwide_prior_improves_routing": bool(d2), "seconds": round(time.time() - t0)}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "router_result.json").write_text(json.dumps(res, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({"decision_rule_2": d2, "pairs": n}))
    for c in classes:
        for k in names:
            s = summary[f"{k}|{c}"]
            print(f"{c:8s} {k:9s} exposure {s['mean_exposure_share']:.4f} reduction {s['reduction_vs_flat']:+.4f} {[round(x, 4) for x in s['reduction_ci95']]} +min {s['mean_added_free_flow_min']:.2f} (trip {s['mean_trip_min_flat']:.1f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
