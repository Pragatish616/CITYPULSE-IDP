"""Part C3 step 2 (ADR-026): the nationwide model, trained without any cell from the Chennai study area, scored on Chennai (PREREGISTRATION_C3.md).

Needs national_samples_all.npz (addendum B2) and chennai250.npz (sus_c3_grid.py). Writes data/results/2026-10-04-susceptibility-chennai-c3/transfer_result.json
and the 250 m score grid (git-ignored) used by sus_c3_router.py.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sus_national_train import TERRAIN, balanced_train_weights, best_single, hgb  # noqa: E402
from sus_train import ci, joint_boot  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
OUT = ROOT / "data" / "results" / "2026-10-04-susceptibility-chennai-c3"
SEED = 20261004
AREA = (79.3, 12.5, 80.35, 13.4)


def main() -> int:
    t0 = time.time()
    OUT.mkdir(parents=True, exist_ok=True)
    z = np.load(BASE / "national_samples_all.npz")
    y, ev = z["y"], z["event"]
    lon, lat = z["lon"], z["lat"]
    in_area = (lon >= AREA[0]) & (lon <= AREA[2]) & (lat >= AREA[1]) & (lat <= AREA[3])
    keep = ~in_area
    Xt = np.column_stack([z[k] for k in TERRAIN]).astype(np.float32)
    w_eval = z["w"].astype(np.float64)
    for e in np.unique(ev):
        w_eval[ev == e] /= w_eval[ev == e].sum()
    w_train = balanced_train_weights(y, ev)
    print(f"training rows {int(keep.sum()):,} of {len(y):,} (removed {int(in_area.sum()):,} inside the Chennai study area)", flush=True)
    model = hgb().fit(Xt[keep], y[keep], sample_weight=w_train[keep])
    j, ap_train = best_single(Xt[keep], y[keep], w_eval[keep], TERRAIN)

    g = np.load(BASE / "chennai250.npz")
    modelled, y15, block = g["modelled"], g["y2015"], g["block"]
    F = np.stack([g[k] for k in TERRAIN], axis=-1).astype(np.float32)
    Xc = F[modelled]
    yc = y15[modelled]
    bc = block[modelled]
    s_model = model.predict_proba(Xc)[:, 1]
    v = Xc[:, j]
    s_base = -np.where(np.isnan(v), np.nanmax(Xt[keep][:, j]), v)
    point, draws = joint_boot({"model": s_model, "baseline": s_base}, yc, bc, SEED + 41)
    d_ap = draws["model"]["ap"] - draws["baseline"]["ap"]
    d_auc = draws["model"]["auc"] - draws["baseline"]["auc"]
    ok = bool(ci(d_ap)[0] > 0 and ci(d_auc)[0] > 0)
    # single-feature table for context
    singles = {}
    for k, name in enumerate(TERRAIN):
        s = -np.where(np.isnan(Xc[:, k]), np.nanmax(Xt[keep][:, k]), Xc[:, k])
        from sus_train import prepare
        singles[name] = {m: round(v_, 4) for m, v_ in prepare(s, yc)["point"].items() if m in ("ap", "auc")}
    res = {
        "task": "ADR-026 Part C3 transfer: nationwide terrain model applied to Chennai",
        "preregistration_commit": subprocess.run(["git", "log", "--format=%H", "-1", "--", str(BASE / "PREREGISTRATION_C3.md")], capture_output=True, text=True, cwd=ROOT).stdout.strip(),
        "training_rows": int(keep.sum()), "rows_removed_inside_chennai_area": int(in_area.sum()), "chennai_cells": int(len(yc)), "chennai_positives": int(yc.sum()),
        "base_rate": float(yc.mean()), "best_single_feature_on_training": TERRAIN[j], "best_single_feature_training_ap": ap_train,
        "model": {**point["model"], "ci95": {m: ci(d) for m, d in draws["model"].items() if m in ("ap", "auc")}},
        "baseline": {**point["baseline"], "ci95": {m: ci(d) for m, d in draws["baseline"].items() if m in ("ap", "auc")}},
        "model_minus_baseline": {"ap": point["model"]["ap"] - point["baseline"]["ap"], "ap_ci95": ci(d_ap), "auc": point["model"]["auc"] - point["baseline"]["auc"], "auc_ci95": ci(d_auc)},
        "single_feature_scores_on_chennai": singles,
        "decision_rule_1_transfers_to_chennai": ok, "seconds": round(time.time() - t0),
    }
    (OUT / "transfer_result.json").write_text(json.dumps(res, indent=2, sort_keys=True), encoding="utf-8")
    grid = np.full(modelled.shape, np.nan, dtype=np.float32)
    grid[modelled] = s_model
    base_grid = np.full(modelled.shape, np.nan, dtype=np.float32)
    base_grid[modelled] = s_base
    np.savez_compressed(BASE / "chennai250_scores.npz", model=grid, baseline=base_grid)
    print(json.dumps({k: res[k] for k in ("base_rate", "best_single_feature_on_training", "model", "baseline", "model_minus_baseline", "decision_rule_1_transfers_to_chennai")}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
