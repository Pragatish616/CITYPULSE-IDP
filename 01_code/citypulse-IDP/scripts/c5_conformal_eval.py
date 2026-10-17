"""C5: conformal flags for flood-reported edges, exactly as pre-registered in ml/conformal/PREREGISTRATION.md (committed 0dd6a7a).

Run from 01_code/citypulse-IDP:  python scripts/c5_conformal_eval.py
Writes data/results/2026-10-17-c5-conformal/result.json. Seeds: Study 2 pools 20260918 (unchanged), splits 20261017.
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT))

import study2_calibration as s2  # noqa: E402
import t3_2_replay_engine as t32  # noqa: E402

from ml.conformal.flags import fit_thresholds, flag, rates  # noqa: E402

ALPHA = 0.10
N_SPLITS = 200
SPLIT_SEED = 20261017
CELL_DEG = 0.01
KILL_BELOW = 0.85
OUT = ROOT / "data" / "results" / "2026-10-17-c5-conformal" / "result.json"
SCORES = {"S1_c3_p_mean": "p_mean_c3_ours", "S2_prior_only": "p_mean_prior_only"}


def obs_positions() -> dict[str, tuple[float, float]]:
    out = {}
    with open(ROOT / "data" / "corpus" / "2026-09-17" / "observations.ndjson", encoding="utf-8") as f:
        for line in f:
            o = json.loads(line)
            lon, lat = o["geometry"]["coordinates"]
            out[o["id"]] = (lat, lon)
    return out


def build_rows() -> list[dict]:
    hazard_classes = t32.load_hazard_classes()
    crowd_pool, no_report_pool, _ = s2.load_edge_pools()
    crowd_rows = [r for r in s2.score_crowd_pool(crowd_pool, hazard_classes) if r["age_bucket_hours"] == 0]
    no_rows = s2.score_no_report_pool(no_report_pool)
    pos = obs_positions()
    prior = t32.load_prior()
    for r in crowd_rows:
        pts = [pos[o.id] for o in crowd_pool[r["edge_id"]]["crowd_observations"]]
        r["lat"], r["lon"] = float(np.mean([p[0] for p in pts])), float(np.mean([p[1] for p in pts]))
    for r in no_rows:
        geo = prior[r["edge_id"]].get("geometry") or []
        if not geo:
            raise SystemExit(f"no geometry for no-report edge {r['edge_id']}")
        r["lat"], r["lon"] = float(np.mean([g["lat"] for g in geo])), float(np.mean([g["lon"] for g in geo]))
    return crowd_rows + no_rows


def summarise(xs: list[float]) -> dict:
    a = np.array([x for x in xs if not math.isnan(x)])
    if len(a) == 0:
        return {"mean": None, "p05": None, "p95": None, "splits": 0}
    return {"mean": float(a.mean()), "p05": float(np.quantile(a, 0.05)), "p95": float(np.quantile(a, 0.95)), "splits": int(len(a))}


def evaluate(rows: list[dict], split_kind: str, rng: np.random.Generator) -> dict:
    labels = np.array([r["label"] for r in rows])
    groups = np.array([r["hazard_class"] for r in rows], dtype=object)
    cells = np.array([f"{math.floor(r['lat'] / CELL_DEG)}:{math.floor(r['lon'] / CELL_DEG)}" for r in rows], dtype=object)
    unique_cells = np.array(sorted(set(cells)), dtype=object)
    group_names = sorted(set(groups))
    acc: dict = {s: {g: {"cov": [], "ff": [], "c1_cov": [], "c1_ff": [], "tau": []} for g in group_names} for s in SCORES}
    for _ in range(N_SPLITS):
        if split_kind == "random":
            perm = rng.permutation(len(rows))
            cal = np.zeros(len(rows), dtype=bool)
            cal[perm[: len(rows) // 2]] = True
        else:
            pc = rng.permutation(len(unique_cells))
            cal_cells = set(unique_cells[pc[: len(unique_cells) // 2]])
            cal = np.array([c in cal_cells for c in cells])
        test = ~cal
        for sname, key in SCORES.items():
            sc = np.array([r[key] for r in rows], dtype=float)
            th = fit_thresholds(sc[cal], labels[cal], groups[cal], ALPHA)
            f = flag(sc[test], groups[test], th)
            c1 = sc[test] >= 0.5
            for g in group_names:
                m = groups[test] == g
                rr = rates(f[m], labels[test][m])
                r1 = rates(c1[m], labels[test][m])
                a = acc[sname][g]
                a["cov"].append(rr.coverage)
                a["ff"].append(rr.false_flag)
                a["c1_cov"].append(r1.coverage)
                a["c1_ff"].append(r1.false_flag)
                a["tau"].append(th.get(g, -math.inf))
    out: dict = {}
    for sname in SCORES:
        out[sname] = {}
        for g in group_names:
            a = acc[sname][g]
            taus = np.array(a["tau"])
            out[sname][g] = {
                "coverage": summarise(a["cov"]),
                "false_flag_rate": summarise(a["ff"]),
                "c1_block_p_ge_0_5_coverage": summarise(a["c1_cov"]),
                "c1_block_p_ge_0_5_false_flag_rate": summarise(a["c1_ff"]),
                "share_of_splits_threshold_minus_inf": float(np.mean(~np.isfinite(taus))),
                "threshold_median_finite": float(np.median(taus[np.isfinite(taus)])) if np.isfinite(taus).any() else None,
            }
    return out


def main() -> None:
    rows = build_rows()
    labels = np.array([r["label"] for r in rows])
    groups = [r["hazard_class"] for r in rows]
    counts = {
        g: {"positives": int(sum(1 for r in rows if r["hazard_class"] == g and r["label"] == 1)),
            "negatives": int(sum(1 for r in rows if r["hazard_class"] == g and r["label"] == 0))}
        for g in sorted(set(groups))
    }
    rng = np.random.default_rng(SPLIT_SEED)
    random_split = evaluate(rows, "random", rng)
    spatial_split = evaluate(rows, "spatial_blocks", rng)
    decision = {}
    for g in counts:
        cov = spatial_split["S1_c3_p_mean"][g]["coverage"]["mean"]
        ff = spatial_split["S1_c3_p_mean"][g]["false_flag_rate"]["mean"]
        all_inf = spatial_split["S1_c3_p_mean"][g]["share_of_splits_threshold_minus_inf"]
        decision[g] = {
            "spatial_coverage_S1": cov,
            "killed": cov is None or cov < KILL_BELOW,
            "no_information": (ff is not None and ff >= 0.999) or all_inf >= 0.5,
        }
    try:
        commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, cwd=ROOT).stdout.strip()
    except OSError:
        commit = "unknown"
    result = {
        "task": "C5 conformal flags for flood-reported edges",
        "preregistration": "ml/conformal/PREREGISTRATION.md (commit 0dd6a7a)",
        "code_commit_at_run": commit,
        "alpha": ALPHA,
        "splits_per_kind": N_SPLITS,
        "split_seed": SPLIT_SEED,
        "pool_seed": s2.SEED,
        "cell_degrees": CELL_DEG,
        "kill_below_spatial_coverage": KILL_BELOW,
        "rows": len(rows),
        "positives": int(labels.sum()),
        "counts_by_group": counts,
        "random_split": random_split,
        "spatial_split": spatial_split,
        "decision": decision,
        "label_note": "label = edge also has an official report (Study 2); co-location, not observed flooding",
        "limits": "one event (2015), one proxy timestamp; guarantee is within this corpus only",
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"counts": counts, "decision": decision}, indent=1))


if __name__ == "__main__":
    main()
