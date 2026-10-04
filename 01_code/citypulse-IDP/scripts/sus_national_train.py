"""Part B step 2 (ADR-026): train and evaluate the nationwide terrain model, exactly as pre-registered in PREREGISTRATION_B.md.

Primary: five-fold spatial-block cross-validation (2 degree blocks) over all sampled cells of all frozen events, pooled out-of-fold.
Secondary: train on events up to 2012, test on later events in blocks that held no training cells.
Models: M1 = terrain features; M2 = M1 plus rainfall climatology from the NASA POWER district points (the earlier rainfall work).
Baselines: the single terrain feature (lower = riskier) with the best weighted AP on the training folds.
Weights: each event counts equally; inside an event the sampled cells are re-weighted to its true observed class sizes (evaluation) or
to equal class totals (training).
Output: data/results/2026-10-04-susceptibility-national/result.json
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree
from sklearn.ensemble import HistGradientBoostingClassifier

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sus_train import ci, weighted_auc, weighted_ap  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
ALL = os.environ.get("SUS_SAMPLES") == "all"  # addendum B2: the windowed builder's samples for all 91 maps
OUT = ROOT / "data" / "results" / ("2026-10-04-susceptibility-national-all" if ALL else "2026-10-04-susceptibility-national")
SEED = 20261004
BOOT = 1000
TERRAIN = ["elev", "elev_min", "elev_range", "slope", "relief5km", "tpi5km", "dist_sea_km", "dist_water_km", "hand_water"]
RAIN = ["rain_annual_mm", "rain_p95_wet_mm"]
RAIN_MAX_KM = 150.0


def hgb():
    return HistGradientBoostingClassifier(learning_rate=0.1, max_depth=4, max_iter=200, l2_regularization=1.0, early_stopping=False, random_state=SEED)


def rain_features(lon, lat):
    z = np.load(BASE.parent.parent / "nationwide_flood" / "2026-10-04" / "power_daily_precip.npz")
    P = z["precip_mm"][:, :7305]  # 1990 to 2009
    annual = P.mean(axis=1) * 365.25
    p95 = np.array([np.percentile(r[r >= 1.0], 95) if (r >= 1.0).any() else np.nan for r in P])
    k = np.cos(np.radians(22.0))
    tree = cKDTree(np.column_stack([z["latitude"], z["longitude"] * k]))
    d, i = tree.query(np.column_stack([lat, lon * k]))
    km = d * 111.0
    far = km > RAIN_MAX_KM
    a, b = annual[i].astype(np.float32), p95[i].astype(np.float32)
    a[far] = np.nan
    b[far] = np.nan
    return a, b, float(far.mean())


def balanced_train_weights(y, ev):
    w = np.zeros(len(y))
    for e in np.unique(ev):
        m = ev == e
        npos, nneg = (y[m] == 1).sum(), (y[m] == 0).sum()
        w[m & (y == 1)] = 0.5 / max(npos, 1)
        w[m & (y == 0)] = 0.5 / max(nneg, 1)
    return w


def sort_pack(score, y, w):
    s = score.astype(np.float64) + np.random.default_rng(SEED).random(len(score)) * 1e-9
    o = np.argsort(-s, kind="stable")
    return o, y[o].astype(np.float64), w[o]


def point(score, y, w):
    o, ys, ws = sort_pack(score, y, w)
    return {"ap": weighted_ap(ys, ws), "auc": weighted_auc(ys, ws)}


def per_event(score, y, w, ev):
    out = {}
    for e in np.unique(ev):
        m = ev == e
        p = point(score[m], y[m], w[m])
        out[int(e)] = {"ap": p["ap"], "auc": p["auc"], "positives_sampled": int((y[m] == 1).sum()), "base_rate": float(np.average(y[m], weights=w[m]))}
    return out


def boot(scores: dict, y, w, blk, seed):
    packs = {k: sort_pack(v, y, w) for k, v in scores.items()}
    nb = int(blk.max()) + 1
    rng = np.random.default_rng(seed)
    d = {k: {"ap": [], "auc": []} for k in scores}
    for _ in range(BOOT):
        mult = np.bincount(rng.integers(0, nb, nb), minlength=nb).astype(np.float64)
        for k, (o, ys, ws) in packs.items():
            ww = ws * mult[blk[o]]
            d[k]["ap"].append(weighted_ap(ys, ww))
            d[k]["auc"].append(weighted_auc(ys, ww))
    return {k: {m: np.array(v) for m, v in dd.items()} for k, dd in d.items()}


def best_single(X, y, w, names):
    best = (-1.0, 0)
    for j in range(X.shape[1]):
        v = np.where(np.isnan(X[:, j]), np.nanmax(X[:, j]), X[:, j])
        ap = point(-v, y, w)["ap"]
        if ap > best[0]:
            best = (ap, j)
    return best[1], best[0]


def main() -> int:
    t0 = time.time()
    OUT.mkdir(parents=True, exist_ok=True)
    z = np.load(BASE / ("national_samples_all.npz" if ALL else "national_samples.npz"))
    y, ev, year = z["y"], z["event"], z["year"]
    lon, lat = z["lon"], z["lat"]
    Xt = np.column_stack([z[k] for k in TERRAIN]).astype(np.float32)
    ra, rp, far_share = rain_features(lon, lat)
    Xr = np.column_stack([Xt, ra, rp])
    w_eval = z["w"].astype(np.float64)
    for e in np.unique(ev):
        w_eval[ev == e] /= w_eval[ev == e].sum()
    w_train = balanced_train_weights(y, ev)
    _, blk = np.unique(np.floor((lat - 5.0) / 2.0).astype(int) * 100 + np.floor((lon - 60.0) / 2.0).astype(int), return_inverse=True)
    fold = (blk * 7919 + 104729) % 5
    print(f"rows {len(y):,}; events {len(np.unique(ev))}; blocks {blk.max() + 1}; positives sampled {int(y.sum()):,}; rain climatology missing for {far_share:.1%}", flush=True)

    oof = {"m1": np.zeros(len(y)), "m2": np.zeros(len(y)), "base": np.zeros(len(y))}
    chosen = []
    for f in range(5):
        tr, te = fold != f, fold == f
        oof["m1"][te] = hgb().fit(Xt[tr], y[tr], sample_weight=w_train[tr]).predict_proba(Xt[te])[:, 1]
        oof["m2"][te] = hgb().fit(Xr[tr], y[tr], sample_weight=w_train[tr]).predict_proba(Xr[te])[:, 1]
        j, ap_tr = best_single(Xt[tr], y[tr], w_eval[tr], TERRAIN)
        chosen.append(TERRAIN[j])
        v = Xt[te][:, j]
        oof["base"][te] = -np.where(np.isnan(v), np.nanmax(Xt[tr][:, j]), v)
        print(f"fold {f} done {time.time() - t0:.0f}s", flush=True)
    pts = {k: point(v, y, w_eval) for k, v in oof.items()}
    d = boot(oof, y, w_eval, blk, SEED + 1)

    def diff(a, b):
        return {m: {"estimate": pts[a][m] - pts[b][m], "ci95": ci(d[a][m] - d[b][m])} for m in ("ap", "auc")}

    res = {
        "spatial_blocks": {
            "rows": int(len(y)), "events": int(len(np.unique(ev))), "best_baseline_per_fold": chosen,
            "m1_terrain": {**pts["m1"], "ci95": {m: ci(d["m1"][m]) for m in ("ap", "auc")}},
            "m2_terrain_plus_rain": {**pts["m2"], "ci95": {m: ci(d["m2"][m]) for m in ("ap", "auc")}},
            "best_single_feature": {**pts["base"], "ci95": {m: ci(d["base"][m]) for m in ("ap", "auc")}},
            "m1_minus_baseline": diff("m1", "base"), "m2_minus_m1": diff("m2", "m1"), "m2_minus_baseline": diff("m2", "base"),
            "per_event_m1": per_event(oof["m1"], y, w_eval, ev), "per_event_baseline": per_event(oof["base"], y, w_eval, ev),
        },
    }
    # secondary: later events, in blocks that held no earlier training cells
    early, late = year <= 2012, year >= 2013
    train_blocks = set(blk[early].tolist())
    keep = late & ~np.isin(blk, list(train_blocks))
    if keep.sum() > 500 and y[keep].sum() > 20 and (y[keep] == 0).sum() > 20 and early.sum() > 500:
        m1 = hgb().fit(Xt[early], y[early], sample_weight=w_train[early])
        j, _ = best_single(Xt[early], y[early], w_eval[early], TERRAIN)
        sc = {"m1": m1.predict_proba(Xt[keep])[:, 1],
              "base": -np.where(np.isnan(Xt[keep][:, j]), np.nanmax(Xt[early][:, j]), Xt[keep][:, j])}
        w2 = w_eval[keep].copy()
        for e in np.unique(ev[keep]):
            w2[ev[keep] == e] /= w2[ev[keep] == e].sum()
        _, b2 = np.unique(blk[keep], return_inverse=True)
        p2 = {k: point(v, y[keep], w2) for k, v in sc.items()}
        d2 = boot(sc, y[keep], w2, b2, SEED + 2)
        res["later_events_unseen_blocks"] = {
            "train_events": int(len(np.unique(ev[early]))), "test_events": int(len(np.unique(ev[keep]))), "test_rows": int(keep.sum()), "baseline_feature": TERRAIN[j],
            "m1": p2["m1"], "baseline": p2["base"],
            "m1_minus_baseline": {m: {"estimate": p2["m1"][m] - p2["base"][m], "ci95": ci(d2["m1"][m] - d2["base"][m])} for m in ("ap", "auc")}}
    else:
        res["later_events_unseen_blocks"] = {"skipped": "too few cells or events after excluding blocks seen in training"}

    a_ok = all(res["spatial_blocks"]["m1_minus_baseline"][m]["ci95"][0] > 0 for m in ("ap", "auc"))
    b_ok = all(res["spatial_blocks"]["m2_minus_m1"][m]["ci95"][0] > 0 for m in ("ap", "auc"))
    out = {
        "task": "ADR-026 Part B nationwide terrain model",
        "preregistration_commit": subprocess.run(["git", "log", "--format=%H", "-1", "--", str(BASE / "PREREGISTRATION_B.md")], capture_output=True, text=True, cwd=ROOT).stdout.strip(),
        "seed": SEED, "bootstrap_resamples": BOOT, "results": res,
        "decision_rule": {"terrain_model_beats_best_single_feature": bool(a_ok), "rain_climatology_adds_over_terrain": bool(b_ok)},
        "seconds": round(time.time() - t0),
    }
    (OUT / "result.json").write_text(json.dumps(out, indent=2, sort_keys=True), encoding="utf-8")
    import joblib
    full = hgb().fit(Xt, y, sample_weight=w_train)
    joblib.dump({"model_terrain": full, "features": TERRAIN}, OUT / "model_terrain.joblib")
    s = res["spatial_blocks"]
    print(json.dumps(out["decision_rule"], indent=1))
    print("M1 AP", round(s["m1_terrain"]["ap"], 4), "AUC", round(s["m1_terrain"]["auc"], 4), "| M2 AP", round(s["m2_terrain_plus_rain"]["ap"], 4), "AUC", round(s["m2_terrain_plus_rain"]["auc"], 4),
          "| baseline AP", round(s["best_single_feature"]["ap"], 4), "AUC", round(s["best_single_feature"]["auc"], 4))
    return 0


if __name__ == "__main__":
    sys.exit(main())
