"""Part C (ADR-026): does a learned flood prior route people away from a real flood better than other priors?

Follows data/susceptibility/2026-10-04/PREREGISTRATION_ROUTER.md. Steps:
  1. make packs for the Chennai graph that differ ONLY in the per-edge prior, all holding the SAME multiset of prior values as the
     current pack (equal prior mass, different allocation): current GCC prior; model prior (trained on the 2005 flood only);
     elevation-only prior (the best single feature on 2005); random allocation; flat (every edge at the flat value);
  2. route seeded node pairs through each with the Dart engine (tool/prior_routes.dart);
  3. score each route by the share of its length inside the December 2015 flood extent (which none of the model, elevation or random priors
     has seen; the current GCC prior was built from the same 2015 event and is a reference, not a competitor).
Usage: python scripts/sus_router_eval.py [--pairs N]
"""

from __future__ import annotations

import argparse
import json
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
PACK = ROOT / "data" / "packs" / "2026-10-02"
RES = ROOT / "data" / "results" / "2026-10-04-susceptibility-chennai"
SEED = 20261004
CLASSES = ["commuter", "pedestrian"]
FLAT_MILLI = -3892


def read_pack():
    g = (PACK / "graph.bin").read_bytes()
    _, n_nodes, n_edges = struct.unpack("<III", g[4:16])
    src = np.frombuffer(g, dtype="<i4", count=n_edges, offset=16)
    dst = np.frombuffer(g, dtype="<i4", count=n_edges, offset=16 + 4 * n_edges)
    nd = (PACK / "nodes.bin").read_bytes()
    lat = np.frombuffer(nd, dtype="<f8", count=n_nodes, offset=16)
    lon = np.frombuffer(nd, dtype="<f8", count=n_nodes, offset=16 + 8 * n_nodes)
    meta = (PACK / "meta.bin").read_bytes()
    prior = np.frombuffer(meta, dtype="<i2", count=n_edges, offset=20).copy()
    return src, dst, lat, lon, prior, meta


def cell_index(lon, lat, lon_g, lat_g):
    c = np.rint((lon - lon_g[0]) / (lon_g[1] - lon_g[0])).astype(int)
    r = np.rint((lat - lat_g[0]) / (lat_g[1] - lat_g[0])).astype(int)
    ok = (r >= 0) & (r < len(lat_g)) & (c >= 0) & (c < len(lon_g))
    return r, c, ok


def allocate(values_sorted_desc, score):
    """Give the highest prior values to the highest scores; unscored edges (NaN) come last."""
    s = np.where(np.isnan(score), -np.inf, score)
    jitter = np.random.default_rng(SEED).random(len(s)) * 1e-12
    order = np.argsort(-(np.where(np.isfinite(s), s, -1e18) + jitter), kind="stable")
    out = np.empty(len(s), dtype=np.int16)
    out[order] = values_sorted_desc
    return out


def write_variant(name, prior, meta, src_dir=PACK):
    d = BASE / "packs" / name
    d.mkdir(parents=True, exist_ok=True)
    shutil.copy(src_dir / "graph.bin", d / "graph.bin")
    shutil.copy(src_dir / "nodes.bin", d / "nodes.bin")
    buf = bytearray(meta)
    buf[20:20 + 2 * len(prior)] = prior.astype("<i2").tobytes()
    (d / "meta.bin").write_bytes(bytes(buf))
    return d


def densify(path, step_m=50.0):
    pts = np.asarray(path, dtype=np.float64)
    out = [pts[0:1]]
    lat0 = np.radians(pts[:, 0].mean())
    for a, b in zip(pts[:-1], pts[1:]):
        dy = (b[0] - a[0]) * 111320.0
        dx = (b[1] - a[1]) * 111320.0 * np.cos(lat0)
        n = max(int(np.hypot(dx, dy) // step_m), 1)
        t = (np.arange(1, n + 1) / n)[:, None]
        out.append(a + (b - a) * t)
    return np.vstack(out), step_m


def exposure_share(path, y_grid, lon_g, lat_g):
    p, _ = densify(path)
    r, c, ok = cell_index(p[:, 1], p[:, 0], lon_g, lat_g)
    inside = np.zeros(len(p), dtype=bool)
    inside[ok] = y_grid[r[ok], c[ok]]
    return float(inside.mean())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pairs", type=int, default=600)
    a = ap.parse_args()
    t0 = time.time()
    g = np.load(BASE / "grid.npz")
    lon_g, lat_g = g["lon"], g["lat"]
    modelled = g["modelled"]
    FEATS = ["elev", "slope", "tpi1km", "tpi5km", "relief5km", "dist_sea_km", "dist_drain_km", "hand_drain", "dist_water_km", "hand_water"]
    import joblib
    mod = joblib.load(RES / "models.joblib")
    res = json.loads((RES / "result.json").read_text(encoding="utf-8"))
    base_feat = res["results"]["loeo_2005_to_2015_inbox"]["best_baseline"]["feature"]
    F = np.stack([g[f] for f in FEATS], axis=-1).astype(np.float32)
    score_model = np.full(modelled.shape, np.nan)
    score_model[modelled] = mod["model_2005"].predict_proba(F[modelled])[:, 1]
    score_base = np.full(modelled.shape, np.nan)
    score_base[modelled] = -F[modelled][:, FEATS.index(base_feat)]

    src, dst, nlat, nlon, prior, meta = read_pack()
    mlat, mlon = (nlat[src] + nlat[dst]) / 2, (nlon[src] + nlon[dst]) / 2
    r, c, ok = cell_index(mlon, mlat, lon_g, lat_g)
    ok &= modelled[np.clip(r, 0, len(lat_g) - 1), np.clip(c, 0, len(lon_g) - 1)]
    values = np.sort(prior)[::-1].copy()  # highest first: the multiset every variant must use

    def edge_scores(grid):
        s = np.full(len(src), np.nan)
        s[ok] = grid[r[ok], c[ok]]
        return s

    variants = {
        "gcc": prior,
        "model05": allocate(values, edge_scores(score_model)),
        "base05": allocate(values, edge_scores(score_base)),
        "random": allocate(values, np.random.default_rng(SEED + 7).random(len(src))),
        "flat": np.full(len(src), FLAT_MILLI, dtype=np.int16),
    }
    for k, v in variants.items():
        if k != "flat":
            assert np.array_equal(np.sort(v), np.sort(prior)), f"{k} does not hold the same prior values"
        write_variant(k, v, meta)
    print(f"packs written ({time.time()-t0:.0f}s); scored edges {int(ok.sum()):,} of {len(src):,}; baseline feature {base_feat}", flush=True)

    out_json = BASE / "routes.json"
    cmd = ["dart", "run", "tool/prior_routes.dart", str(out_json), str(a.pairs), str(SEED + 11)] + [f"{k}={BASE / 'packs' / k}" for k in variants]
    p = subprocess.run(cmd, cwd=ROOT / "packages" / "pulse_router", capture_output=True, text=True, shell=(sys.platform == "win32"))
    print(p.stdout.strip(), p.stderr.strip()[-400:], flush=True)
    if p.returncode != 0:
        return p.returncode
    data = json.loads(out_json.read_text(encoding="utf-8"))
    y15 = g["y2015"]
    rows = data["rows"]
    names = list(variants)
    table = {f"{k}|{c}": {"exposure": [], "added_min": [], "dist_km": []} for k in names for c in CLASSES}
    for row in rows:
        for c in CLASSES:
            ref = row["routes"][f"flat|{c}"]
            for k in names:
                rt = row["routes"][f"{k}|{c}"]
                t = table[f"{k}|{c}"]
                t["exposure"].append(exposure_share(rt["path"], y15, lon_g, lat_g))
                t["added_min"].append((rt["free_flow_s"] - ref["free_flow_s"]) / 60.0)
                t["dist_km"].append(rt["distance_m"] / 1000.0)
    arr = {k: {m: np.array(v) for m, v in d.items()} for k, d in table.items()}
    rng = np.random.default_rng(SEED + 21)
    n = len(rows)
    idx = [rng.integers(0, n, n) for _ in range(2000)]

    def ci_mean(x):
        b = [x[i].mean() for i in idx]
        return [float(np.percentile(b, 2.5)), float(np.percentile(b, 97.5))]

    summary = {}
    for c in CLASSES:
        flat = arr[f"flat|{c}"]
        for k in names:
            d = arr[f"{k}|{c}"]
            red = flat["exposure"] - d["exposure"]
            summary[f"{k}|{c}"] = {
                "mean_exposure_share": float(d["exposure"].mean()), "reduction_vs_flat": float(red.mean()), "reduction_ci95": ci_mean(red),
                "mean_added_free_flow_min": float(d["added_min"].mean()), "added_min_ci95": ci_mean(d["added_min"]),
                "mean_distance_km": float(d["dist_km"].mean()),
                "share_of_routes_changed": float(np.mean(d["dist_km"] != flat["dist_km"])),
            }
        for other in ("base05", "random", "gcc"):
            diff = (arr[f"{other}|{c}"]["exposure"] - arr[f"model05|{c}"]["exposure"])
            summary[f"model05_better_than_{other}|{c}"] = {"mean_exposure_difference": float(diff.mean()), "ci95": ci_mean(diff)}
    trip_min = float(np.mean([r["routes"][f"flat|commuter"]["free_flow_s"] for r in rows]) / 60.0)
    ok_a = all(summary[f"model05|{c}"]["reduction_ci95"][0] > 0 for c in CLASSES)
    ok_b = summary["model05_better_than_base05|pedestrian"]["ci95"][0] > 0 and summary["model05_better_than_random|pedestrian"]["ci95"][0] > 0
    ok_c = all(summary[f"model05|{c}"]["mean_added_free_flow_min"] <= 0.05 * trip_min for c in CLASSES)
    out = {
        "task": "ADR-026 part C: learned prior against other priors, December 2015 flood extent",
        "preregistration_commit": subprocess.run(["git", "log", "--format=%H", "-1", "--", str(BASE / "PREREGISTRATION_ROUTER.md")], capture_output=True, text=True, cwd=ROOT).stdout.strip(),
        "pairs_requested": a.pairs, "pairs_scored": n, "mean_trip_free_flow_min_flat": trip_min,
        "baseline_feature": base_feat, "scored_edges": int(ok.sum()), "edges": int(len(src)),
        "share_of_pairs_where_route_inside_extent_ever": float(np.mean([arr['flat|commuter']['exposure'][i] > 0 for i in range(n)])),
        "summary": summary,
        "decision_rule": {"a_reduces_exposure_both_classes": bool(ok_a), "b_beats_elevation_and_random_pedestrian": bool(ok_b), "c_added_time_within_5pct": bool(ok_c),
                          "model_prior_improves_routing": bool(ok_a and ok_b and ok_c)},
        "seconds": round(time.time() - t0),
    }
    RES.mkdir(parents=True, exist_ok=True)
    (RES / "router_result.json").write_text(json.dumps(out, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({"decision_rule": out["decision_rule"], "trip_min": trip_min}, indent=1))
    for c in CLASSES:
        for k in names:
            s = summary[f"{k}|{c}"]
            print(f"{c:10s} {k:8s} exposure {s['mean_exposure_share']:.4f}  reduction {s['reduction_vs_flat']:+.4f} {s['reduction_ci95']}  +min {s['mean_added_free_flow_min']:.2f}  changed {s['share_of_routes_changed']:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
