# Findings to defend (D3_evaluation)

## F1 [Critical] C-1. Both arms of the C1 vs C3 comparison are circular, and the paper concedes only one of them
**Location:** .** §V-C (metrics); §VI-A; §VI-B ("Against hard avoidance, the soft penalty reached lower expected exposure at a smaller mean detour"); §VIII Conclusion ("scored fairly … at small detours the soft penalty reduced expected exposure more than hard blocking did"); Table I; Fig. 2.

**Claimed problem:** .** The paper says C1 wins the threshold metric "by construction". It does not say that C3 wins the cumulative metrics by construction too:
  - With δ=1 and z=0, C3 minimises Σ_e τ_e (1+λ p̄_e s_e). That is a weighted-sum scalarisation of (free-flow time, Σ s·τ·p̄).
  - Every C3 route is therefore a supported Pareto point for exactly the "time-weighted p̄" exposure that Table I reports. Σp̄ is a close relative of that quantity.
  - C1 optimises free-flow time subject to a p̄ threshold. It wins the "share touching p̄≥θ" metric by construction.
  - So each method wins the metric that mirrors its own objective. The ranking is set by the choice of metric, not measured.

## F2 [Critical] C-2. The whole soft-over-hard advantage comes from prior-only (GCC zone default) edges, not from observed flood evidence
**Location:** .** §VI-B; abstract ("With risk weights between 5 and 20, the expected number of hazardous edges per route fell …"); Conclusion.

**Claimed problem:** .** Σp̄ splits into two parts: edges with ≥1 observation (5,775 edges) and prior-only edges (8,759 edges, prior p 0.25–0.45, n_eff=0).
  - C1 can never act on prior-only edges. Their maximum p̄ is 0.44999 (the "Very High" category default), so none of them crosses 0.5.
  - C1's detours actually *increase* prior-only exposure. On the fresh uniform sample it goes from 0.583 to 0.665.
  - C3 reduces Σp̄ mostly by avoiding GCC hazard-zone polygons. Their probabilities are planning defaults that the paper itself calls uncalibrated, and Study 2 finds the beliefs over-predict.
  - On the evidence-bearing edges, C3λ5 is no better than C1 and slightly worse.

## F3 [Significant] S-1. "Soft beats hard" is directionally robust on Σp̄ but rests on few informative pairs and has no stated uncertainty
**Location:** .** §VI-B; Table I has no CIs; `extra.json`.

**Claimed problem:** .** The comparison is two point estimates without intervals.
  - 59 of the 100 pairs give identical routes to C0 under both C1 and C3λ5, which leaves about 41 informative pairs.
  - One pair (#4: ΔΣp̄ −6.95, with C3 143 s slower there) accounts for 29% of the summed difference.

## F4 [Significant] S-2. C1 is a single, threshold-matched point, and failures of hard blocking are silently dropped
**Location:** .** §V-B; `study_common.build_c1_injected_overrides`; Table I.

**Claimed problem:** .**
  - C1 is one point (θ=0.5), using the same threshold as the headline metric. It also uses λ=0, so it has no soft term at all.
  - A fair baseline family is "hard block at θ" swept over θ, plus a hybrid (block at θ_hi with a soft penalty below it).
  - The text says "removes edges with p̄≥0.5". The code uses `p_mean > threshold`. I checked: no edge has p̄ exactly 0.5, so this has no numerical effect.
  - Hard blocking can disconnect an OD pair. The CLI then returns an error and the pair drops out of the comparison, which hides C1's worst outcome. On the paper's 100 pairs this did not happen, but on fresh samples it does.

## F5 [Significant] S-3. The "share touching p̄≥0.5" metric effectively means "the route crosses an edge with an official report"
**Location:** .** §V-C; §VI-A ("29% … against 30%"); abstract.

**Claimed problem:** .** The threshold metric depends almost entirely on which edges carry an official report:
  - 364 edges have p̄≥0.5, and 356 of them have an official_feed report.
  - Prior-only edges never exceed 0.45.
  - With official reports held out, crowd evidence lifts p̄ above 0.5 on only 8 edges (max p̄ 0.567).

  Crowd and official evidence also barely overlap: 1,017 edges have an official report, 4,874 have a crowd report, and only 116 have both. The metric is therefore a proxy for "touches a GCC stagnation or official flood point", and those points are also inputs to the router.

## F6 [Significant] S-4. "Expected number of hazardous edges" is mislabelled and truncated
**Location:** .** Abstract, §V-C, §VI-A, §VI-B, Conclusion.

**Claimed problem:** .** Σp̄ is not an expected count of hazardous edges, for four reasons:
  - **Not calibrated.** It would be an expected count only if p̄ were calibrated, and Study 2 shows over-prediction.
  - **Truncated.** It counts only the 14,534 configured edges. T1.3 gave a nonzero prior (0.02–0.12) to 193,385 edges in total, but unconfigured edges count as p=0 in both router and reference. In the evaluation, 93.7% of C0 route free-flow time lies on unconfigured edges.
  - **Segmentation-dependent.** It depends on how OSM splits roads into edges: the median route has 222 edges, and Spearman ρ(Σp̄, edge count) = 0.38 for C0.
  - **Severity mismatch.** Severity weights the objective (waterlogging s=0.6, on 624 edges) but not the metric.

## F7 [Significant] S-5. The OD sampling and trip-length distribution are not described, and the sample is not representative
**Location:** .** §V-C ("sampled with the harness's pinned seed"); `t3_2_replay_engine.sample_od_pairs`.

**Claimed problem:** .** The sampler draws a source uniformly over all 193,191 OSM nodes, then a target uniformly from the source's BFS-reachable set.
  - This gives long, metro-scale trips. Free-flow time: min 64 s, P10 1,045 s, median 1,834 s (31 min), P90 3,178 s, max 3,954 s. Distance: median 24.9 km, P90 45.5 km, max 62.4 km.
  - The sample follows OSM node density, not population or travel demand.
  - Exposure grows with trip length, so headline levels such as "30% of routes" and "1.61" are artefacts of this choice.
  - Dead-end and reachability handling is fine: 0 dead-end draws, 100 attempts.

## F8 [Significant] S-6. The z sweep mostly measures "avoid zones with no evidence", which is why pessimism cannot be credited
**Location:** .** §VI-C ("This is expected rather than informative").

**Claimed problem:** .** The paper says higher z cannot be credited without ground truth. There is also a mechanical reason.
  - Prior-only edges have n_eff=0, so the bound puts the largest inflation on them:
    - at z=1, median p̃ is 0.74 on prior-only edges and 0.38 on edges with an actual flood report;
    - at z=1.28, 14.9% of prior-only edges saturate at p̃=1;
    - at z=2, 100% saturate.
  - Observed edges have median n_eff 0.97 (P90 0.999), so in practice almost every observed edge has one effective report.
  - At z≥1, the router therefore treats an edge with no reports, inside a hazard zone, as riskier than an edge with a flood report.

## F9 [Significant] S-7. N=100 is no longer justified, and the statistics are too thin
**Location:** .** §V-C ("which is why the harness used 100 rather than 1,000 pairs"); Threats ("Scale").

**Claimed problem:** .**
  - The 3.07 s per call is a CLI process-start cost. The validated SciPy re-implementation routes in about 0.04 s per query: 600 pairs × 10 configurations ran in about 2 minutes here.
  - With C3 at its default, only 7/100 pairs change. The bootstrap CI for +0.026 s ([0.003, 0.061]) comes from 7 non-zero values among 93 zeros, and calling that "significant" is meaningless.
  - The 30 sweep points in Table I have no CIs and no multiplicity control.

## F10 [Significant] S-8. The SciPy re-implementation matches the Dart cost, but it was validated only where routes barely change
**Location:** .** §V-C ("reproduced the production router's C3 node sequences on 100 of 100 pairs"); contributions bullet ("reproduces the production router's paths").

**Claimed problem:** .** The cost formula matches. `edge_cost.dart` computes `τ(1+p̃(δ−1)) + λ p̃ s τ`. Depth is null on all edges, so δ=1 and w = τ(1+λ p̃ s). Unconfigured edges cost τ (`query_orchestrator.dart`), and the SciPy weights are the same. Two further checks came back clean:
  - **Parallel edges.** There are 2,100 (u,v) pairs with parallel edges, and 92 of them have edges with different hazard. SciPy keeps the minimum-weight edge per pair, which is correct. The re-analysis maps Dart node paths to the minimum-τ parallel edge. I checked every step of the C1 and C3 traces and found 0 cases where that edge differs from the minimum-cost edge, so there is no mapping error.
  - **Ties.** Bidirectional Dijkstra and SciPy may break equal-cost ties differently. No mismatch appeared.

  The gap is scope. The 100/100 check is at λ=0.3, where 93/100 routes equal the free-flow route, so it really tests only 7 hazard-aware routes. I additionally confirmed C0 (100/100) and C1 at θ=0.5 (100/100). No sweep point with λ≥1 or z>0 has been checked against Dart, and those are where ties and near-ties on detoured paths matter.

## F11 [Significant] S-9. Overclaiming sentences in paper.tex
**Location:** 

**Claimed problem:** 

## F12 [Significant] S-10. A source-holdout route study is feasible now, and its pilot result is negative for the fusion claim
**Location:** .** Threats ("Ground truth independent of the belief is required"); Future work.

**Claimed problem:** .** The paper treats independent ground truth as unavailable. A partly independent check can be run on the existing corpus: route on crowd plus prior, then score routes against official-report edges. This mirrors Study 2's label design. I piloted it on 300 fresh uniform pairs.

## F13 [Critical] C1. The label is time-invariant, so "report age" cannot be evaluated, and decay variants differ only by construction
**Location:** .** `study2_calibration.py` L37–41, L157–176; paper Sec. V-D ("Report ages … were simulated"), Sec. VI-D, abstract ("no advantage of class-specific decay"), conclusion.

**Claimed problem:** .**
  - The label y_edge says whether an official point exists on the edge. It is the same at every simulated age. Every crowd report on an edge has the same age, so "age a" means multiplying the whole crowd log-odds shift by one global constant, exp(−a/T).
  - Scoring a time-varying p(t) against a fixed label rewards whichever constant best fits the label's base rate. That tests evidence weighting, not the shape of the decay.
  - With the corpus's single timestamp the three decay models collapse:
    - At 0 h, C2, C3 and C4 are identical.
    - At 24 h and later, all three equal the prior-only prediction.
    - They differ only in the 1 h and 6 h buckets, which are 2 of the 6.
  - The crowd pool is 100% flood class, so "class-specific" C3 uses T = 7200 s against C2's shared T = 7300 s. Those are the same model to within 0.0012 in any row.

## F14 [Critical] C2. Crowd evidence lowers skill under this label, so "faster decay wins" just means "discarding the crowd wins"
**Location:** .** `result.json["metrics_by_report_age_bucket"]`; paper Sec. VI-D, Table III.

**Claimed problem:** .** Brier improves steadily as crowd evidence is decayed away. Once the evidence is gone (the prior alone), the model scores better than with it. This explains the whole ranking: C4 scores worst because it keeps the crowd evidence at full weight for 6 h, and C2 and C3 score better because they discard it sooner. None of this concerns the decay mechanism.

## F15 [Critical] C3. Every model is worse than a constant forecast, and the paper does not say so
**Location:** .** Table III; Sec. VI-D.

**Claimed problem:** .**
  - Climatology means always predicting the base rate. Its Brier score equals the uncertainty term: 0.0202 pooled and 0.0236 on the crowd pool.
  - Every reported model scores worse:

    | Model | Brier skill score, pooled | Brier skill score, crowd pool |
    |---|---|---|
    | C3 | −0.70 | −0.66 |
    | C4 | −0.81 | −0.78 |
    | Beta | −13.4 | −11.7 |

  - Prior-only on the crowd pool scores −0.53, the best of the non-trivial predictors, and still worse than climatology.
  - The paper reports reliability and resolution but leaves out the single most interpretable fact: the forecasts have negative skill.

## F16 [Critical] C4. All discrimination comes from non-hazard confounds: GCC coverage and edge length
**Location:** .** Label construction (`study2_calibration.py` L105–126); paper Sec. VI-D ("weak discrimination").

**Claimed problem:** .**
  - **Coverage confound.** The prior falls back to 0.02 on edges more than 600 m from any GCC hazard zone, which in practice means outside GCC's mapping coverage. Official points (GCC stagnation and GCC hotspots) exist only inside GCC coverage.
    - All 118 positive edges lie inside the convex hull of official points. Only 35% of prior-floor crowd edges do, against 99.6% of non-floor crowd edges.
    - Within coverage, the models have no discrimination at all:

      | Subset | Prior AUROC | C3 (0 h) AUROC |
      |---|---|---|
      | Non-floor (zone-covered) edges, n = 3,787, 115 positives | 0.456 | 0.455 |
      | Inside-hull edges, n = 4,151, all 118 positives | 0.494 | 0.492 |

    - A bare "inside hull" indicator scores 0.576, above C3's 0.566.
  - **Edge-length confound.** y = 1 needs an official point to snap to the same edge as a crowd point, so longer edges are more likely to be positive.
    - Edge length alone has AUROC 0.651 on the crowd pool, and 0.659 within coverage. That beats every model in Table III.
    - Median length is 141 m for positives and 92 m for negatives.
    - A logistic fit on log(length) plus prior reaches an in-sample AUROC of 0.653.

## F17 [Critical] C5. The headline AUROC of 0.61 is inflated by 5,000 random easy negatives that the paper never mentions
**Location:** .** Abstract ("area under the ROC curve 0.61"); Sec. V-D ("giving 34,256 edge–age rows with 708 positives"); Table III caption.

**Claimed problem:** .**
  - The 34,256 rows are 4,876 crowd edges × 6 ages (29,256 rows) plus 5,000 randomly sampled edges with no observations. Those 5,000 are labelled 0 by construction and predicted by the prior alone.
  - Positives can only arise in the crowd pool, so those negatives are easy. The AUROC implied for positives against the no-report negatives is 0.852 (C3), 0.860 (C4) and 0.987 (Beta). The pooled 0.609 is a mixture of 0.566 and 0.852.
  - The 5,000 rows also pull the pooled Brier down: their mean p is 0.048, so their mean p² is 0.006.
  - Sec. V-D does not mention the no-report pool, and "34,256 edge–age rows" is arithmetically false: 4,876 × 6 = 29,256.

## F18 [Significant] S1. Selection and collider bias in pool construction; the label measures co-location at edge resolution
**Location:** .** `load_edge_pools` L105–143.

**Claimed problem:** .**
  - The crowd pool keeps only edges with at least one crowd report. 899 of the 1,017 edges with an official point have no crowd report, and they are dropped from the study completely; they are in neither pool. So the positives are "official AND crowd on the same directed edge", which is a co-location event.
  - The label is badly sensitive to spatial granularity:
    - 456 negative edges have an official point within 100 m, nearly four times the 118 positives.
    - 1,477 negatives have one within 200 m.
    - 86% of positives have one within 100 m.
  - Each crowd "observation" is one OSM way, placed at its first sub-segment's midpoint (`t31_build_replay_corpus.py` L100–109). A flooded street therefore gives evidence to one edge only. An official point on another edge of the same flooded street yields y = 0.

## F19 [Significant] S2. Calibration-in-the-large reflects the proxy's base rate, not the hazard probability
**Location:** .** Sec. VI-D ("predicted probabilities far above observed frequencies"); Fig. 3 caption.

**Claimed problem:** .**
  - The proxy's prevalence (2.4% of crowd edges) is set by how many GCC points exist and how they snap. It does not represent P(flooded).
  - The prior's category probabilities (0.02 to 0.45) and the crowd weight α = 0.6 are meant to represent P(flooded). A gap between 0.10 mean prediction and 0.024 observed frequency is therefore uninterpretable; it may be the label, not the model.
  - The reliability diagrams also show something the paper does not state: the observed frequency is flat across predicted bins. At 0 h:

    | Mean predicted p | Observed frequency | 95% Wilson interval |
    |---|---|---|
    | 0.080 | 0.025 | [0.020, 0.030] |
    | 0.277 | 0.023 | [0.016, 0.032] |
    | 0.449 | 0.035 | [0.012, 0.098] |

    A higher predicted p does not mean a higher label rate.

## F20 [Significant] S3. The Beta-reputation baseline is structurally crippled, and the paper and ADR-012 misdiagnose why
**Location:** .** `study_common.beta_reputation_p` L382–417; ADR-012 point 6; paper Sec. VI-D ("largely because it falls back to 0.5 where no reports exist").

**Claimed problem:** .**
  - The implementation has no base rate. It computes E[Beta(r+1, s+1)] = (r+1)/(r+s+2), and the corpus has only positive reports (s = 0), so p ≥ 0.5 on every row. The minimum p on the crowd pool is exactly 0.5.
  - So the 0.5 fallback on no-report edges is not the main cause. On the crowd-only pool, where every edge has reports, Beta still scores Brier 0.299.
  - Beta also differs from C2/C3 on more than decay:
    - It weights by α linearly rather than by logit(α).
    - Its forgetting rate of 0.9 per hour is a time constant of about 9.5 h, against 2 h for C2/C3.
    - It gets no prior.
  - The comparison therefore does not isolate "the decay mechanism", contrary to the docstring at L389–392.
  - The repo flags the formulation as [UNVERIFIED DETAIL], since the primary paper was not opened. The paper cites it as Jøsang & Ismail without that caveat.

## F21 [Significant] S4. No uncertainty quantification, and rows are pseudo-replicated
**Location:** .** Table III; `compute_metrics_table`.

**Claimed problem:** .**
  - Each crowd edge appears in six rows (one per age), and each pooled metric treats the 29,256 rows as independent. The independent units are 4,876 edges with 118 positive edges. 708 "positives" means 118 edges × 6.
  - Half the rows (24 h and later) are identical prior-only predictions for all decay variants.
  - No confidence intervals are reported. The paper prints AUROC to three decimals (0.609, 0.609, 0.609) and Brier to four, which suggests a precision the data cannot support.

## F22 [Significant] S5. The "official" label is partly a susceptibility designation, not an event observation, so it is circular with the prior in kind
**Location:** .** Corpus `gcc_flood_hotspots_2015.kml` (327 points); paper Sec. V-A/V-D.

**Claimed problem:** .**
  - The hotspot records carry `vulnerability` ("Low Vulnerability") and `inundation_ft_band` ("<2ft", "3 to 5 ft") fields. These look like GCC's designated vulnerable locations, a hazard map, rather than dated 2015 observations. The prior is also a GCC hazard map.
  - Content leakage turned out to be weak in practice. Among all observed edges, prior AUROC for official-vs-crowd-only is 0.511 (0.524 for the hotspot layer, 0.505 for stagnation). But that only shows the two GCC products disagree. It does not make the hotspot layer ground truth.
  - The stagnation layer (753 points, 70 of the 118 positives) has no date either.
