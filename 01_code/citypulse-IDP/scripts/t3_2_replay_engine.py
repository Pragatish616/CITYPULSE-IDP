"""
T3.2 -- Deterministic replay engine (docs/IMPLEMENTATION_PLAN.md Phase 3).

**Scope, per the task card.** This is infrastructure, not Study 1/2 themselves: it feeds T3.1's
replay corpus (data/corpus/2026-09-17/) into the same AOT-compiled `pulse_router` CLI the app
runs, at real per-observation timestamps, with a fixed-seed OD sample -- and proves the pipeline
is deterministic. No Pareto sweep across C0-C4/oracle, no Brier/reliability/ECE/AUROC, no
Josang-Ismail baseline. Smoke scale: N=50 OD pairs, one representative user_class (commuter).
Those are Study 1 (T3.3) / Study 2 (T3.4)'s job, built on top of what this script proves works.

**Pipeline, in order:**
  1. Corpus loader -- observations.ndjson + edge_snap_index.json -> observations grouped by
     snapped edge_id (docs/CONTRACTS.md section 1 fields, plus the snap distance).
  2. Hazard config builder -- per edge, the CLI's EdgeHazardConfig fields
     (packages/pulse_router/lib/src/cli_io.dart's hazardInputFromJson doc comment), from T1.3's
     prior_logodds and config/hazard_classes.yaml's per-class constants. See
     `choose_dominant_hazard_class` below for the one-hazard-class-per-edge policy this forces,
     and `PRIOR_ONLY_THRESHOLD` for which prior-only edges get carried.
  3. Query-time windowing -- `filter_observations_by_clock` drops any observation with
     `observed_at > at` before it reaches the CLI. This is what makes it a *replay*: the CLI's
     own `pulse_belief.fuse()` would otherwise throw (it rejects future-dated observations,
     packages/pulse_belief/lib/src/fusion.dart) rather than silently leak them, so a windowing
     bug here is loud, not silent -- but the filtering is still done explicitly and unit-tested,
     not left to that as a safety net.
  4. OD-pair sampling -- N reachable (source, target) pairs from the real CSR graph, via
     `random.Random(seed)` and one BFS reachability check per candidate source (no CLI-based
     probing needed: reachability is a directed-graph topology question the graph itself
     answers, and doing it in Python avoids N wasted CLI invocations against unreachable pairs).
  5. CLI invocation -- one call per OD pair, same shared windowed-observations file (query time
     is fixed for this smoke run, so the file does not change across pairs).
  6. Determinism check -- run steps 3-5 twice, byte-compare every trace.
  7. Output -- data/results/<date>-t32-replay-engine/result.json + traces/traces.ndjson.

Usage: .venv/Scripts/python.exe scripts/t3_2_replay_engine.py
"""

from __future__ import annotations

import hashlib
import json
import os
import random
import subprocess
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent

CORPUS_DIR = ROOT / "data" / "corpus" / "2026-09-17"
GRAPH_DIR = ROOT / "data" / "graph" / "2026-09-14"
HAZARD_CLASSES_PATH = ROOT / "config" / "hazard_classes.yaml"
# PULSE_ROUTER_BIN lets a study pin a specific compiled CLI (a dated build under data/bin/<date>/)
# without overwriting the binary an earlier study was run with.
CLI_BINARY = (
    Path(os.environ["PULSE_ROUTER_BIN"])
    if os.environ.get("PULSE_ROUTER_BIN")
    else ROOT / "data" / "bin" / "pulse_router.exe"
)
CLI_SOURCE = ROOT / "packages" / "pulse_router" / "bin" / "pulse_router.dart"
CLI_CWD = ROOT / "packages" / "pulse_router"

RESULTS_DATE = "2026-09-17"
RESULTS_DIR = ROOT / "data" / "results" / f"{RESULTS_DATE}-t32-replay-engine"

SEED = 20260917  # pinned, recorded in result.json (CLAUDE.md section 7)
N_OD_PAIRS = 50  # smoke scale -- Study 1's N=1000 is out of scope here
USER_CLASS = "commuter"  # one representative config; sweeping is T3.3/T3.4's job

# The corpus-wide proxy observed_at (data/corpus/2026-09-17/MANIFEST.md) -- every observation
# in this corpus carries exactly this timestamp, a known, already-flagged data limitation, not
# a harness bug. Query clock is pinned to it so the smoke run actually sees the corpus's hazard
# evidence (an "at" strictly before this would window out every single observation).
REPLAY_CLOCK = "2015-12-02T00:00:00Z"

# Static-prior inclusion threshold for edges with zero real observations
# (config/hazard_classes.yaml has no per-class prior; T1.3's ell_0 is a single generic
# flood-hazard-zone-derived prior). "Non-trivial" is defined here as the top two of the five
# GCC CATEGORY risk bands T1.3 used (category_to_probability: High=0.25, Very High=0.45) --
# a documented, arbitrary-but-stated choice, not a fitted one. Carrying every edge above the
# lowest bands (>=105k edges) would bloat the hazards file for no benefit at smoke scale.
PRIOR_ONLY_THRESHOLD = 0.25
PRIOR_ONLY_HAZARD_CLASS = "flood"


# --------------------------------------------------------------------------------------------
# 1. Corpus loading
# --------------------------------------------------------------------------------------------


@dataclass
class ObsRecord:
    id: str
    hazard_class: str
    polarity: int
    observed_at: datetime
    source_class: str
    distance_m: float


def parse_iso8601(s: str) -> datetime:
    """RFC 3339 'Z' timestamps -> aware UTC datetime. Never naive -- a naive/aware mix is a
    classic silent-comparison bug when this feeds `observed_at <= at` filtering below.
    """
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def build_reverse_twin_index(graph_edges: list[dict]) -> dict[int, list[int]]:
    """edge_id -> edge_ids of the same street in the opposite direction.

    A two-way street is two directed edges (u->v and v->u, see pulse_router's
    csr_graph.dart), and T3.1 snapped each report to ONE of them. KNOWN_FLAWS F-02: of 5,775
    observed edges, 5,177 have a reverse twin and only 2 of those twins carried the evidence, so
    a flooded two-way street was penalised in one direction only. This index lets the loader
    attach each observation to both. One-way streets have no twin and are untouched.
    """
    by_pair: dict[tuple[int, int], list[int]] = defaultdict(list)
    for e in graph_edges:
        by_pair[(e["from"], e["to"])].append(e["edge_id"])
    twins: dict[int, list[int]] = {}
    for (u, v), ids in by_pair.items():
        if u == v:
            continue
        reverse = by_pair.get((v, u))
        if reverse:
            for edge_id in ids:
                twins[edge_id] = list(reverse)
    return twins


def load_corpus(
    obs_path: Path = CORPUS_DIR / "observations.ndjson",
    snap_path: Path = CORPUS_DIR / "edge_snap_index.json",
    reverse_twins: dict[int, list[int]] | None = None,
) -> dict[int, list[ObsRecord]]:
    """Loads T3.1's replay corpus and groups by snapped edge_id.

    Returns *all* observations per edge, unfiltered by hazard_class or query time -- those are
    separate, later steps (`choose_dominant_hazard_class`, `filter_observations_by_clock`).

    With `reverse_twins=None` (the default) each observation stays on the single edge it was
    snapped to -- the pre-fix behaviour, kept so the 2026-09-17/18 result folders remain
    reproducible. Pass `build_reverse_twin_index(...)` (or call `load_corpus_both_directions`)
    to attach each observation to the opposite direction of a two-way street as well (F-02).
    The twin gets the same snap distance: the two directed edges lie on the same centreline.
    """
    with open(obs_path, encoding="utf-8") as f:
        obs_by_id = {}
        for line in f:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            obs_by_id[rec["id"]] = rec

    with open(snap_path, encoding="utf-8") as f:
        snaps = json.load(f)

    by_edge: dict[int, list[ObsRecord]] = defaultdict(list)
    missing = 0
    for snap in snaps:
        obs = obs_by_id.get(snap["observation_id"])
        if obs is None:
            missing += 1
            continue
        by_edge[snap["edge_id"]].append(
            ObsRecord(
                id=obs["id"],
                hazard_class=obs["hazard_class"],
                polarity=obs["polarity"],
                observed_at=parse_iso8601(obs["observed_at"]),
                source_class=obs["source_class"],
                distance_m=float(snap["snap_distance_m"]),
            )
        )
    if missing:
        raise ValueError(
            f"{missing} edge_snap_index.json entries referenced an observation_id "
            "absent from observations.ndjson -- corpus/index are out of sync."
        )
    if reverse_twins:
        for edge_id, records in list(by_edge.items()):
            for twin_id in reverse_twins.get(edge_id, ()):
                present = {r.id for r in by_edge.get(twin_id, ())}
                for r in records:
                    if r.id not in present:
                        by_edge[twin_id].append(r)
                        present.add(r.id)
    return dict(by_edge)


_TWIN_INDEX_CACHE: dict[Path, dict[int, list[int]]] = {}


def load_corpus_both_directions(
    obs_path: Path = CORPUS_DIR / "observations.ndjson",
    snap_path: Path = CORPUS_DIR / "edge_snap_index.json",
    graph_path: Path = GRAPH_DIR / "chennai_graph_cli.json",
) -> dict[int, list[ObsRecord]]:
    """`load_corpus` with every observation on both directions of a two-way street (F-02).

    This is the loader new studies must use. The twin index is built once per graph file and
    cached for the process.
    """
    if graph_path not in _TWIN_INDEX_CACHE:
        with open(graph_path, encoding="utf-8") as f:
            graph_doc = json.load(f)
        _TWIN_INDEX_CACHE[graph_path] = build_reverse_twin_index(graph_doc["edges"])
    return load_corpus(obs_path, snap_path, reverse_twins=_TWIN_INDEX_CACHE[graph_path])


# --------------------------------------------------------------------------------------------
# 2. Hazard config builder
# --------------------------------------------------------------------------------------------


def load_hazard_classes(path: Path = HAZARD_CLASSES_PATH) -> dict:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_prior(path: Path = GRAPH_DIR / "chennai_prior_ell0.json") -> dict[int, dict]:
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    return {e["edge_id"]: e for e in doc["edges"]}


@dataclass
class EdgeHazardConfigBuild:
    edge_id: int
    hazard_class: str
    prior_logodds: float
    decay_tau_seconds: float
    severity: float
    h_max_mm: float
    epsilon: float
    observations: list[ObsRecord]  # dominant class only, unwindowed


def choose_dominant_hazard_class(
    records: list[ObsRecord], severity_by_class: dict[str, float]
) -> tuple[str, list[ObsRecord], list[ObsRecord]]:
    """The CLI's EdgeHazardConfig carries exactly one hazard_class per edge (cli_io.dart:
    'hazards' is a flat per-edge list, one entry each) -- it does not support fusing two
    hazard classes on the same edge. Where an edge in this corpus has observations of more
    than one class (124 of 5775 edges, both flood and waterlogging -- verified against this
    corpus snapshot), this is a genuine information loss the CLI format forces, not something
    to silently paper over.

    Policy (documented, not hidden): the class with the most observations on that edge wins;
    ties broken by higher configured `severity` (the more cautious characterization, in
    keeping with this project's whole pessimism-under-uncertainty design stance), then by
    class name for full determinism. Every observation of the losing class is dropped from
    this edge's hazard config entirely for this smoke task -- counted and reported, never
    silently discarded.
    """
    counts: dict[str, int] = defaultdict(int)
    for r in records:
        counts[r.hazard_class] += 1
    dominant = min(
        counts.keys(),
        key=lambda c: (-counts[c], -severity_by_class.get(c, 0.0), c),
    )
    kept = [r for r in records if r.hazard_class == dominant]
    dropped = [r for r in records if r.hazard_class != dominant]
    return dominant, kept, dropped


def build_hazard_configs(
    obs_by_edge: dict[int, list[ObsRecord]],
    prior_by_edge: dict[int, dict],
    hazard_classes: dict,
) -> tuple[dict[int, EdgeHazardConfigBuild], dict]:
    """Builds one EdgeHazardConfig per edge that has >=1 observation OR a non-trivial static
    prior (PRIOR_ONLY_THRESHOLD). Returns the configs plus a stats dict for result.json.
    """
    classes_cfg = hazard_classes["classes"]
    severity_by_class = {k: v["severity"] for k, v in classes_cfg.items()}

    configs: dict[int, EdgeHazardConfigBuild] = {}
    multi_class_edges = 0
    dropped_obs_total = 0

    for edge_id, records in obs_by_edge.items():
        dominant, kept, dropped = choose_dominant_hazard_class(
            records, severity_by_class
        )
        if dropped:
            multi_class_edges += 1
            dropped_obs_total += len(dropped)
        cls_cfg = classes_cfg[dominant]
        prior_entry = prior_by_edge.get(edge_id)
        prior_logodds = prior_entry["prior_logodds"] if prior_entry is not None else 0.0
        configs[edge_id] = EdgeHazardConfigBuild(
            edge_id=edge_id,
            hazard_class=dominant,
            prior_logodds=prior_logodds,
            decay_tau_seconds=float(cls_cfg["T_c_seconds"]),
            severity=float(cls_cfg["severity"]),
            h_max_mm=float(cls_cfg["h_max_mm"]),
            epsilon=float(cls_cfg["epsilon"]),
            observations=kept,
        )

    prior_only_count = 0
    prior_cls_cfg = classes_cfg[PRIOR_ONLY_HAZARD_CLASS]
    for edge_id, prior_entry in prior_by_edge.items():
        if edge_id in configs:
            continue
        if prior_entry["prior_p"] < PRIOR_ONLY_THRESHOLD:
            continue
        configs[edge_id] = EdgeHazardConfigBuild(
            edge_id=edge_id,
            hazard_class=PRIOR_ONLY_HAZARD_CLASS,
            prior_logodds=prior_entry["prior_logodds"],
            decay_tau_seconds=float(prior_cls_cfg["T_c_seconds"]),
            severity=float(prior_cls_cfg["severity"]),
            h_max_mm=float(prior_cls_cfg["h_max_mm"]),
            epsilon=float(prior_cls_cfg["epsilon"]),
            observations=[],
        )
        prior_only_count += 1

    stats = {
        "edges_with_real_observations": len(obs_by_edge),
        "edges_multi_hazard_class_conflict": multi_class_edges,
        "observations_dropped_minority_class": dropped_obs_total,
        "edges_prior_only_added": prior_only_count,
        "prior_only_threshold_prior_p": PRIOR_ONLY_THRESHOLD,
        "total_edges_with_hazard_config": len(configs),
        "total_edges_in_graph": len(prior_by_edge),
        "note_depth_mm": (
            "depth_mm is null for every edge in this corpus (T3.1 MANIFEST.md limitation 2 -- "
            "no source KML carries measured depth). packages/pulse_router/lib/src/edge_cost.dart "
            "only evaluates the hard chance constraint when depthMm is non-null, so it never "
            "fires in this replay -- edges are only ever cost-penalised via p-tilde, never "
            "removed outright. This is a real corpus limitation, not a harness bug; flagged per "
            "CLAUDE.md section 8.4 rather than silently working around it."
        ),
    }
    return configs, stats


# --------------------------------------------------------------------------------------------
# 3. Query-time windowing (pure function -- unit-tested separately)
# --------------------------------------------------------------------------------------------


def filter_observations_by_clock(
    configs: dict[int, EdgeHazardConfigBuild], at: datetime
) -> dict[int, list[ObsRecord]]:
    """The replay-correctness function. Returns, per edge, only the observations with
    `observed_at <= at` -- what the system would actually have known at that moment. An
    observation with `observed_at > at` must never reach the CLI: `pulse_belief.fuse()` throws
    on exactly that case (a future-dated observation), so a bug here would fail loudly on the
    very first offending query rather than silently leaking future data -- but this function is
    still the explicit, tested guard, not a reliance on that as a safety net.
    """
    out: dict[int, list[ObsRecord]] = {}
    for edge_id, cfg in configs.items():
        out[edge_id] = [r for r in cfg.observations if r.observed_at <= at]
    return out


def to_cli_hazards_json(
    configs: dict[int, EdgeHazardConfigBuild],
    windowed_observations: dict[int, list[ObsRecord]],
    alpha_by_source_class: dict[str, float],
) -> dict:
    """Builds the CLI-only 'hazards' JSON document (cli_io.dart's hazardInputFromJson doc
    comment). `source_reliability` is alpha_c straight from config/hazard_classes.yaml's
    `source_reliability` map -- the CLI/pulse_belief.WeightedObservation field doc comment
    ('already resolved by the caller') confirms this is the raw alpha_c value, not a derived
    quantity.
    """
    hazards = []
    for edge_id in sorted(configs.keys()):
        cfg = configs[edge_id]
        obs_list = windowed_observations.get(edge_id, [])
        hazards.append(
            {
                "edge_id": edge_id,
                "hazard_class": cfg.hazard_class,
                "prior_logodds": cfg.prior_logodds,
                "decay_tau_seconds": cfg.decay_tau_seconds,
                "severity": cfg.severity,
                "h_max_mm": cfg.h_max_mm,
                "epsilon": cfg.epsilon,
                "depth_mm": None,
                "stale_after_seconds": None,
                "observations": [
                    {
                        "id": r.id,
                        "polarity": r.polarity,
                        "distance_m": r.distance_m,
                        "observed_at": r.observed_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "source_reliability": alpha_by_source_class[r.source_class],
                        "source_class": r.source_class,
                    }
                    for r in obs_list
                ],
            }
        )
    return {"hazards": hazards}


# --------------------------------------------------------------------------------------------
# 4. OD-pair sampling
# --------------------------------------------------------------------------------------------


def load_graph_cli(path: Path = GRAPH_DIR / "chennai_graph_cli.json") -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build_adjacency(graph: dict) -> dict[int, list[int]]:
    adj: dict[int, list[int]] = defaultdict(list)
    for e in graph["edges"]:
        adj[e["from"]].append(e["to"])
    return dict(adj)


def bfs_reachable(adjacency: dict[int, list[int]], source: int) -> set[int]:
    seen = {source}
    q = deque([source])
    while q:
        u = q.popleft()
        for v in adjacency.get(u, ()):
            if v not in seen:
                seen.add(v)
                q.append(v)
    return seen


def sample_od_pairs(
    node_count: int,
    adjacency: dict[int, list[int]],
    seed: int,
    n: int,
    max_attempts: int = 10_000,
) -> tuple[list[tuple[int, int]], dict]:
    """Samples n reachable, distinct (source, target) pairs with random.Random(seed). A
    candidate source with no reachable node other than itself (dead end / isolated node) is
    resampled, not treated as a failure -- the graph legitimately has some of these (T1.3's
    directed edge splitting can leave dangling stub nodes at the OSM extract boundary).
    """
    rng = random.Random(seed)
    reach_cache: dict[int, set[int]] = {}
    pairs: list[tuple[int, int]] = []
    seen_pairs: set[tuple[int, int]] = set()
    attempts = 0
    dead_end_sources = 0
    while len(pairs) < n and attempts < max_attempts:
        attempts += 1
        source = rng.randrange(node_count)
        if source not in reach_cache:
            reach_cache[source] = bfs_reachable(adjacency, source)
        reachable = reach_cache[source]
        candidates = reachable - {source}
        if not candidates:
            dead_end_sources += 1
            continue
        target = rng.choice(sorted(candidates))
        if (source, target) in seen_pairs:
            continue
        seen_pairs.add((source, target))
        pairs.append((source, target))
    stats = {
        "requested": n,
        "sampled": len(pairs),
        "attempts": attempts,
        "dead_end_source_draws": dead_end_sources,
    }
    return pairs, stats


# --------------------------------------------------------------------------------------------
# 5. CLI invocation
# --------------------------------------------------------------------------------------------


def invoke_cli(
    cli_binary: Path,
    graph_path: Path,
    observations_path: Path,
    source: int,
    target: int,
    at_iso: str,
    user_class: str,
    z: float,
    lam: float,
    query_id: str,
) -> tuple[int, str, str]:
    result = subprocess.run(
        [
            str(cli_binary),
            "route",
            "--graph",
            str(graph_path),
            "--observations",
            str(observations_path),
            "--source",
            str(source),
            "--target",
            str(target),
            "--at",
            at_iso,
            "--user-class",
            user_class,
            "--z",
            str(z),
            "--lambda",
            str(lam),
            "--query-id",
            query_id,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode, result.stdout, result.stderr


def invoke_cli_batch(
    cli_binary: Path,
    graph_path: Path,
    observations_path: Path,
    pairs: list[tuple[int, int]],
    at_iso: str,
    user_class: str,
    z: float,
    lam: float,
    query_id_prefix: str,
    work_dir: Path,
) -> tuple[list[dict | None], list[dict]]:
    """One `route-batch` process for many pairs (KNOWN_FLAWS F-20). Returns
    `(traces_by_index, errors)`: `traces_by_index[i]` is the DecisionTrace dict for pairs[i], or
    None where the router reported an error line (unreachable pair / bad node); `errors` lists
    those error objects. Index alignment lets callers pair results across configurations even when
    one configuration (e.g. a hard block) disconnects a pair that another can route."""
    work_dir.mkdir(parents=True, exist_ok=True)
    pairs_file = work_dir / f"pairs-{query_id_prefix}.txt"
    pairs_file.write_text("".join(f"{s} {t}\n" for s, t in pairs), encoding="utf-8")
    result = subprocess.run(
        [
            str(cli_binary),
            "route-batch",
            "--graph",
            str(graph_path),
            "--observations",
            str(observations_path),
            "--pairs",
            str(pairs_file),
            "--at",
            at_iso,
            "--user-class",
            user_class,
            "--z",
            str(z),
            "--lambda",
            str(lam),
            "--query-id-prefix",
            query_id_prefix,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"route-batch failed ({result.returncode}): {result.stderr[:500]}")
    traces: list[dict | None] = [None] * len(pairs)
    errors: list[dict] = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        obj = json.loads(line)
        if "error" in obj:
            errors.append(obj)
        else:
            idx = int(obj["query_id"].rsplit("-", 1)[1])
            traces[idx] = obj
    return traces, errors


# --------------------------------------------------------------------------------------------
# 6. Full pipeline (one run)
# --------------------------------------------------------------------------------------------


@dataclass
class RunResult:
    traces: list[str]  # raw stdout JSON text, one per OD pair, in pair order
    errors: list[dict]  # any non-zero-exit invocations, with full context


def run_pipeline(
    seed: int,
    n: int,
    at_iso: str,
    user_class: str,
    z: float,
    lam: float,
    work_dir: Path,
) -> tuple[RunResult, dict]:
    hazard_classes = load_hazard_classes()
    alpha_by_source_class = hazard_classes["source_reliability"]

    obs_by_edge = load_corpus_both_directions()
    prior_by_edge = load_prior()
    configs, hazard_stats = build_hazard_configs(
        obs_by_edge, prior_by_edge, hazard_classes
    )

    at = parse_iso8601(at_iso)
    windowed = filter_observations_by_clock(configs, at)
    hazards_json = to_cli_hazards_json(configs, windowed, alpha_by_source_class)

    work_dir.mkdir(parents=True, exist_ok=True)
    observations_path = work_dir / "hazards.json"
    with open(observations_path, "w", encoding="utf-8") as f:
        json.dump(hazards_json, f)

    graph = load_graph_cli()
    adjacency = build_adjacency(graph)
    pairs, sample_stats = sample_od_pairs(graph["node_count"], adjacency, seed, n)

    traces: list[str] = []
    errors: list[dict] = []
    for i, (source, target) in enumerate(pairs):
        query_id = f"t32-{seed}-{i:04d}"
        code, stdout, stderr = invoke_cli(
            CLI_BINARY,
            GRAPH_DIR / "chennai_graph_cli.json",
            observations_path,
            source,
            target,
            at_iso,
            user_class,
            z,
            lam,
            query_id,
        )
        if code != 0:
            errors.append(
                {
                    "index": i,
                    "source": source,
                    "target": target,
                    "exit_code": code,
                    "stderr": stderr.strip(),
                }
            )
        else:
            traces.append(stdout.strip())

    run_stats = {
        "hazard_config": hazard_stats,
        "od_sampling": sample_stats,
        "cli_errors": errors,
    }
    return RunResult(traces=traces, errors=errors), run_stats


def hash_traces(traces: list[str]) -> str:
    h = hashlib.sha256()
    for t in traces:
        h.update(t.encode("utf-8"))
        h.update(b"\n")
    return h.hexdigest()


# --------------------------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------------------------


def ensure_cli_compiled() -> None:
    if CLI_BINARY.exists():
        return
    CLI_BINARY.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "dart",
            "compile",
            "exe",
            str(CLI_SOURCE.relative_to(CLI_CWD)),
            "-o",
            str(CLI_BINARY),
        ],
        cwd=str(CLI_CWD),
        check=True,
    )


def main() -> None:
    ensure_cli_compiled()

    user_classes_cfg = load_hazard_classes()["user_classes"]
    z = user_classes_cfg[USER_CLASS]["z"]
    lam = user_classes_cfg[USER_CLASS]["lambda"]

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    traces_dir = RESULTS_DIR / "traces"
    traces_dir.mkdir(parents=True, exist_ok=True)

    import tempfile

    t0 = datetime.now(timezone.utc)
    with tempfile.TemporaryDirectory() as tmp:
        run_a, stats_a = run_pipeline(
            SEED, N_OD_PAIRS, REPLAY_CLOCK, USER_CLASS, z, lam, Path(tmp) / "run_a"
        )
    t1 = datetime.now(timezone.utc)

    with tempfile.TemporaryDirectory() as tmp:
        run_b, _stats_b = run_pipeline(
            SEED, N_OD_PAIRS, REPLAY_CLOCK, USER_CLASS, z, lam, Path(tmp) / "run_b"
        )
    t2 = datetime.now(timezone.utc)

    hash_a = hash_traces(run_a.traces)
    hash_b = hash_traces(run_b.traces)
    byte_identical = run_a.traces == run_b.traces
    determinism_pass = (
        byte_identical and hash_a == hash_b and not run_a.errors and not run_b.errors
    )

    # Canonical output: run A's traces, one compact JSON object per line (true NDJSON --
    # the CLI's own stdout is pretty-printed, so each trace is re-serialised compact here).
    traces_ndjson_path = traces_dir / "traces.ndjson"
    with open(traces_ndjson_path, "w", encoding="utf-8") as f:
        f.writelines(
            json.dumps(json.loads(t), separators=(",", ":")) + "\n"
            for t in run_a.traces
        )

    result = {
        "task": "T3.2 deterministic replay engine (smoke scale)",
        "seed": SEED,
        "n_od_pairs_requested": N_OD_PAIRS,
        "n_od_pairs_sampled": stats_a["od_sampling"]["sampled"],
        "user_class": USER_CLASS,
        "z": z,
        "lambda": lam,
        "replay_clock": REPLAY_CLOCK,
        "determinism_check": {
            "pass": determinism_pass,
            "byte_identical_trace_lists": byte_identical,
            "sha256_run_a": hash_a,
            "sha256_run_b": hash_b,
            "n_traces_run_a": len(run_a.traces),
            "n_traces_run_b": len(run_b.traces),
            "n_cli_errors_run_a": len(run_a.errors),
            "n_cli_errors_run_b": len(run_b.errors),
        },
        "timing": {
            "run_a_seconds": (t1 - t0).total_seconds(),
            "run_b_seconds": (t2 - t1).total_seconds(),
        },
        "hazard_config_stats": stats_a["hazard_config"],
        "od_sampling_stats": stats_a["od_sampling"],
        "cli_errors_run_a": run_a.errors,
        "deferred_to_study_1_2": [
            "N=1000 OD pairs (Study 1 scale) -- this smoke run uses N=50 only.",
            (
                "Configurations C0-C4 and the oracle C-infinity -- this run uses one fixed "
                "config (commuter, z=0.0, lambda=0.3) only; no sweep."
            ),
            (
                "Route-quality metrics (impassable-edge-hit rate, detour ratio distribution, "
                "exposure-reduction efficiency, false-avoidance cost) -- not computed here."
            ),
            (
                "Calibration metrics (Brier/Murphy decomposition, stratified reliability "
                "diagrams, adaptive ECE, AUROC) and the Fixed-TTL / hand-tuned-exponential / "
                "Josang-Ismail-with-forgetting baselines -- not computed here."
            ),
            (
                "Event/monsoon-episode-based splitting -- not applicable yet: this corpus is "
                "a single event (2015 Chennai floods) with a single proxy timestamp, so there "
                "is no monsoon-episode axis to split on until a second event's data exists."
            ),
        ],
        "reproduce_with": "python scripts/t3_2_replay_engine.py",
    }
    with open(RESULTS_DIR / "result.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print("=== T3.2 replay engine ===")
    print(f"OD pairs sampled: {stats_a['od_sampling']['sampled']}/{N_OD_PAIRS}")
    print(f"Determinism check: {'PASS' if determinism_pass else 'FAIL'}")
    print(f"  sha256 run A: {hash_a}")
    print(f"  sha256 run B: {hash_b}")
    print(
        f"Hazard configs built: {stats_a['hazard_config']['total_edges_with_hazard_config']}"
    )
    print(
        f"  from real observations: {stats_a['hazard_config']['edges_with_real_observations']}"
    )
    print(f"  prior-only added: {stats_a['hazard_config']['edges_prior_only_added']}")
    print(f"Wrote {RESULTS_DIR / 'result.json'}")
    print(f"Wrote {traces_ndjson_path}")


if __name__ == "__main__":
    main()
