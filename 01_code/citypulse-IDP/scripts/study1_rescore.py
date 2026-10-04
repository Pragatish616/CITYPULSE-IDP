"""Study 1 re-scoring under ONE reference belief (PLAN M1.11; CLAUDE.md section 5.1).

The 2026-09-18 harness scored every configuration under its own belief and counted penalty
seconds as travel time, so the configurations were not comparable (07_reanalysis/README.md).
This script reads the routes written by `study1_route_quality.py` (2026-10-02) and scores each
under a single reference belief, the Beta posterior mean of the C3 model at the replay clock
(independent of z), and measures detours in free-flow time. It reports:

  * sum of the reference p-mean over the edges of each route, split into edges that carry a
    report and prior-only edges (the review found the advantage over a hard block comes from
    the prior, not from reports);
  * the share of routes touching an edge with p-mean >= 0.5;
  * the mean free-flow detour against C0;
  * pairs a configuration disconnects (a hard block can);
  * paired bootstrap 95% CIs over origin-destination pairs (the pairs are independent draws, so
    resampling pairs is the right unit; seed pinned);
  * the held-out check: route with the prior only vs prior + crowd reports, at lambda = 5 and 20,
    and count the edges that carry an *official* report on the route. Official reports are held
    out of both beliefs. This is the check that asks whether crowd reports add anything.

Node paths come from each trace's `geometry_ref`; each hop (u, v) is mapped to the parallel edge
with the smallest free-flow time. Where two parallel edges join the same nodes and the router
picked the other one, an edge id can differ; that affects the edge-level split by a small amount
and is stated in the result.

Needs the router build that produced the traces; the held-out stage runs the CLI again, so set
PULSE_ROUTER_BIN as for Study 1.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import numpy as np
import study1_route_quality as s1
import study_common as sc
import t3_2_replay_engine as t32

SEED = 20261002  # bootstrap seed, pinned before the run
BOOTSTRAP_B = 5000
RESULTS_DATE = "2026-10-02"
SRC_DIR = t32.ROOT / "data" / "results" / f"{RESULTS_DATE}-study1-route-quality"
OUT_DIR = t32.ROOT / "data" / "results" / f"{RESULTS_DATE}-study1-rescored"
HIGH_P = 0.5
HELD_OUT_LAMBDAS = [5.0, 20.0]  # fixed in advance (CLAUDE.md R3)


def load_routes(name: str, n_pairs: int) -> list[list[int] | None]:
    """Node path per pair index (None where the router found no route)."""
    out: list[list[int] | None] = [None] * n_pairs
    path = SRC_DIR / "traces" / f"{name}.ndjson"
    for line in path.read_text(encoding="utf-8").splitlines():
        tr = json.loads(line)
        idx = int(tr["query_id"].rsplit("-", 1)[1])
        out[idx] = [int(x) for x in tr["chosen"]["geometry_ref"].split(":", 1)[1].split(",")]
    return out


def boot_ci(diffs: np.ndarray, rng: np.random.Generator) -> list[float]:
    n = len(diffs)
    if n == 0:
        return [float("nan"), float("nan")]
    idx = rng.integers(0, n, size=(BOOTSTRAP_B, n))
    means = diffs[idx].mean(axis=1)
    return [float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)

    hazard_classes = t32.load_hazard_classes()
    alpha = hazard_classes["source_reliability"]
    at = t32.parse_iso8601(s1.REPLAY_CLOCK)
    configs, windowed, _alpha, _stats = s1._build_windowed(hazard_classes, s1.REPLAY_CLOCK)

    # Reference belief: Beta posterior mean per hazard-config edge (z-independent).
    p_ref: dict[int, float] = {}
    has_obs: set[int] = set()
    official_edges: set[int] = set()
    for eid, cfg in configs.items():
        obs = windowed.get(eid, [])
        belief = sc.fuse_beta_py(
            sc.with_reliability(obs, alpha), cfg.prior_logodds, at, cfg.decay_tau_seconds
        )
        p_ref[eid] = belief["p_mean"]
        if obs:
            has_obs.add(eid)
        if any(o.source_class != "crowd" for o in obs):
            official_edges.add(eid)

    graph = t32.load_graph_cli()
    best: dict[tuple[int, int], tuple[float, int]] = {}
    for e in graph["edges"]:
        key = (int(e["from"]), int(e["to"]))
        ff = float(e["free_flow_seconds"])
        if key not in best or ff < best[key][0]:
            best[key] = (ff, int(e["edge_id"]))

    def edges_of(nodes: list[int]) -> list[tuple[float, int]]:
        return [best[(u, v)] for u, v in zip(nodes, nodes[1:])]

    def score(nodes: list[int] | None) -> dict | None:
        if nodes is None:
            return None
        hops = edges_of(nodes)
        ps = [(p_ref.get(eid, 0.0), eid) for _, eid in hops]
        return {
            "ff_s": sum(ff for ff, _ in hops),
            "sum_p": sum(p for p, _ in ps),
            "sum_p_observed": sum(p for p, eid in ps if eid in has_obs),
            "sum_p_prior_only": sum(p for p, eid in ps if eid in p_ref and eid not in has_obs),
            "touches_p_ge_0_5": any(p >= HIGH_P for p, _ in ps),
            "n_official_edges": sum(1 for _, eid in ps if eid in official_edges),
        }

    n_pairs = s1.N_MAIN
    names = [c[0] for c in s1.MAIN_CONFIGS]
    scored = {n: [score(r) for r in load_routes(n, n_pairs)] for n in names}

    def summarise(name: str, upto: int) -> dict:
        rows = scored[name][:upto]
        base = scored["C0"][:upto]
        ok = [(r, b) for r, b in zip(rows, base) if r is not None and b is not None]
        n = len(ok)
        arr = lambda key: np.array([r[key] for r, _ in ok], dtype=float)  # noqa: E731
        detour = np.array([r["ff_s"] / b["ff_s"] for r, b in ok])
        return {
            "n_pairs": upto,
            "n_routed": sum(r is not None for r in rows),
            "n_disconnected": sum(r is None for r in rows),
            "sum_p_mean": float(arr("sum_p").mean()),
            "sum_p_observed_mean": float(arr("sum_p_observed").mean()),
            "sum_p_prior_only_mean": float(arr("sum_p_prior_only").mean()),
            "share_routes_touching_p_ge_0_5": float(arr("touches_p_ge_0_5").mean()),
            "mean_free_flow_detour_pct": float((detour.mean() - 1) * 100),
            "n_used_paired_with_c0": n,
        }

    summary = {n: summarise(n, n_pairs) for n in names}
    summary_first_100 = {n: summarise(n, s1.N_FIRST) for n in names}

    def paired(a: str, b: str, key: str) -> dict:
        d = np.array(
            [
                x[key] - y[key]
                for x, y in zip(scored[a], scored[b])
                if x is not None and y is not None
            ],
            dtype=float,
        )
        return {
            "a": a,
            "b": b,
            "metric": key,
            "n_paired": int(len(d)),
            "mean_diff_a_minus_b": float(d.mean()) if len(d) else float("nan"),
            "ci95": boot_ci(d, rng),
        }

    contrasts = []
    for a, b in [
        ("C1", "C0"),
        ("Chyb", "C0"),
        ("C3", "C0"),
        ("C3_l5", "C0"),
        ("C3_l20", "C0"),
        ("C3_l5", "C1"),
        ("C3_l5", "Chyb"),
        ("C3_l20", "Chyb"),
    ]:
        for key in ("sum_p", "sum_p_observed", "sum_p_prior_only"):
            contrasts.append(paired(a, b, key))
    n_changed = {
        n: sum(
            1
            for r, b in zip(load_routes(n, n_pairs), load_routes("C0", n_pairs))
            if r is not None and b is not None and r != b
        )
        for n in names
        if n != "C0"
    }

    # ---- held-out check: does adding crowd reports change routing toward official reports? ----
    held_out = {}
    graph_path = t32.GRAPH_DIR / "chennai_graph_cli.json"
    adj = t32.build_adjacency(t32.load_graph_cli())
    pairs, _ = t32.sample_od_pairs(graph["node_count"], adj, s1.SEED, n_pairs)
    crowd_only = {
        eid: [o for o in obs if o.source_class == "crowd"] for eid, obs in windowed.items()
    }
    prior_only = {eid: [] for eid in windowed}
    with tempfile.TemporaryDirectory() as tmp:
        for lam in HELD_OUT_LAMBDAS:
            counts = {}
            for tag, wobs in (("prior_only", prior_only), ("prior_plus_crowd", crowd_only)):
                work = Path(tmp) / f"{tag}_{lam}"
                work.mkdir(parents=True, exist_ok=True)
                haz = t32.to_cli_hazards_json(configs, wobs, alpha)
                obs_path = work / "hazards.json"
                obs_path.write_text(json.dumps(haz), encoding="utf-8")
                traces, _errs = t32.invoke_cli_batch(
                    t32.CLI_BINARY,
                    graph_path,
                    obs_path,
                    pairs,
                    s1.REPLAY_CLOCK,
                    s1.USER_CLASS,
                    0.0,
                    lam,
                    f"heldout-{tag}-{lam}",
                    work,
                )
                counts[tag] = [
                    score(
                        [int(x) for x in tr["chosen"]["geometry_ref"].split(":", 1)[1].split(",")]
                    )
                    if tr is not None
                    else None
                    for tr in traces
                ]
            d = np.array(
                [
                    a["n_official_edges"] - b["n_official_edges"]
                    for a, b in zip(counts["prior_plus_crowd"], counts["prior_only"])
                    if a is not None and b is not None
                ],
                dtype=float,
            )
            held_out[f"lambda_{lam}"] = {
                "official_edges_per_route_prior_only": float(
                    np.mean([r["n_official_edges"] for r in counts["prior_only"] if r])
                ),
                "official_edges_per_route_prior_plus_crowd": float(
                    np.mean([r["n_official_edges"] for r in counts["prior_plus_crowd"] if r])
                ),
                "mean_diff_crowd_minus_prior_only": float(d.mean()),
                "ci95": boot_ci(d, rng),
                "n_paired": int(len(d)),
                "reading": (
                    "negative = adding crowd reports moved routes away from official-report "
                    "edges; a CI that includes 0 means no measurable effect"
                ),
            }
            print(f"held-out lambda {lam}: {held_out[f'lambda_{lam}']}", flush=True)

    result = {
        "task": "Study 1 re-scoring under one reference belief (PLAN M1.11)",
        "source_results": str(SRC_DIR.relative_to(t32.ROOT)),
        "reference_belief": (
            "Beta posterior mean (ADR-015) of the C3 model at the replay clock, all report "
            "sources, independent of z; identical for every configuration"
        ),
        "bootstrap": {"unit": "origin-destination pair", "B": BOOTSTRAP_B, "seed": SEED},
        "edge_mapping_caveat": (
            "node paths mapped to the smallest-free-flow parallel edge per hop; where the router "
            "used a parallel twin the edge id may differ"
        ),
        "router_build": os.environ.get("PULSE_ROUTER_BIN", "data/bin/pulse_router.exe (default)"),
        "summary_all_pairs": summary,
        "summary_first_100_pairs": summary_first_100,
        "routes_changed_vs_c0": n_changed,
        "paired_contrasts": contrasts,
        "held_out_official_check": held_out,
        "corpus_caveats": [
            "single proxy timestamp, all reports positive, no depth (CLAUDE.md section 4.4): decay, "
            "the chance constraint and false-avoidance cost are untestable here",
            "'official' points include GCC vulnerability designations, not only dated observations",
        ],
        "reproduce_with": "PULSE_ROUTER_BIN=... python scripts/study1_rescore.py",
    }
    (OUT_DIR / "result.json").write_text(json.dumps(result, indent=2, default=str), encoding="utf-8")
    print(f"Wrote {OUT_DIR / 'result.json'}")
    for n in names:
        s = summary[n]
        print(
            f"{n:7s} routed={s['n_routed']} disc={s['n_disconnected']} sum_p={s['sum_p_mean']:.3f} "
            f"(obs {s['sum_p_observed_mean']:.3f} / prior {s['sum_p_prior_only_mean']:.3f}) "
            f"touch>=.5={s['share_routes_touching_p_ge_0_5']:.2%} detour={s['mean_free_flow_detour_pct']:.2f}%"
        )


if __name__ == "__main__":
    main()
