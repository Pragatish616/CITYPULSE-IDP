"""Step 4 (ADR-025): train and evaluate the nationwide district flood-event model, exactly as pre-registered.

Follows data/nationwide_flood/2026-10-04/PREREGISTRATION.md (committed before this script was run). Where the
pre-registration left a detail open, the choice made here was fixed before any run and is listed in `clarifications`
in the result file:
  * Grid configurations are ranked by validation average precision, each at its best validation log-loss iteration
    (checked every 10 iterations).
  * Ties in scores (the monthly-rate baseline has many) are broken with a tiny fixed random jitter for every method,
    so that "top 2%" is well defined.
  * The bootstrap resamples the 8 test years; each resample re-weights the rows of a year by how often it was drawn.

Output: data/results/2026-10-04-nationwide-flood-gating/result.json (and model.joblib).
"""

from __future__ import annotations

import csv
import datetime as dt
import json
import re
import subprocess
import sys
import time
from itertools import product
from pathlib import Path

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import average_precision_score, brier_score_loss, log_loss

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "nationwide_flood" / "2026-10-04"
OUT = ROOT / "data" / "results" / "2026-10-04-nationwide-flood-gating"
SEED = 20261004
START = dt.date(1990, 1, 1)
T = 12418
TRAIN_END, VAL_END = dt.date(2009, 12, 31), dt.date(2015, 12, 31)
ALERT_FRACTION = 0.02
GRID = list(product([0.05, 0.1], [3, 5], [0.0, 1.0]))  # learning rate, max depth, l2
FEATURES = [
    "r0", "r3", "r7", "r14", "r30", "r90", "mx7",
    "n_r0", "n_r3", "n_r7", "n_r14", "n_r30", "n_r90", "n_mx7",
    "doy_sin", "doy_cos", "elevation",
]


def slug(did: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", did)


def load():
    geo = json.loads((BASE / "geocode.json").read_text(encoding="utf-8"))
    merged = geo["merged_into"]
    ids = sorted(geo["chosen"])
    index = {d: i for i, d in enumerate(ids)}
    P = np.zeros((len(ids), T), dtype=np.float32)
    elev = np.zeros(len(ids), dtype=np.float32)
    for d in ids:
        j = json.loads((BASE / "rain" / f"{slug(d)}.json").read_text(encoding="utf-8"))
        P[index[d]] = np.array([0.0 if v is None else v for v in j["precip_mm"]], dtype=np.float32)
        elev[index[d]] = j.get("elevation") or 0.0
    Y = np.zeros((len(ids), T), dtype=bool)
    events = []  # (district index, first day index, last day index)
    dropped = 0
    for r in csv.DictReader((BASE / "district_events.csv").open(encoding="utf-8")):
        did = merged.get(r["district_id"], r["district_id"])
        if did not in index:
            dropped += 1
            continue
        a = max((dt.date.fromisoformat(r["start"]) - START).days, 0)
        b = min((dt.date.fromisoformat(r["end"]) - START).days, T - 1)
        if b < a:
            continue
        Y[index[did], a : b + 1] = True
        events.append((index[did], a, b))
    states = [d.split("|")[0] for d in ids]
    return ids, states, P, elev, Y, events, dropped


def rolling_sum(P, k):
    cs = np.cumsum(P, axis=1, dtype=np.float64)
    out = cs.copy()
    out[:, k:] = cs[:, k:] - cs[:, :-k]
    return out.astype(np.float32)


def rolling_max(P, k):
    pad = np.pad(P, ((0, 0), (k - 1, 0)))
    win = np.lib.stride_tricks.sliding_window_view(pad, k, axis=1)
    return win.max(axis=2)


def build_features(P, elev, train_cols):
    D = P.shape[0]
    r = {"r0": P, "r3": rolling_sum(P, 3), "r7": rolling_sum(P, 7), "r14": rolling_sum(P, 14),
         "r30": rolling_sum(P, 30), "r90": rolling_sum(P, 90), "mx7": rolling_max(P, 7)}
    tr = P[:, train_cols]
    mean_annual = tr.sum(axis=1) / 20.0
    wet_p95 = np.ones(D, dtype=np.float32)
    for d in range(D):
        wet = tr[d][tr[d] >= 1.0]
        if wet.size:
            wet_p95[d] = max(np.percentile(wet, 95), 1.0)
    p95_3d = np.maximum(np.percentile(r["r3"][:, train_cols], 95, axis=1), 1.0).astype(np.float32)
    div = {"r0": wet_p95, "r3": p95_3d, "r7": p95_3d, "r14": np.maximum(mean_annual / 26.0, 1.0),
           "r30": np.maximum(mean_annual / 12.0, 1.0), "r90": np.maximum(mean_annual / 4.0, 1.0), "mx7": wet_p95}
    feats = {k: v for k, v in r.items()}
    for k in r:
        feats["n_" + k] = r[k] / div[k][:, None]
    doy = np.array([(START + dt.timedelta(i)).timetuple().tm_yday for i in range(T)], dtype=np.float32)
    feats["doy_sin"] = np.broadcast_to(np.sin(2 * np.pi * doy / 366)[None, :], P.shape)
    feats["doy_cos"] = np.broadcast_to(np.cos(2 * np.pi * doy / 366)[None, :], P.shape)
    feats["elevation"] = np.broadcast_to(elev[:, None], P.shape)
    return feats, r["r3"], p95_3d


def flat(feats, cols, d_idx=None):
    sel = slice(None) if d_idx is None else d_idx
    return np.stack([np.ascontiguousarray(feats[k][sel][:, cols]).reshape(-1) for k in FEATURES], axis=1).astype(np.float32)


def weighted_ap(order_y, w):
    """Average precision with row weights, rows already sorted by descending score."""
    tp = np.cumsum(w * order_y)
    seen = np.cumsum(w)
    precision = tp / np.maximum(seen, 1e-12)
    pos = (w * order_y).sum()
    return float((w * order_y * precision).sum() / pos) if pos > 0 else float("nan")


def evaluate(scores, y, years, events_te, day_year_offset, n_days_te, n_dist, boot, rng_seed):
    """Point estimates and a year-block bootstrap for one score vector over the test block."""
    rng = np.random.default_rng(SEED + 1)
    jitter = np.random.default_rng(SEED).random(scores.shape[0]) * 1e-9
    s = scores.astype(np.float64) + jitter
    order = np.argsort(-s, kind="stable")
    ys = y[order]
    yrs = years[order]
    ap = average_precision_score(y, s)
    thr = np.partition(s, int(len(s) * (1 - ALERT_FRACTION)))[int(len(s) * (1 - ALERT_FRACTION))]
    S = s.reshape(n_dist, n_days_te)
    caught = []
    for d, a, b in events_te:  # day indices relative to the test block
        lo = max(a - 1, 0)
        caught.append(bool(S[d, lo : b + 1].max() >= thr))
    caught = np.array(caught)
    ev_years = np.array([day_year_offset[a] for _, a, _ in events_te])
    uy = np.unique(years)
    ap_b, rec_b = [], []
    for _ in range(boot):
        draw = rng.choice(uy, size=len(uy), replace=True)
        mult = {y_: int((draw == y_).sum()) for y_ in uy}
        w_rows = np.array([mult[int(y_)] for y_ in yrs], dtype=np.float64)
        ap_b.append(weighted_ap(ys, w_rows))
        wc = np.array([mult[int(y_)] for y_ in ev_years], dtype=np.float64)
        rec_b.append(float((wc * caught).sum() / max(wc.sum(), 1e-12)))
    return {
        "ap": float(ap), "event_recall_at_2pct": float(caught.mean()), "alerted_share": float((s >= thr).mean()),
        "brier": None,
    }, np.array(ap_b), np.array(rec_b)


def main() -> int:
    t0 = time.time()
    OUT.mkdir(parents=True, exist_ok=True)
    ids, states, P, elev, Y, events, dropped = load()
    D = len(ids)
    day = np.array([(START + dt.timedelta(i)) for i in range(T)])
    year = np.array([d.year for d in day])
    month = np.array([d.month for d in day])
    train_cols = np.where(np.array([d <= TRAIN_END for d in day]))[0]
    val_cols = np.where(np.array([TRAIN_END < d <= VAL_END for d in day]))[0]
    test_cols = np.where(np.array([d > VAL_END for d in day]))[0]
    assert len(train_cols) == 7305
    feats, r3, p95_3d = build_features(P, elev, train_cols)
    state_arr = np.array(states)

    # --- baselines ---
    month_rate = np.zeros((D, 12), dtype=np.float32)
    for m in range(1, 13):
        cols = train_cols[month[train_cols] == m]
        month_rate[:, m - 1] = Y[:, cols].mean(axis=1)
    b1 = month_rate[:, month - 1]
    b2 = feats["n_r3"]

    def block(cols, arr):
        return arr[:, cols].reshape(-1)

    Xtr, ytr = flat(feats, train_cols), Y[:, train_cols].reshape(-1)
    Xva, yva = flat(feats, val_cols), Y[:, val_cols].reshape(-1)
    Xte, yte = flat(feats, test_cols), Y[:, test_cols].reshape(-1)
    print(f"districts {D}; train rows {len(ytr):,} (pos {int(ytr.sum()):,}); val {len(yva):,} (pos {int(yva.sum()):,}); test {len(yte):,} (pos {int(yte.sum()):,}); load {time.time()-t0:.0f}s", flush=True)

    # --- grid on validation ---
    grid_log = []
    best = None
    for lr, depth, l2 in GRID:
        m = HistGradientBoostingClassifier(learning_rate=lr, max_depth=depth, l2_regularization=l2, max_iter=300,
                                           early_stopping=False, class_weight="balanced", random_state=SEED)
        m.fit(Xtr, ytr)
        best_ll, best_it, p_at = 1e9, 10, None
        for i, p in enumerate(m.staged_predict_proba(Xva)):
            if (i + 1) % 10 == 0:
                ll = log_loss(yva, p[:, 1], labels=[False, True])
                if ll < best_ll:
                    best_ll, best_it, p_at = ll, i + 1, p[:, 1].copy()
        ap = float(average_precision_score(yva, p_at))
        grid_log.append({"learning_rate": lr, "max_depth": depth, "l2": l2, "best_iteration": best_it, "val_logloss": best_ll, "val_ap": ap})
        print(f"grid lr={lr} depth={depth} l2={l2}: best_it={best_it} val_ap={ap:.4f} ({time.time()-t0:.0f}s)", flush=True)
        if best is None or ap > best[0]:
            best = (ap, (lr, depth, l2), best_it, m)
    _, (lr, depth, l2), best_it, model = best

    def score(m, X, it):
        for i, p in enumerate(m.staged_predict_proba(X)):
            if i + 1 == it:
                return p[:, 1].astype(np.float64)

    # --- test, once ---
    te_year = np.repeat(year[test_cols][None, :], D, axis=0).reshape(-1)
    te_events = [(d, a - test_cols[0], b - test_cols[0]) for d, a, b in events if a >= test_cols[0]]
    te_events = [(d, a, min(b, len(test_cols) - 1)) for d, a, b in te_events]
    day_year = year[test_cols]
    boot = 2000
    results, boots = {}, {}
    scores = {"model": score(model, Xte, best_it), "b1_month_rate": block(test_cols, b1).astype(np.float64), "b2_rain_rule": block(test_cols, b2).astype(np.float64)}
    for name, s in scores.items():
        met, ap_b, rec_b = evaluate(s, yte, te_year, te_events, day_year, len(test_cols), D, boot, SEED)
        met["brier"] = float(brier_score_loss(yte, np.clip(s, 0, 1))) if name == "b1_month_rate" else None
        results[name], boots[name] = met, (ap_b, rec_b)
    diffs = {}
    for base in ("b1_month_rate", "b2_rain_rule"):
        for i, metric in enumerate(("ap", "event_recall_at_2pct")):
            d = boots["model"][i] - boots[base][i]
            lo, hi = np.percentile(d, [2.5, 97.5])
            diffs[f"model_minus_{base}__{metric}"] = {"estimate": results["model"][metric] - results[base][metric], "ci95": [float(lo), float(hi)]}
    for name in results:
        ap_b, rec_b = boots[name]
        results[name]["ap_ci95"] = [float(x) for x in np.percentile(ap_b, [2.5, 97.5])]
        results[name]["event_recall_ci95"] = [float(x) for x in np.percentile(rec_b, [2.5, 97.5])]

    # --- state holdout (validation years) ---
    uniq = sorted(set(states))
    fold_of = {s: i % 5 for i, s in enumerate(uniq)}
    folds = []
    full_val = score(model, Xva, best_it)
    for f in range(5):
        held = np.array([fold_of[s] == f for s in states])
        if held.sum() == 0:
            continue
        Xf, yf = flat(feats, train_cols, ~held), Y[~held][:, train_cols].reshape(-1)
        mf = HistGradientBoostingClassifier(learning_rate=lr, max_depth=depth, l2_regularization=l2, max_iter=best_it,
                                            early_stopping=False, class_weight="balanced", random_state=SEED).fit(Xf, yf)
        Xh, yh = flat(feats, val_cols, held), Y[held][:, val_cols].reshape(-1)
        row_held = np.repeat(held, len(val_cols))
        folds.append({
            "fold": f, "held_out_states": [s for s in uniq if fold_of[s] == f], "districts": int(held.sum()),
            "positives": int(yh.sum()),
            "ap_model_unseen_states": float(average_precision_score(yh, mf.predict_proba(Xh)[:, 1])),
            "ap_model_trained_on_all_states": float(average_precision_score(yh, full_val[row_held])),
            "ap_b1": float(average_precision_score(yh, block(val_cols, b1)[row_held])),
            "ap_b2": float(average_precision_score(yh, block(val_cols, b2)[row_held])),
        })
        print("fold", f, folds[-1], flush=True)

    ap_unseen = float(np.mean([x["ap_model_unseen_states"] for x in folds]))
    ap_base_best = float(max(np.mean([x["ap_b1"] for x in folds]), np.mean([x["ap_b2"] for x in folds])))
    wins = all(diffs[k]["ci95"][0] > 0 for k in diffs) and ap_unseen >= ap_base_best
    result = {
        "task": "ADR-025 nationwide district flood-event model",
        "preregistration_commit": subprocess.run(["git", "log", "--format=%H", "-1", "--", str(BASE / "PREREGISTRATION.md")], capture_output=True, text=True, cwd=ROOT).stdout.strip(),
        "seed": SEED,
        "data": {"districts": D, "states": len(uniq), "events_dropped_unresolved_district_mentions": dropped,
                 "train_rows": int(len(ytr)), "train_positives": int(ytr.sum()), "val_rows": int(len(yva)), "val_positives": int(yva.sum()),
                 "test_rows": int(len(yte)), "test_positives": int(yte.sum()), "test_event_district_pairs": len(te_events)},
        "chosen_config": {"learning_rate": lr, "max_depth": depth, "l2": l2, "iterations": best_it},
        "grid": grid_log,
        "test": results,
        "test_differences_vs_baselines": diffs,
        "state_holdout_validation_years": folds,
        "state_holdout_mean_ap": {"model_unseen_states": ap_unseen, "best_baseline": ap_base_best},
        "decision_rule": {"model_adds_value": bool(wins),
                          "text": "beats both baselines on AP and event recall@2% with 95% CI above zero, and state-holdout AP >= better baseline"},
        "clarifications": ["grid ranked by validation AP at best log-loss iteration (every 10 iterations)",
                           "score ties broken with a fixed 1e-9 jitter for every method",
                           "bootstrap re-weights test years by draw count; 2000 resamples",
                           "Brier score is reported only for the monthly-rate baseline and the reliability table is not produced: the model is trained with balanced class weights, so its scores are rankings, not probabilities"],
        "seconds": round(time.time() - t0),
    }
    (OUT / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    try:
        import joblib
        joblib.dump(model, OUT / "model.joblib")
    except Exception as e:  # saving the model is a convenience
        print("model not saved:", e, file=sys.stderr)
    print(json.dumps({k: result[k] for k in ("data", "chosen_config", "test", "test_differences_vs_baselines", "state_holdout_mean_ap", "decision_rule")}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
