"""Shared infrastructure for Study 1 (route quality, T3.3) and Study 2 (calibration, T3.4).

**Reuses `scripts/t3_2_replay_engine.py` rather than duplicating it** (per this task's explicit
instruction): the corpus loader, hazard-config builder, query-time windowing, OD-pair sampler,
and CLI invocation all come from there unchanged. This module adds only what T3.2 deliberately
left out of scope: the C0-C4/oracle *configuration variants*, a tested Python replica of
`pulse_belief`'s pure belief-fusion arithmetic (used for scoring and for building the C1 variant
-- never for routing/search, see the note below), the Jøsang & Ismail (2002) Beta-reputation
baseline, and the Study 1/2 metric functions.

**Why a Python replica of `fuse`/`pessimistic` does not violate "never reimplement routing
logic in Python" (CLAUDE.md/task instructions):** `fuse()` (packages/pulse_belief/lib/src/
fusion.dart) and `pessimistic()` (pessimistic.dart) are closed-form, non-iterative arithmetic --
a log-odds sum with an exponential-decay/kernel weight, and a UCB-style square-root band. They
are not the routing algorithm (bidirectional Dijkstra + ALT), which this module never touches --
every Study 1 route-quality number in `study1_route_quality.py` still comes from invoking the
real compiled `pulse_router` CLI (`data/bin/pulse_router.exe`), exactly as T3.2 did. The replica
below exists only for (a) the ~5,775-edge, many-report-age-bucket calibration scoring Study 2
needs (thousands of scores; one CLI subprocess per score would cost hours for no routing
content, since scoring one edge's belief needs no graph search at all) and (b) deciding, in
Python, which edges cross a fixed probability threshold for the C1 variant below (§ C1). It is
verified for parity against `pulse_belief`'s own test vectors in
`scripts/tests/test_study_common.py::TestFusePyParity`, translated directly from
`packages/pulse_belief/test/fusion_test.dart` and `pessimistic_test.dart` -- not merely asserted
to match.
"""

from __future__ import annotations

import copy
import math
import sys
from dataclasses import replace
from datetime import datetime
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import t3_2_replay_engine as t32

ROOT = t32.ROOT

# --------------------------------------------------------------------------------------------
# Python replica of pulse_belief's pure arithmetic (fuse / pessimistic / kernel / sigmoid /
# logit) -- see this module's docstring for exactly what this is and is not used for.
# --------------------------------------------------------------------------------------------

KERNEL_BANDWIDTH_M = (
    75.0  # packages/pulse_belief/lib/src/kernel.dart SpatialKernel defaults
)
KERNEL_CUTOFF_M = 300.0


def sigmoid_py(x: float) -> float:
    return 1.0 / (1.0 + math.exp(-x))


def logit_py(p: float) -> float:
    if not (0.0 < p < 1.0):
        raise ValueError(f"logit is undefined outside (0, 1): got {p}")
    return math.log(p / (1.0 - p))


def kernel_py(distance_m: float) -> float:
    if not (distance_m >= 0):
        raise ValueError(f"distance_m must be non-negative: got {distance_m}")
    if distance_m > KERNEL_CUTOFF_M:
        return 0.0
    return math.exp(-distance_m / KERNEL_BANDWIDTH_M)


def fuse_py(
    observations: list[t32.ObsRecord],
    prior_logodds: float,
    at: datetime,
    decay_tau_seconds: float,
) -> dict:
    """Replica of `pulse_belief.fuse()`. Returns a dict with posterior_logodds, p_mean, n_eff,
    newest_observation_at, contributing_ids -- the same fields `EdgeBelief` carries.
    """
    if not (decay_tau_seconds > 0):
        raise ValueError("decay_tau_seconds must be positive")
    log_odds_shift = 0.0
    n_eff = 0.0
    newest: datetime | None = None
    contributing: list[str] = []
    for obs in observations:
        kappa = kernel_py(obs.distance_m)
        if not (kappa > 0):
            continue
        age_seconds = (at - obs.observed_at).total_seconds()
        if not (age_seconds >= 0):
            raise ValueError(
                f"observation {obs.id} observed after query time (future-dated): "
                f"observed_at={obs.observed_at}, at={at}"
            )
        weight = kappa * math.exp(-age_seconds / decay_tau_seconds)
        n_eff += weight
        log_odds_shift += obs.polarity * weight * logit_py(obs.source_reliability_hint)
        if newest is None or obs.observed_at > newest:
            newest = obs.observed_at
        contributing.append(obs.id)
    posterior_logodds = prior_logodds + log_odds_shift
    return {
        "prior_logodds": prior_logodds,
        "posterior_logodds": posterior_logodds,
        "p_mean": sigmoid_py(posterior_logodds),
        "n_eff": n_eff,
        "newest_observation_at": newest,
        "contributing_ids": contributing,
    }


def pessimistic_py(p_mean: float, n_eff: float, z: float) -> float:
    if not (0.0 <= p_mean <= 1.0):
        raise ValueError("p_mean must be in [0, 1]")
    if not (n_eff >= 0):
        raise ValueError("n_eff must be non-negative")
    if not (z >= 0):
        raise ValueError("z must be non-negative")
    band = z * math.sqrt(p_mean * (1 - p_mean) / (n_eff + 1))
    raw = p_mean + band
    return min(raw, 1.0)


# `ObsRecord` (t3_2_replay_engine) does not carry a resolved source_reliability -- the harness
# resolves alpha_c from `source_class` only at CLI-serialisation time (`to_cli_hazards_json`).
# `fuse_py` needs the resolved number, so this module attaches it via a tiny wrapper rather than
# changing T3.2's dataclass (do not touch T3.2's `ObsRecord` -- other code constructs it
# positionally).
class _ObsWithReliability:
    __slots__ = (
        "distance_m",
        "id",
        "observed_at",
        "polarity",
        "source_reliability_hint",
    )

    def __init__(self, base: t32.ObsRecord, alpha_by_source_class: dict[str, float]):
        self.id = base.id
        self.polarity = base.polarity
        self.distance_m = base.distance_m
        self.observed_at = base.observed_at
        self.source_reliability_hint = alpha_by_source_class[base.source_class]


def with_reliability(
    observations: list[t32.ObsRecord], alpha_by_source_class: dict[str, float]
) -> list[_ObsWithReliability]:
    return [_ObsWithReliability(o, alpha_by_source_class) for o in observations]


# --------------------------------------------------------------------------------------------
# Configuration variants (Study 1's C0-C4, C-infinity)
# --------------------------------------------------------------------------------------------

# C2 -- hand-tuned single global decay constant: documented as the plain corpus-wide mean of
# config/hazard_classes.yaml's seven per-class T_c_seconds values (7200, 5400, 900, 1800,
# 14400, 10800, 10800) = 7300s (rounded). Arbitrary-but-stated, exactly the T1.3
# PRIOR_ONLY_THRESHOLD precedent for "documented, not fitted."
C2_SHARED_TC_SECONDS = 7300.0

# C1 -- hard hazard avoidance, naive, no confidence. p_mean threshold above which an edge is
# hard-blocked. 0.5 is the natural "more likely than not" cut for a naive policy; documented,
# not fitted (paper-worthy sweep is Study 1's C3 Pareto frontier, not this baseline).
C1_P_MEAN_THRESHOLD = 0.5
C1_INJECTED_EPSILON = 1e-6  # forces the chance constraint whenever p_pessimistic > 0

# C4 -- fixed TTL (Waze-style). Observations older than this are dropped entirely rather than
# exponentially decayed. 6 hours: longer than debris/accident T_c, shorter than closure/flood
# T_c -- documented, not fitted, matching this task's instruction to pick a defensible constant.
C4_TTL_SECONDS = 6 * 3600.0
C4_NO_DECAY_TAU_SECONDS = (
    1e12  # within the TTL window, treat evidence as effectively undecayed
)


def make_c0_hazards_json() -> dict:
    """C0 -- shortest time, hazard-blind. Exact realisation, not an approximation:
    `cli_io.dart hazardInputFromJson` treats an edge absent from `hazards` as having *no*
    hazard config at all, and `query_orchestrator.dart planRoute`'s `hazardAwareCost` returns
    `edge.freeFlowSeconds` outright for such edges (`if (config == null) return
    edge.freeFlowSeconds;`) -- cost reduces to free-flow time on every edge, with no Python-side
    cost computation involved. Confirmed against packages/pulse_router/lib/src/
    query_orchestrator.dart:136-138.
    """
    return {"hazards": []}


def make_c2_hazard_classes(hazard_classes: dict) -> dict:
    """C2 -- hand-tuned single exponential decay. Deep-copies `hazard_classes.yaml`'s document
    and overrides every class's `T_c_seconds` to one shared constant, leaving severity/h_max/
    epsilon/source_reliability/user_classes untouched -- isolates the decay-shape axis exactly,
    the same axis C4 and Study 2's baselines vary.
    """
    out = copy.deepcopy(hazard_classes)
    for cls in out["classes"].values():
        cls["T_c_seconds"] = C2_SHARED_TC_SECONDS
    return out


def build_c1_injected_overrides(
    configs: dict[int, t32.EdgeHazardConfigBuild],
    windowed_obs_by_edge: dict[int, list[t32.ObsRecord]],
    alpha_by_source_class: dict[str, float],
    at: datetime,
    threshold: float = C1_P_MEAN_THRESHOLD,
) -> tuple[dict[int, float], dict[int, float], dict]:
    """C1 -- hard hazard avoidance, naive, no confidence.

    **Not cleanly expressible via existing CLI flags alone** -- flagged per this task's
    instruction. The CLI's only hard-removal mechanism is the depth-based chance constraint
    (`edge_cost.dart`'s `depthMm > hMaxMm && pPessimistic >= epsilon`), and this corpus's
    `depth_mm` is null for every edge (T3.2's already-flagged limitation) -- so no CLI flag
    combination makes any edge hard-block on probability alone.

    **Closest faithful approximation, mechanically realised as follows:** this function decides,
    in Python, which edges cross `threshold` on `p_mean` computed with `z=0` (so
    `p_pessimistic == p_mean` exactly -- `pessimistic()`'s own docstring/tests confirm the `z=0`
    case is exact, not approximate -- which is what "ignoring n_eff/confidence" means here: the
    UCB confidence-widening term is switched off, not approximated away). For edges crossing the
    threshold, the harness injects a synthetic `depth_mm` (`h_max_mm + 1`) and a near-zero
    `epsilon` into that edge's hazard config before it reaches the CLI -- using the CLI's own,
    real chance-constraint removal mechanism (`edge_cost.dart`, untouched) to enforce the hard
    block, rather than removing the edge from the graph in Python. Edges below threshold are
    left with `depth_mm=None` (delta=1, no chance-constraint check) and the harness additionally
    calls the CLI with `lambda=0` for this config, so their cost is exactly `free_flow_seconds`
    -- a pure binary block/no-block policy, no continuous risk-weighted soft cost, matching
    "naive" hard avoidance as distinct from C3's pessimistic plug-in.

    Returns `(depth_mm_overrides, epsilon_overrides, stats)` keyed by edge_id.
    """
    depth_overrides: dict[int, float] = {}
    epsilon_overrides: dict[int, float] = {}
    p_means: dict[int, float] = {}
    for edge_id, cfg in configs.items():
        obs = with_reliability(
            windowed_obs_by_edge.get(edge_id, []), alpha_by_source_class
        )
        belief = fuse_beta_py(obs, cfg.prior_logodds, at, cfg.decay_tau_seconds)
        p_mean = belief["p_mean"]
        p_means[edge_id] = p_mean
        if p_mean > threshold:
            depth_overrides[edge_id] = cfg.h_max_mm + 1.0
            epsilon_overrides[edge_id] = C1_INJECTED_EPSILON
    stats = {
        "threshold": threshold,
        "edges_scored": len(configs),
        "edges_hard_blocked": len(depth_overrides),
        "p_mean_distribution_percentiles": _percentiles(
            list(p_means.values()), [50, 90, 99]
        ),
    }
    return depth_overrides, epsilon_overrides, stats


def apply_fixed_ttl(
    configs: dict[int, t32.EdgeHazardConfigBuild],
    windowed_obs_by_edge: dict[int, list[t32.ObsRecord]],
    at: datetime,
    ttl_seconds: float = C4_TTL_SECONDS,
) -> tuple[dict[int, t32.EdgeHazardConfigBuild], dict[int, list[t32.ObsRecord]], dict]:
    """C4 -- fixed TTL (Waze-style). Drops any observation older than `ttl_seconds` at query
    time `at` entirely (a genuine pre-filter, not a decay-weight change), and overrides every
    edge's `decay_tau_seconds` to a very large constant so any observation that survives the TTL
    filter is treated as effectively undecayed within the window -- "fixed TTL" as a binary
    cutoff, structurally distinct from C2/C3's continuous exponential decay, realised with the
    existing `decay_tau_seconds` field plus a harness-side pre-filter (no CLI changes).
    """
    ttl_configs = {
        edge_id: replace(cfg, decay_tau_seconds=C4_NO_DECAY_TAU_SECONDS)
        for edge_id, cfg in configs.items()
    }
    dropped = 0
    kept = 0
    ttl_windowed: dict[int, list[t32.ObsRecord]] = {}
    for edge_id, obs_list in windowed_obs_by_edge.items():
        survivors = []
        for o in obs_list:
            age = (at - o.observed_at).total_seconds()
            if age <= ttl_seconds:
                survivors.append(o)
                kept += 1
            else:
                dropped += 1
        ttl_windowed[edge_id] = survivors
    stats = {
        "ttl_seconds": ttl_seconds,
        "observations_kept": kept,
        "observations_dropped": dropped,
    }
    return ttl_configs, ttl_windowed, stats


def skip_windowing(
    configs: dict[int, t32.EdgeHazardConfigBuild],
) -> dict[int, list[t32.ObsRecord]]:
    """C-infinity -- oracle with perfect hindsight. Skips `filter_observations_by_clock`
    entirely: every observation in the corpus reaches the CLI regardless of query time `at`.

    **Degenerates to C3 in this corpus snapshot -- flagged, not papered over.** T3.1's corpus
    carries exactly one proxy timestamp for every observation
    (`2015-12-02T00:00:00Z`, MANIFEST.md limitation 1) and this replay's query clock is pinned to
    that same instant (T3.2 precedent, `REPLAY_CLOCK`), so `filter_observations_by_clock` is
    already a no-op there: every observation already satisfies `observed_at <= at`. Skipping the
    filter therefore changes nothing about *which* observations reach the CLI in this run --
    oracle and C3 will produce byte-identical traces here. This is a real, corpus-driven
    degeneracy of the same kind as the single-event/no-monsoon-episode-split limitation this
    task calls out, not a harness bug: oracle only diverges from C3 once genuine future
    information exists at query time to leak, which requires multi-timestamp data this corpus
    does not have.
    """
    return {edge_id: list(cfg.observations) for edge_id, cfg in configs.items()}


def to_cli_hazards_json_with_overrides(
    configs: dict[int, t32.EdgeHazardConfigBuild],
    windowed_observations: dict[int, list[t32.ObsRecord]],
    alpha_by_source_class: dict[str, float],
    depth_mm_override: dict[int, float] | None = None,
    epsilon_override: dict[int, float] | None = None,
) -> dict:
    """Like `t3_2_replay_engine.to_cli_hazards_json`, plus optional per-edge `depth_mm`/
    `epsilon` overrides -- the mechanism `build_c1_injected_overrides` needs. Never mutates
    T3.2's own function; a parallel function so T3.2 stays untouched.
    """
    depth_mm_override = depth_mm_override or {}
    epsilon_override = epsilon_override or {}
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
                "epsilon": epsilon_override.get(edge_id, cfg.epsilon),
                "depth_mm": depth_mm_override.get(edge_id),
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
# Beta-posterior belief (ADR-015) -- replica of packages/pulse_belief/lib/src/beta_belief.dart.
# --------------------------------------------------------------------------------------------
# The router replaced the Wald index with a Beta posterior quantile (KNOWN_FLAWS F-01/F-12). The
# functions above (`fuse_py`, `pessimistic_py`) replicate the OLD model and are kept only so the
# 2026-09-18 result folders remain reproducible. Everything new uses the functions below.
#
# Checked against numbers produced by the Dart implementation itself:
# scripts/tests/fixtures/beta_golden.json (generated by packages/pulse_belief/tool/
# golden_vectors.dart) -- see tests/test_study_common.py::TestFuseBetaParity.

BETA_PRIOR_STRENGTH = 2.0  # n0, placeholder (ADR-015)
BETA_EVIDENCE_SCALE = 2.0  # s, placeholder (ADR-015)
BETA_REFERENCE_RELIABILITY = 0.97  # alpha_ref


def reliability_weight_py(alpha: float, reference: float = BETA_REFERENCE_RELIABILITY) -> float:
    """min(1, logit(alpha)/logit(reference)); 0 for alpha <= 0.5."""
    w = logit_py(alpha) / logit_py(reference)
    return 0.0 if w <= 0 else min(w, 1.0)


def fuse_beta_py(
    observations: list,
    prior_logodds: float,
    at: datetime,
    decay_tau_seconds: float,
    prior_strength: float = BETA_PRIOR_STRENGTH,
    evidence_scale: float = BETA_EVIDENCE_SCALE,
    reference_reliability: float = BETA_REFERENCE_RELIABILITY,
) -> dict:
    """Replica of `fuseBeta`. `observations` are `_ObsWithReliability`-like objects. Returns the
    Beta parameters, the mean, the net evidence |S| (called n_eff, as in the Dart `nEff`)."""
    if not (decay_tau_seconds > 0):
        raise ValueError("decay_tau_seconds must be positive")
    signed = 0.0
    newest: datetime | None = None
    contributing: list[str] = []
    for obs in observations:
        kappa = kernel_py(obs.distance_m)
        if not (kappa > 0):
            continue
        age_seconds = (at - obs.observed_at).total_seconds()
        if not (age_seconds >= 0):
            raise ValueError(
                f"observation {obs.id} observed after query time (future-dated): "
                f"observed_at={obs.observed_at}, at={at}"
            )
        weight = kappa * math.exp(-age_seconds / decay_tau_seconds)
        signed += obs.polarity * weight * reliability_weight_py(
            obs.source_reliability_hint, reference_reliability
        )
        if newest is None or obs.observed_at > newest:
            newest = obs.observed_at
        contributing.append(obs.id)
    p0 = min(max(sigmoid_py(prior_logodds), 1e-6), 1 - 1e-6)
    a = prior_strength * p0 + evidence_scale * max(signed, 0.0)
    b = prior_strength * (1 - p0) + evidence_scale * max(-signed, 0.0)
    return {
        "prior_logodds": prior_logodds,
        "alpha": a,
        "beta": b,
        "p_mean": a / (a + b),
        "n_eff": abs(signed),
        "net_evidence": signed,
        "newest_observation_at": newest,
        "contributing_ids": contributing,
    }


def pessimistic_beta_py(belief: dict, z: float) -> float:
    """Replica of `pessimisticBeta`: the Phi(z) upper quantile of the Beta, floored at the
    mean, capped at 1. z = 0 returns the mean. Uses SciPy for the quantile; the Dart code uses
    its own inverse incomplete beta (agreement is tested to 1e-6)."""
    from scipy.stats import beta as _beta
    from scipy.stats import norm as _norm

    if not (z >= 0 and math.isfinite(z)):
        raise ValueError("z must be finite and non-negative")
    mean = belief["p_mean"]
    if z == 0:
        return mean
    upper = float(_beta.ppf(float(_norm.cdf(z)), belief["alpha"], belief["beta"]))
    return min(max(mean, upper), 1.0)


# --------------------------------------------------------------------------------------------
# Jøsang & Ismail (2002) Beta reputation system with forgetting -- Study 2's mandatory baseline.
# --------------------------------------------------------------------------------------------

# [UNVERIFIED DETAIL] per CLAUDE.md section 7's citation discipline: this is "the standard
# documented version" of a Beta reputation system with a forgetting/decay factor on pseudo-
# counts (Jøsang, A. and Ismail, R., "The Beta Reputation System," 15th Bled Electronic Commerce
# Conference, 2002 -- widely summarised in trust-management surveys), reconstructed from the
# standard formulation (positive/negative evidence counts r/s, reputation score
# E[Beta(r+1, s+1)] = (r+1)/(r+s+2), a per-time-unit forgetting factor lambda_f applied to both
# counts). The original paper PDF has not been opened in this task -- flag, do not silently drop,
# per repo convention. Do not cite this as a verified reproduction in the paper without opening
# the primary source first.
BETA_FORGETTING_LAMBDA_PER_HOUR = (
    0.9  # a decay-per-hour constant; documented, not fitted
)
BETA_TIME_UNIT_SECONDS = 3600.0


def beta_reputation_p(
    observations: list[_ObsWithReliability],
    at: datetime,
    forgetting_lambda_per_hour: float = BETA_FORGETTING_LAMBDA_PER_HOUR,
) -> dict:
    """Beta-reputation-with-forgetting belief for one edge.

    Uses the same spatial kernel and source-reliability inputs as `fuse_py` (so the *only* axis
    that differs from our model is the decay mechanism: a per-hour forgetting factor on Beta
    pseudo-counts, instead of a per-hazard-class exponential on log-odds) -- this isolates
    exactly the comparison Study 2 needs, the same way C2/C4 isolate it for Study 1.

    `r`/`s` are forgetting-discounted, reliability- and kernel-weighted positive/negative
    evidence counts; the reputation score is the Beta(r+1, s+1) posterior mean.
    """
    r = 0.0
    s = 0.0
    for obs in observations:
        kappa = kernel_py(obs.distance_m)
        if not (kappa > 0):
            continue
        age_seconds = (at - obs.observed_at).total_seconds()
        if age_seconds < 0:
            continue  # future-dated; never reaches this function in practice (pre-windowed)
        age_hours = age_seconds / BETA_TIME_UNIT_SECONDS
        weight = (
            kappa
            * obs.source_reliability_hint
            * (forgetting_lambda_per_hour**age_hours)
        )
        if obs.polarity > 0:
            r += weight
        else:
            s += weight
    p = (r + 1.0) / (r + s + 2.0)
    return {"r": r, "s": s, "p_mean": p}


# --------------------------------------------------------------------------------------------
# Study 1 metrics
# --------------------------------------------------------------------------------------------


def _percentiles(values: list[float], pcts: list[int]) -> dict[str, float]:
    if not values:
        return {f"p{p}": float("nan") for p in pcts}
    xs = sorted(values)
    out = {}
    for p in pcts:
        if len(xs) == 1:
            out[f"p{p}"] = xs[0]
            continue
        k = (len(xs) - 1) * (p / 100.0)
        f = math.floor(k)
        c = math.ceil(k)
        if f == c:
            out[f"p{p}"] = xs[int(k)]
        else:
            out[f"p{p}"] = xs[f] + (xs[c] - xs[f]) * (k - f)
    return out


def detour_ratio(trace: dict) -> float:
    """chosen route's hazard-aware duration / the free-flow-optimal route's duration. The
    free-flow-optimal duration is `alternatives[0].duration_s` when the chosen and free-flow-
    optimal paths differ (query_orchestrator.dart always searches both; `alternatives` is only
    emitted when they diverge), else `chosen.free_flow_duration_s` (the chosen path already *is*
    the free-flow-optimal one, so its own free-flow time is that optimum).
    """
    chosen = trace["chosen"]
    if trace["alternatives"]:
        free_flow_optimal = trace["alternatives"][0]["duration_s"]
    else:
        free_flow_optimal = chosen["free_flow_duration_s"]
    if free_flow_optimal <= 0:
        return 1.0
    return chosen["duration_s"] / free_flow_optimal


def worst_edge_p(trace: dict) -> float:
    return trace["chosen"]["worst_edge_p"]


def hazard_time_penalty_seconds(trace: dict) -> float:
    return trace["chosen"]["hazard_time_penalty_s"]


def hard_block_triggered(trace: dict) -> bool:
    """Whether this query's alternative was rejected by the chance constraint -- the only
    metric variant where the literal "impassable-edge-hit" mechanism can fire in this corpus
    (C1's synthetic depth injection). Always `False` for C0/C2/C3/C4/C-infinity here (depth_mm
    is null for every real edge -- T3.2's already-flagged corpus limitation, restated in
    study1_route_quality.py's result manifest rather than silently reproduced).
    """
    for alt in trace["alternatives"]:
        if alt["rejected_because"] == "chance_constraint":
            return True
    return False


def high_risk_exposure(trace: dict, risk_threshold: float) -> bool:
    """Proxy safety-violation indicator for the Pareto frontier: whether the chosen route's
    worst edge still carries p_pessimistic above `risk_threshold`, i.e. hazard-aware costing
    was not enough to route the traveller away from a high-risk edge entirely (there was no
    lower-risk path available at any cost, or the risk was simply not high enough to detour
    around at this z/lambda). Distinct from `hard_block_triggered` -- see this module's Study 1
    docstring in study1_route_quality.py for why the literal chance-constraint metric is
    degenerate here.
    """
    return trace["chosen"]["worst_edge_p"] > risk_threshold


# --------------------------------------------------------------------------------------------
# Study 2 metrics: Brier/Murphy decomposition, adaptive ECE, log loss, AUROC
# --------------------------------------------------------------------------------------------


def brier_murphy_decomposition(
    probs: list[float], outcomes: list[int], n_bins: int = 10
) -> dict:
    """Brier score with Murphy (1973)'s reliability/resolution/uncertainty decomposition:
    `Brier = reliability - resolution + uncertainty`, using equal-width probability bins.
    """
    n = len(probs)
    if n == 0:
        raise ValueError("no scored samples")
    brier = sum((p - y) ** 2 for p, y in zip(probs, outcomes)) / n
    ybar = sum(outcomes) / n
    uncertainty = ybar * (1 - ybar)

    bins: list[list[tuple[float, int]]] = [[] for _ in range(n_bins)]
    for p, y in zip(probs, outcomes):
        idx = min(int(p * n_bins), n_bins - 1)
        bins[idx].append((p, y))

    reliability = 0.0
    resolution = 0.0
    for bucket in bins:
        if not bucket:
            continue
        n_k = len(bucket)
        p_bar_k = sum(p for p, _ in bucket) / n_k
        o_bar_k = sum(y for _, y in bucket) / n_k
        reliability += n_k * (p_bar_k - o_bar_k) ** 2
        resolution += n_k * (o_bar_k - ybar) ** 2
    reliability /= n
    resolution /= n

    return {
        "brier": brier,
        "reliability": reliability,
        "resolution": resolution,
        "uncertainty": uncertainty,
        "decomposition_check": reliability - resolution + uncertainty,
        "n_bins": n_bins,
        "n_samples": n,
    }


def adaptive_ece(probs: list[float], outcomes: list[int], n_bins: int = 10) -> float:
    """Adaptive (equal-frequency / quantile) expected calibration error -- bins by rank rather
    than by fixed probability width, so every bin carries roughly the same sample count even
    when predicted probabilities cluster (the usual case here: most edges have low p_mean).
    """
    n = len(probs)
    if n == 0:
        raise ValueError("no scored samples")
    order = sorted(range(n), key=lambda i: probs[i])
    bin_size = max(1, n // n_bins)
    ece = 0.0
    i = 0
    while i < n:
        j = min(i + bin_size, n)
        idxs = order[i:j]
        bucket_n = len(idxs)
        p_bar = sum(probs[k] for k in idxs) / bucket_n
        o_bar = sum(outcomes[k] for k in idxs) / bucket_n
        ece += (bucket_n / n) * abs(p_bar - o_bar)
        i = j
    return ece


def log_loss(probs: list[float], outcomes: list[int], eps: float = 1e-12) -> float:
    n = len(probs)
    if n == 0:
        raise ValueError("no scored samples")
    total = 0.0
    for p, y in zip(probs, outcomes):
        pc = min(max(p, eps), 1 - eps)
        total += -(y * math.log(pc) + (1 - y) * math.log(1 - pc))
    return total / n


def auroc(probs: list[float], outcomes: list[int]) -> float:
    """AUROC via the Mann-Whitney U / rank-sum identity (no sklearn/scipy dependency
    available in this environment -- confirmed: only numpy/matplotlib are installed).
    Handles ties with midranks. Reported separately from calibration metrics, per this task's
    explicit instruction not to conflate discrimination and calibration.
    """
    n = len(probs)
    pos = [i for i in range(n) if outcomes[i] == 1]
    neg = [i for i in range(n) if outcomes[i] == 0]
    if not pos or not neg:
        return float("nan")  # undefined: only one class present
    order = sorted(range(n), key=lambda i: probs[i])
    ranks = [0.0] * n
    i = 0
    while i < n:
        j = i
        while j + 1 < n and probs[order[j + 1]] == probs[order[i]]:
            j += 1
        avg_rank = (i + j) / 2.0 + 1.0  # 1-indexed midrank
        for k in range(i, j + 1):
            ranks[order[k]] = avg_rank
        i = j + 1
    rank_sum_pos = sum(ranks[i] for i in pos)
    n_pos, n_neg = len(pos), len(neg)
    u = rank_sum_pos - n_pos * (n_pos + 1) / 2.0
    return u / (n_pos * n_neg)
