"""C5b: route certificates, exactly as pre-registered in ml/conformal/PREREGISTRATION.md (section C5b, committed 4d31f85).

Run from 01_code/citypulse-IDP:  python scripts/c5b_route_certificates.py
Writes data/results/2026-10-18-c5b-route-certificates/result.json. Seeds: Study 2 pools 20260918 (unchanged), splits 20261018.
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT))

import study2_calibration as s2  # noqa: E402
import t3_2_replay_engine as t32  # noqa: E402

from ml.conformal.flags import positive_threshold, route_covered, route_threshold  # noqa: E402

ALPHA = 0.10
N_SPLITS = 200
SPLIT_SEED = 20261018
KILL_BELOW = 0.85
TRACES = ROOT / "data" / "results" / "2026-10-02-study1-route-quality" / "traces"
OUT = ROOT / "data" / "results" / "2026-10-18-c5b-route-certificates" / "result.json"


def load_routes(config: str, edge_of: dict[tuple[int, int], int]) -> list[list[int]]:
    routes = []
    with open(TRACES / f"{config}.ndjson", encoding="utf-8") as f:
        for line in f:
            t = json.loads(line)
            ref = t["chosen"]["geometry_ref"]
            if not ref.startswith("nodes:"):
                raise SystemExit(f"unexpected geometry_ref in {config}")
            nodes = [int(x) for x in ref[len("nodes:") :].split(",") if x]
            edges = [edge_of[(a, b)] for a, b in zip(nodes, nodes[1:], strict=False)]
            routes.append(edges)
    return routes


def main() -> None:
    graph = t32.load_graph_cli()
    edge_of: dict[tuple[int, int], int] = {}
    seconds: dict[int, float] = {}
    for e in graph["edges"]:
        key = (e["from"], e["to"])
        seconds[e["edge_id"]] = e["free_flow_seconds"]
        if key not in edge_of or e["free_flow_seconds"] < seconds[edge_of[key]]:
            edge_of[key] = e["edge_id"]

    obs = t32.load_corpus_both_directions()
    positive = {e for e, recs in obs.items() if any(r.source_class == "official_feed" for r in recs)}
    prior = t32.load_prior()
    prior_p = {e: float(v["prior_p"]) for e, v in prior.items()}
    crowd_pool, _, _ = s2.load_edge_pools()
    crowd_rows = [r for r in s2.score_crowd_pool(crowd_pool, t32.load_hazard_classes()) if r["age_bucket_hours"] == 0]
    s2_score = dict(prior_p)
    s1_score = dict(prior_p)
    for r in crowd_rows:
        s1_score[r["edge_id"]] = float(r["p_mean_c3_ours"])
    scores = {"S1_c3_p_mean": s1_score, "S2_prior_only": s2_score}

    rng = np.random.default_rng(SPLIT_SEED)
    result: dict = {
        "task": "C5b route certificates",
        "preregistration": "ml/conformal/PREREGISTRATION.md, section C5b (commit 4d31f85)",
        "alpha": ALPHA,
        "splits": N_SPLITS,
        "split_seed": SPLIT_SEED,
        "positive_edges": len(positive),
        "configs": {},
    }
    for config in ("C0", "C3"):
        routes = load_routes(config, edge_of)
        with_pos = sum(1 for r in routes if any(e in positive for e in r))
        cfg_out: dict = {"routes": len(routes), "routes_with_a_positive_edge": with_pos, "scores": {}}
        for sname, sc in scores.items():
            acc = {k: [] for k in ("cov", "share_edges", "share_seconds", "edge_cov", "edge_share_edges", "edge_share_seconds", "tau")}
            med_share = []
            for _ in range(N_SPLITS):
                perm = rng.permutation(len(routes))
                cal = [routes[i] for i in perm[: len(routes) // 2]]
                test = [routes[i] for i in perm[len(routes) // 2 :]]
                tau = route_threshold(cal, sc, positive, ALPHA)
                cal_edges = {e for r in cal for e in r}
                tau_edge = positive_threshold([sc.get(e, 0.0) for e in cal_edges if e in positive], ALPHA)
                for t, kc, ke, ks in ((tau, "cov", "share_edges", "share_seconds"), (tau_edge, "edge_cov", "edge_share_edges", "edge_share_seconds")):
                    cov = [route_covered(r, sc, positive, t) for r in test]
                    cov = [c for c in cov if c is not None]
                    acc[kc].append(float(np.mean(cov)) if cov else math.nan)
                    shares_e = [np.mean([sc.get(e, 0.0) >= t for e in r]) for r in test if r]
                    shares_s = [
                        sum(seconds[e] for e in r if sc.get(e, 0.0) >= t) / max(sum(seconds[e] for e in r), 1e-9) for r in test if r
                    ]
                    acc[ke].append(float(np.mean(shares_e)))
                    acc[ks].append(float(np.mean(shares_s)))
                    if kc == "cov":
                        med_share.append(float(np.median(shares_s)))
                acc["tau"].append(tau)

            def summ(xs: list[float]) -> dict:
                a = np.array([x for x in xs if not math.isnan(x)])
                return {"mean": round(float(a.mean()), 4), "p05": round(float(np.quantile(a, 0.05)), 4), "p95": round(float(np.quantile(a, 0.95)), 4)}

            taus = np.array(acc["tau"])
            cfg_out["scores"][sname] = {
                "route_certificate": {
                    "route_coverage": summ(acc["cov"]),
                    "share_of_route_edges_flagged": summ(acc["share_edges"]),
                    "share_of_route_seconds_flagged": summ(acc["share_seconds"]),
                    "median_route_share_of_seconds_flagged": summ(med_share),
                    "tau_median": float(np.median(taus[np.isfinite(taus)])) if np.isfinite(taus).any() else None,
                    "share_of_splits_tau_minus_inf": float(np.mean(~np.isfinite(taus))),
                },
                "c5_edge_level_rule_on_routes": {
                    "route_coverage": summ(acc["edge_cov"]),
                    "share_of_route_edges_flagged": summ(acc["edge_share_edges"]),
                    "share_of_route_seconds_flagged": summ(acc["edge_share_seconds"]),
                },
            }
        result["configs"][config] = cfg_out
    main_cert = result["configs"]["C0"]["scores"]["S1_c3_p_mean"]["route_certificate"]
    result["decision"] = {
        "route_coverage_C0_S1": main_cert["route_coverage"]["mean"],
        "killed": main_cert["route_coverage"]["mean"] < KILL_BELOW,
        "uninformative": main_cert["median_route_share_of_seconds_flagged"]["mean"] > 0.5,
    }
    try:
        result["code_commit_at_run"] = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, cwd=ROOT
        ).stdout.strip()
    except OSError:
        result["code_commit_at_run"] = "unknown"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
