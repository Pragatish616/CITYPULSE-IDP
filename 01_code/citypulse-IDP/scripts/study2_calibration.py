"""T3.4 -- Study 2: confidence calibration (docs/EVALUATION.md Study 2,
docs/IMPLEMENTATION_PLAN.md T3.4).

**What this scores, and why not via the CLI.** Study 2 asks whether `p_mean` (the belief
model's posterior probability, `pulse_belief.fuse()`) *means* something -- not whether `p̃`
(the pessimistic plug-in) is calibrated, which it is deliberately not: `p̃`'s whole purpose
(CLAUDE.md section 6, ADR-002) is to be a conservative *overestimate* under sparse evidence, so
scoring it for calibration would be scoring a deliberate design choice as if it were a bug. This
script reports `p_mean` as the headline calibration target and `p̃` once, separately, as an
explicit sanity check that it is *not* well calibrated (as designed).

Computing `p_mean` for thousands of (edge, report-age-bucket) combinations needs no graph search
at all -- it is `pulse_belief.fuse()`'s closed-form arithmetic evaluated many times, not a
routing decision. Doing this through the CLI would mean one subprocess invocation (~3s each,
dominated by loading the 471k-edge graph and rebuilding ALT landmarks -- see
`study1_route_quality.py`'s measured timing) per (edge, bucket, baseline) combination -- hours
for zero routing content. `study_common.fuse_beta_py`/`pessimistic_beta_py` (a tested replica of
the Beta-posterior belief, ADR-015; parity-tested against Dart-generated vectors; the exact Dart formulas, verified against `pulse_belief`'s own test vectors in
`scripts/tests/test_study_common.py`) is used instead. Study 1's route-quality numbers, which
*are* routing decisions, still come from the real compiled CLI exclusively.

**Ground-truth label -- a proxy, not true ground truth, flagged loudly.** This corpus
(data/corpus/2026-09-17/) has no confirmed-absence data (every observation carries
`polarity: 1` -- see study1_route_quality.py's docstring) and a single proxy timestamp for every
record (T3.1 MANIFEST.md), so there is no way to hold out genuinely *future* information to
score calibration against. This script instead uses a **source-class holdout**: `y_edge = 1` if
the edge has at least one `official_feed` observation (treated as the more authoritative
confirmation), `y_edge = 0` otherwise; the *predictor* input for every baseline excludes
`official_feed` observations entirely and fuses only `crowd` reports + the static prior --
scoring whether crowd evidence alone predicts official confirmation. **This is an imperfect
proxy**: an edge with only crowd reports and no official confirmation is not proven hazard-free,
merely not officially confirmed in this dataset -- the `y=0` class is contaminated with
unconfirmed true positives, which will bias every calibration/discrimination number here
optimistically-in-some-places and pessimistically in others. Reported honestly, not smoothed
over; this is the same class of corpus limitation T3.1/T3.2 already flagged for other fields.

**Report-age buckets** are simulated by evaluating the query clock `at` = the corpus's single
proxy observation time + a swept offset (0h, 1h, 6h, 24h, 72h, 168h) -- since every real
`observed_at` in this corpus is identical, sweeping `at` is the only way to produce genuine
report-age variation at all; this is stated explicitly, not hidden, as a consequence of the
corpus's degenerate timestamp (same root limitation flagged throughout T3.1/T3.2/Study 1).

**Mandatory baselines** (docs/EVALUATION.md): fixed TTL (reused from Study 1's C4 realisation --
harness pre-filter + large decay_tau), hand-tuned exponential (reused from Study 1's C2 -- one
shared T_c), and Jøsang & Ismail (2002) Beta reputation with forgetting
(`study_common.beta_reputation_p` -- **[UNVERIFIED DETAIL]**, see that function's docstring: the
standard documented formulation was implemented, the original paper PDF was not opened).

**Splitting rule.** Same corpus, same single-event limitation as Study 1 -- see
`result.json["event_split"]`.

Usage: .venv/Scripts/python.exe scripts/study2_calibration.py
"""

from __future__ import annotations

import json
import random
import sys
import time
from datetime import timedelta
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import study_common as sc
import t3_2_replay_engine as t32

SEED = 20260918  # pinned (CLAUDE.md section 7) -- same seed as Study 1, different sampler use
RESULTS_DATE = "2026-10-02"
RESULTS_DIR = t32.ROOT / "data" / "results" / f"{RESULTS_DATE}-study2-calibration"

CORPUS_T0 = t32.parse_iso8601(t32.REPLAY_CLOCK)  # the corpus's single proxy timestamp
AGE_BUCKETS_HOURS = [0, 1, 6, 24, 72, 168]  # simulated report ages -- see docstring
N_NO_REPORT_SAMPLE = 5000  # negative-control pool: edges with zero observations at all

EMERGENCY_Z = (
    2.0  # config/hazard_classes.yaml user_classes.emergency.z -- for the p-tilde
)
# sanity check only (Study 2's headline target is p_mean, see this file's docstring)


def load_edge_pools() -> tuple[dict[int, dict], dict[int, dict], dict]:
    """Builds the two scoring pools.

    `crowd_pool[edge_id]` = {"prior_logodds", "hazard_class" (dominant among crowd reports),
    "crowd_observations" (ObsRecord list, dominant class only, official_feed excluded),
    "label"} for every edge with >=1 crowd observation.

    `no_report_pool[edge_id]` = {"prior_logodds", "hazard_class": "flood", "label": 0} for a
    random sample of edges with zero observations at all (a negative-control stratum, reported
    once, not repeated across report-age buckets -- there is no report to age).
    """
    hazard_classes = t32.load_hazard_classes()
    severity_by_class = {k: v["severity"] for k, v in hazard_classes["classes"].items()}
    obs_by_edge = t32.load_corpus_both_directions()
    prior_by_edge = t32.load_prior()

    crowd_pool: dict[int, dict] = {}
    stats = {"edges_with_official_confirmation": 0, "edges_crowd_only": 0}
    for edge_id, records in obs_by_edge.items():
        crowd_records = [r for r in records if r.source_class == "crowd"]
        if not crowd_records:
            continue
        has_official = any(r.source_class == "official_feed" for r in records)
        dominant, kept, _dropped = t32.choose_dominant_hazard_class(
            crowd_records, severity_by_class
        )
        prior_entry = prior_by_edge.get(edge_id)
        prior_logodds = prior_entry["prior_logodds"] if prior_entry is not None else 0.0
        crowd_pool[edge_id] = {
            "prior_logodds": prior_logodds,
            "hazard_class": dominant,
            "crowd_observations": kept,
            "label": 1 if has_official else 0,
        }
        if has_official:
            stats["edges_with_official_confirmation"] += 1
        else:
            stats["edges_crowd_only"] += 1

    no_obs_edge_ids = [e for e in prior_by_edge if e not in obs_by_edge]
    rng = random.Random(SEED)
    sampled_no_report_ids = rng.sample(
        no_obs_edge_ids, min(N_NO_REPORT_SAMPLE, len(no_obs_edge_ids))
    )
    no_report_pool = {
        edge_id: {
            "prior_logodds": prior_by_edge[edge_id]["prior_logodds"],
            "hazard_class": "flood",  # the static prior is a single generic flood-zone prior
            "label": 0,
        }
        for edge_id in sampled_no_report_ids
    }
    stats["edges_no_report_sampled"] = len(no_report_pool)
    stats["edges_no_report_available"] = len(no_obs_edge_ids)
    return crowd_pool, no_report_pool, stats


def score_crowd_pool(crowd_pool: dict[int, dict], hazard_classes: dict) -> list[dict]:
    """Returns one record per (edge, age_bucket): label, hazard_class, age_bucket_hours, and
    each baseline's p_mean (plus C3's p_tilde at z=emergency, the sanity check).
    """
    classes_cfg = hazard_classes["classes"]
    alpha = hazard_classes["source_reliability"]
    rows: list[dict] = []
    for edge_id, entry in crowd_pool.items():
        cls_cfg = classes_cfg[entry["hazard_class"]]
        tau_c3 = float(cls_cfg["T_c_seconds"])
        obs = entry["crowd_observations"]
        for age_h in AGE_BUCKETS_HOURS:
            at = CORPUS_T0 + timedelta(hours=age_h)
            obs_reliab = sc.with_reliability(obs, alpha)

            p_c3 = sc.fuse_beta_py(obs_reliab, entry["prior_logodds"], at, tau_c3)
            p_c2 = sc.fuse_beta_py(
                obs_reliab, entry["prior_logodds"], at, sc.C2_SHARED_TC_SECONDS
            )

            ttl_obs = [
                o
                for o in obs
                if (at - o.observed_at).total_seconds() <= sc.C4_TTL_SECONDS
            ]
            ttl_obs_reliab = sc.with_reliability(ttl_obs, alpha)
            p_c4 = sc.fuse_beta_py(
                ttl_obs_reliab, entry["prior_logodds"], at, sc.C4_NO_DECAY_TAU_SECONDS
            )

            beta = sc.beta_reputation_p(obs_reliab, at)

            p_tilde_emergency = sc.pessimistic_beta_py(p_c3, z=EMERGENCY_Z)

            rows.append(
                {
                    "edge_id": edge_id,
                    "label": entry["label"],
                    "hazard_class": entry["hazard_class"],
                    "age_bucket_hours": age_h,
                    "p_mean_c3_ours": p_c3["p_mean"],
                    "p_mean_c2_single_decay": p_c2["p_mean"],
                    "p_mean_c4_fixed_ttl": p_c4["p_mean"],
                    "p_mean_beta_reputation": beta["p_mean"],
                    "p_mean_prior_only": min(
                        max(sc.sigmoid_py(entry["prior_logodds"]), 1e-6), 1 - 1e-6
                    ),
                    "p_tilde_c3_emergency_z2_sanity_check": p_tilde_emergency,
                }
            )
    return rows


def score_no_report_pool(no_report_pool: dict[int, dict]) -> list[dict]:
    rows = []
    for edge_id, entry in no_report_pool.items():
        p_mean = sc.sigmoid_py(entry["prior_logodds"])
        rows.append(
            {
                "edge_id": edge_id,
                "label": entry["label"],
                "hazard_class": entry["hazard_class"],
                "age_bucket_hours": "no_report",
                "p_mean_c3_ours": p_mean,
                "p_mean_c2_single_decay": p_mean,
                "p_mean_c4_fixed_ttl": p_mean,
                "p_mean_beta_reputation": 0.5,  # Beta(1,1) uninformative prior -- no observations
                "p_mean_prior_only": p_mean,
                "p_tilde_c3_emergency_z2_sanity_check": p_mean,
            }
        )
    return rows


BASELINE_KEYS = {
    "c3_ours": "p_mean_c3_ours",
    "c2_single_decay": "p_mean_c2_single_decay",
    "c4_fixed_ttl": "p_mean_c4_fixed_ttl",
    "beta_reputation_with_forgetting": "p_mean_beta_reputation",
    # The static prior alone: what the crowd evidence has to beat (KNOWN_FLAWS F-14).
    "prior_only": "p_mean_prior_only",
}


def compute_metrics_table(rows: list[dict]) -> dict:
    outcomes = [r["label"] for r in rows]
    out = {
        "n": len(rows),
        "n_positive": sum(outcomes),
        "n_negative": len(rows) - sum(outcomes),
    }
    for name, key in BASELINE_KEYS.items():
        probs = [r[key] for r in rows]
        try:
            brier = sc.brier_murphy_decomposition(probs, outcomes)
            ece = sc.adaptive_ece(probs, outcomes)
            ll = sc.log_loss(probs, outcomes)
            roc = sc.auroc(probs, outcomes)
        except ValueError as e:
            out[name] = {"error": str(e)}
            continue
        out[name] = {
            "brier": brier["brier"],
            "murphy_reliability": brier["reliability"],
            "murphy_resolution": brier["resolution"],
            "murphy_uncertainty": brier["uncertainty"],
            "decomposition_check": brier["decomposition_check"],
            "adaptive_ece": ece,
            "log_loss": ll,
            "auroc_discrimination_only": roc,
        }
    # Brier skill scores (1 - Brier / Brier_reference): against climatology (the base rate of this
    # stratum, which equals the Murphy uncertainty term) and against the prior alone. Negative =
    # worse than the reference.
    if "brier" in out.get("prior_only", {}):
        brier_prior = out["prior_only"]["brier"]
        for name in BASELINE_KEYS:
            m = out.get(name)
            if isinstance(m, dict) and "brier" in m:
                unc = m["murphy_uncertainty"]
                m["brier_skill_vs_climatology"] = 1 - m["brier"] / unc if unc > 0 else None
                m["brier_skill_vs_prior_only"] = (
                    1 - m["brier"] / brier_prior if brier_prior > 0 else None
                )
    # p_tilde sanity check, pooled only (not stratified -- one summary number is enough to make
    # the point that it is deliberately not calibrated)
    p_tilde_probs = [r["p_tilde_c3_emergency_z2_sanity_check"] for r in rows]
    out["p_tilde_sanity_check_not_expected_to_calibrate"] = {
        "brier": sc.brier_murphy_decomposition(p_tilde_probs, outcomes)["brier"],
        "mean_p_tilde": sum(p_tilde_probs) / len(p_tilde_probs),
        "mean_p_mean_c3": sum(r["p_mean_c3_ours"] for r in rows) / len(rows),
        "note": (
            "p_tilde (z=2.0, emergency class) is expected to systematically overstate risk "
            "relative to p_mean and therefore score worse on Brier/ECE -- that is the design "
            "(ADR-002 pessimism-under-uncertainty), not a defect. Confirms mean_p_tilde > "
            "mean_p_mean_c3 as a sanity check that this baseline table is wired correctly."
        ),
    }
    return out


def _event_split_placeholder(record_count: int) -> dict:
    return {
        "method": "split_by_event_and_monsoon_episode",
        "n_events_available": 1,
        "event_ids": ["chennai_2015_flood_2015-12-02_proxy"],
        "folds": [
            {
                "fold": 0,
                "event_ids": ["chennai_2015_flood_2015-12-02_proxy"],
                "n_records": record_count,
            }
        ],
        "honest_limitation": (
            "Identical limitation to Study 1 (study1_route_quality.py's event_split field): "
            "T3.1's corpus is one event with one proxy timestamp -- no second event/monsoon "
            "episode exists to hold out. A genuine multi-event split is not currently possible; "
            "not fabricated here."
        ),
    }


def main() -> None:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    figures_dir = RESULTS_DIR / "figures"
    figures_dir.mkdir(parents=True, exist_ok=True)

    t0 = time.monotonic()
    hazard_classes = t32.load_hazard_classes()
    crowd_pool, no_report_pool, pool_stats = load_edge_pools()
    crowd_rows = score_crowd_pool(crowd_pool, hazard_classes)
    no_report_rows = score_no_report_pool(no_report_pool)
    t1 = time.monotonic()

    all_rows = crowd_rows + no_report_rows

    overall = compute_metrics_table(all_rows)
    crowd_only_overall = compute_metrics_table(crowd_rows)

    # Stratified by report-age bucket (crowd pool only -- no_report has no age axis)
    by_age_bucket = {}
    for age_h in AGE_BUCKETS_HOURS:
        subset = [r for r in crowd_rows if r["age_bucket_hours"] == age_h]
        if subset:
            by_age_bucket[str(age_h)] = compute_metrics_table(subset)

    # Stratified by hazard class (crowd pool only)
    by_hazard_class = {}
    for cls in sorted({r["hazard_class"] for r in crowd_rows}):
        subset = [r for r in crowd_rows if r["hazard_class"] == cls]
        if subset:
            by_hazard_class[cls] = compute_metrics_table(subset)
    hazard_class_confound_note = (
        "Corpus-driven confound found while running this study, flagged rather than papered "
        "over (CLAUDE.md section 8.4): every crowd_sourced_flooding_2015.kml observation is "
        "hazard_class='flood' (5,052/5,052) and every gcc_stagnation_2015.kml (waterlogging) "
        "observation is source_class='official_feed' (753/753) -- verified against "
        "data/corpus/2026-09-17/observations.ndjson. Because this study's ground-truth label "
        "is a source-class holdout (crowd predicts official_feed confirmation, see this file's "
        "module docstring), the crowd-only predictor pool contains *zero* waterlogging edges by "
        "construction -- 'stratified by hazard_class' degenerates to a single ('flood') stratum "
        "for this specific ground-truth design, not from a shortage of waterlogging data in the "
        "corpus overall (753 waterlogging records exist, all in the label side of the split, "
        "none in the predictor side). This is a real limitation of the source-holdout proxy "
        "itself, distinct from the already-flagged single-timestamp and all-positive-polarity "
        "limitations, and is being written into docs/DECISIONS.md."
    )

    # Stratified by BOTH (the mandatory cross-stratification, docs/EVALUATION.md Study 2)
    by_age_and_class: dict[str, dict] = {}
    for age_h in AGE_BUCKETS_HOURS:
        for cls in sorted({r["hazard_class"] for r in crowd_rows}):
            subset = [
                r
                for r in crowd_rows
                if r["age_bucket_hours"] == age_h and r["hazard_class"] == cls
            ]
            if (
                len(subset) >= 5
            ):  # too few points otherwise makes Brier/AUROC meaningless
                by_age_and_class[f"{cls}__age_{age_h}h"] = compute_metrics_table(subset)
            elif subset:
                by_age_and_class[f"{cls}__age_{age_h}h"] = {
                    "n": len(subset),
                    "note": "n<5, too small to report calibration metrics meaningfully",
                }

    # --- Figure 4: reliability diagrams, stratified by hazard_class (rows) x age bucket (cols) ---
    hazard_class_list = sorted({r["hazard_class"] for r in crowd_rows})
    fig, axes = plt.subplots(
        len(hazard_class_list),
        len(AGE_BUCKETS_HOURS),
        figsize=(4 * len(AGE_BUCKETS_HOURS), 4 * len(hazard_class_list)),
        squeeze=False,
    )
    n_bins_fig = 5
    for ri, cls in enumerate(hazard_class_list):
        for ci, age_h in enumerate(AGE_BUCKETS_HOURS):
            ax = axes[ri][ci]
            subset = [
                r
                for r in crowd_rows
                if r["hazard_class"] == cls and r["age_bucket_hours"] == age_h
            ]
            ax.plot([0, 1], [0, 1], "k--", linewidth=1, label="perfect")
            for name, key in BASELINE_KEYS.items():
                if len(subset) < 5:
                    continue
                probs = [r[key] for r in subset]
                outcomes = [r["label"] for r in subset]
                # equal-width bins for the plot (adaptive_ece uses equal-frequency internally;
                # the plot uses equal-width bins, the conventional reliability-diagram axis)
                bin_p, bin_o = [], []
                for b in range(n_bins_fig):
                    lo, hi = b / n_bins_fig, (b + 1) / n_bins_fig
                    idxs = [
                        i
                        for i, p in enumerate(probs)
                        if (lo <= p < hi) or (b == n_bins_fig - 1 and p == hi)
                    ]
                    if idxs:
                        bin_p.append(sum(probs[i] for i in idxs) / len(idxs))
                        bin_o.append(sum(outcomes[i] for i in idxs) / len(idxs))
                if bin_p:
                    ax.plot(
                        bin_p, bin_o, marker="o", markersize=3, linewidth=1, label=name
                    )
            ax.set_title(f"{cls}, age={age_h}h (n={len(subset)})", fontsize=9)
            ax.set_xlim(0, 1)
            ax.set_ylim(0, 1)
            if ri == len(hazard_class_list) - 1:
                ax.set_xlabel("predicted p_mean")
            if ci == 0:
                ax.set_ylabel("observed frequency")
    axes[0][0].legend(fontsize=6, loc="upper left")
    fig.suptitle(
        "Study 2 -- reliability diagrams stratified by hazard class x report-age bucket\n"
        "(ground truth: official_feed confirmation, a proxy -- see result.json's docstring notes)",
        fontsize=11,
    )
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    fig.savefig(figures_dir / "figure4_reliability_diagrams.png", dpi=150)
    plt.close(fig)

    # --- Supplementary: AUROC / Brier vs. report-age bucket, per baseline (discrimination decay) ---
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
    for name in BASELINE_KEYS:
        xs, aurocs, briers = [], [], []
        for age_h in AGE_BUCKETS_HOURS:
            key = str(age_h)
            if key in by_age_bucket and name in by_age_bucket[key]:
                m = by_age_bucket[key][name]
                if isinstance(m, dict) and "auroc_discrimination_only" in m:
                    xs.append(age_h)
                    aurocs.append(m["auroc_discrimination_only"])
                    briers.append(m["brier"])
        ax1.plot(xs, aurocs, marker="o", label=name)
        ax2.plot(xs, briers, marker="o", label=name)
    ax1.set_xlabel("report age (hours, simulated)")
    ax1.set_ylabel("AUROC (discrimination)")
    ax1.set_title("Discrimination vs. report age")
    ax1.legend(fontsize=7)
    ax2.set_xlabel("report age (hours, simulated)")
    ax2.set_ylabel("Brier score")
    ax2.set_title("Calibration (Brier) vs. report age")
    ax2.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(figures_dir / "figure4b_auroc_brier_vs_age.png", dpi=150)
    plt.close(fig)

    t2 = time.monotonic()

    result = {
        "task": "T3.4 Study 2 -- confidence calibration",
        "seed": SEED,
        "corpus_t0": t32.REPLAY_CLOCK,
        "age_buckets_hours_simulated": AGE_BUCKETS_HOURS,
        "timing": {
            "scoring_seconds": t1 - t0,
            "figures_seconds": t2 - t1,
            "total_seconds": t2 - t0,
        },
        "ground_truth_label_method": (
            "y_edge=1 iff the edge has >=1 official_feed observation; predictor input excludes "
            "official_feed entirely (crowd observations + static prior only) -- a source-class "
            "holdout, not true confirmed-absence ground truth. See this file's module docstring "
            "for the full honesty caveat; this is the single most important limitation of "
            "Study 2 as run against this corpus."
        ),
        "pool_stats": pool_stats,
        "n_crowd_pool_edges": len(crowd_pool),
        "n_crowd_pool_rows_all_age_buckets": len(crowd_rows),
        "n_no_report_pool_edges": len(no_report_pool),
        "baselines": list(BASELINE_KEYS.keys()),
        "beta_reputation_baseline_source": (
            "Jøsang, A. and Ismail, R., 'The Beta Reputation System', 15th Bled Electronic "
            "Commerce Conference, 2002. [UNVERIFIED DETAIL] per CLAUDE.md section 7's citation "
            "discipline -- the primary paper PDF was not opened for this task; the standard "
            "documented formulation (Beta(r+1,s+1) posterior mean over forgetting-discounted, "
            "reliability- and kernel-weighted positive/negative evidence counts) was "
            "reconstructed and implemented directly in study_common.beta_reputation_p, verified "
            "only against hand-computed toy cases (scripts/tests/test_study_common.py), not "
            "against a reference implementation of the paper itself. Do not cite as a verified "
            "reproduction without opening the primary source first."
        ),
        "metrics_overall_all_edges": overall,
        "metrics_crowd_pool_only": crowd_only_overall,
        "metrics_by_report_age_bucket": by_age_bucket,
        "metrics_by_hazard_class": by_hazard_class,
        "hazard_class_stratification_confound": hazard_class_confound_note,
        "metrics_by_age_bucket_and_hazard_class": by_age_and_class,
        "auroc_reported_separately_from_calibration": (
            "Every metrics table above reports auroc_discrimination_only as a distinct field "
            "from brier/adaptive_ece/log_loss, per this task's explicit instruction not to "
            "conflate discrimination and calibration."
        ),
        "event_split": _event_split_placeholder(len(all_rows)),
        "reproduce_with": "python scripts/study2_calibration.py",
    }
    with open(RESULTS_DIR / "result.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, default=str)

    print("=== Study 2: confidence calibration ===")
    print(
        f"Crowd pool: {len(crowd_pool)} edges, no-report pool: {len(no_report_pool)} edges"
    )
    print(
        f"Positive rate (official-confirmed): {pool_stats['edges_with_official_confirmation']}/{len(crowd_pool)}"
    )
    for name in BASELINE_KEYS:
        m = crowd_only_overall[name]
        print(
            f"  {name}: brier={m['brier']:.4f} ece={m['adaptive_ece']:.4f} auroc={m['auroc_discrimination_only']:.4f}"
        )
    print(f"Wrote {RESULTS_DIR / 'result.json'}")
    print(f"Wrote {figures_dir / 'figure4_reliability_diagrams.png'}")
    print(f"Wrote {figures_dir / 'figure4b_auroc_brier_vs_age.png'}")


if __name__ == "__main__":
    main()
