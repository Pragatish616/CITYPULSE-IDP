"""Stress test and alternative-technique comparison for the nationwide terrain model (ADR-026 B2).

Follows data/susceptibility/2026-10-04/PREREGISTRATION_SCORECARD.md (committed before this script was run). Nothing is tuned.
Stages (run all, or name some on the command line):  repro blocks control calib spread slices learning ablation alt

Output: data/results/2026-10-11-model-scorecard/stress.json (aggregates only; the sampled cells come from CC BY-NC-ND flood maps and stay out of git).
Out-of-fold scores are cached in the scratchpad given by STRESS_CACHE so that a crash does not lose finished stages.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.isotonic import IsotonicRegression
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import SplineTransformer, StandardScaler

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sus_national_train import TERRAIN, balanced_train_weights, best_single, boot, per_event, point  # noqa: E402
from sus_train import ci  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
OUT = ROOT / "data" / "results" / "2026-10-11-model-scorecard"
CACHE = Path(os.environ.get("STRESS_CACHE", str(OUT / "_cache")))
SEED = 20261004
BOOT = 1000


def hgb(mono=None):
    return HistGradientBoostingClassifier(learning_rate=0.1, max_depth=4, max_iter=200, l2_regularization=1.0, early_stopping=False,
                                          random_state=SEED, monotonic_cst=mono)


# ---------------------------------------------------------------- data
z = np.load(BASE / "national_samples_all.npz")
y, ev, year = z["y"], z["event"], z["year"]
lon, lat = z["lon"], z["lat"]
X = np.column_stack([z[k] for k in TERRAIN]).astype(np.float32)
w_eval = z["w"].astype(np.float64)
for e in np.unique(ev):
    w_eval[ev == e] /= w_eval[ev == e].sum()
w_train = balanced_train_weights(y, ev)


def blocks(s):
    key = np.floor((lat - 5.0) / s).astype(int) * 100 + np.floor((lon - 60.0) / s).astype(int)
    _, b = np.unique(key, return_inverse=True)
    return b, (b * 7919 + 104729) % 5


def renorm(w, mask):
    out = w[mask].copy()
    for e in np.unique(ev[mask]):
        m = ev[mask] == e
        out[m] /= out[m].sum()
    return out


def cv(model_fn, Xm, blk, fold, idx=None, train_frac=None, shuffle_y=None, subsample=None):
    """Out-of-fold scores. idx: restrict to these rows (others get NaN). Returns (score, best-single-baseline score, chosen feature names)."""
    n = len(y)
    idx = np.arange(n) if idx is None else idx
    yy = y.copy() if shuffle_y is None else shuffle_y
    score = np.full(n, np.nan)
    base = np.full(n, np.nan)
    chosen = []
    for f in range(5):
        tr = idx[fold[idx] != f]
        te = idx[fold[idx] == f]
        if train_frac is not None:
            rng = np.random.default_rng(SEED + f)
            evs = np.unique(ev[tr])
            keep = rng.choice(evs, size=max(1, int(round(train_frac * len(evs)))), replace=False)
            tr = tr[np.isin(ev[tr], keep)]
        fit_idx = tr
        if subsample is not None and len(tr) > subsample:
            fit_idx = np.random.default_rng(SEED).choice(tr, size=subsample, replace=False)
        m = model_fn()
        m.fit(Xm[fit_idx], yy[fit_idx], **({"sample_weight": w_train[fit_idx]} if not hasattr(m, "steps") else {"logisticregression__sample_weight": w_train[fit_idx]}))
        score[te] = m.predict_proba(Xm[te])[:, 1]
        j, _ = best_single(X[tr], y[tr], w_eval[tr], TERRAIN)
        chosen.append(TERRAIN[j])
        v = X[te][:, j]
        base[te] = -np.where(np.isnan(v), np.nanmax(X[tr][:, j]), v)
    return score, base, chosen


def summarise(score, base, mask, blk, seed):
    """AP/AUC with block-bootstrap CIs for model and baseline and their paired difference, on the rows in mask (renormalised per event)."""
    w = renorm(w_eval, mask)
    yy = y[mask]
    _, b = np.unique(blk[mask], return_inverse=True)
    sc = {"model": score[mask], "base": base[mask]}
    pts = {k: point(v, yy, w) for k, v in sc.items()}
    d = boot(sc, yy, w, b, seed)
    out = {k: {**pts[k], "ci95": {m: ci(d[k][m]) for m in ("ap", "auc")}} for k in sc}
    out["model_minus_base"] = {m: {"estimate": pts["model"][m] - pts["base"][m], "ci95": ci(d["model"][m] - d["base"][m])} for m in ("ap", "auc")}
    pr = float(np.average(yy, weights=w))
    out["prevalence"] = pr
    out["ap_lift_over_prevalence"] = pts["model"]["ap"] / pr if pr > 0 else None
    out["ap_skill_vs_base"] = (pts["model"]["ap"] - pts["base"]["ap"]) / (1 - pts["base"]["ap"])
    out["auc_skill_vs_base"] = (pts["model"]["auc"] - pts["base"]["auc"]) / (1 - pts["base"]["auc"])
    out["rows"] = int(mask.sum())
    out["events"] = int(len(np.unique(ev[mask])))
    return out


def calibrate(score, blk, fold, seed):
    """Isotonic map fitted on the other folds' out-of-fold scores; Brier skill, ECE and slope on the held-out folds."""
    cal = np.zeros(len(y))
    for f in range(5):
        tr, te = fold != f, fold == f
        iso = IsotonicRegression(out_of_bounds="clip", y_min=0.0, y_max=1.0).fit(score[tr], y[tr], sample_weight=w_eval[tr])
        cal[te] = iso.predict(score[te])
    clim = np.zeros(len(y))
    for f in range(5):
        clim[fold == f] = np.average(y[fold != f], weights=w_eval[fold != f])
    brier = float(np.average((cal - y) ** 2, weights=w_eval))
    brier_clim = float(np.average((clim - y) ** 2, weights=w_eval))
    # block bootstrap of the Brier skill score
    _, b = np.unique(blk, return_inverse=True)
    nb = b.max() + 1
    rng = np.random.default_rng(seed)
    bss = []
    num_m = np.bincount(b, weights=w_eval * (cal - y) ** 2, minlength=nb)
    num_c = np.bincount(b, weights=w_eval * (clim - y) ** 2, minlength=nb)
    den = np.bincount(b, weights=w_eval, minlength=nb)
    for _ in range(BOOT):
        mult = np.bincount(rng.integers(0, nb, nb), minlength=nb).astype(float)
        bss.append(1 - (mult * num_m).sum() / (mult * num_c).sum())
    # ECE over 10 equal-count bins (weighted)
    o = np.argsort(cal, kind="stable")
    cw = np.cumsum(w_eval[o])
    bins = np.minimum((cw / cw[-1] * 10).astype(int), 9)
    ece, table = 0.0, []
    for k in range(10):
        m = bins == k
        if not m.any():
            continue
        ww = w_eval[o][m]
        pm, ym = float(np.average(cal[o][m], weights=ww)), float(np.average(y[o][m], weights=ww))
        ece += ww.sum() / w_eval.sum() * abs(pm - ym)
        table.append({"mean_predicted": pm, "observed_rate": ym, "weight_share": float(ww.sum() / w_eval.sum())})
    lg = np.log(np.clip(cal, 1e-4, 1 - 1e-4) / (1 - np.clip(cal, 1e-4, 1 - 1e-4)))
    slope = float(LogisticRegression(C=1e6, max_iter=500).fit(lg.reshape(-1, 1), y, sample_weight=w_eval).coef_[0, 0])
    return {"brier": brier, "brier_climatology": brier_clim, "brier_skill_score": 1 - brier / brier_clim, "brier_skill_ci95": ci(bss),
            "ece": float(ece), "calibration_slope": slope, "reliability": table}


def load(name):
    p = CACHE / f"{name}.npz"
    return np.load(p) if p.exists() else None


def save(name, **arrs):
    CACHE.mkdir(parents=True, exist_ok=True)
    np.savez(CACHE / f"{name}.npz", **arrs)


def oof(name, blk_deg, **kw):
    c = load(name)
    if c is not None:
        return c["score"], c["base"], list(c["chosen"])
    blk, fold = blocks(blk_deg)
    t = time.time()
    s, b, ch = cv(lambda: hgb(), X, blk, fold, **kw)
    save(name, score=s, base=b, chosen=np.array(ch))
    print(f"  {name}: {time.time() - t:.0f}s", flush=True)
    return s, b, ch


def main(stages) -> int:
    t0 = time.time()
    OUT.mkdir(parents=True, exist_ok=True)
    res_path = OUT / os.environ.get("STRESS_JSON", "stress.json")  # parallel runs of different stages write different files; merged afterwards
    start = res_path if res_path.exists() else OUT / "stress.json"
    res = json.loads(start.read_text(encoding="utf-8")) if start.exists() else {}
    res.update({"task": "scorecard stress test of the ADR-026 B2 terrain model", "seed": SEED, "bootstrap_resamples": BOOT,
                "preregistration_commit": subprocess.run(["git", "log", "--format=%H", "-1", "--", str(BASE / "PREREGISTRATION_SCORECARD.md")],
                                                         capture_output=True, text=True, cwd=ROOT).stdout.strip(),
                "rows": int(len(y)), "events": int(len(np.unique(ev)))})

    def flush():
        res_path.write_text(json.dumps(res, indent=2, sort_keys=True), encoding="utf-8")

    allm = np.ones(len(y), dtype=bool)
    blk2, fold2 = blocks(2)
    blk5, fold5 = blocks(5)
    blk10, fold10 = blocks(10)
    print(f"rows {len(y):,}; events {len(np.unique(ev))}; blocks 2/5/10 deg: {blk2.max() + 1}/{blk5.max() + 1}/{blk10.max() + 1}", flush=True)

    if "repro" in stages:
        s, b, ch = oof("oof_2deg", 2)
        r = summarise(s, b, allm, blk2, SEED + 1)
        stored = json.loads((ROOT / "data/results/2026-10-04-susceptibility-national-all/result.json").read_text(encoding="utf-8"))["results"]["spatial_blocks"]
        r["stored_ap"], r["stored_auc"] = stored["m1_terrain"]["ap"], stored["m1_terrain"]["auc"]
        r["reproduced_to_3_decimals"] = bool(abs(r["model"]["ap"] - r["stored_ap"]) < 5e-4 and abs(r["model"]["auc"] - r["stored_auc"]) < 5e-4)
        r["baseline_features"] = ch
        res["t1_repro_2deg"] = r
        flush()
        print("repro", round(r["model"]["ap"], 4), round(r["model"]["auc"], 4), "reproduced:", r["reproduced_to_3_decimals"], flush=True)
        if not r["reproduced_to_3_decimals"]:
            print("STOP: the registered result did not reproduce", flush=True)
            return 1

    if "blocks" in stages:
        for deg, blk in ((5, blk5), (10, blk10)):
            s, b, ch = oof(f"oof_{deg}deg", deg)
            r = summarise(s, b, allm, blk, SEED + deg)
            r["baseline_features"] = ch
            res[f"t2_blocks_{deg}deg"] = r
            flush()
            print(f"blocks {deg}deg AP {r['model']['ap']:.4f} AUC {r['model']['auc']:.4f} | base AP {r['base']['ap']:.4f} AUC {r['base']['auc']:.4f}", flush=True)

    if "control" in stages:
        rng = np.random.default_rng(SEED + 99)
        ys = y.copy()
        for e in np.unique(ev):  # shuffle the labels within each event
            m = np.where(ev == e)[0]
            ys[m] = y[m][rng.permutation(len(m))]
        c = load("oof_control")
        if c is None:
            t = time.time()
            s, b, ch = cv(lambda: hgb(), X, blk2, fold2, shuffle_y=ys)
            save("oof_control", score=s, base=b, chosen=np.array(ch))
            print(f"  control: {time.time() - t:.0f}s", flush=True)
        else:
            s = c["score"]
        w = w_eval
        pt = point(s, ys, w)  # scored against the shuffled labels it was trained on (AUC must be near 0.5)
        res["t3_negative_control"] = {"auc_on_shuffled_labels": pt["auc"], "ap_on_shuffled_labels": pt["ap"],
                                      "passes_0.45_to_0.55": bool(0.45 <= pt["auc"] <= 0.55)}
        flush()
        print("control AUC", round(pt["auc"], 4), flush=True)

    if "calib" in stages:
        for deg, blk, fold in ((2, blk2, fold2), (5, blk5, fold5)):
            s, _, _ = oof(f"oof_{deg}deg", deg)
            res[f"t4_calibration_{deg}deg"] = calibrate(s, blk, fold, SEED + 4)
            r = res[f"t4_calibration_{deg}deg"]
            print(f"calib {deg}deg BSS {r['brier_skill_score']:.3f} {r['brier_skill_ci95']} ECE {r['ece']:.4f} slope {r['calibration_slope']:.2f}", flush=True)
        flush()

    if "spread" in stages:
        s, b, _ = oof("oof_2deg", 2)
        pe = per_event(s, y, w_eval, ev)
        pb = per_event(b, y, w_eval, ev)
        aucs = np.array([v["auc"] for v in pe.values()])
        aps = np.array([v["ap"] for v in pe.values()])
        lifts = np.array([pe[k]["ap"] / pe[k]["base_rate"] if pe[k]["base_rate"] > 0 else np.nan for k in pe])
        res["t5_spread_over_events"] = {
            "events": int(len(pe)), "median_auc": float(np.nanmedian(aucs)), "median_ap": float(np.nanmedian(aps)), "median_ap_lift_over_event_prevalence": float(np.nanmedian(lifts)),
            "share_auc_above_0.5": float(np.nanmean(aucs > 0.5)), "share_auc_above_0.7": float(np.nanmean(aucs > 0.7)), "share_auc_above_0.8": float(np.nanmean(aucs > 0.8)),
            "share_events_model_auc_above_best_single_feature": float(np.mean([pe[k]["auc"] > pb[k]["auc"] for k in pe])),
            "share_events_model_ap_above_best_single_feature": float(np.mean([pe[k]["ap"] > pb[k]["ap"] for k in pe])),
            "worst_5_events_by_auc": sorted([(float(v["auc"]), int(k)) for k, v in pe.items()])[:5]}
        flush()
        print("spread", {k: v for k, v in res["t5_spread_over_events"].items() if k.startswith("share") or k.startswith("median")}, flush=True)

    if "slices" in stages:
        s, b, _ = oof("oof_2deg", 2)
        sl = {"elev_at_most_10m": X[:, 0] <= 10.0,
              "peninsular_india_lat_lt16_lon_76_81": (lat < 16) & (lon >= 76) & (lon <= 81),
              "gangetic_plain_lat_23_30_lon_77_89": (lat >= 23) & (lat <= 30) & (lon >= 77) & (lon <= 89)}
        res["t6_slices"] = {}
        for name, m in sl.items():
            r = summarise(s, b, m, blk2, SEED + 6)
            res["t6_slices"][name] = r
            print(f"slice {name}: events {r['events']} rows {r['rows']:,} AP {r['model']['ap']:.4f} AUC {r['model']['auc']:.4f} | base AP {r['base']['ap']:.4f}", flush=True)
        flush()

    if "learning" in stages:
        res["t7_learning_curve_5deg"] = {}
        for frac in (0.25, 0.5):
            s, b, _ = oof(f"oof_5deg_frac{int(frac * 100)}", 5, train_frac=frac)
            r = summarise(s, b, allm, blk5, SEED + 7)
            res["t7_learning_curve_5deg"][f"{int(frac * 100)}%_of_training_events"] = {"ap": r["model"]["ap"], "auc": r["model"]["auc"], "ci95": r["model"]["ci95"]}
            print(f"learning {frac:.0%}: AP {r['model']['ap']:.4f} AUC {r['model']['auc']:.4f}", flush=True)
        full = res["t2_blocks_5deg"]["model"]
        res["t7_learning_curve_5deg"]["100%_of_training_events"] = {"ap": full["ap"], "auc": full["auc"], "ci95": full["ci95"]}
        flush()

    if "ablation" in stages:
        res.setdefault("t8_feature_ablation_5deg", {})  # only the numbers are kept between runs (a score cache per feature would fill the disk)
        full = res["t2_blocks_5deg"]["model"] if "t2_blocks_5deg" in res else json.loads((OUT / "stress_p1.json").read_text(encoding="utf-8"))["t2_blocks_5deg"]["model"]
        for j, name in enumerate(TERRAIN):
            if name in res["t8_feature_ablation_5deg"]:
                continue
            keep = [k for k in range(len(TERRAIN)) if k != j]
            s, _, _ = cv(lambda: hgb(), X[:, keep], blk5, fold5)
            pt = point(s, y, w_eval)
            res["t8_feature_ablation_5deg"][name] = {"ap": pt["ap"], "auc": pt["auc"], "ap_loss": full["ap"] - pt["ap"], "auc_loss": full["auc"] - pt["auc"]}
            print(f"drop {name}: AP {pt['ap']:.4f} (loss {full['ap'] - pt['ap']:+.4f}) AUC {pt['auc']:.4f}", flush=True)
            flush()

    if "alt" in stages:
        lock = ((blk5 * 104729 + 7919) % 10) < 4
        dev_idx, lock_idx = np.where(~lock)[0], np.where(lock)[0]
        print(f"dev rows {len(dev_idx):,} ({int((~lock).sum()):,}); lock rows {len(lock_idx):,}; dev blocks {len(np.unique(blk5[dev_idx]))}, lock blocks {len(np.unique(blk5[lock_idx]))}", flush=True)
        mono = [-1, -1, 0, -1, -1, -1, -1, -1, -1]  # elev, elev_min, elev_range, slope, relief5km, tpi5km, dist_sea, dist_water, hand_water
        assert TERRAIN == ["elev", "elev_min", "elev_range", "slope", "relief5km", "tpi5km", "dist_sea_km", "dist_water_km", "hand_water"]
        cands = {
            "a_hgb_m1": (lambda: hgb(), None),
            "b_hgb_monotone": (lambda: hgb(mono), None),
            "c_spline_logistic": (lambda: make_pipeline(SimpleImputer(strategy="median"), SplineTransformer(n_knots=6, degree=3, knots="quantile", extrapolation="constant"),
                                                        StandardScaler(), LogisticRegression(C=1.0, max_iter=300)), 400_000),
            "d_random_forest": (lambda: RandomForestClassifier(n_estimators=200, min_samples_leaf=200, n_jobs=-1, random_state=SEED, max_features="sqrt"), 400_000),
        }
        Xi = SimpleImputer(strategy="median").fit_transform(X)
        dev = {}
        prev_dev = dict(res.get("t9_alternatives_dev", {}))
        res["t9_alternatives_dev"] = {}
        for name, (fn, sub) in cands.items():
            c = load(f"alt_dev_{name}")
            if c is None:
                t = time.time()
                Xm = Xi if name.startswith("d_") else X
                s, b, ch = cv(fn, Xm, blk5, fold5, idx=dev_idx, subsample=sub)
                save(f"alt_dev_{name}", score=s, base=b, chosen=np.array(ch))
                print(f"  {name}: {time.time() - t:.0f}s", flush=True)
            else:
                s, b = c["score"], c["base"]
            dev[name] = (s, b)
            devm = ~lock
            if name in prev_dev:  # finished in an earlier run that stopped (disk full); reuse its numbers
                res["t9_alternatives_dev"][name] = prev_dev[name]
                print(f"dev {name}: AP {prev_dev[name]['ap']:.4f} AUC {prev_dev[name]['auc']:.4f} (from the earlier run)", flush=True)
                continue
            r = summarise(s, b, devm, blk5, SEED + 9)
            res["t9_alternatives_dev"][name] = {"ap": r["model"]["ap"], "auc": r["model"]["auc"], "ci95": r["model"]["ci95"], "base_ap": r["base"]["ap"]}
            print(f"dev {name}: AP {r['model']['ap']:.4f} AUC {r['model']['auc']:.4f} (best single feature AP {r['base']['ap']:.4f})", flush=True)
            flush()
        best = max(dev, key=lambda k: res["t9_alternatives_dev"][k]["ap"])
        chosen = best
        if best != "a_hgb_m1":
            devm = ~lock
            w = renorm(w_eval, devm)
            _, bb = np.unique(blk5[devm], return_inverse=True)
            sc = {"x": dev[best][0][devm], "a": dev["a_hgb_m1"][0][devm]}
            d = boot(sc, y[devm], w, bb, SEED + 10)
            lo = ci(d["x"]["ap"] - d["a"]["ap"])[0]
            res["t9_alternatives_dev"]["best_vs_a_ap_diff_ci95"] = ci(d["x"]["ap"] - d["a"]["ap"])
            if lo <= 0:
                chosen = "a_hgb_m1"
        res["t9_chosen_by_rule"] = {"highest_dev_ap": best, "kept_after_interval_rule": chosen}
        print("chosen:", best, "->", chosen, flush=True)
        flush()
        # single lock evaluation: train on all dev cells, score lock cells once
        res["t9_lock_evaluation"] = {}
        lock_scores = {}
        for name in sorted({"a_hgb_m1", chosen}):
            fn, sub = cands[name]
            fit_idx = dev_idx if sub is None or len(dev_idx) <= sub else np.random.default_rng(SEED).choice(dev_idx, size=sub, replace=False)
            Xm = Xi if name.startswith("d_") else X
            m = fn()
            m.fit(Xm[fit_idx], y[fit_idx], **({"sample_weight": w_train[fit_idx]} if not hasattr(m, "steps") else {"logisticregression__sample_weight": w_train[fit_idx]}))
            lock_scores[name] = m.predict_proba(Xm[lock_idx])[:, 1]
        j, _ = best_single(X[dev_idx], y[dev_idx], w_eval[dev_idx], TERRAIN)
        v = X[lock_idx][:, j]
        lock_scores["best_single_feature"] = -np.where(np.isnan(v), np.nanmax(X[dev_idx][:, j]), v)
        wl = renorm(w_eval, lock)
        _, bl = np.unique(blk5[lock], return_inverse=True)
        d = boot(lock_scores, y[lock], wl, bl, SEED + 11)
        for name, sc in lock_scores.items():
            pt = point(sc, y[lock], wl)
            res["t9_lock_evaluation"][name] = {**pt, "ci95": {m: ci(d[name][m]) for m in ("ap", "auc")}}
        for name in sorted(k for k in lock_scores if k != "best_single_feature"):
            res["t9_lock_evaluation"][f"{name}_minus_best_single_feature"] = {m: {"estimate": float(point(lock_scores[name], y[lock], wl)[m] - point(lock_scores["best_single_feature"], y[lock], wl)[m]),
                                                                                  "ci95": ci(d[name][m] - d["best_single_feature"][m])} for m in ("ap", "auc")}
        res["t9_lock_evaluation"]["baseline_feature"] = TERRAIN[j]
        res["t9_lock_evaluation"]["lock_rows"] = int(len(lock_idx))
        res["t9_lock_evaluation"]["lock_events"] = int(len(np.unique(ev[lock])))
        res["t9_lock_evaluation"]["lock_prevalence"] = float(np.average(y[lock], weights=wl))
        if chosen != "a_hgb_m1":
            res["t9_lock_evaluation"]["chosen_minus_a"] = {m: {"estimate": float(point(lock_scores[chosen], y[lock], wl)[m] - point(lock_scores["a_hgb_m1"], y[lock], wl)[m]),
                                                               "ci95": ci(d[chosen][m] - d["a_hgb_m1"][m])} for m in ("ap", "auc")}
        # calibrated probabilities of the chosen model on the lock blocks: isotonic fitted on the dev out-of-fold scores
        sdev = dev[chosen][0][dev_idx]
        iso = IsotonicRegression(out_of_bounds="clip", y_min=0.0, y_max=1.0).fit(sdev, y[dev_idx], sample_weight=w_eval[dev_idx])
        pc = iso.predict(lock_scores[chosen])
        clim = np.average(y[dev_idx], weights=w_eval[dev_idx])
        bm = float(np.average((pc - y[lock]) ** 2, weights=wl))
        bc = float(np.average((clim - y[lock]) ** 2, weights=wl))
        res["t9_lock_evaluation"]["calibrated_brier_skill_vs_climatology"] = 1 - bm / bc
        flush()
        for name in lock_scores:
            print(f"lock {name}: AP {res['t9_lock_evaluation'][name]['ap']:.4f} AUC {res['t9_lock_evaluation'][name]['auc']:.4f} {res['t9_lock_evaluation'][name]['ci95']}", flush=True)
        print("lock calibrated BSS", round(res["t9_lock_evaluation"]["calibrated_brier_skill_vs_climatology"], 3), flush=True)

    res["seconds_last_invocation"] = round(time.time() - t0)
    flush()
    print(f"done in {time.time() - t0:.0f}s", flush=True)
    return 0


if __name__ == "__main__":
    ALL_STAGES = ["repro", "blocks", "control", "calib", "spread", "slices", "learning", "ablation", "alt"]
    sys.exit(main(sys.argv[1:] or ALL_STAGES))
