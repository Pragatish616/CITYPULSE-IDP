"""T3.3 -- Study 1: route quality (docs/EVALUATION.md Study 1, docs/IMPLEMENTATION_PLAN.md T3.3).

Builds on `scripts/t3_2_replay_engine.py` (corpus loader, hazard-config builder, windowing,
OD sampler, CLI invocation) and `scripts/study_common.py` (config variants, metrics). Every
route-quality number below comes from invoking the real compiled `pulse_router` CLI
(`data/bin/pulse_router.exe`) -- no route or cost is computed in Python; see
`study_common.py`'s module docstring for exactly what *is* replicated in Python (belief-fusion
scoring only, for C1's config-building step, never for costing or search) and why that is not
the "reimplementing routing logic" the task warns against.

**Configurations and exactly how each was mechanically realised** (see `study_common.py` for
the code):
  - C0 (hazard-blind)        -- `{"hazards": []}`. Exact.
  - C1 (naive hard avoidance) -- NOT expressible via existing CLI flags alone (the only hard-
    removal mechanism is the depth-based chance constraint, and this corpus's depth_mm is null
    everywhere). Approximated by injecting a synthetic depth_mm/epsilon on edges whose
    z=0 p_mean crosses a fixed threshold, so the CLI's own real chance-constraint mechanism
    performs the removal. See `study_common.build_c1_injected_overrides`'s docstring.
  - C2 (hand-tuned single decay) -- hazard_classes.yaml deep-copied with every class's T_c
    replaced by one shared constant. Exact, uses the real per-hazard-class-elsewhere pipeline.
  - C3 (ours)                -- hazard_classes.yaml as-is, real z > 0. Identical to T3.2.
  - C4 (fixed TTL)           -- harness pre-filters observations by age at query time and
    overrides decay_tau to a very large constant (no decay within the surviving window). Exact
    mechanism, not an approximation of a CLI flag that does not exist.
  - C-infinity (oracle)      -- windowing skipped entirely. Degenerates to C3 in this corpus
    snapshot (single proxy timestamp) -- flagged loudly in the result manifest, not hidden.

**Real corpus limitation carried over from T3.2, restated here because it changes what
"impassable-edge-hit rate" can mean:** `depth_mm` is null for every real edge in this corpus (no
source KML carries measured depth). The literal chance-constraint hard-removal in
`edge_cost.dart` therefore never fires for C0/C2/C3/C4/C-infinity -- there is no honest way to
report a nonzero "impassable-edge-hit rate" for those configs from this data, and reporting one
would misrepresent the corpus. This script reports it as an explicit `not_applicable` field for
those configs, and reports C1's *synthetic* hard-block trigger rate separately and distinctly
labelled (it exercises the same CLI mechanism, but on harness-injected, not measured, depth
values).

**False-avoidance cost** ("detours taken for hazards that were not there," per docs/
EVALUATION.md, using negative-polarity observations as ground truth where available) **cannot be
computed from this corpus at all**: every one of its 6,132 observations carries `polarity: 1`
(verified against `data/corpus/2026-09-17/observations.ndjson` -- `Counter({1: 6132})`, zero
`-1` records). There is no confirmed-absent ground truth in this snapshot. Reported as
`not_computable` with this reason, not a fabricated proxy.

**Splitting rule.** This corpus is the single 2015 Chennai flood event with one proxy timestamp
(T3.1 MANIFEST.md) -- there is no second event or monsoon episode to split across. The
event/monsoon-episode split is implemented as a real, general function
(`split_by_event`) applied here as a documented single-fold no-op, exactly as T3.2 flagged for
Study 2's splitting rule; see this script's `result.json["event_split"]` field.

**Re-run of 2026-10-02 (PLAN M1.11).** The router now uses the Beta-posterior index (ADR-015,
KNOWN_FLAWS F-01/F-12) and the harness uses the `route-batch` CLI mode (F-20), so N_main is 1000
(the size docs/EVALUATION.md asked for). It adds the configurations the October review said were
missing: the hybrid baseline (hard block p-mean > 0.5 plus a soft lambda = 5 cost) and the
lambda = 5 / lambda = 20 C3 settings, and it records, per configuration, how many pairs the
router reported as disconnected. Results go to a new dated folder; the 2026-09-18 folder is
untouched. Build the CLI first and point `PULSE_ROUTER_BIN` at it:
`PULSE_ROUTER_BIN=data/bin/2026-10-02/pulse_router.exe python scripts/study1_route_quality.py`.

Usage: .venv/Scripts/python.exe scripts/study1_route_quality.py
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import study_common as sc
import t3_2_replay_engine as t32

SEED = 20260918  # pinned (CLAUDE.md section 7), distinct from T3.2's seed -- a fresh OD sample
RESULTS_DATE = "2026-10-02"
RESULTS_DIR = t32.ROOT / "data" / "results" / f"{RESULTS_DATE}-study1-route-quality"

REPLAY_CLOCK = (
    t32.REPLAY_CLOCK
)  # corpus's single proxy timestamp -- see T3.2's own note
USER_CLASS = "commuter"

# Scale: chosen from real measured timing, not guessed -- see "Scale decision" in main().
N_MAIN = 1000  # OD pairs per main config; the first 100 are the same pairs the 2026-09-18 run used
N_FIRST = 100  # size of the comparison subset reported alongside (the 07_reanalysis sample)
N_SWEEP = 100  # OD pairs per Pareto grid point (C3 sweep)
MAIN_CONFIGS = [
    # (name, kind, z, lambda). Parameters are fixed here, before any run (CLAUDE.md R3).
    ("C0", "C0", None, None),
    ("C1", "C1", 0.0, 0.0),
    ("Chyb", "Chyb", 0.0, 5.0),  # block p-mean > 0.5 AND soft lambda = 5
    ("C2", "C2", None, None),
    ("C3", "C3", None, None),  # class default z, lambda (commuter 0 / 0.3)
    ("C3_l5", "C3", 0.0, 5.0),
    ("C3_l20", "C3", 0.0, 20.0),
    ("C4", "C4", None, None),
    ("Cinf", "Cinf", None, None),
]
Z_GRID = [0.0, 0.5, 1.0, 1.28, 2.0]
LAMBDA_GRID = [0.3, 0.6, 1.0]
HIGH_RISK_THRESHOLD = (
    0.5  # worst_edge_p above this = "high risk exposure" (Pareto y-axis)
)


def _event_split_placeholder(record_count: int) -> dict:
    """Real, general split-by-event/monsoon-episode logic, applied as a documented single-fold
    no-op here -- ready the moment a richer, multi-event corpus exists (per this task's explicit
    instruction not to fabricate synthetic events). T3.1's corpus is one event with one proxy
    timestamp (MANIFEST.md limitation 1), so every record falls in fold 0 by construction.
    """
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
            "T3.1's corpus (data/corpus/2026-09-17/) carries exactly one degenerate proxy "
            "timestamp for all 6,132 observations (2015-12-02T00:00:00Z, MANIFEST.md limitation "
            "1) -- there is no second event or monsoon episode to hold out. This is a genuine "
            "single-fold application of a correctly-implemented general split, not a random "
            "split and not a fabricated multi-event split. A true train/held-out-event "
            "evaluation is not currently possible with this corpus."
        ),
    }


def _build_windowed(hazard_classes: dict, at_iso: str) -> tuple[dict, dict, dict]:
    """Common setup shared by every config: load corpus/prior once, build base hazard configs,
    window by the replay clock. Returns (configs, windowed_obs_by_edge, alpha_by_source_class).
    """
    alpha_by_source_class = hazard_classes["source_reliability"]
    obs_by_edge = t32.load_corpus_both_directions()
    prior_by_edge = t32.load_prior()
    configs, hazard_stats = t32.build_hazard_configs(
        obs_by_edge, prior_by_edge, hazard_classes
    )
    at = t32.parse_iso8601(at_iso)
    windowed = t32.filter_observations_by_clock(configs, at)
    return configs, windowed, alpha_by_source_class, hazard_stats


def run_config(
    config_name: str,
    pairs: list[tuple[int, int]],
    z: float,
    lam: float,
    work_dir: Path,
) -> tuple[list[dict], list[dict], dict]:
    """Runs one configuration across `pairs`, returns (traces, errors, config_meta)."""
    base_hazard_classes = t32.load_hazard_classes()
    at_iso = REPLAY_CLOCK
    at = t32.parse_iso8601(at_iso)

    kind = "C3" if config_name.startswith("C3") else config_name
    if kind == "C0":
        hazards_json = sc.make_c0_hazards_json()
        config_meta = {"realisation": "empty hazards document -- exact"}
    elif kind in ("C1", "Chyb"):
        configs, windowed, alpha, _ = _build_windowed(base_hazard_classes, at_iso)
        depth_ov, eps_ov, c1_stats = sc.build_c1_injected_overrides(
            configs, windowed, alpha, at
        )
        hazards_json = sc.to_cli_hazards_json_with_overrides(
            configs, windowed, alpha, depth_ov, eps_ov
        )
        if kind == "C1":
            z, lam = (
                0.0,
                0.0,
            )  # "naive, no confidence" -- z=0 (no UCB widening), lambda=0 (no soft
            # harm-weighting on non-blocked edges: pure binary block/no-block policy)
        # Chyb keeps the z and lambda the caller passes (0, 5): a hard block on top of the soft cost.
        config_meta = {
            "realisation": "synthetic depth_mm/epsilon injection"
            + (" plus soft lambda cost" if kind == "Chyb" else ""),
            **c1_stats,
        }
    elif kind == "C2":
        c2_hazard_classes = sc.make_c2_hazard_classes(base_hazard_classes)
        configs, windowed, alpha, _ = _build_windowed(c2_hazard_classes, at_iso)
        hazards_json = t32.to_cli_hazards_json(configs, windowed, alpha)
        config_meta = {
            "realisation": "all classes' T_c_seconds overridden to shared constant",
            "shared_tc_seconds": sc.C2_SHARED_TC_SECONDS,
        }
    elif kind == "C3":
        configs, windowed, alpha, _ = _build_windowed(base_hazard_classes, at_iso)
        hazards_json = t32.to_cli_hazards_json(configs, windowed, alpha)
        config_meta = {"realisation": "hazard_classes.yaml as-is (identical to T3.2)"}
    elif kind == "C4":
        configs, windowed, alpha, _ = _build_windowed(base_hazard_classes, at_iso)
        ttl_configs, ttl_windowed, ttl_stats = sc.apply_fixed_ttl(configs, windowed, at)
        hazards_json = t32.to_cli_hazards_json(ttl_configs, ttl_windowed, alpha)
        config_meta = {
            "realisation": "harness pre-filter by TTL + large decay_tau",
            **ttl_stats,
        }
    elif kind == "Cinf":
        configs, _windowed, alpha, _ = _build_windowed(base_hazard_classes, at_iso)
        unwindowed = sc.skip_windowing(configs)
        hazards_json = t32.to_cli_hazards_json(configs, unwindowed, alpha)
        config_meta = {
            "realisation": "windowing skipped entirely (oracle)",
            "degenerates_to_c3_in_this_snapshot": True,
        }
    else:
        raise ValueError(config_name)

    work_dir.mkdir(parents=True, exist_ok=True)
    observations_path = work_dir / "hazards.json"
    with open(observations_path, "w", encoding="utf-8") as f:
        json.dump(hazards_json, f)

    graph_path = t32.GRAPH_DIR / "chennai_graph_cli.json"
    # One router process per configuration (KNOWN_FLAWS F-20). traces_by_index[i] is None where the
    # router found no route for pairs[i] under this configuration, so a configuration that
    # disconnects a pair (a hard block can) is recorded, not silently dropped.
    traces_by_index, batch_errors = t32.invoke_cli_batch(
        t32.CLI_BINARY,
        graph_path,
        observations_path,
        pairs,
        at_iso,
        USER_CLASS,
        z,
        lam,
        f"study1-{config_name}",
        work_dir,
    )
    errors = [
        {"index": e["index"], "source": e["source"], "target": e["target"], "error": e["error"]}
        for e in batch_errors
    ]
    traces = traces_by_index
    config_meta["z"] = z
    config_meta["lambda"] = lam
    return traces, errors, config_meta


def summarise_traces(
    config_name: str, traces_by_index: list[dict | None], errors: list[dict]
) -> dict:
    """`traces_by_index` keeps a None for every pair the router reported as unreachable under this
    configuration; those are counted in `n_disconnected`, never averaged in."""
    traces = [tr for tr in traces_by_index if tr is not None]
    detours = [sc.detour_ratio(t) for t in traces]
    worst_ps = [sc.worst_edge_p(t) for t in traces]
    penalties = [sc.hazard_time_penalty_seconds(t) for t in traces]
    hard_blocks = [sc.hard_block_triggered(t) for t in traces]
    n = len(traces)
    return {
        "config": config_name,
        "n_pairs": len(traces_by_index),
        "n_traces": n,
        "n_disconnected": len(traces_by_index) - n,
        "n_errors": len(errors),
        "disconnected_pair_indices": [i for i, tr in enumerate(traces_by_index) if tr is None],
        "detour_ratio_percentiles": sc._percentiles(detours, [50, 75, 90, 95, 99, 100]),
        "detour_ratio_mean": sum(detours) / n if n else float("nan"),
        "worst_edge_p_percentiles": sc._percentiles(worst_ps, [50, 90, 99]),
        "worst_edge_p_mean": sum(worst_ps) / n if n else float("nan"),
        "hazard_time_penalty_seconds_mean": sum(penalties) / n if n else float("nan"),
        "hard_block_trigger_rate": (
            sum(hard_blocks) / n
            if n and config_name in ("C1", "Chyb")
            else "not_applicable_depth_mm_null_in_corpus"
        ),
        "false_avoidance_cost": (
            "not_computable: zero negative-polarity observations exist in this corpus "
            "(data/corpus/2026-09-17/observations.ndjson: Counter({1: 6132}), no -1 records) "
            "-- no confirmed-absent ground truth available"
        ),
    }


def exposure_reduction_efficiency(
    baseline_traces: list[dict], config_traces: list[dict]
) -> dict:
    """Risk avoided per extra second travelled, relative to C0 (hazard-blind), paired by OD-pair
    index (both configs run on the identical sampled pairs). Uses `worst_edge_p` (the single
    riskiest edge on the chosen route) as the risk proxy -- the trace schema
    (`docs/CONTRACTS.md` section 3) does not carry a full per-edge exposure integral over the
    whole path, only this single worst-edge figure and the route's total duration; flagged here
    as the metric this trace schema can honestly support, not a full risk-integral efficiency.
    """
    assert len(baseline_traces) == len(config_traces)
    ratios = []
    for base, cfg in zip(baseline_traces, config_traces):
        if base is None or cfg is None:
            continue  # unreachable under one of the two configurations: no paired route
        risk_avoided = sc.worst_edge_p(base) - sc.worst_edge_p(cfg)
        extra_seconds = cfg["chosen"]["duration_s"] - base["chosen"]["duration_s"]
        if extra_seconds > 0:
            ratios.append(risk_avoided / extra_seconds)
    return {
        "n_pairs_with_positive_extra_time": len(ratios),
        "n_pairs_total": sum(
            1 for b, c in zip(baseline_traces, config_traces) if b is not None and c is not None
        ),
        "risk_avoided_per_extra_second_percentiles": sc._percentiles(
            ratios, [10, 50, 90]
        ),
        "risk_avoided_per_extra_second_mean": (
            sum(ratios) / len(ratios) if ratios else float("nan")
        ),
        "note": (
            "proxy metric: worst_edge_p delta / extra chosen-route seconds vs C0, paired by "
            "OD-pair index -- not a full route risk integral (unavailable from DecisionTrace's "
            "schema, docs/CONTRACTS.md section 3, which carries only the single worst edge per "
            "route, not a per-edge p breakdown for the whole chosen path)"
        ),
    }


def main() -> None:
    t32.ensure_cli_compiled()
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    traces_dir = RESULTS_DIR / "traces"
    traces_dir.mkdir(parents=True, exist_ok=True)
    figures_dir = RESULTS_DIR / "figures"
    figures_dir.mkdir(parents=True, exist_ok=True)

    hazard_classes = t32.load_hazard_classes()
    user_class_cfg = hazard_classes["user_classes"][USER_CLASS]
    base_z, base_lambda = user_class_cfg["z"], user_class_cfg["lambda"]

    graph = t32.load_graph_cli()
    adjacency = t32.build_adjacency(graph)
    main_pairs, sample_stats = t32.sample_od_pairs(
        graph["node_count"], adjacency, SEED, N_MAIN
    )
    sweep_pairs = main_pairs[
        :N_SWEEP
    ]  # identical prefix -- paired comparison, not a new sample

    scale_decision = {
        "n_main": N_MAIN,
        "n_first_subset": N_FIRST,
        "n_sweep_per_point": N_SWEEP,
        "n_sweep_grid_points": len(Z_GRID) * len(LAMBDA_GRID),
        "note": (
            "N_main = 1000 is the size docs/EVALUATION.md asked for. It became affordable because "
            "the router now has a route-batch mode (KNOWN_FLAWS F-20): one process parses the 47 MB "
            "graph once per configuration instead of once per pair. The 2026-09-18 run used 100 "
            "pairs and 25 per Pareto point. The first 100 pairs here are the same pairs (same seed, "
            "same sampler), so the N=100 subset is reported alongside for a like-for-like look."
        ),
    }

    t_start = time.monotonic()

    main_results: dict[str, dict] = {}
    first_results: dict[str, dict] = {}
    main_traces: dict[str, list[dict | None]] = {}
    config_metas: dict[str, dict] = {}
    with tempfile.TemporaryDirectory() as tmp:
        for config_name, kind, cz, clam in MAIN_CONFIGS:
            z = base_z if cz is None else cz
            lam = base_lambda if clam is None else clam
            traces, errors, meta = run_config(
                config_name, main_pairs, z, lam, Path(tmp) / config_name
            )
            main_traces[config_name] = traces
            config_metas[config_name] = meta
            main_results[config_name] = summarise_traces(config_name, traces, errors)
            first_results[config_name] = summarise_traces(
                config_name, traces[:N_FIRST], [e for e in errors if e["index"] < N_FIRST]
            )
            with open(traces_dir / f"{config_name}.ndjson", "w", encoding="utf-8") as f:
                f.writelines(
                    json.dumps(tr, separators=(",", ":")) + "\n"
                    for tr in traces
                    if tr is not None
                )
            print(
                f"{config_name}: {main_results[config_name]['n_traces']} routes, "
                f"{main_results[config_name]['n_disconnected']} disconnected",
                flush=True,
            )

    t_main_done = time.monotonic()

    exposure_efficiency = {
        cfg: exposure_reduction_efficiency(main_traces["C0"], main_traces[cfg])
        for cfg, _k, _z, _l in MAIN_CONFIGS
        if cfg != "C0"
    }

    # --- Pareto sweep (C3 only, per docs/EVALUATION.md's explicit instruction) ---
    frontier_points = []
    with tempfile.TemporaryDirectory() as tmp:
        for z in Z_GRID:
            for lam in LAMBDA_GRID:
                traces_idx, errors, _meta = run_config(
                    "C3", sweep_pairs, z, lam, Path(tmp) / f"z{z}_l{lam}"
                )
                traces = [tr for tr in traces_idx if tr is not None]
                n = len(traces)
                if n == 0:
                    continue
                detours = [sc.detour_ratio(t) for t in traces]
                high_risk = [
                    sc.high_risk_exposure(t, HIGH_RISK_THRESHOLD) for t in traces
                ]
                frontier_points.append(
                    {
                        "z": z,
                        "lambda": lam,
                        "n": n,
                        "n_errors": len(errors),
                        "median_detour_ratio": sc._percentiles(detours, [50])["p50"],
                        "p90_detour_ratio": sc._percentiles(detours, [90])["p90"],
                        "high_risk_exposure_rate": sum(high_risk) / n,
                    }
                )
    t_sweep_done = time.monotonic()

    # --- Figure 3: Pareto frontier ---
    fig, ax = plt.subplots(figsize=(7, 5))
    for lam in LAMBDA_GRID:
        pts = [p for p in frontier_points if p["lambda"] == lam]
        pts.sort(key=lambda p: p["z"])
        ax.plot(
            [p["median_detour_ratio"] for p in pts],
            [p["high_risk_exposure_rate"] for p in pts],
            marker="o",
            label=f"lambda={lam}",
        )
        for p in pts:
            ax.annotate(
                f"z={p['z']}",
                (p["median_detour_ratio"], p["high_risk_exposure_rate"]),
                fontsize=7,
            )
    ax.set_xlabel("median detour ratio (chosen / free-flow-optimal duration)")
    ax.set_ylabel(f"high-risk exposure rate (worst_edge_p > {HIGH_RISK_THRESHOLD})")
    ax.set_title(
        f"Study 1 -- C3 Pareto frontier: safety vs. detour (N={N_SWEEP}/point)\n"
        "(safety proxy: worst_edge_p, since depth_mm is null in this corpus -- see result.json)"
    )
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(figures_dir / "figure3_pareto_frontier.png", dpi=150)
    plt.close(fig)

    # --- Figure 3b: detour ratio distributions across main configs (skewed -- report the shape) ---
    fig, ax = plt.subplots(figsize=(7, 5))
    labels = [c[0] for c in MAIN_CONFIGS]
    data = [
        [sc.detour_ratio(tr) for tr in main_traces[c] if tr is not None] for c in labels
    ]
    ax.boxplot(data, tick_labels=labels, showfliers=True)
    ax.set_ylabel("detour ratio")
    ax.set_title(f"Study 1 -- detour ratio distribution by config (N={N_MAIN})")
    fig.tight_layout()
    fig.savefig(figures_dir / "figure3b_detour_ratio_distributions.png", dpi=150)
    plt.close(fig)

    t_end = time.monotonic()

    result = {
        "task": "T3.3 Study 1 -- route quality",
        "seed": SEED,
        "belief_model": "Beta posterior (ADR-015)",
        "user_class": USER_CLASS,
        "replay_clock": REPLAY_CLOCK,
        "scale_decision": scale_decision,
        "timing": {
            "main_configs_seconds": t_main_done - t_start,
            "pareto_sweep_seconds": t_sweep_done - t_main_done,
            "total_seconds": t_end - t_start,
        },
        "od_sampling_stats": sample_stats,
        "config_realisations": config_metas,
        "results_by_config": main_results,
        "results_by_config_first_100_pairs": first_results,
        "main_configs": [
            {"name": n, "kind": k, "z": z, "lambda": l} for n, k, z, l in MAIN_CONFIGS
        ],
        "exposure_reduction_efficiency_vs_c0": exposure_efficiency,
        "pareto_frontier_c3": {
            "z_grid": Z_GRID,
            "lambda_grid": LAMBDA_GRID,
            "n_per_point": N_SWEEP,
            "high_risk_threshold": HIGH_RISK_THRESHOLD,
            "points": frontier_points,
        },
        "event_split": _event_split_placeholder(N_MAIN),
        "router_build": os.environ.get("PULSE_ROUTER_BIN", "data/bin/pulse_router.exe (default)"),
        "corpus_limitations_carried_forward_from_t3_2": [
            (
                "depth_mm is null for every edge -- the literal chance-constraint hard-removal "
                "never fires for C0/C2/C3/C4/C-infinity; 'impassable-edge-hit rate' is reported "
                "as not_applicable for those configs, and C1's synthetic hard-block rate is "
                "reported separately and distinctly labelled."
            ),
            (
                "false-avoidance cost is not computable: zero negative-polarity observations "
                "exist in this corpus (all 6,132 records carry polarity=1)."
            ),
            (
                "single proxy timestamp (2015-12-02T00:00:00Z) for every observation -- oracle "
                "(C-infinity) degenerates to C3 in this snapshot; see config_realisations.Cinf."
            ),
            "event/monsoon-episode split is a documented single-fold no-op -- see event_split.",
        ],
        "reproduce_with": "python scripts/study1_route_quality.py",
    }
    with open(RESULTS_DIR / "result.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, default=str)

    print("=== Study 1: route quality ===")
    for cfg, r in main_results.items():
        print(
            f"{cfg}: n={r['n_traces']} median_detour={r['detour_ratio_percentiles']['p50']:.4f}"
        )
    print(f"Wrote {RESULTS_DIR / 'result.json'}")
    print(f"Wrote {figures_dir / 'figure3_pareto_frontier.png'}")
    print(f"Wrote {figures_dir / 'figure3b_detour_ratio_distributions.png'}")


if __name__ == "__main__":
    main()
