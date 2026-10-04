"""Part A step 2 (ADR-026): train and evaluate the terrain-and-past-floods susceptibility model, exactly as pre-registered.

Follows data/susceptibility/2026-10-04/PREREGISTRATION.md. Interpretations fixed before the first run:
  * Decision rule (a) uses the leave-one-event-out results INSIDE the 2005 box (2005 -> 2015 restricted to the box, and 2015 -> 2005);
    the whole-area 2005 -> 2015 result is reported as secondary.
  * Rule (b) pools the five spatial folds' out-of-fold scores; the best baseline is chosen per fold on that fold's training cells.
  * Rule (c): a point set counts as "scored" by each model that did not see its event: gcc2015 by the 2005 model, irs2005 by the 2015
    (whole-area) model, gcc2020 by both; the model must beat the best baseline's mean percentile in every one of those four cases.
  * Percentile of a point = share of modelled cells inside the 2005 box whose score is at most the point's cell score.
  * Bootstrap draws are shared between a model and its baseline so their difference is paired.
Output: data/results/2026-10-04-susceptibility-chennai/result.json
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.preprocessing import StandardScaler

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
SMOKE = bool(os.environ.get("SUS_SMOKE"))  # a wiring check with few resamples; its numbers mean nothing
OUT = ROOT / "data" / "results" / ("_smoke_sus" if SMOKE else "2026-10-04-susceptibility-chennai")
SEED = 20261004
FEATURES = ["elev", "slope", "tpi1km", "tpi5km", "relief5km", "dist_sea_km", "dist_drain_km", "hand_drain", "dist_water_km", "hand_water"]
BOOT = 5 if SMOKE else 1000
BLOCK = 0.05
AREA_LON0, AREA_LAT0 = 79.3, 12.5


def hgb():
    return HistGradientBoostingClassifier(learning_rate=0.1, max_depth=4, max_iter=200, l2_regularization=1.0,
                                          class_weight="balanced", early_stopping=False, random_state=SEED)


def weighted_ap(y_desc, w):
    tp = np.cumsum(w * y_desc)
    seen = np.cumsum(w)
    precision = tp / np.maximum(seen, 1e-12)
    pos = (w * y_desc).sum()
    return float((w * y_desc * precision).sum() / pos) if pos > 0 else float("nan")


def weighted_auc(y_desc, w):
    wn = w * (1 - y_desc)
    neg_after = wn.sum() - np.cumsum(wn)
    pos_w = w * y_desc
    denom = pos_w.sum() * wn.sum()
    return float((pos_w * neg_after).sum() / denom) if denom > 0 else float("nan")


def ci(x):
    x = np.asarray(x, dtype=float)
    return [float(np.nanpercentile(x, 2.5)), float(np.nanpercentile(x, 97.5))]


def prepare(score, y):
    s = score.astype(np.float64) + np.random.default_rng(SEED).random(score.shape[0]) * 1e-9
    order = np.argsort(-s, kind="stable")
    thr = np.quantile(s, 0.9)
    return {"order": order, "y": y[order].astype(np.float64), "top": (s[order] >= thr).astype(np.float64),
            "point": {"ap": float(average_precision_score(y, s)), "auc": float(roc_auc_score(y, s)),
                      "top10_capture": float(y[s >= thr].sum() / max(y.sum(), 1))}}


def joint_boot(scores: dict, y, blk, seed):
    """Point estimates plus block-bootstrap draws for several score vectors that share each resample."""
    prep = {k: prepare(v, y) for k, v in scores.items()}
    nb = int(blk.max()) + 1
    rng = np.random.default_rng(seed)
    draws = {k: {"ap": [], "auc": [], "top10_capture": []} for k in scores}
    for _ in range(BOOT):
        mult = np.bincount(rng.integers(0, nb, nb), minlength=nb).astype(np.float64)
        for k, p in prep.items():
            w = mult[blk[p["order"]]]
            draws[k]["ap"].append(weighted_ap(p["y"], w))
            draws[k]["auc"].append(weighted_auc(p["y"], w))
            draws[k]["top10_capture"].append(float((w * p["y"] * p["top"]).sum() / max((w * p["y"]).sum(), 1e-12)))
    return {k: p["point"] for k, p in prep.items()}, {k: {m: np.array(v) for m, v in d.items()} for k, d in draws.items()}


def best_baseline(X, y):
    aps = [average_precision_score(y, -X[:, j]) for j in range(X.shape[1])]
    j = int(np.argmax(aps))
    return j, float(aps[j]), {FEATURES[k]: round(float(a), 4) for k, a in enumerate(aps)}


def evaluate(name, Xtr, ytr, Xte, yte, blk_te, seed):
    m = hgb().fit(Xtr, ytr)
    sm = m.predict_proba(Xte)[:, 1]
    sc = StandardScaler().fit(Xtr)
    lr = LogisticRegression(max_iter=300, class_weight="balanced").fit(sc.transform(Xtr), ytr)
    sl = lr.predict_proba(sc.transform(Xte))[:, 1]
    j, ap_tr, all_tr = best_baseline(Xtr, ytr)
    sb = -Xte[:, j]
    point, draws = joint_boot({"model": sm, "baseline": sb}, yte, blk_te, seed)
    logistic = prepare(sl, yte)["point"]
    d_ap = draws["model"]["ap"] - draws["baseline"]["ap"]
    d_auc = draws["model"]["auc"] - draws["baseline"]["auc"]
    out = {
        "name": name, "train_cells": int(len(ytr)), "train_positives": int(ytr.sum()), "test_cells": int(len(yte)),
        "test_positives": int(yte.sum()), "test_base_rate": float(yte.mean()),
        "model": {**point["model"], "ci95": {k: ci(v) for k, v in draws["model"].items()}},
        "logistic": logistic,
        "best_baseline": {"feature": FEATURES[j], "train_ap": ap_tr, **point["baseline"], "ci95": {k: ci(v) for k, v in draws["baseline"].items()}},
        "single_feature_train_ap": all_tr,
        "model_minus_best_baseline": {"ap": point["model"]["ap"] - point["baseline"]["ap"], "ap_ci95": ci(d_ap),
                                      "auc": point["model"]["auc"] - point["baseline"]["auc"], "auc_ci95": ci(d_auc)},
        "ci_above_zero_ap": bool(ci(d_ap)[0] > 0),
    }
    return out, m, j


def percentile_of_points(score_grid, pts, lon, lat, valid_mask):
    ref_sorted = np.sort(score_grid[valid_mask])
    res, dropped = [], 0
    for lo, la in pts:
        c = int(np.argmin(np.abs(lon - lo))); r = int(np.argmin(np.abs(lat - la)))
        if abs(lon[c] - lo) > 0.002 or abs(lat[r] - la) > 0.002 or not valid_mask[r, c]:
            dropped += 1
            continue
        res.append(float(np.searchsorted(ref_sorted, score_grid[r, c], side="right") / len(ref_sorted)))
    res = np.array(res)
    return {"n": int(len(res)), "dropped": dropped, "mean_percentile": float(res.mean()), "share_top20": float((res >= 0.8).mean())}


def main() -> int:
    t0 = time.time()
    OUT.mkdir(parents=True, exist_ok=True)
    g = np.load(BASE / "grid.npz")
    modelled, y15, y05, box = g["modelled"], g["y2015"], g["y2005"], g["in_box05"]
    lon, lat = g["lon"], g["lat"]
    H, W = modelled.shape
    F = np.stack([g[f] for f in FEATURES], axis=-1).astype(np.float32)
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
    print(f"cells: area {S15.sum():,} (pos2015 {int(ya15.sum()):,}); box {S05.sum():,} (pos2005 {int(ya05.sum()):,}; pos2015 {int(y15_in.sum()):,})", flush=True)

    res["loeo_2005_to_2015_inbox"], m05, j05 = evaluate("2005 -> 2015, inside the 2005 box", X05, ya05, X05, y15_in, b05, SEED + 1)
    print("1a done", f"{time.time()-t0:.0f}s", flush=True)
    res["loeo_2005_to_2015_wholearea"], _, _ = evaluate("2005 -> 2015, whole area", X05, ya05, X15, ya15, b15, SEED + 2)
    print("1a2 done", f"{time.time()-t0:.0f}s", flush=True)
    res["loeo_2015_to_2005"], _, _ = evaluate("2015 (box) -> 2005", X05, y15_in, X05, ya05, b05, SEED + 3)
    print("1b done", f"{time.time()-t0:.0f}s", flush=True)

    fold = fold_of_block[b15]
    oof_m, oof_b, chosen = np.zeros(len(ya15)), np.zeros(len(ya15)), []
    for f in range(5):
        tr, te = fold != f, fold == f
        oof_m[te] = hgb().fit(X15[tr], ya15[tr]).predict_proba(X15[te])[:, 1]
        j, _, _ = best_baseline(X15[tr], ya15[tr])
        chosen.append(FEATURES[j])
        oof_b[te] = -X15[te][:, j]
    point, draws = joint_boot({"model": oof_m, "baseline": oof_b}, ya15, b15, SEED + 4)
    d_ap = draws["model"]["ap"] - draws["baseline"]["ap"]
    res["spatial_blocks_2015"] = {
        "cells": int(len(ya15)), "positives": int(ya15.sum()), "best_baseline_per_fold": chosen,
        "model": {**point["model"], "ci95": {k: ci(v) for k, v in draws["model"].items()}},
        "baseline": {**point["baseline"], "ci95": {k: ci(v) for k, v in draws["baseline"].items()}},
        "model_minus_baseline_ap": point["model"]["ap"] - point["baseline"]["ap"], "ap_ci95": ci(d_ap), "ci_above_zero_ap": bool(ci(d_ap)[0] > 0)}
    print("2 done", f"{time.time()-t0:.0f}s", flush=True)

    m15 = hgb().fit(X15, ya15)
    j15 = best_baseline(X15, ya15)[0]
    j05b = best_baseline(X05, ya05)[0]

    def grid_scores(model=None, j=None):
        sg = np.full((H, W), np.nan)
        sg[modelled] = model.predict_proba(F[modelled])[:, 1] if model is not None else -F[modelled][:, j]
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
        "task": "ADR-026 Part A susceptibility, Chennai region",
        "preregistration_commit": subprocess.run(["git", "log", "--format=%H", "-1", "--", str(BASE / "PREREGISTRATION.md")], capture_output=True, text=True, cwd=ROOT).stdout.strip(),
        "seed": SEED, "bootstrap_resamples": BOOT, "block_deg": BLOCK, "results": res,
        "decision_rule": {"a_both_loeo_directions": bool(a_ok), "b_spatial_blocks": bool(b_ok), "c_external_points": bool(c_ok), "model_adds_value": bool(a_ok and b_ok and c_ok)},
        "seconds": round(time.time() - t0),
    }
    (OUT / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    import joblib
    joblib.dump({"model_2005": m05, "model_2015": m15, "features": FEATURES}, OUT / "models.joblib")
    print(json.dumps(result["decision_rule"], indent=1))
    for k, v in res.items():
        if k != "external_points":
            mdl = v["model"]
            print(k, "| model AP", round(mdl["ap"], 4), "AUC", round(mdl["auc"], 4), "| base rate", round(v.get("test_base_rate", v["positives"] / v["cells"] if "positives" in v else 0), 4))
    return 0


if __name__ == "__main__":
    sys.exit(main())
