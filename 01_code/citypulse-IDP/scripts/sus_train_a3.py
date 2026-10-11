"""Part A3 step 2 (ADR-034): do the OpenStreetMap features add value over the A2 feature set? As pre-registered in PREREGISTRATION_A3.md.

Model B = the 15 A2 features plus six OSM features; comparator A2 = the 15 A2 features, trained on the same rows and folds in the same run so
that every difference is paired. Cells, labels, classifier, folds, blocks and bootstrap are those of sus_train_a2.py.
Rule: the OSM features add value only if (a) in both core directions the AUC of B beats the AUC of A2 with the 95% interval of the paired
difference above zero, and (b) in the spatial blocks the AP of B beats the AP of A2 the same way.
Output: data/results/2026-10-11-susceptibility-chennai-a3/result.json
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from sklearn.inspection import permutation_importance
from sklearn.metrics import average_precision_score

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sus_train import AREA_LAT0, AREA_LON0, BLOCK, SEED, ci, hgb, joint_boot, percentile_of_points  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
OUT = ROOT / "data" / "results" / "2026-10-11-susceptibility-chennai-a3"
OLD = ["elev", "slope", "tpi1km", "tpi5km", "relief5km", "dist_sea_km", "dist_drain_km", "hand_drain", "dist_water_km", "hand_water"]
A2NEW = ["fill_depth", "log_upslope", "twi", "road_density", "node_density"]
A3NEW = ["bld_share_90m", "bld_share_1km", "built_landuse_1km", "green_landuse_1km", "dist_waterway_km", "dist_waterbody_km"]
A2F = OLD + A2NEW
FEATURES = A2F + A3NEW
# score = DIR * feature: lower is riskier (-1) or higher is riskier (+1)
DIR = np.array([-1.0] * len(OLD) + [1.0] * len(A2NEW) + [1.0, 1.0, 1.0, -1.0, -1.0, -1.0])
NA2 = len(A2F)


def best_baseline(X, y):
    aps = [average_precision_score(y, DIR[j] * np.nan_to_num(X[:, j], nan=np.nanmedian(X[:, j]))) for j in range(X.shape[1])]
    j = int(np.argmax(aps))
    return j, float(aps[j])


def paired(name, Xtr, ytr, Xte, yte, blk_te, seed, low_mask_te):
    """Train B (all features) and A2 (first 15) on the training event, score the test event, paired bootstrap."""
    mB = hgb().fit(Xtr, ytr)
    mA = hgb().fit(Xtr[:, :NA2], ytr)
    sB, sA = mB.predict_proba(Xte)[:, 1], mA.predict_proba(Xte[:, :NA2])[:, 1]
    j, ap_tr = best_baseline(Xtr, ytr)
    sb = DIR[j] * np.nan_to_num(Xte[:, j], nan=np.nanmedian(Xtr[:, j]))
    point, draws = joint_boot({"B": sB, "A2": sA, "baseline": sb}, yte, blk_te, seed)

    def d(a, b, m):
        return {"estimate": point[a][m] - point[b][m], "ci95": ci(draws[a][m] - draws[b][m])}

    out = {"name": name, "train_cells": int(len(ytr)), "train_positives": int(ytr.sum()), "test_cells": int(len(yte)), "test_positives": int(yte.sum()),
           "test_base_rate": float(yte.mean()), "best_baseline": {"feature": FEATURES[j], "train_ap": ap_tr},
           "B_osm_added": {**point["B"], "ci95": {k: ci(v) for k, v in draws["B"].items()}},
           "A2": {**point["A2"], "ci95": {k: ci(v) for k, v in draws["A2"].items()}},
           "baseline": {**point["baseline"], "ci95": {k: ci(v) for k, v in draws["baseline"].items()}},
           "B_minus_A2": {m: d("B", "A2", m) for m in ("ap", "auc")}, "B_minus_baseline": {m: d("B", "baseline", m) for m in ("ap", "auc")}}
    if low_mask_te is not None and low_mask_te.sum() > 1000 and yte[low_mask_te].sum() > 50 and (1 - yte[low_mask_te]).sum() > 50:
        p2, d2 = joint_boot({"B": sB[low_mask_te], "A2": sA[low_mask_te], "baseline": sb[low_mask_te]}, yte[low_mask_te], blk_te[low_mask_te], seed + 50)
        out["cells_at_most_10m_elevation"] = {"cells": int(low_mask_te.sum()), "B": p2["B"], "A2": p2["A2"], "baseline": p2["baseline"],
                                              "B_minus_A2_auc": {"estimate": p2["B"]["auc"] - p2["A2"]["auc"], "ci95": ci(d2["B"]["auc"] - d2["A2"]["auc"])}}
    return out, mB, j


def main() -> int:
    t0 = time.time()
    OUT.mkdir(parents=True, exist_ok=True)
    g = np.load(BASE / "grid.npz")
    a2 = np.load(BASE / "grid_a2.npz")
    a3 = np.load(BASE / "grid_a3.npz")
    modelled, y15, y05, box = g["modelled"], g["y2015"], g["y2005"], g["in_box05"]
    lon, lat = g["lon"], g["lat"]
    H, W = modelled.shape
    F = np.stack([(g[f] if f in OLD else a2[f] if f in A2NEW else a3[f]) for f in FEATURES], axis=-1).astype(np.float32)
    elev = g["elev"]
    iy = np.floor((np.repeat(lat[:, None], W, 1) - AREA_LAT0) / BLOCK).astype(int)
    ix = np.floor((np.repeat(lon[None, :], H, 0) - AREA_LON0) / BLOCK).astype(int)
    _, block_idx = np.unique((iy * 1000 + ix)[modelled], return_inverse=True)
    block_all = np.full((H, W), -1, dtype=np.int64)
    block_all[modelled] = block_idx
    fold_of_block = (np.arange(block_idx.max() + 1) * 7919 + 104729) % 5

    S15, S05 = modelled, modelled & box
    X15, b15, e15 = F[S15], block_all[S15], elev[S15]
    X05, b05, e05 = F[S05], block_all[S05], elev[S05]
    ya15, ya05, y15_in = y15[S15], y05[S05], y15[S05]
    res = {}
    res["core_2005_to_2015"], m05, j05 = paired("2005 -> 2015, inside the 2005 box (the city core)", X05, ya05, X05, y15_in, b05, SEED + 1, e05 <= 10.0)
    print("core 2005->2015 done", f"{time.time()-t0:.0f}s", flush=True)
    res["core_2015_to_2005"], _, _ = paired("2015 (box) -> 2005, the city core", X05, y15_in, X05, ya05, b05, SEED + 3, e05 <= 10.0)
    print("core 2015->2005 done", f"{time.time()-t0:.0f}s", flush=True)

    fold = fold_of_block[b15]
    oB, oA, ob, chosen = np.zeros(len(ya15)), np.zeros(len(ya15)), np.zeros(len(ya15)), []
    for f in range(5):
        tr, te = fold != f, fold == f
        oB[te] = hgb().fit(X15[tr], ya15[tr]).predict_proba(X15[te])[:, 1]
        oA[te] = hgb().fit(X15[tr][:, :NA2], ya15[tr]).predict_proba(X15[te][:, :NA2])[:, 1]
        j, _ = best_baseline(X15[tr], ya15[tr])
        chosen.append(FEATURES[j])
        ob[te] = DIR[j] * np.nan_to_num(X15[te][:, j], nan=np.nanmedian(X15[tr][:, j]))
    point, draws = joint_boot({"B": oB, "A2": oA, "baseline": ob}, ya15, b15, SEED + 4)

    def d(a, b, m):
        return {"estimate": point[a][m] - point[b][m], "ci95": ci(draws[a][m] - draws[b][m])}

    res["spatial_blocks_2015"] = {
        "cells": int(len(ya15)), "positives": int(ya15.sum()), "best_baseline_per_fold": chosen,
        "B_osm_added": {**point["B"], "ci95": {k: ci(v) for k, v in draws["B"].items()}},
        "A2": {**point["A2"], "ci95": {k: ci(v) for k, v in draws["A2"].items()}},
        "baseline": {**point["baseline"], "ci95": {k: ci(v) for k, v in draws["baseline"].items()}},
        "B_minus_A2": {m: d("B", "A2", m) for m in ("ap", "auc")}, "B_minus_baseline": {m: d("B", "baseline", m) for m in ("ap", "auc")}}
    low = e15 <= 10.0
    p2, d2 = joint_boot({"B": oB[low], "A2": oA[low], "baseline": ob[low]}, ya15[low], b15[low], SEED + 5)
    res["spatial_blocks_2015"]["cells_at_most_10m_elevation"] = {
        "cells": int(low.sum()), "positives": int(ya15[low].sum()), "B": p2["B"], "A2": p2["A2"], "baseline": p2["baseline"],
        "B_minus_A2_auc": {"estimate": p2["B"]["auc"] - p2["A2"]["auc"], "ci95": ci(d2["B"]["auc"] - d2["A2"]["auc"])}}
    print("spatial blocks done", f"{time.time()-t0:.0f}s", flush=True)

    tr, te = fold != 0, fold == 0
    mm = hgb().fit(X15[tr], ya15[tr])
    sub = np.random.default_rng(SEED).choice(np.nonzero(te)[0], size=min(60000, int(te.sum())), replace=False)
    pi = permutation_importance(mm, X15[sub], ya15[sub], scoring="average_precision", n_repeats=3, random_state=SEED)
    res["permutation_importance_fold0"] = {FEATURES[k]: round(float(pi.importances_mean[k]), 4) for k in np.argsort(-pi.importances_mean)}

    m15 = hgb().fit(X15, ya15)
    j15 = best_baseline(X15, ya15)[0]
    j05b = best_baseline(X05, ya05)[0]

    def grid_scores(model=None, j=None):
        sg = np.full((H, W), np.nan)
        sg[modelled] = model.predict_proba(F[modelled])[:, 1] if model is not None else DIR[j] * np.nan_to_num(F[modelled][:, j], nan=0.0)
        return sg

    sg_m05, sg_b05, sg_m15, sg_b15 = grid_scores(m05), grid_scores(None, j05b), grid_scores(m15), grid_scores(None, j15)
    pts = {k: g[f"pts_{k}"] for k in ("gcc2015", "gcc2020", "irs2005")}
    ext = {}
    for pname, mname, sgm, sgb in [("gcc2015", "model_2005", sg_m05, sg_b05), ("gcc2020", "model_2005", sg_m05, sg_b05),
                                   ("irs2005", "model_2015", sg_m15, sg_b15), ("gcc2020", "model_2015", sg_m15, sg_b15)]:
        a = percentile_of_points(sgm, pts[pname], lon, lat, S05)
        b = percentile_of_points(sgb, pts[pname], lon, lat, S05)
        ext[f"{pname}__{mname}"] = {"model": a, "best_baseline": b, "model_better": bool(a["mean_percentile"] > b["mean_percentile"])}
    res["external_points"] = ext

    a_ok = all(res[k]["B_minus_A2"]["auc"]["ci95"][0] > 0 for k in ("core_2005_to_2015", "core_2015_to_2005"))
    b_ok = res["spatial_blocks_2015"]["B_minus_A2"]["ap"]["ci95"][0] > 0
    a2_rule = {
        "a_both_loeo_directions_ap_beats_baseline": bool(all(res[k]["B_minus_baseline"]["ap"]["ci95"][0] > 0 for k in ("core_2005_to_2015", "core_2015_to_2005"))),
        "b_spatial_blocks_ap_beats_baseline": bool(res["spatial_blocks_2015"]["B_minus_baseline"]["ap"]["ci95"][0] > 0),
        "c_external_points": bool(all(v["model_better"] for v in ext.values()))}
    result = {
        "task": "ADR-034 Part A3: OpenStreetMap street-scale features, Chennai region",
        "preregistration_commit": subprocess.run(["git", "log", "--format=%H", "-1", "--", str(BASE / "PREREGISTRATION_A3.md")], capture_output=True, text=True, cwd=ROOT).stdout.strip(),
        "seed": SEED, "features": FEATURES, "results": res,
        "decision_rule": {"a_core_both_directions_auc_B_beats_A2": bool(a_ok), "b_spatial_blocks_ap_B_beats_A2": bool(b_ok), "osm_features_add_value": bool(a_ok and b_ok)},
        "a2_style_rule_reported_only": a2_rule,
        "seconds": round(time.time() - t0),
    }
    (OUT / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({"decision_rule": result["decision_rule"], "a2_style": a2_rule}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
