"""Scorecard for the trained flood models (data/susceptibility/2026-10-04/PREREGISTRATION_SCORECARD.md).

Reads only result files already on disk (the earlier pre-registered studies and stress.json from scripts/sus_stress.py) and applies the
score fixed in advance:   skill = (M - B) / (1 - B)   with bands  >= 0.30 useful | 0.10-0.30 modest | 0-0.10 marginal | < 0 or interval
including 0 -> no evidence of skill.  No number is typed in here; every one comes from a JSON file.

    python scripts/model_scorecard.py        ->  data/results/2026-10-11-model-scorecard/scorecard.json
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
R = ROOT / "data" / "results"
OUT = R / "2026-10-11-model-scorecard"


def load(p):
    return json.loads((R / p).read_text(encoding="utf-8"))


def skill(m, b):
    return (m - b) / (1 - b)


def band(sk, ci_lo):
    if ci_lo is not None and ci_lo <= 0:
        return "no evidence of skill (interval for the difference includes 0)"
    if sk < 0:
        return "no evidence of skill (negative)"
    if sk >= 0.30:
        return "useful"
    if sk >= 0.10:
        return "modest"
    return "marginal"


def row(name, task, metric, m, b, baseline, diff_ci, prevalence=None, note=""):
    sk = skill(m, b)
    out = {"model": name, "task": task, "metric": metric, "model_value": m, "baseline": baseline, "baseline_value": b,
           "skill_vs_baseline": sk, "difference_ci95": diff_ci, "verdict": band(sk, diff_ci[0] if diff_ci else None), "note": note}
    if prevalence:
        out["prevalence"] = prevalence
        out["lift_over_prevalence"] = m / prevalence
    return out


def main() -> None:
    rows = []
    # N: nationwide district flood-event model (ADR-025), 2016-2023 test years, used once
    n = load("2026-10-04-nationwide-flood-gating/result.json")
    t = n["test"]
    d = n["test_differences_vs_baselines"]
    prev = n["data"]["test_positives"] / n["data"]["test_rows"]
    rows.append(row("N nationwide district flood-event model", "will a district report a flood event today (rain features), test 2016-2023", "average precision",
                    t["model"]["ap"], t["b1_month_rate"]["ap"], "district-and-month event rate", d["model_minus_b1_month_rate__ap"]["ci95"], prev,
                    "ranks below the plain event-rate table on AP"))
    rows.append(row("N nationwide district flood-event model", "same, event recall at a 2% alert budget", "recall at 2%",
                    t["model"]["event_recall_at_2pct"], t["b2_rain_rule"]["event_recall_at_2pct"], "3-day rain above its 95th percentile",
                    d["model_minus_b2_rain_rule__event_recall_at_2pct"]["ci95"], None, "a one-line rain rule recovers as many events"))

    # T: nationwide terrain model (ADR-026 B2), held-out spatial blocks
    s = load("2026-10-04-susceptibility-national-all/result.json")["results"]["spatial_blocks"]
    rows.append(row("T nationwide terrain model", "which cells of an Indian flood map are flooded, 2-degree blocks held out (registered)", "average precision",
                    s["m1_terrain"]["ap"], s["best_single_feature"]["ap"], "relief within 5 km (best single terrain feature)", s["m1_minus_baseline"]["ap"]["ci95"],
                    None, "AUC %.3f vs %.3f" % (s["m1_terrain"]["auc"], s["best_single_feature"]["auc"])))
    st = {}
    for f in ("stress.json", "stress_p1.json", "stress_p2.json"):
        if (OUT / f).exists():
            st.update(json.loads((OUT / f).read_text(encoding="utf-8")))
    for deg in (5, 10):
        k = f"t2_blocks_{deg}deg"
        if k in st:
            r = st[k]
            rows.append(row("T nationwide terrain model", f"same, {deg}-degree blocks held out (stress test)", "average precision", r["model"]["ap"], r["base"]["ap"],
                            "best single terrain feature", r["model_minus_base"]["ap"]["ci95"], r["prevalence"], "AUC %.3f vs %.3f" % (r["model"]["auc"], r["base"]["auc"])))
    if "t9_lock_evaluation" in st:
        L = st["t9_lock_evaluation"]
        a, bsf = L["a_hgb_m1"], L["best_single_feature"]
        rows.append(row("T nationwide terrain model", "same, 40% of 5-degree blocks never used in any decision (lock blocks)", "average precision", a["ap"], bsf["ap"],
                        "best single terrain feature", L["a_hgb_m1_minus_best_single_feature"]["ap"]["ci95"], L.get("lock_prevalence"), "single evaluation on blocks no decision used"))

    # C: Chennai-local models and transfer
    A = load("2026-10-04-susceptibility-chennai/result.json")["results"]
    sb = A["spatial_blocks_2015"]
    rows.append(row("C Chennai-local terrain model (A)", "which cells flooded in Dec 2015, blocks held out across the Chennai area", "average precision",
                    sb["model"]["ap"], sb["baseline"]["ap"], "best single feature (elevation)", sb["ap_ci95"], sb["positives"] / sb["cells"]))
    lo = A["loeo_2005_to_2015_inbox"]
    rows.append(row("C Chennai-local terrain model (A)", "train on the 2005 flood, test on 2015, inside the 2005 area (the city core)", "average precision",
                    lo["model"]["ap"], lo["best_baseline"]["ap"], "best single feature", lo["model_minus_best_baseline"]["ap_ci95"], lo["test_base_rate"],
                    "AUC %.3f vs %.3f (interval for the AUC difference: %s)" % (lo["model"]["auc"], lo["best_baseline"]["auc"], lo["model_minus_best_baseline"]["auc_ci95"])))
    c3 = load("2026-10-04-susceptibility-chennai-c3/transfer_result.json")
    rows.append(row("T applied to Chennai (C3)", "nationwide model, Chennai area removed from training, scored on the 2015 flood", "average precision",
                    c3["model"]["ap"], c3["baseline"]["ap"], "relief within 5 km", [c3["model_minus_baseline"]["ap_ci95"][0], c3["model_minus_baseline"]["ap_ci95"][1]],
                    c3["base_rate"], "AUC %.3f vs %.3f; single-feature elevation alone had AP %.3f and distance-to-sea %.3f on Chennai" %
                    (c3["model"]["auc"], c3["baseline"]["auc"], c3["single_feature_scores_on_chennai"]["elev"]["ap"], c3["single_feature_scores_on_chennai"]["dist_sea_km"]["ap"])))
    rt = load("2026-10-04-susceptibility-chennai-c3/router_result.json")["summary"]
    rr = rt["national|ped_l20"]
    orc = rt["oracle|ped_l20"]
    rows.append({"model": "T prior used in the router (C3 routing)", "task": "share of a walker's route inside the 2015 flood, reduction vs a flat prior (risk weight 20)", "metric": "reduction in exposure share",
                 "model_value": rr["reduction_vs_flat"], "baseline": "flat prior", "baseline_value": 0.0, "difference_ci95": rr["reduction_ci95"],
                 "oracle_value": orc["reduction_vs_flat"], "oracle_ci95": orc["reduction_ci95"],
                 "verdict": band(rr["reduction_vs_flat"], rr["reduction_ci95"][0]),
                 "note": "an oracle prior built from the flood itself removes %.1f%% of the walker's exposure; this prior removes %.2f%%" %
                 (100 * orc["reduction_vs_flat"] / (orc["mean_exposure_share"] + orc["reduction_vs_flat"]), 100 * rr["reduction_vs_flat"] / (rr["mean_exposure_share"] + rr["reduction_vs_flat"]))})

    out = {"task": "scorecard of the trained flood models", "score_definition": "skill = (M - B) / (1 - B); bands: >=0.30 useful, 0.10-0.30 modest, 0-0.10 marginal, <0 or interval including 0 no evidence",
           "preregistration": "data/susceptibility/2026-10-04/PREREGISTRATION_SCORECARD.md", "rows": rows,
           "not_scored": "advisor (hand-set), event miner (no labelled set), accident logic (no data); there is no trained model for any of them"}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "scorecard.json").write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
    for r in rows:
        sk = r.get("skill_vs_baseline")
        print(f"{r['model'][:40]:40} | {r['metric'][:22]:22} | M {r['model_value']:.4f} B {r['baseline_value']:.4f}" + (f" skill {sk:+.3f}" if sk is not None else "") + f" | {r['verdict']}")


if __name__ == "__main__":
    main()
