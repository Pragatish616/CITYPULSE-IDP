"""CSFE benchmark B1 (subway closure from rain), exactly as pre-registered in data/csfe/BENCHMARK_PREREGISTRATION.md (commit cd54e9a).

Run from 01_code/citypulse-IDP after scripts/build_csfe_proto.py:  python scripts/csfe_benchmark_b1.py
Reads data/csfe/2026-10-30/observations.csv (news rows linked to a watchlist subway); writes data/results/2026-10-30-csfe-b1/result.json.
"""

from __future__ import annotations

import csv
import json
import math
from collections import defaultdict
from pathlib import Path

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score

ROOT = Path(__file__).resolve().parents[1]
OBS = ROOT / "data" / "csfe" / "2026-10-30" / "observations.csv"
OUT = ROOT / "data" / "results" / "2026-10-30-csfe-b1" / "result.json"
# Addendum 1: python scripts/csfe_benchmark_b1.py <observations.csv> <result.json> (the first run used the defaults above, with the
# build then at data/csfe/2026-10-30 and now kept as data/csfe/2026-10-30-windowA).
import sys  # noqa: E402

if len(sys.argv) == 3:
    OBS, OUT = Path(sys.argv[1]), Path(sys.argv[2])
SEED = 20261030
POS = {"closed"}
NEG = {"not_waterlogged", "waterlogged_open", "open"}


def load() -> list[dict]:
    rows = []
    for r in csv.DictReader(OBS.open(encoding="utf-8")):
        if r["source_type"] != "news" or not r["place_id"] or r["kind"] not in POS | NEG:
            continue
        if r["rain_day_mm_city_median"] == "" or r["rain_prev2d_mm_city_median"] == "":
            continue
        rows.append({"event": r["event_id"], "subway": r["place_id"], "y": int(r["kind"] in POS),
                     "rain": float(r["rain_day_mm_city_median"]), "prev": float(r["rain_prev2d_mm_city_median"])})
    return rows


def predict_fold(train: list[dict], test: list[dict]) -> dict[str, np.ndarray]:
    base = float(np.mean([r["y"] for r in train]))
    hist: dict[str, list[int]] = defaultdict(list)
    for r in train:
        hist[r["subway"]].append(r["y"])

    def h(r) -> float:
        return float(np.mean(hist[r["subway"]])) if hist.get(r["subway"]) else base

    def x_rain(rs) -> np.ndarray:
        return np.array([[math.log1p(r["rain"]), math.log1p(r["prev"])] for r in rs])

    out = {"base": np.full(len(test), base), "history": np.array([h(r) for r in test])}
    ytr = np.array([r["y"] for r in train])
    if len(set(ytr)) < 2:  # a fold whose training rows are all one class: the model can only give the base rate
        out["rain"] = out["base"].copy()
        out["rain_history"] = out["history"].copy()
        return out
    m3 = LogisticRegression().fit(x_rain(train), ytr)
    out["rain"] = m3.predict_proba(x_rain(test))[:, 1]
    x4 = lambda rs: np.column_stack([x_rain(rs), [h(r) for r in rs]])  # noqa: E731
    m4 = LogisticRegression().fit(x4(train), ytr)
    out["rain_history"] = m4.predict_proba(x4(test))[:, 1]
    return out


def main() -> None:
    rows = load()
    events = sorted({r["event"] for r in rows})
    preds: dict[str, list[float]] = defaultdict(list)
    ys, ev_of = [], []
    for e in events:
        train = [r for r in rows if r["event"] != e]
        test = [r for r in rows if r["event"] == e]
        p = predict_fold(train, test)
        for k, v in p.items():
            preds[k] += list(v)
        ys += [r["y"] for r in test]
        ev_of += [e] * len(test)
    y = np.array(ys)
    ev = np.array(ev_of)
    P = {k: np.array(v) for k, v in preds.items()}

    def metrics(idx: np.ndarray) -> dict:
        out = {}
        b_base = float(np.mean((P["base"][idx] - y[idx]) ** 2))
        for k, p in P.items():
            b = float(np.mean((p[idx] - y[idx]) ** 2))
            auc = float(roc_auc_score(y[idx], p[idx])) if len(set(y[idx])) == 2 else float("nan")
            out[k] = {"brier": b, "bss_vs_base": (1 - b / b_base) if b_base > 0 else float("nan"), "auroc": auc}
        out["brier_diff_rain_history_minus_rain"] = out["rain_history"]["brier"] - out["rain"]["brier"]
        return out

    full = metrics(np.arange(len(y)))
    rng = np.random.default_rng(SEED)
    boots = []
    for _ in range(2000):
        pick = rng.choice(events, len(events), replace=True)
        idx = np.concatenate([np.nonzero(ev == e)[0] for e in pick])
        boots.append(metrics(idx))

    def ci(path) -> list[float]:
        vals = [path(b) for b in boots]
        vals = [v for v in vals if not (isinstance(v, float) and math.isnan(v))]
        return [round(float(np.quantile(vals, 0.025)), 4), round(float(np.quantile(vals, 0.975)), 4)] if vals else [None, None]

    result = {
        "task": "CSFE B1 subway closure from rain",
        "input": str(OBS.relative_to(ROOT)) if OBS.is_relative_to(ROOT) else str(OBS),
        "preregistration": "data/csfe/BENCHMARK_PREREGISTRATION.md (commit cd54e9a)",
        "rows": len(rows),
        "positives": int(y.sum()),
        "events": {e: {"rows": int((ev == e).sum()), "closed": int(y[ev == e].sum())} for e in events},
        "subways": len({r["subway"] for r in rows}),
        "models": {k: {m: round(v, 4) if isinstance(v, float) and not math.isnan(v) else None for m, v in full[k].items()}
                   for k in P},
        "ci95": {
            "rain_bss_vs_base": ci(lambda b: b["rain"]["bss_vs_base"]),
            "rain_history_bss_vs_base": ci(lambda b: b["rain_history"]["bss_vs_base"]),
            "history_bss_vs_base": ci(lambda b: b["history"]["bss_vs_base"]),
            "brier_diff_rain_history_minus_rain": ci(lambda b: b["brier_diff_rain_history_minus_rain"]),
        },
        "brier_diff_rain_history_minus_rain": round(full["brier_diff_rain_history_minus_rain"], 4),
    }
    lo = result["ci95"]["rain_bss_vs_base"][0]
    result["reading"] = {
        "rain_helps": lo is not None and lo > 0,
        "history_helps_beyond_rain": (result["ci95"]["brier_diff_rain_history_minus_rain"][1] or 0) < 0,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
