"""Part C2 (ADR-026): routing test, round 2, as pre-registered in PREREGISTRATION_ROUTER_2.md.

Reuses the five prior packs written by round 1 (sus_router_eval.py) and adds an `oracle` pack, then routes 250 new seeded pairs for the
more cautious traveller classes of hazard_classes_round2.yaml. Output: data/results/2026-10-04-susceptibility-chennai/router_round2_result.json
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
from sus_router_eval import BASE, FLAT_MILLI, RES, ROOT, SEED, cell_index, exposure_share, read_pack, write_variant  # noqa: E402

CLASSES = ["ped_l5", "ped_l20", "car_l5"]
PAIRS = 250
ORACLE_MILLI = 2197  # logit(0.9) * 1000


def main() -> int:
    t0 = time.time()
    g = np.load(BASE / "grid.npz")
    lon_g, lat_g, y15 = g["lon"], g["lat"], g["y2015"]
    src, dst, nlat, nlon, prior, meta = read_pack()
    mlat, mlon = (nlat[src] + nlat[dst]) / 2, (nlon[src] + nlon[dst]) / 2
    r, c, ok = cell_index(mlon, mlat, lon_g, lat_g)
    inside = np.zeros(len(src), dtype=bool)
    inside[ok] = y15[r[ok], c[ok]]
    oracle = np.where(inside, ORACLE_MILLI, FLAT_MILLI).astype(np.int16)
    write_variant("oracle", oracle, meta)
    names = ["flat", "gcc", "model05", "base05", "random", "oracle"]
    for n in names[:-1]:
        assert (BASE / "packs" / n / "meta.bin").exists(), f"run sus_router_eval.py first: pack {n} missing"
    print(f"oracle edges {int(inside.sum()):,} of {len(src):,}", flush=True)

    out_json = BASE / "routes_round2.json"
    env = {**os.environ, "HAZARD_CONFIG": str(BASE / "hazard_classes_round2.yaml"), "ROUTE_CLASSES": ",".join(CLASSES)}
    cmd = ["dart", "run", "tool/prior_routes.dart", str(out_json), str(PAIRS), str(SEED + 13)] + [f"{n}={BASE / 'packs' / n}" for n in names]
    p = subprocess.run(cmd, cwd=ROOT / "packages" / "pulse_router", capture_output=True, text=True, env=env, shell=(sys.platform == "win32"))
    print(p.stdout.strip(), p.stderr.strip()[-400:], flush=True)
    if p.returncode != 0:
        return p.returncode
    data = json.loads(out_json.read_text(encoding="utf-8"))
    rows = data["rows"]
    n = len(rows)
    table = {f"{k}|{c}": {"exposure": np.zeros(n), "added_min": np.zeros(n), "dist_km": np.zeros(n)} for k in names for c in CLASSES}
    for i, row in enumerate(rows):
        for c in CLASSES:
            ref = row["routes"][f"flat|{c}"]
            for k in names:
                rt = row["routes"][f"{k}|{c}"]
                t = table[f"{k}|{c}"]
                t["exposure"][i] = exposure_share(rt["path"], y15, lon_g, lat_g)
                t["added_min"][i] = (rt["free_flow_s"] - ref["free_flow_s"]) / 60.0
                t["dist_km"][i] = rt["distance_m"] / 1000.0
    rng = np.random.default_rng(SEED + 31)
    idx = [rng.integers(0, n, n) for _ in range(2000)]

    def ci_mean(x):
        b = [x[i].mean() for i in idx]
        return [float(np.percentile(b, 2.5)), float(np.percentile(b, 97.5))]

    summary = {}
    trip = {c: float(np.mean([r["routes"][f"flat|{c}"]["free_flow_s"] for r in rows]) / 60.0) for c in CLASSES}
    for c in CLASSES:
        flat = table[f"flat|{c}"]
        for k in names:
            d = table[f"{k}|{c}"]
            red = flat["exposure"] - d["exposure"]
            summary[f"{k}|{c}"] = {
                "mean_exposure_share": float(d["exposure"].mean()), "reduction_vs_flat": float(red.mean()), "reduction_ci95": ci_mean(red),
                "relative_reduction": float(red.mean() / max(flat["exposure"].mean(), 1e-12)),
                "mean_added_free_flow_min": float(d["added_min"].mean()), "mean_trip_min_flat": trip[c],
                "share_of_routes_changed": float(np.mean(d["dist_km"] != flat["dist_km"])),
            }
        for other in ("base05", "random", "gcc"):
            diff = table[f"{other}|{c}"]["exposure"] - table[f"model05|{c}"]["exposure"]
            summary[f"model05_better_than_{other}|{c}"] = {"mean_exposure_difference": float(diff.mean()), "ci95": ci_mean(diff)}
    o = summary["oracle|ped_l20"]
    d1 = bool(o["relative_reduction"] >= 0.25 and o["reduction_ci95"][0] > 0 and o["mean_added_free_flow_min"] <= 0.05 * o["mean_trip_min_flat"])
    d2 = all(summary[f"model05|{c}"]["reduction_ci95"][0] > 0 and summary[f"model05|{c}"]["mean_added_free_flow_min"] <= 0.05 * trip[c]
             and summary[f"model05_better_than_base05|{c}"]["ci95"][0] > 0 and summary[f"model05_better_than_random|{c}"]["ci95"][0] > 0
             for c in ("ped_l5", "ped_l20"))
    res = {
        "task": "ADR-026 part C2: routing test round 2",
        "preregistration_commit": subprocess.run(["git", "log", "--format=%H", "-1", "--", str(BASE / "PREREGISTRATION_ROUTER_2.md")], capture_output=True, text=True, cwd=ROOT).stdout.strip(),
        "pairs_requested": PAIRS, "pairs_scored": n, "oracle_edges": int(inside.sum()), "summary": summary,
        "decision_rule": {"D1_oracle_removes_25pct_exposure_for_ped_l20_within_5pct_time": d1, "D2_learned_prior_helps_when_router_cares": bool(d2)},
        "seconds": round(time.time() - t0),
    }
    (RES / "router_round2_result.json").write_text(json.dumps(res, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(res["decision_rule"], indent=1))
    for c in CLASSES:
        for k in names:
            s = summary[f"{k}|{c}"]
            print(f"{c:8s} {k:8s} exposure {s['mean_exposure_share']:.4f} reduction {s['reduction_vs_flat']:+.4f} {[round(x, 4) for x in s['reduction_ci95']]} rel {s['relative_reduction']:+.2f} +min {s['mean_added_free_flow_min']:.2f} (trip {s['mean_trip_min_flat']:.1f}) changed {s['share_of_routes_changed']:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
