"""Part A2 step 2 (ADR-026): train and evaluate with the five added hydrology and street-pattern features, as pre-registered in PREREGISTRATION_A2.md.

Identical to sus_train.py (Part A) in cells, labels, models, folds, intervals and decision rule; differences: 15 features, and a direction for
each single-feature baseline (lower = riskier for the ten terrain features, higher = riskier for the five new ones).
Also reports (not part of the rule): permutation importance on a held-out fold, and the Part A feature set on the same spatial folds.
Output: data/results/2026-10-04-susceptibility-chennai-a2/result.json
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from sklearn.inspection import permutation_importance
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score
from sklearn.preprocessing import StandardScaler

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sus_train import (AREA_LAT0, AREA_LON0, BLOCK, SEED, ci, hgb, joint_boot, percentile_of_points, prepare)  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
OUT = ROOT / "data" / "results" / "2026-10-04-susceptibility-chennai-a2"
OLD = ["elev", "slope", "tpi1km", "tpi5km", "relief5km", "dist_sea_km", "dist_drain_km", "hand_drain", "dist_water_km", "hand_water"]
NEW = ["fill_depth", "log_upslope", "twi", "road_density", "node_density"]
FEATURES = OLD + NEW
DIR = np.array([-1.0] * len(OLD) + [1.0] * len(NEW))  # score = DIR * feature: lower is riskier (-1) or higher is riskier (+1)


def best_baseline(X, y):
    aps = [average_precision_score(y, DIR[j] * X[:, j]) for j in range(X.shape[1])]
    j = int(np.argmax(aps))
    return j, float(aps[j]), {FEATURES[k]: round(float(a), 4) for k, a in enumerate(aps)}


def evaluate(name, Xtr, ytr, Xte, yte, blk_te, seed):
    m = hgb().fit(Xtr, ytr)
    sm = m.predict_proba(Xte)[:, 1]
    sc = StandardScaler().fit(Xtr)
    sl = LogisticRegression(max_iter=300, class_weight="balanced").fit(sc.transform(Xtr), ytr).predict_proba(sc.transform(Xte))[:, 1]
    j, ap_tr, all_tr = best_baseline(Xtr, ytr)
    sb = DIR[j] * Xte[:, j]
    point, draws = joint_boot({"model": sm, "baseline": sb}, yte, blk_te, seed)
    d_ap = draws["model"]["ap"] - draws["baseline"]["ap"]
    d_auc = draws["model"]["auc"] - draws["baseline"]["auc"]
    return {
        "name": name, "train_cells": int(len(ytr)), "train_positives": int(ytr.sum()), "test_cells": int(len(yte)), "test_positives": int(yte.sum()),
        "test_base_rate": float(yte.mean()),
        "model": {**point["model"], "ci95": {k: ci(v) for k, v in draws["model"].items()}},
        "logistic": prepare(sl, yte)["point"],
        "best_baseline": {"feature": FEATURES[j], "train_ap": ap_tr, **point["baseline"], "ci95": {k: ci(v) for k, v in draws["baseline"].items()}},
        "single_feature_train_ap": all_tr,
        "model_minus_best_baseline": {"ap": point["model"]["ap"] - point["baseline"]["ap"], "ap_ci95": ci(d_ap),
                                      "auc": point["model"]["auc"] - point["baseline"]["auc"], "auc_ci95": ci(d_auc)},
        "ci_above_zero_ap": bool(ci(d_ap)[0] > 0),
    }, m, j


def main() -> int:
    t0 = time.time()
    OUT.mkdir(parents=True, exist_ok=True)
    g = np.load(BASE / "grid.npz")
    a2 = np.load(BASE / "grid_a2.npz")
    modelled, y15, y05, box = g["modelled"], g["y2015"], g["y2005"], g["in_box05"]
    lon, lat = g["lon"], g["lat"]
    H, W = modelled.shape
    F = np.stack([(g[f] if f in OLD else a2[f]) for f in FEATURES], axis=-1).astype(np.float32)
    iy = np.floor((np.repeat(lat[:, None], W, 1) - AREA_LAT0) / BLOCK).astype(int)
    ix = np.floor((np.repeat(lon[None, :], H, 0) - AREA_LON0) / BLOCK).astype(int)
    _, block_idx = np.unique((iy * 1000 + ix)[modelled], return_inverse=True)
    block_all = np.full((H, W), -1, dtype=np.int64)
    block_all[modelled] = block_idx
    fold_of_block = (np.arange(block_idx.max() + 1) * 7919 + 104729) % 5

    S15, S05 = modelled, modelled & box
    X15, b15 = F[S15], block_all[S15]
    X05, b05 = F[S05], block_all[S05]
    ya15, ya05, y15_in = y15[S15], y05[S05], y15[S05]
    res = {}
    res["loeo_2005_to_2015_inbox"], m05, j05 = evaluate("2005 -> 2015, inside the 2005 box", X05, ya05, X05, y15_in, b05, SEED + 1)
    print("1a done", f"{time.time()-t0:.0f}s", flush=True)
    res["loeo_2005_to_2015_wholearea"], _, _ = evaluate("2005 -> 2015, whole area", X05, ya05, X15, ya15, b15, SEED + 2)
    res["loeo_2015_to_2005"], _, _ = evaluate("2015 (box) -> 2005", X05, y15_in, X05, ya05, b05, SEED + 3)
    print("1b done", f"{time.time()-t0:.0f}s", flush=True)

    fold = fold_of_block[b15]
    oof_m, oof_old, oof_b, chosen = np.zeros(len(ya15)), np.zeros(len(ya15)), np.zeros(len(ya15)), []
    old_idx = list(range(len(OLD)))
    for f in range(5):
        tr, te = fold != f, fold == f
        oof_m[te] = hgb().fit(X15[tr], ya15[tr]).predict_proba(X15[te])[:, 1]
        oof_old[te] = hgb().fit(X15[tr][:, old_idx], ya15[tr]).predict_proba(X15[te][:, old_idx])[:, 1]
        j, _, _ = best_baseline(X15[tr], ya15[tr])
        chosen.append(FEATURES[j])
        oof_b[te] = DIR[j] * X15[te][:, j]
    point, draws = joint_boot({"model": oof_m, "part_a_features": oof_old, "baseline": oof_b}, ya15, b15, SEED + 4)
    d_ap = draws["model"]["ap"] - draws["baseline"]["ap"]
    d_vs_old = draws["model"]["ap"] - draws["part_a_features"]["ap"]
    res["spatial_blocks_2015"] = {
        "cells": int(len(ya15)), "positives": int(ya15.sum()), "best_baseline_per_fold": chosen,
        "model": {**point["model"], "ci95": {k: ci(v) for k, v in draws["model"].items()}},
        "part_a_feature_set_same_folds": {**point["part_a_features"], "ci95": {k: ci(v) for k, v in draws["part_a_features"].items()}},
        "baseline": {**point["baseline"], "ci95": {k: ci(v) for k, v in draws["baseline"].items()}},
        "model_minus_baseline_ap": point["model"]["ap"] - point["baseline"]["ap"], "ap_ci95": ci(d_ap), "ci_above_zero_ap": bool(ci(d_ap)[0] > 0),
        "model_minus_part_a_features_ap": point["model"]["ap"] - point["part_a_features"]["ap"], "vs_part_a_ap_ci95": ci(d_vs_old)}
    print("2 done", f"{time.time()-t0:.0f}s", flush=True)

    # permutation importance on the held-out fold 0 (reported, not part of the rule)
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
        sg[modelled] = model.predict_proba(F[modelled])[:, 1] if model is not None else DIR[j] * F[modelled][:, j]
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

    a_ok = all(res[k]["ci_above_zero_ap"] for k in ("loeo_2005_to_2015_inbox", "loeo_2015_to_2005"))
    b_ok = res["spatial_blocks_2015"]["ci_above_zero_ap"]
    c_ok = all(v["model_better"] for v in ext.values())
    result = {
        "task": "ADR-026 Part A2 susceptibility with hydrology and street-pattern features, Chennai region",
        "preregistration_commit": subprocess.run(["git", "log", "--format=%H", "-1", "--", str(BASE / "PREREGISTRATION_A2.md")], capture_output=True, text=True, cwd=ROOT).stdout.strip(),
        "seed": SEED, "features": FEATURES, "results": res,
        "decision_rule": {"a_both_loeo_directions": bool(a_ok), "b_spatial_blocks": bool(b_ok), "c_external_points": bool(c_ok), "model_adds_value": bool(a_ok and b_ok and c_ok)},
        "seconds": round(time.time() - t0),
    }
    (OUT / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    import joblib
    joblib.dump({"model_2005": m05, "model_2015": m15, "features": FEATURES, "direction": DIR}, OUT / "models.joblib")
    print(json.dumps(result["decision_rule"], indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
