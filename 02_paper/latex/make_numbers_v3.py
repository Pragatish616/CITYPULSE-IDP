"""Generate every number, table and figure of paper v3 from the project's result files (no number is typed by hand).

Run from 02_paper/latex:  python make_numbers_v3.py
Inputs (all under 01_code/citypulse-IDP/data/results/ unless noted):
  2026-10-02-study1-rescored/result.json      Study 1, 1,000 pairs, Beta index, common reference belief (ADR-017)
  2026-10-02-study2-calibration/result.json   Study 2 (ADR-017) and figures/figure4_reliability_diagrams.png
  2026-10-02-verifier[-baseline]/result.json  explanation gate before and after the 2 Oct fixes
  2026-10-17-c5-conformal/result.json, 2026-10-18-c5b-route-certificates/result.json   (ADR-036)
  graph and corpus counts: recomputed from data/graph/2026-09-14 and data/corpus/2026-09-17 with the harness's own loaders
  worked example of Section III-B: packages/pulse_belief/tool/paper_example.dart (output copied below, with the command)
Outputs: numbers.tex, sweep_table.tex, cal_table.tex, fig_pareto_common.pdf, fig_decomp.pdf, fig_reliability.png
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

HERE = Path(__file__).resolve().parent
CODE = HERE.parents[1] / "01_code" / "citypulse-IDP"
RES = CODE / "data" / "results"
sys.path.insert(0, str(CODE / "scripts"))

S1 = json.loads((RES / "2026-10-02-study1-rescored" / "result.json").read_text(encoding="utf-8"))
S2 = json.loads((RES / "2026-10-02-study2-calibration" / "result.json").read_text(encoding="utf-8"))
VF = json.loads((RES / "2026-10-02-verifier" / "result.json").read_text(encoding="utf-8"))
VB = json.loads((RES / "2026-10-02-verifier-baseline" / "result.json").read_text(encoding="utf-8"))
C5 = json.loads((RES / "2026-10-17-c5-conformal" / "result.json").read_text(encoding="utf-8"))
C5B = json.loads((RES / "2026-10-18-c5b-route-certificates" / "result.json").read_text(encoding="utf-8"))

# Output of `dart run tool/paper_example.dart` in packages/pulse_belief (29 Oct 2026): prior 0.05, fresh crowd reports alpha = 0.6.
WORKED = {
    1.28: {"wald": [0.329, 0.309, 0.333, 0.380], "beta": [0.164, 0.453, 0.581, 0.657]},
    2.0: {"wald": [0.486, 0.441, 0.461, 0.509], "beta": [0.499, 0.724, 0.799, 0.840]},
}

macros: dict[str, str] = {}


def m(name: str, value) -> None:
    macros[name] = str(value)


def f(x: float, nd: int = 2) -> str:
    return f"{x:.{nd}f}"


def signed(x: float, nd: int = 3) -> str:
    return f"{x:+.{nd}f}".replace("-", "$-$") if x < 0 else f"{x:+.{nd}f}"


def thousands(n: int) -> str:
    return f"{n:,}"


# ---------------------------------------------------------------- graph and corpus
import t3_2_replay_engine as t32  # noqa: E402

graph = json.loads((CODE / "data/graph/2026-09-14/chennai_graph_cli.json").read_text(encoding="utf-8"))
m("NNodes", thousands(graph["node_count"]))
m("NEdges", thousands(len(graph["edges"])))
obs_by_edge = t32.load_corpus_both_directions()
prior = t32.load_prior()
n_obs_edges = len(obs_by_edge)
n_prior_only = sum(1 for e, v in prior.items() if e not in obs_by_edge and v["prior_p"] >= 0.25)
m("NObsEdges", thousands(n_obs_edges))
m("NPriorEdges", thousands(n_prior_only))
m("NHazEdges", thousands(n_obs_edges + n_prior_only))
m("NOfficialEdges", thousands(C5B["positive_edges"]))
corpus = [json.loads(line) for line in (CODE / "data/corpus/2026-09-17/observations.ndjson").open(encoding="utf-8")]
m("NObs", thousands(len(corpus)))
m("NFlood", thousands(sum(1 for o in corpus if o["hazard_class"] == "flood")))
m("NWater", thousands(sum(1 for o in corpus if o["hazard_class"] == "waterlogging")))
m("NOfficial", thousands(sum(1 for o in corpus if o["source_class"] == "official_feed")))
m("NCrowd", thousands(sum(1 for o in corpus if o["source_class"] == "crowd")))
m("CrowdShare", round(100 * sum(1 for o in corpus if o["source_class"] == "crowd") / len(corpus)))
kml = (CODE / "data/watchlist_raw/chennai_flood_hazard_zones.kml").read_text(encoding="utf-8")
m("NZones", thousands(kml.count("<Placemark")))
snaps = json.loads((CODE / "data/corpus/2026-09-17/edge_snap_index.json").read_text(encoding="utf-8"))
import statistics  # noqa: E402

m("SnapMed", f(statistics.median(s["snap_distance_m"] for s in snaps), 1))

# ---------------------------------------------------------------- Study 1
A = S1["summary_all_pairs"]
NOD = A["C0"]["n_pairs"]
m("NOD", thousands(NOD))
m("BootB", thousands(S1["bootstrap"]["B"]))
changed = S1["routes_changed_vs_c0"]
names = {"C0": "Zero", "C1": "One", "Chyb": "Hyb", "C3": "Three", "C3_l5": "ThreeFive", "C3_l20": "ThreeTwenty"}
for k, n in names.items():
    a = A[k]
    m(f"Sp{n}", f(a["sum_p_mean"]))
    m(f"SpObs{n}", f(a["sum_p_observed_mean"]))
    m(f"SpPrior{n}", f(a["sum_p_prior_only_mean"]))
    m(f"Hr{n}", f(100 * a["share_routes_touching_p_ge_0_5"], 1))
    m(f"Det{n}", f(a["mean_free_flow_detour_pct"], 2))
    m(f"Chg{n}", thousands(changed.get(k, 0)))
    m(f"Disc{n}", a["n_disconnected"])


def contrast(a: str, b: str, metric: str) -> dict:
    return next(c for c in S1["paired_contrasts"] if c["a"] == a and c["b"] == b and c["metric"] == metric)


for (a, b, tag) in [("C3", "C0", "ThreeZero"), ("C1", "C0", "OneZero"), ("Chyb", "C0", "HybZero"), ("C3_l5", "C0", "FiveZero"),
                    ("C3_l20", "C0", "TwentyZero"), ("C3_l5", "C1", "FiveOne"), ("C3_l5", "Chyb", "FiveHyb")]:
    for metric, mt in [("sum_p", ""), ("sum_p_observed", "Obs"), ("sum_p_prior_only", "Prior")]:
        try:
            c = contrast(a, b, metric)
        except StopIteration:
            continue
        m(f"D{mt}{tag}", signed(c["mean_diff_a_minus_b"]))
        m(f"D{mt}{tag}lo", signed(c["ci95"][0]))
        m(f"D{mt}{tag}hi", signed(c["ci95"][1]))

H = S1["held_out_official_check"]
for lam, tag in [("lambda_5.0", "Five"), ("lambda_20.0", "Twenty")]:
    h = H[lam]
    m(f"HoPrior{tag}", f(h["official_edges_per_route_prior_only"], 3))
    m(f"HoCrowd{tag}", f(h["official_edges_per_route_prior_plus_crowd"], 3))
    m(f"HoDiff{tag}", signed(h["mean_diff_crowd_minus_prior_only"]))
    m(f"HoDiff{tag}lo", signed(h["ci95"][0]))
    m(f"HoDiff{tag}hi", signed(h["ci95"][1]))

# ---------------------------------------------------------------- Study 2
OV = S2["metrics_overall_all_edges"]
CP = S2["metrics_crowd_pool_only"]
AGE0 = S2["metrics_by_report_age_bucket"]["0"]
m("CalN", thousands(OV["n"]))
m("CalPos", thousands(OV["n_positive"]))
m("CrowdEdges", thousands(S2["n_crowd_pool_edges"]))
m("CrowdRows", thousands(S2["n_crowd_pool_rows_all_age_buckets"]))
m("PosEdges", thousands(S2["pool_stats"]["edges_with_official_confirmation"]))
m("NoRepEdges", thousands(S2["n_no_report_pool_edges"]))
m("CliBrier", f(OV["c3_ours"]["murphy_uncertainty"], 4))
m("CliBrierCrowd", f(CP["c3_ours"]["murphy_uncertainty"], 4))
models = [("prior_only", "Prior"), ("c3_ours", "Three"), ("c2_single_decay", "Two"), ("c4_fixed_ttl", "Four"),
          ("beta_reputation_with_forgetting", "Beta")]
for key, tag in models:
    for pool, pt in [(OV, ""), (CP, "Crowd")]:
        v = pool[key]
        m(f"Brier{tag}{pt}", f(v["brier"], 4))
        m(f"BssCli{tag}{pt}", signed(v["brier_skill_vs_climatology"], 2))
        m(f"BssPrior{tag}{pt}", signed(v["brier_skill_vs_prior_only"], 2))
        m(f"Ece{tag}{pt}", f(v["adaptive_ece"], 3))
        m(f"Auc{tag}{pt}", f(v["auroc_discrimination_only"], 3))
        m(f"Res{tag}{pt}", f"{v['murphy_resolution']:.1e}".replace("e-0", "\\times10^{-").replace("e-", "\\times10^{-") + "}")
m("BrierThreeAgeZero", f(AGE0["c3_ours"]["brier"], 4))
m("BrierPriorAgeZero", f(AGE0["prior_only"]["brier"], 4))

# ---------------------------------------------------------------- explanation gate
m("VfReject", VF["n_must_reject"])
m("VfAccept", VF["n_must_accept"])
m("VfFalseAcc", VF["false_accepts"])
m("VfFalseRej", VF["false_rejects"])
m("VbFalseAcc", VB["false_accepts"])
m("VbFalseAccPct", f(100 * VB["false_accept_rate"], 1))

# ---------------------------------------------------------------- conformal (ADR-036)
sp = C5["spatial_split"]["S1_c3_p_mean"]["flood"]
pr = C5["spatial_split"]["S2_prior_only"]["flood"]
m("CfCov", f(sp["coverage"]["mean"], 3))
m("CfFf", f(100 * sp["false_flag_rate"]["mean"], 1))
m("CfFfPrior", f(100 * pr["false_flag_rate"]["mean"], 1))
m("CfCOneCov", f(sp["c1_block_p_ge_0_5_coverage"]["mean"], 3))
cb = C5B["configs"]["C0"]["scores"]["S1_c3_p_mean"]
m("CbTau", f(cb["route_certificate"]["tau_median"], 2))
m("CbShare", f(100 * cb["route_certificate"]["share_of_route_seconds_flagged"]["mean"], 0))
m("CbEdgeCov", f(cb["c5_edge_level_rule_on_routes"]["route_coverage"]["mean"], 3))
m("CbEdgeShare", f(100 * cb["c5_edge_level_rule_on_routes"]["share_of_route_seconds_flagged"]["mean"], 0))

# ---------------------------------------------------------------- CSFE prototype dataset and benchmark B1
CS = json.loads((CODE / "data" / "csfe" / "2026-10-30" / "summary.json").read_text(encoding="utf-8"))
B1 = json.loads((RES / "2026-10-30-csfe-b1-addendum2" / "result.json").read_text(encoding="utf-8"))
m("CsfeObs", thousands(CS["observations"]))
m("CsfeNeg", thousands(sum(CS["by_kind"].get(k, 0) for k in ("not_waterlogged", "open", "waterlogged_open"))))
m("CsfeClosed", thousands(CS["by_kind"].get("closed", 0)))
m("CsfeNews", thousands(CS["news_facts"]))
m("CsfeNewsEvents", CS["news_events"])
m("CsfeTimed", thousands(CS["with_time_to_the_day_or_better"]))
m("CsfeSubways", CS["subways_in_timeline"])
m("CsfeGaugeDays", thousands(CS["rain_daily_rows"]))
m("CsfeGauges", CS["gauges_with_position"])
m("CsfeWlStations", CS["water_level_stations"])
m("CsfeCrowd", thousands(CS["by_source_type"]["crowd"]))
m("CsfeOfficial", thousands(CS["by_source_type"]["official"]))
m("BoneRows", B1["rows"])
m("BoneEvents", len(B1["events"]))
m("BonePos", B1["positives"])
m("BoneRainBss", signed(B1["models"]["rain"]["bss_vs_base"], 2))
m("BoneRainBsslo", signed(B1["ci95"]["rain_bss_vs_base"][0], 2))
_hi = B1["ci95"]["rain_bss_vs_base"][1]
m("BoneRainBsshi", "0.00" if abs(_hi) < 0.005 else signed(_hi, 2))

# ---------------------------------------------------------------- worked example
for z, tag in [(1.28, "Lo"), (2.0, "Hi")]:
    for kind in ("wald", "beta"):
        for k, v in enumerate(WORKED[z][kind]):
            m(f"Ex{kind.capitalize()}{tag}{'ABCD'[k]}", f(v, 3))

# ---------------------------------------------------------------- write numbers.tex
lines = ["% Generated by make_numbers_v3.py from the project's result files. Do not edit by hand."]
lines += [f"\\newcommand{{\\{k}}}{{{v}}}" for k, v in macros.items()]
(HERE / "numbers.tex").write_text("\n".join(lines) + "\n", encoding="utf-8")

# ---------------------------------------------------------------- tables
rows = [("C0 free-flow", "Zero"), ("C1 block $\\bar p\\ge0.5$", "One"), ("Hybrid: C1 + soft, $\\lambda=5$", "Hyb"),
        ("C3 default ($z=0$, $\\lambda=0.3$)", "Three"), ("C3, $z=0$, $\\lambda=5$", "ThreeFive"), ("C3, $z=0$, $\\lambda=20$", "ThreeTwenty")]
t = ["\\begin{tabular}{lrrrrrr}", "\\toprule",
     "Configuration & Changed & $\\sum\\bar p$ & Observed & Prior-only & Touch $\\ge0.5$ & Detour\\\\",
     " & routes & per route & edges & edges & (\\%) & (\\%)\\\\", "\\midrule"]
for label, n in rows:
    t.append(f"{label} & {macros['Chg' + n]} & {macros['Sp' + n]} & {macros['SpObs' + n]} & {macros['SpPrior' + n]} & "
             f"{macros['Hr' + n]} & {macros['Det' + n]}\\\\")
t += ["\\bottomrule", "\\end{tabular}"]
(HERE / "sweep_table.tex").write_text("\n".join(t) + "\n", encoding="utf-8")

c = ["\\begin{tabular}{lrrrrr}", "\\toprule", "Model & Brier & BSS$_{\\text{clim}}$ & BSS$_{\\text{prior}}$ & Adapt.\\ ECE & AUROC\\\\",
     "\\midrule", f"Climatology & {macros['CliBrier']} & 0 & -- & -- & 0.500\\\\"]
for key, tag in models:
    label = {"Prior": "Prior only", "Three": "C3 class-specific decay", "Two": "C2 single decay", "Four": "C4 fixed TTL (6 h)",
             "Beta": "Beta reputation~\\cite{josang2002beta}"}[tag]
    bss_prior = "0" if tag == "Prior" else macros["BssPrior" + tag]
    c.append(f"{label} & {macros['Brier' + tag]} & {macros['BssCli' + tag]} & {bss_prior} & {macros['Ece' + tag]} & "
             f"{macros['Auc' + tag]}\\\\")
c += ["\\bottomrule", "\\end{tabular}"]
(HERE / "cal_table.tex").write_text("\n".join(c) + "\n", encoding="utf-8")

# ---------------------------------------------------------------- figures
plt.rcParams.update({"font.size": 8, "font.family": "serif"})
cfg = [("C0", "C0"), ("C1", "C1"), ("Chyb", "Hybrid"), ("C3", "C3 ($\\lambda$=0.3)"), ("C3_l5", "C3 ($\\lambda$=5)"),
       ("C3_l20", "C3 ($\\lambda$=20)")]
MARK = {"C0": "s", "C1": "D", "Chyb": "^", "C3": "o", "C3_l5": "o", "C3_l20": "o"}
COL = {"C0": "#333333", "C1": "#8172B2", "Chyb": "#55A868", "C3": "#C44E52", "C3_l5": "#DD8452", "C3_l20": "#4C72B0"}
fig, ax = plt.subplots(1, 2, figsize=(3.5, 2.3), sharex=True)
for k, lab in cfg:
    a = A[k]
    for i, (yk, title) in enumerate([("sum_p_mean", "$\\sum\\bar p$ per route"),
                                     ("share_routes_touching_p_ge_0_5", "Routes touching $\\bar p\\geq0.5$")]):
        y = a[yk] * (100 if i == 1 else 1)
        ax[i].scatter(a["mean_free_flow_detour_pct"], y, s=14, marker=MARK[k], color=COL[k], label=lab if i == 0 else None,
                      zorder=3)
        ax[i].set_title(title, fontsize=7)
xs = [A[k]["mean_free_flow_detour_pct"] for k in ("C3", "C3_l5", "C3_l20")]
ax[0].plot(xs, [A[k]["sum_p_mean"] for k in ("C3", "C3_l5", "C3_l20")], lw=0.6, color="gray")
ax[1].plot(xs, [100 * A[k]["share_routes_touching_p_ge_0_5"] for k in ("C3", "C3_l5", "C3_l20")], lw=0.6, color="gray")
for a_ in ax:
    a_.set_xlabel("Mean extra free-flow time (%)", fontsize=6.5)
    a_.tick_params(labelsize=6)
ax[1].set_ylabel("%", fontsize=6.5)
fig.legend(loc="lower center", ncol=3, fontsize=5.5, frameon=False, bbox_to_anchor=(0.5, 0.0))
fig.tight_layout(rect=(0, 0.13, 1, 1))
fig.savefig(HERE / "fig_pareto_common.pdf")
if os.environ.get("PREVIEW"):
    fig.savefig(Path(os.environ["PREVIEW"]) / "fig_pareto_common.png", dpi=200)
plt.close(fig)

fig, ax = plt.subplots(figsize=(3.5, 1.9))
labels = [lab for _, lab in cfg]
obs = [A[k]["sum_p_observed_mean"] for k, _ in cfg]
pri = [A[k]["sum_p_prior_only_mean"] for k, _ in cfg]
ax.bar(labels, obs, label="edges with observations", color="#4C72B0")
ax.bar(labels, pri, bottom=obs, label="prior-only edges", color="#DD8452")
for i, (k, _) in enumerate(cfg):
    ax.text(i, obs[i] + pri[i] + 0.03, f"{A[k]['mean_free_flow_detour_pct']:.2f}%", ha="center", fontsize=5.5)
ax.set_ylabel("$\\sum\\bar p$ per route", fontsize=7)
ax.tick_params(axis="x", labelsize=5.5, rotation=20)
ax.tick_params(axis="y", labelsize=6)
ax.set_ylim(0, max(o + q for o, q in zip(obs, pri, strict=True)) * 1.32)
ax.legend(fontsize=6, frameon=False, loc="upper right", ncol=2)
fig.tight_layout()
fig.savefig(HERE / "fig_decomp.pdf")
if os.environ.get("PREVIEW"):
    fig.savefig(Path(os.environ["PREVIEW"]) / "fig_decomp.png", dpi=200)
plt.close(fig)

# Study 2's own figure, with its working title (which refers to internal notes) cropped off; the paper's caption describes it.
from PIL import Image  # noqa: E402

img = Image.open(RES / "2026-10-02-study2-calibration" / "figures" / "figure4_reliability_diagrams.png")
img.crop((0, int(img.height * 0.17), img.width, img.height)).save(HERE / "fig_reliability.png")
print(f"{len(macros)} macros; tables and figures written")
