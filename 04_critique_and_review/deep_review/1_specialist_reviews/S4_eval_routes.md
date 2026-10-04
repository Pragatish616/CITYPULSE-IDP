# S4: Evaluation validity of the route-quality study (Study 1 and the independent re-analysis)

Reviewer S4. Scope: Study 1 route quality (paper Sections V–VII, Table I, Fig. 2, `numbers.tex`, `sweep_table.tex`), the team's harness (`study1_route_quality.py`, `study_common.py`, `t3_2_replay_engine.py`), the Dart cost (`edge_cost.dart`, `query_orchestrator.dart`), and the re-analysis (`reanalyze.py`, `reanalysis_result.json`, `extra.json`). Out of scope: novelty, the calibration study, business.

**Computations.** I ran everything here myself on the read-only data with numpy and scipy. I reused `reanalyze.py`'s belief rebuild (`fuse_py` on `build_hazard_configs`), its min-weight-per-(u,v) graph build and its SciPy Dijkstra. Scripts and raw outputs are in the scratchpad: `/tmp/claude-0/-home-claude/aa10ead1-266e-5d6e-9869-ab7db0329f5f/scratchpad/s4/` (`s4_setup.py`, `s4_analysis.py`, `s4_analysis2.py`, `s4_analysis3.py`, and `s4_result*.json`).

**Bootstrap settings.** Unless stated otherwise, intervals are paired percentile bootstraps over OD pairs: 10,000 resamples, seed 20261001. "C3λ5" means C3 with z=0 and λ=5, routed in SciPy. "C1" means the Dart C1 trace. On the paper's 100 pairs the SciPy C1 reproduces it exactly.

**Bottom line.** The re-analysis fixed real defects in the original harness (self-scoring with p̃, and penalty seconds counted as detour). The paper is also unusually candid about the circular reference. The remaining problem is the one positive comparative claim, "the soft penalty beats hard blocking at small detour". That claim is:

- decided by the choice of metric in both directions;
- carried entirely by edges that have no observations, i.e. uncalibrated GCC zone defaults rather than flood evidence;
- unsupported by the only partly independent check available: in a source-holdout pilot, crowd evidence added nothing over the prior.

The "nearly hazard-blind default" finding is robust.

---

## Critical

### C-1. Both arms of the C1 vs C3 comparison are circular, and the paper concedes only one of them
- **Location.** §V-C (metrics); §VI-A; §VI-B ("Against hard avoidance, the soft penalty reached lower expected exposure at a smaller mean detour"); §VIII Conclusion ("scored fairly … at small detours the soft penalty reduced expected exposure more than hard blocking did"); Table I; Fig. 2.
- **Problem.** The paper says C1 wins the threshold metric "by construction". It does not say that C3 wins the cumulative metrics by construction too:
  - With δ=1 and z=0, C3 minimises Σ_e τ_e (1+λ p̄_e s_e). That is a weighted-sum scalarisation of (free-flow time, Σ s·τ·p̄).
  - Every C3 route is therefore a supported Pareto point for exactly the "time-weighted p̄" exposure that Table I reports. Σp̄ is a close relative of that quantity.
  - C1 optimises free-flow time subject to a p̄ threshold. It wins the "share touching p̄≥θ" metric by construction.
  - So each method wins the metric that mirrors its own objective. The ranking is set by the choice of metric, not measured.
- **Why it matters.** This is the paper's only positive comparative result, and it is restated in the abstract and the conclusion. At IEEE review it will be read as an argument the authors set up to win.
- **Suggested fix.**
  - State the C3/metric alignment explicitly, next to the existing C1 caveat.
  - Compare frontiers against frontiers (C1 threshold sweep against C3 λ sweep), each on both a cumulative and a worst-segment metric.
  - Pre-declare which metric is primary, and why.
  - Delete "scored fairly" from the conclusion.
- **Confidence.** High.
- **Evidence (method).** I swept the C1 blocking threshold θ ∈ {0.3, 0.4, 0.5, 0.6} in SciPy (validated: θ=0.5 reproduces the Dart C1 node paths on 100/100 pairs) and ran C3 at λ ∈ {5, 20}. Everything was scored under the same reference as the paper.
- **Evidence (result, 100 pairs).**

| Config | Mean extra time (%) | Σp̄ | Share ≥0.3 | Share ≥0.4 | Share ≥0.5 | Share ≥0.6 | Worst p̄ (mean) |
|---|---|---|---|---|---|---|---|
| C0 | 0 | 1.61 | 45 | 38 | 30 | 16 | 0.290 |
| C1 θ=0.6 | 0.57 | 1.53 | 43 | 32 | 21 | 0 | 0.245 |
| C1 θ=0.5 | 1.53 | 1.22 | 39 | 17 | 0 | 0 | 0.193 |
| C1 θ=0.4 | 2.63 | 1.09 | 32 | 0 | 0 | 0 | 0.169 |
| C1 θ=0.3 | 3.88 | 0.72 | 0 | 0 | 0 | 0 | 0.133 |
| C3 λ=0.3 (default) | 0.00 | 1.52 | 45 | 38 | 29 | 13 | 0.284 |
| C3 λ=5 | 0.85 | 0.98 | 36 | 28 | 21 | 10 | 0.235 |
| C3 λ=20 | 4.53 | 0.44 | 26 | 17 | 6 | 1 | 0.170 |

  - On Σp̄, C3 lies below every C1 point at matched detour. For example, interpolating C3 at 3.9% detour gives about 0.54, against 0.72 for C1 θ=0.3.
  - On every share-touching metric, each C1 θ dominates C3 at θ and above. C1 θ=0.4 reaches 0% touching p̄≥0.4 at 2.6% detour. C3 λ=20 still touches 17% at 4.5%.
  - The pattern replicates on 297 fresh uniform OD pairs (seed 20261002) and on 295 short trips (5–20 min). See S-5.
  - Head-to-head on worst p̄ per route, C3λ5 is worse than C1 by +0.043 [0.014, 0.073] (C1 better on 22 pairs, C3 on 9).

### C-2. The whole soft-over-hard advantage comes from prior-only (GCC zone default) edges, not from observed flood evidence
- **Location.** §VI-B; abstract ("With risk weights between 5 and 20, the expected number of hazardous edges per route fell …"); Conclusion.
- **Problem.** Σp̄ splits into two parts: edges with ≥1 observation (5,775 edges) and prior-only edges (8,759 edges, prior p 0.25–0.45, n_eff=0).
  - C1 can never act on prior-only edges. Their maximum p̄ is 0.44999 (the "Very High" category default), so none of them crosses 0.5.
  - C1's detours actually *increase* prior-only exposure. On the fresh uniform sample it goes from 0.583 to 0.665.
  - C3 reduces Σp̄ mostly by avoiding GCC hazard-zone polygons. Their probabilities are planning defaults that the paper itself calls uncalibrated, and Study 2 finds the beliefs over-predict.
  - On the evidence-bearing edges, C3λ5 is no better than C1 and slightly worse.
- **Why it matters.** The paper's thesis is fusing a prior with decaying reports. What actually drives the measured gain is a fixed, uncalibrated zone map. Any router with a static zone penalty would show the same gain. The reader is not told this.
- **Suggested fix.**
  - Report Σp̄ separately for observed and prior-only edges.
  - Add two ablations:
    - routing on the prior alone (no reports);
    - routing on reports alone (with a flat or neutral prior).
  - Remove or qualify "soft beats hard" accordingly.
- **Confidence.** High.
- **Evidence (method).** Paired bootstrap of (C3λ5 − C1) on each component of Σp̄.
- **Evidence (result).**

| Sample | Observed-edge part | Prior-only part | Total |
|---|---|---|---|
| Paper's 100 pairs | +0.040 [−0.075, 0.160] | −0.284 [−0.471, −0.129] | −0.243 [−0.456, −0.072] |
| Fresh 297 uniform pairs | +0.059 [−0.011, 0.131] | −0.308 [−0.430, −0.194] | −0.249 [−0.375, −0.136] |
| 295 short trips | +0.007 [−0.033, 0.050] | −0.154 [−0.249, −0.075] | n/a |

  - **Source-holdout pilot (S-10 has the details).** Route on beliefs that exclude official reports, then score routes on edges that carry an official report. On 300 pairs, crowd plus prior is no better than prior alone:
    - at λ=5: Δ official edges per route −0.013 [−0.043, +0.010];
    - at λ=20: +0.05 [0.00, +0.107], i.e. crowd plus prior is worse, at a larger detour.

---

## Significant

### S-1. "Soft beats hard" is directionally robust on Σp̄ but rests on few informative pairs and has no stated uncertainty
- **Location.** §VI-B; Table I has no CIs; `extra.json`.
- **Problem.** The comparison is two point estimates without intervals.
  - 59 of the 100 pairs give identical routes to C0 under both C1 and C3λ5, which leaves about 41 informative pairs.
  - One pair (#4: ΔΣp̄ −6.95, with C3 143 s slower there) accounts for 29% of the summed difference.
- **Why it matters.** At N=100 the claim depends on a handful of OD pairs, and the paper gives no CI for the head-to-head comparison.
- **Suggested fix.**
  - Give paired CIs and the win/loss counts for every comparison in Table I.
  - Use a Wilcoxon or sign test as a secondary check.
  - Report an influence or leave-one-out analysis.
  - Increase N (see S-7).
- **Confidence.** High.
- **Evidence (method).** Paired bootstrap and Wilcoxon signed-rank test on the 100 pairs. Mean of ratios versus ratio of means.
- **Evidence (result, C3λ5 − C1).**

| Quantity | Mean | 95% CI | Wilcoxon p | Pairs C3 better / C1 better |
|---|---|---|---|---|
| Σp̄ | −0.243 | [−0.456, −0.072] | 0.026 | 24 / 12 |
| Extra free-flow time | −11.7 s | [−21.6, −2.3] | 0.043 | 19 / 17 (faster) |
| Detour, mean of per-pair % | −0.68 pp | [−1.25, −0.17] | n/a | n/a |
| Σp̄, pair #4 dropped | −0.176 | [−0.333, −0.042] | n/a | n/a |
| Σp̄, three most favourable pairs dropped | −0.106 | [−0.223, −0.0002] | n/a | n/a |

  - Mean of ratios versus ratio of means does not flip the ordering:
    - C1: 1.53% vs 1.39%; bootstrap ratio of means [0.86%, 2.0%].
    - C3λ5: 0.85% vs 0.79%; bootstrap ratio of means [0.45%, 1.19%].
  - The direction and size replicate on 297 fresh pairs: ΔΣp̄ −0.249 [−0.375, −0.136], Δtime −15.1 s [−22.4, −8.2].

### S-2. C1 is a single, threshold-matched point, and failures of hard blocking are silently dropped
- **Location.** §V-B; `study_common.build_c1_injected_overrides`; Table I.
- **Problem.**
  - C1 is one point (θ=0.5), using the same threshold as the headline metric. It also uses λ=0, so it has no soft term at all.
  - A fair baseline family is "hard block at θ" swept over θ, plus a hybrid (block at θ_hi with a soft penalty below it).
  - The text says "removes edges with p̄≥0.5". The code uses `p_mean > threshold`. I checked: no edge has p̄ exactly 0.5, so this has no numerical effect.
  - Hard blocking can disconnect an OD pair. The CLI then returns an error and the pair drops out of the comparison, which hides C1's worst outcome. On the paper's 100 pairs this did not happen, but on fresh samples it does.
- **Why it matters.**
  - Baseline: with a single threshold-matched C1 point, the comparison is closer to a strawman than to a fair test.
  - Disconnections: dropping them biases the detour metrics in C1's favour.
- **Suggested fix.**
  - Sweep θ for C1 and add a hybrid baseline.
  - Count unreachable OD pairs as an explicit outcome, e.g. "stranded" or an infinite detour, reported separately.
  - Fix the ≥/> wording.
- **Confidence.** High.
- **Evidence.** For the θ sweep see the table in C-1. Unreachable pairs (SciPy, blocked edges removed):

| C1 threshold | Fresh uniform (300 pairs) | Short trips (300 pairs) |
|---|---|---|
| θ=0.5 | 0 | 1 |
| θ=0.4 | 0 | 2 |
| θ=0.3 | 3 | 5 |

  `n_edges_pm_exactly_0.5 = 0`.

### S-3. The "share touching p̄≥0.5" metric effectively means "the route crosses an edge with an official report"
- **Location.** §V-C; §VI-A ("29% … against 30%"); abstract.
- **Problem.** The threshold metric depends almost entirely on which edges carry an official report:
  - 364 edges have p̄≥0.5, and 356 of them have an official_feed report.
  - Prior-only edges never exceed 0.45.
  - With official reports held out, crowd evidence lifts p̄ above 0.5 on only 8 edges (max p̄ 0.567).

  Crowd and official evidence also barely overlap: 1,017 edges have an official report, 4,874 have a crowd report, and only 116 have both. The metric is therefore a proxy for "touches a GCC stagnation or official flood point", and those points are also inputs to the router.
- **Why it matters.**
  - It answers the brief's question. The 30% share depends only on observed edges, and in practice on official ones; prior-only edges contribute nothing at θ=0.5.
  - At θ≤0.4 the picture changes: 1,150 prior-only edges cross 0.4, and 3,028 cross 0.3.
- **Suggested fix.** Say what the metric measures. Report θ ∈ {0.3, 0.4, 0.5, 0.6} (table below), or better, a threshold-free curve.
- **Confidence.** High.
- **Evidence (threshold sensitivity, 100 pairs; % of routes touching p̄≥θ).**

| θ | C0 | C3 default | C1 (θ_b=0.5) | C3λ5 | C3λ20 |
|---|---|---|---|---|---|
| 0.3 | 45 | 45 | 39 | 36 | 26 |
| 0.4 | 38 | 38 | 17 | 28 | 17 |
| 0.5 | 30 | 29 | 0 | 21 | 6 |
| 0.6 | 16 | 13 | 0 | 10 | 1 |

  - "The default is nearly hazard-blind" holds at every θ.
  - "C1 removes all crossings" holds only for θ≥0.5.
  - At θ=0.3, C3λ5 (36%) beats C1 (39%) at a smaller detour. At θ≥0.4, C1 wins.

### S-4. "Expected number of hazardous edges" is mislabelled and truncated
- **Location.** Abstract, §V-C, §VI-A, §VI-B, Conclusion.
- **Problem.** Σp̄ is not an expected count of hazardous edges, for four reasons:
  - **Not calibrated.** It would be an expected count only if p̄ were calibrated, and Study 2 shows over-prediction.
  - **Truncated.** It counts only the 14,534 configured edges. T1.3 gave a nonzero prior (0.02–0.12) to 193,385 edges in total, but unconfigured edges count as p=0 in both router and reference. In the evaluation, 93.7% of C0 route free-flow time lies on unconfigured edges.
  - **Segmentation-dependent.** It depends on how OSM splits roads into edges: the median route has 222 edges, and Spearman ρ(Σp̄, edge count) = 0.38 for C0.
  - **Severity mismatch.** Severity weights the objective (waterlogging s=0.6, on 624 edges) but not the metric.
- **Why it matters.** The wording overstates what is being measured. Readers will take it as a real-world expected hazard count.
- **Suggested fix.**
  - Call it "model-believed cumulative exposure Σp̄ (configured edges only)".
  - Add a time-weighted version, Σ τ p̄ in seconds, which is less sensitive to segmentation. Also state that C3 optimises it, per C-1.
  - Add a variant that uses the prior on all edges.
- **Confidence.** High.
- **Evidence.** T1.3 `result.json`: `edges_with_nearby_zone_evidence` = 193,385; category defaults Very Low 0.02, Low 0.05, Moderate 0.12, High 0.25, Very High 0.45; the inclusion threshold is 0.25. `t_unconf_share` mean = 0.937. Spearman correlations computed for C0.

### S-5. The OD sampling and trip-length distribution are not described, and the sample is not representative
- **Location.** §V-C ("sampled with the harness's pinned seed"); `t3_2_replay_engine.sample_od_pairs`.
- **Problem.** The sampler draws a source uniformly over all 193,191 OSM nodes, then a target uniformly from the source's BFS-reachable set.
  - This gives long, metro-scale trips. Free-flow time: min 64 s, P10 1,045 s, median 1,834 s (31 min), P90 3,178 s, max 3,954 s. Distance: median 24.9 km, P90 45.5 km, max 62.4 km.
  - The sample follows OSM node density, not population or travel demand.
  - Exposure grows with trip length, so headline levels such as "30% of routes" and "1.61" are artefacts of this choice.
  - Dead-end and reachability handling is fine: 0 dead-end draws, 100 attempts.
- **Why it matters.** It decides the absolute numbers and the detour percentages, and it is not described in the paper.
- **Suggested fix.**
  - Describe the sampler.
  - Stratify by trip length (e.g. <10, 10–25, >25 min), or sample OD pairs from a demand proxy (population grid or ward centroids).
  - Report results per stratum.
- **Confidence.** High.
- **Evidence (short-trip stratum).** 295 pairs with C0 free-flow time between 5 and 20 min (median 16 min):
  - C0: Σp̄ 0.78; 12.9% of routes touch p̄≥0.5.
  - C1: detour 1.92% as a mean of ratios, 1.48% as a ratio of means. The gap between the two definitions widens on short trips.
  - C3λ5: Σp̄ 0.557 at 0.55% detour, against C1's 0.703 at 1.92%. So the ordering replicates, but the absolute levels halve.

### S-6. The z sweep mostly measures "avoid zones with no evidence", which is why pessimism cannot be credited
- **Location.** §VI-C ("This is expected rather than informative").
- **Problem.** The paper says higher z cannot be credited without ground truth. There is also a mechanical reason.
  - Prior-only edges have n_eff=0, so the bound puts the largest inflation on them:
    - at z=1, median p̃ is 0.74 on prior-only edges and 0.38 on edges with an actual flood report;
    - at z=1.28, 14.9% of prior-only edges saturate at p̃=1;
    - at z=2, 100% saturate.
  - Observed edges have median n_eff 0.97 (P90 0.999), so in practice almost every observed edge has one effective report.
  - At z≥1, the router therefore treats an edge with no reports, inside a hazard zone, as riskier than an edge with a flood report.
- **Why it matters.**
  - The z axis of Fig. 2 is not a test of "caution under thin evidence". It is a re-weighting toward the uncalibrated zone map.
  - It also feeds back into C-2.
- **Suggested fix.**
  - Say so in §VI-C.
  - Report the z sweep separately for prior-only and observed edges.
  - Evaluate z only where n_eff varies meaningfully, which needs a corpus with repeated reports.
- **Confidence.** High (arithmetic). Medium on how much this drives the frontier shape.
- **Evidence.** Computed p̃ distributions from the rebuilt beliefs.

### S-7. N=100 is no longer justified, and the statistics are too thin
- **Location.** §V-C ("which is why the harness used 100 rather than 1,000 pairs"); Threats ("Scale").
- **Problem.**
  - The 3.07 s per call is a CLI process-start cost. The validated SciPy re-implementation routes in about 0.04 s per query: 600 pairs × 10 configurations ran in about 2 minutes here.
  - With C3 at its default, only 7/100 pairs change. The bootstrap CI for +0.026 s ([0.003, 0.061]) comes from 7 non-zero values among 93 zeros, and calling that "significant" is meaningless.
  - The 30 sweep points in Table I have no CIs and no multiplicity control.
- **Why it matters.** IEEE reviewers will treat this as underpowered.
- **Suggested fix.**
  - Use ≥1,000 pairs, stratified as in S-5, routed with SciPy, with a Dart spot-check (S-8).
  - Report the number of changed routes with an exact binomial CI. Report the conditional effect among changed routes.
  - Give per-row CIs in Table I.
- **Confidence.** High.

### S-8. The SciPy re-implementation matches the Dart cost, but it was validated only where routes barely change
- **Location.** §V-C ("reproduced the production router's C3 node sequences on 100 of 100 pairs"); contributions bullet ("reproduces the production router's paths").
- **Problem.** The cost formula matches. `edge_cost.dart` computes `τ(1+p̃(δ−1)) + λ p̃ s τ`. Depth is null on all edges, so δ=1 and w = τ(1+λ p̃ s). Unconfigured edges cost τ (`query_orchestrator.dart`), and the SciPy weights are the same. Two further checks came back clean:
  - **Parallel edges.** There are 2,100 (u,v) pairs with parallel edges, and 92 of them have edges with different hazard. SciPy keeps the minimum-weight edge per pair, which is correct. The re-analysis maps Dart node paths to the minimum-τ parallel edge. I checked every step of the C1 and C3 traces and found 0 cases where that edge differs from the minimum-cost edge, so there is no mapping error.
  - **Ties.** Bidirectional Dijkstra and SciPy may break equal-cost ties differently. No mismatch appeared.

  The gap is scope. The 100/100 check is at λ=0.3, where 93/100 routes equal the free-flow route, so it really tests only 7 hazard-aware routes. I additionally confirmed C0 (100/100) and C1 at θ=0.5 (100/100). No sweep point with λ≥1 or z>0 has been checked against Dart, and those are where ties and near-ties on detoured paths matter.
- **Why it matters.**
  - Table I's sweep rows (everything except C0, C1 and the default C3 row) are produced only by the re-implementation.
  - "Reproduces the production router's paths" claims more than was tested.
- **Suggested fix.**
  - Run the Dart CLI on at least 100 pairs at (z, λ) ∈ {(0,5), (0,20), (2,5), (2,20)} and report identical paths and identical optimal costs.
  - Qualify the contribution bullet in the meantime.
- **Confidence.** High.

### S-9. Overclaiming sentences in paper.tex

| Location | Sentence | Problem | Rewrite |
|---|---|---|---|
| Abstract | "With risk weights between 5 and 20, the expected number of hazardous edges per route fell from 1.61 to between 0.98 and 0.18, at a mean travel-time cost of 0.85% to 12.7%." | The 0.18 / 12.7% endpoint needs z=2. At z=0, λ=20 the figures are 0.44 / 4.53%. "Expected number" has the problems in S-4. | Give the z=0 range (0.98–0.44 at 0.85–4.53%), name z for the other endpoint, and say "model-believed exposure". |
| §VI-A | "reduced the expected number of hazardous edges per route by −0.085 ([−0.250, 0.002])" | The CI includes zero (my recomputation: [−0.248, 0.003]; 7 non-zero pairs). | "did not detectably change …". |
| §VI-B | "Against hard avoidance, the soft penalty reached lower expected exposure at a smaller mean detour" | Needs the C-1 and C-2 caveats. | "lower model-believed cumulative exposure, all of it on prior-only zone edges; C1 is better on worst-segment exposure". |
| §VI-B | "Larger risk weights trade time for exposure smoothly" (title) | Based on 6 λ values per z, with no CIs. | "monotonically, on 6 λ values". |
| §VIII | "scored fairly" | The common reference removes self-scoring bias but not circularity (C-1). | Delete. |
| §VIII | "at small detours the soft penalty reduced expected exposure more than hard blocking did" | Same as §VI-B. | Same as §VI-B. |
| Contributions | "reproduces the production router's paths with an independent implementation" | Overstates the validation (S-8). | Qualify with the validated settings. |
| §VI-C | "Our earlier harness reported … 36% … 72%" | These came from N_SWEEP=25 pairs per point, not 100 (`study1_route_quality.py`). | State the N. |
| §IV (line 120) | The CLI is described as "bidirectional Dijkstra with ALT landmarks" | `planRoute` (`query_orchestrator.dart`) calls `bidirectionalDijkstra` with no landmark potential. `alt_landmarks.dart` is exported but used nowhere in the CLI path. Every evaluated route is plain bidirectional Dijkstra, so Proposition 1 has no bearing on the evaluation. | Correct the description (minor for my scope; flagged for S6/S8). |

- **Confidence.** High.

### S-10. A source-holdout route study is feasible now, and its pilot result is negative for the fusion claim
- **Location.** Threats ("Ground truth independent of the belief is required"); Future work.
- **Problem.** The paper treats independent ground truth as unavailable. A partly independent check can be run on the existing corpus: route on crowd plus prior, then score routes against official-report edges. This mirrors Study 2's label design. I piloted it on 300 fresh uniform pairs.
- **Why it matters.**
  - This is the cheapest less-circular route-level test available, and the paper does not report one.
  - Its pilot result directly undercuts the value of crowd fusion. That is a finding the paper should report rather than avoid.
- **Suggested fix.** Adopt it as the primary Study 1 outcome until 2023 or live data exist. See "Minimum additional experiment" below.
- **Confidence.** Medium. The official and crowd layers may be spatially and semantically different phenomena, and the configured-edge set itself is chosen partly by where observations exist.
- **Evidence (result). Official-report edges per route.**

| Routing belief | λ | Detour | Official edges / route | Δ vs C0 |
|---|---|---|---|---|
| C0 (no hazard) | n/a | 0 | 1.223 | n/a |
| Prior only | 5 | 0.38% | 1.000 | −0.223 [−0.33, −0.13] |
| Prior only | 20 | 2.70% | 0.743 | −0.480 [−0.63, −0.34] |
| Crowd + prior | 5 | 0.45% | 0.987 | −0.237 [−0.35, −0.14] |
| Crowd + prior | 20 | 3.41% | 0.793 | −0.430 [−0.59, −0.29] |
| Hard block on crowd belief (p̄>0.5) | n/a | 0 | 1.223 | 0 |

  - Crowd + prior minus prior only: λ=5 −0.013 [−0.043, +0.010]; λ=20 +0.050 [0.000, +0.107].
  - The hard block on the crowd belief removes nothing, because the crowd-only belief never exceeds 0.5 except on 8 edges.

---

## Minor

### M-1. The re-analysis is not reproducible from the context pack
- **Location.** `reanalyze.py` line 23 (reads `WORK.parent/'prior_sub.txt'`).
- **Problem.** The file the script reads is not in `/home/claude/citypulse_context/`. The repository copy has no `chennai_prior_ell0.json` either, because `data/graph/2026-09-14/` holds only the CLI graph.
- **Suggested fix.** Ship the prior file, or the script that derives it, with the paper's artefact.
- **Confidence.** High.
- **Evidence.** `ls`.

### M-2. The ALT-consistency "engineering check" covers only part of the sweep and proves nothing beyond the formula
- **Location.** §VI-E.
- **Problem.** `min_weight_ratio_over_sweep` checks only z ∈ {0, 2} × λ ∈ {0.3, 5}, which is 4 of the 30 points. The result follows from the formula anyway.
- **Suggested fix.** Present it as a unit-test assertion, or drop it.
- **Confidence.** High.

### M-3. The objective weights severity but the metric does not
- **Location.** §V-C.
- **Problem.** The objective uses severity s_c (waterlogging 0.6, on 624 edges). The metric ignores it, so C3 is deliberately less averse on waterlogging edges, which then count fully in Σp̄.
- **Suggested fix.** State this, or use s-weighted exposure as well.
- **Confidence.** Medium.

### M-4. Table I does not define how "mean extra time" is aggregated
- **Location.** Table I, `sweep_table.tex`.
- **Problem.** "Mean extra time (%)" is a mean of per-pair ratios. `extra.json` also holds the ratio of means for C1 (1.39%), but the paper never states which definition it uses.
- **Suggested fix.** Define it in the caption, and add the ratio-of-means column.
- **Confidence.** High.

### M-5. The dropped minority hazard class is not discussed for Study 1
- **Location.** §V-A (124 edges with two classes; the minority class is dropped).
- **Problem.** Both the router and the reference lose the dropped observations. This is consistent between them, but Study 1 should mention it, since 124 of the corpus's observations are lost.
- **Confidence.** High.

### M-6. Free-flow speeds are defaults
- **Location.** §V-A.
- **Problem.** Speeds are road-class defaults (e.g. residential 20 km/h). Detour percentages are sensitive to the ratios between these speeds.
- **Suggested fix.** Run a sensitivity check (±25% on residential and tertiary speeds), or state the limitation.
- **Confidence.** Medium.

---

## Questions for the authors
1. Were λ=5 and the C1 threshold of 0.5 fixed before the common-reference results were seen? If not, the soft-versus-hard comparison point was chosen after the fact.
2. Are the official GCC stagnation points from the same December 2015 event and the same collection process as the crowd layer? This determines how independent the source-holdout check in S-10 is.
3. Why include prior-only edges only from prior p≥0.25 upward? Do the conclusions change if Moderate (0.12) edges are configured?
4. How will the commuter λ be chosen in the product, given Proposition 2 and the finding that λ≈5 is needed before routes change materially?
5. Can the Dart CLI be run in a warm or batch mode, so the sweep points can be validated against production (S-8)?

---

## Minimum additional experiment for IEEE-conference acceptability of Study 1

All of this is feasible within days using the existing SciPy code. Routing is about 0.04 s per query.

1. **Scale and sampling.**
   - Use ≥1,000 OD pairs, stratified into 3 trip-length bands (or drawn from a population-weighted ward-centroid sample).
   - Use a pre-registered seed.
   - Run a Dart CLI spot-check on ≥100 pairs at 4 sweep settings, reporting identical paths and identical optimal costs.
2. **Frontiers, not points.**
   - C1 threshold sweep, θ ∈ {0.3, …, 0.7}.
   - A hybrid baseline (block at θ_hi with a soft term below it).
   - Count stranded OD pairs as an outcome.
   - Score all of them against the C3 λ sweep on two pre-declared metrics: one cumulative (Σ τ p̄) and one worst-segment (max p̄, or share ≥θ with a θ-curve).
   - Give paired CIs and win/loss counts.
3. **Evidence ablation (the key missing control).** Route on four beliefs: prior only, reports only, prior plus reports (C3), and a static-zone-penalty baseline. Without this, "fusion" cannot be credited with any route-level effect.
4. **A less circular outcome.** Make the source-holdout route score from S-10 the primary Study 1 outcome:
   - route on crowd plus prior;
   - score exposure to official-report edges;
   - add a spatial block holdout (e.g. hold out reports in random 1 km tiles and score on them).
5. **Reporting.** State outright that until a time-stamped, independently labelled event exists (December 2023, or the 2026 monsoon), Study 1 shows only how the router trades travel time against *its own belief*. Say this in the abstract, not only under Threats.

The pilot of items 3 and 4 (S-10) already suggests that crowd evidence adds no measurable route-level benefit over the zone prior on this corpus. The paper should report that, rather than the current soft-over-hard framing.
