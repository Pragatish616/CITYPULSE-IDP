# D3 Evaluation — Defense (arguing for the CityPulse AI authors)

Scope: each finding in `D3_evaluation_findings.md` was tested against `paper.tex`, the Study 1 and Study 2 `result.json` files and traces, and two fresh computations.

The computations used the team's own `t3_2_replay_engine`, `study_common` and `study2_calibration` code. The configured-edge prior came from `prior_sub.txt`, because the full `chennai_prior_ell0.json` is not in the upload. All routing ran on the paper's 100 OD pairs, using the C0-trace endpoints and an exact SciPy Dijkstra with the documented cost.

Scripts and outputs are in `scratchpad/d3/` (`s1.py`, `s1b.py`, `s2.py`, `s1.json`).

## Key new numbers (paper's 100 pairs, common reference p̄)

The two exposure columns split Σp̄ into edges that carry observations and prior-only edges.

| Config | Σp̄ | Σp̄ on observed edges | Σp̄ on prior-only edges | Share of routes touching p̄≥0.5 | Mean extra free-flow time |
|---|---|---|---|---|---|
| C0 | 1.61 | 1.03 | 0.57 | 30% | 0 |
| C1 θ=0.5 | 1.22 | 0.71 | 0.51 | 0% | 1.53% |
| C1 θ=0.4 | 1.09 | 0.62 | 0.47 | 0% | 2.63% |
| C1 θ=0.3 | 0.72 | 0.40 | 0.32 | 0% | 3.88% |
| C1 θ=0.25 (97/100 pairs connected) | 0.36 | 0.36 | 0 | 0% | 5.29% |
| Hybrid: block p̄>0.5, plus λ=5 | 0.79 | 0.52 | 0.27 | 0% | 2.14% |
| C3 z=0, λ=5 | 0.98 | 0.75 | 0.23 | 21% | 0.85% |
| C3 z=0, λ=10 | 0.67 | – | – | 13% | 2.49% |
| C3 z=0, λ=20 | 0.44 | 0.36 | 0.08 | 6% | 4.53% |

**Paired difference, C3λ5 minus C1** (bootstrap with 5,000 resamples):

- ΔΣp̄ = −0.243, 95% CI [−0.460, −0.074].
- Δ free-flow time = −11.7 s, 95% CI [−21.8, −2.1].
- 59 pairs are identical to C0 under both methods. C3 is better on 24 pairs and C1 on 12.
- Dropping the single largest pair still leaves a mean ΔΣp̄ of −0.176.

---

## F1 [Critical] Both arms of C1 vs C3 are circular
- **Strongest defense.** The objective is not identical to the headline metric. C3 minimises Σ τ_e·p̄_e·s_e, a time-weighted and severity-weighted sum. Σp̄ is unweighted, and the two correlate only loosely: Spearman ρ between Σp̄ and edge count is 0.38. So C3's Σp̄ win is favoured by alignment, not guaranteed. A supported Pareto point in (T, Στps) need not dominate C1 in (T, Σp̄). The paper already concedes that the ranking depends on the metric: "Which is preferable depends on whether harm is driven by cumulative exposure or by the single worst segment" (§VI-B).
- **What I checked.**
  - I swept C1 over θ and compared it with C3 on Σp̄. At every θ the hard-block point lies on or above the C3 curve, so soft beats hard on Σp̄ even when C1 gets its best threshold.
  - On metrics neither method optimises, the result is mixed:
    - Mean worst p̄: C1 0.19, C3λ5 0.24.
    - Number of edges with p̄≥0.3: C1 1.07, C3λ5 0.87.
    - Σp̄ on observed edges only: C1 0.71, C3λ5 0.75.
  - The ranking does flip with the metric, as the finding says, but that flip is exactly the trade-off the paper states.
- **Verdict.** PARTIAL. Downgrade to Significant. The required fix is one sentence: C3's objective is aligned with the cumulative metrics in the same way C1's is aligned with the threshold metric. The Conclusion's "scored fairly … reduced expected exposure more than hard blocking" should carry that qualifier.
- **Confidence.** High.

## F2 [Critical] The soft-over-hard advantage comes from prior-only edges
- **Strongest defense.** Fusing the prior is the method. A hard block at 0.5 cannot see GCC "Very High" zones (p≤0.45), and showing that is a legitimate finding about hard blocking, not an artefact. On observed edges C3λ5 gets almost the same reduction as C1 (0.75 against 0.71) at about half the detour (0.85% against 1.53%).
- **What I checked.**
  - The C3λ5 − C1 gap of −0.24 splits into +0.04 on observed edges and −0.28 on prior-only edges. The advantage is therefore entirely prior-driven, which confirms the finding.
  - Max prior-only p̄ is 0.44999, confirmed.
  - On the paper's own pairs C1 slightly *reduces* prior-only Σp̄ (0.57 to 0.51). The "increase" reported in the finding was on a fresh sample, so it is not a property of the paper's numbers.
  - The paper itself calls the prior defaults uncalibrated (L173).
- **Verdict.** PARTIAL. Downgrade to Significant. The headline must say the advantage is in avoiding uncalibrated prior-zone edges, and report the observed/prior-only decomposition. Separately, the counterfactual "C1 increases prior-only exposure" does not hold on the paper's sample.
- **Confidence.** High.

## F3 [Significant] Few informative pairs and no stated uncertainty
- **Strongest defense.** The effect survives proper paired inference.
- **What I checked.**
  - ΔΣp̄ CI [−0.46, −0.07] and Δtime CI [−21.8, −2.1] s both exclude 0.
  - 59 pairs are identical to C0 under both methods; C3 wins 24 to 12 on the rest.
  - The top pair contributes 28.5% of the total, but without it the mean is still −0.18.
- **Verdict.** PARTIAL. Downgrade to Minor. Add the CIs above to Table I and the text. The direction is robust, which the finding's own title concedes.
- **Confidence.** High.

## F4 [Significant] C1 is a single threshold-matched point and failures are dropped
- **Strongest defense.** Sweeping θ does not rescue hard blocking on Σp̄: θ=0.4, 0.3 and 0.25 are all on or above the C3 curve.
  - No edge has p̄ exactly 0.5, so the `>` vs `≥` mismatch has no effect (confirmed: 0 edges).
  - On the paper's pairs, θ=0.5 never disconnects a pair.
- **What I checked.**
  - The θ sweep in the table above.
  - At θ=0.25, 3/100 pairs disconnect, so dropping failures does matter at lower θ.
  - The hybrid (block >0.5 plus λ=5) reaches Σp̄ 0.79 at 2.14% with 0% threshold crossings. That is close to the C3 curve, which interpolates to about 0.74 at 2.14%, and it removes the trade-off the paper presents as forced.
- **Verdict.** PARTIAL. The "soft beats hard" claim survives the θ sweep. The omitted hybrid baseline, however, materially changes the paper's "which is preferable depends…" framing. Keep at Significant, narrowed to the missing hybrid baseline and the need to report disconnections.
- **Confidence.** High.

## F5 [Significant] The threshold metric is in effect "touches an official report"
- **Strongest defense.** The metric is defined on the fused belief, and higher official reliability is a design input. The paper already concedes in Threats that exposure is measured under the router's own belief ("Circular reference").
- **What I checked.**
  - 364 edges have p̄≥0.5, and 356 of them have an official report.
  - Under a crowd+prior belief, 8 edges reach p̄≥0.5, with max 0.567.
  - 1,017 edges have an official report and 4,876 have a crowd report. I count 118 with both; the finding says 116, a minor discrepancy.
  - All of the finding's facts are confirmed.
- **Verdict.** PARTIAL. Downgrade to Minor and fold it into the conceded circular-reference threat. Add one sentence describing what the 0.5 threshold selects in practice.
- **Confidence.** High.

## F6 [Significant] "Expected number of hazardous edges" is mislabelled and truncated
- **Strongest defense.** Σp is the standard expected count under the model's belief. Truncation and segmentation apply equally to every configuration, and all comparisons are paired. The paper flags both the uncalibrated prior and the circular reference.
- **What I checked.**
  - 93.5% of C0 free-flow time is on unconfigured edges; the finding says 93.7%.
  - Spearman ρ between Σp̄ and edge count is 0.378.
  - Both confirm the finding, but they affect levels, not the sign of comparisons.
- **Verdict.** PARTIAL. Downgrade to Minor. Relabel the metric as "believed expected count of configured hazard edges (Σp̄)" in the abstract, §V-C and the Conclusion.
- **Confidence.** High.

## F7 [Significant] OD sampling is undescribed and unrepresentative
- **Strongest defense.** Uniform-node random queries are the standard routing-benchmark protocol, and the design is paired, so relative comparisons are less sensitive than levels.
- **What I checked.** C0 free-flow percentiles exactly match the finding: 64, 1,045, 1,834, 3,178 and 3,954 s. The finding is factually correct.
- **Verdict.** PARTIAL. Downgrade to Minor. Describe the sampler and trip-length distribution, and caveat the absolute levels ("30%", "1.61").
- **Confidence.** Medium-High.

## F8 [Significant] The z sweep mostly measures "avoid zones with no evidence"
- **Strongest defense.** Growing caution as evidence thins is the method's stated design (abstract, L44), and the paper already declines to credit higher z (§VI-C). The finding adds a mechanism that supports the paper's own conclusion.
- **What I checked.**
  - At z=1, median p̃ is 0.738 on prior-only edges and 0.383 on observed edges.
  - At z=1.28, 14.8% of prior-only edges saturate; at z=2, 100% do. All confirmed.
- **Verdict.** PARTIAL. As an evaluation finding, downgrade to Minor: report the mechanism in §VI-C. The substantive point is that a no-report zone edge is treated as riskier than an edge with a flood report. That is a formulation issue and belongs in D4.
- **Confidence.** High.

## F9 [Significant] N=100 is no longer justified and the statistics are thin
- **Strongest defense.**
  - "Which is why the harness used 100" is a historically accurate description of the CLI harness, and the sweep stayed at 100 so it could be validated against the Dart traces.
  - The paper does not call the +0.026 s result "significant". L190 reports only the CI.
  - The key comparison (F3) has a CI that excludes 0 at N=100.
- **What I checked.** The reanalysis CI is [0.003, 0.061]. Every non-zero detour against free-flow is ≥0 by construction, so that CI excluding 0 carries no information. The point stands for that interval, not for the main claim.
- **Verdict.** PARTIAL. Downgrade to Minor. Scaling to ≥1,000 pairs is cheap and should be done. Note that the C3-default CI excludes zero trivially, and add CIs to the sweep.
- **Confidence.** Medium-High.

## F10 [Significant] SciPy validated only where routes barely change
- **Strongest defense.**
  - The cost formula is verified identical, parallel-edge handling is verified, and the reanalysis also checked equal optimal cost on 100/100 pairs.
  - SciPy Dijkstra is exact, so for λ≥1 the sweep is an exact evaluation of the *documented* cost whatever Dart does on ties.
  - Exact float ties are rare, and the finding found no mismatch.
- **What I checked.** Only the C0, C1 and C3-default traces exist, so a Dart check at λ≥1 is impossible without running the CLI. The finding's own checks are all clean.
- **Verdict.** PARTIAL. Downgrade to Minor. Scope the contribution bullet: "reproduces the production router's paths for the three traced configurations; the sweep evaluates the documented cost".
- **Confidence.** High.

## F11 [Significant] Overclaiming sentences in paper.tex
- **Strongest defense.** The finding has no location and no stated problem, so there is nothing to defend against. The likely targets are the "expected number" wording (F6), "scored fairly" (F1) and "reproduces the production router's paths" (F10), each handled above.
- **What I checked.** The finding text is empty.
- **Verdict.** DEFENSE SUCCEEDS as stated: drop it, or merge it into F1, F6 and F10.
- **Confidence.** High.

## F12 [Significant] A source-holdout route study is feasible and negative for fusion
- **Strongest defense.**
  - The paper already says independent ground truth is required.
  - Official-edge "truth" inherits Study 2's label problems (F16, F18, F22: coverage, co-location and GCC hazard designations), so a negative pilot is weak evidence.
  - Hazard-aware routing still reduces contact with held-out official edges against C0.
- **What I checked.** On the paper's 100 pairs, I scored routes by mean number of official edges per route and share of routes touching one:

  | Routing belief | Mean official edges per route | Share touching an official edge | Detour |
  |---|---|---|---|
  | C0 | 1.27 | 48% | 0 |
  | Prior only, λ=5 | 1.07 | 44% | 0.45% |
  | Crowd+prior, λ=5 | 1.09 | 44% | 0.51% |
  | Prior only, λ=20 | 0.86 | 39% | 2.96% |
  | Crowd+prior, λ=20 | 0.91 | 40% | 3.39% |
  | C1 on crowd+prior | No change from C0 | | |

  Adding crowd evidence gives no gain over the prior alone, which confirms the finding's direction.
- **Verdict.** PARTIAL. The fact stands, and the paper should report it: crowd fusion adds nothing against the official holdout. Present it as weak evidence given the label limits, not as a refutation. Keep at Significant.
- **Confidence.** Medium. I used the paper's 100 pairs, not the finding's 300, and ran no detour-matched null.

## F13 [Critical] Time-invariant label; decay variants differ only by construction
- **Strongest defense.** The body already concedes this:
  - Decay-only configurations "produce identical beliefs on a corpus with one timestamp" (L178).
  - "Because the label is a proxy and ages are simulated, we do not read these numbers as evidence for or against class-specific decay" (L214).
- **What I checked.**
  - At 0 h, C2, C3 and C4 are identical.
  - At ≥24 h, all equal the prior (Brier 0.03611).
  - Only the 1 h and 6 h buckets differ.
  - T_c is 7,200 s for C3 and 7,300 s for C2, with max |p_C3 − p_C2| = 0.0012. The C3−C2 Brier difference at 1 h is −5×10⁻⁵, which is practically nil.
  - All confirmed.
- **Verdict.** PARTIAL. Downgrade to Significant. The problem is the abstract and Conclusion phrase "no advantage of class-specific decay over simpler baselines", which implies a test that could not discriminate. Replace it with "untestable on this corpus".
- **Confidence.** High.

## F14 [Critical] Crowd evidence lowers skill, so "faster decay wins" means "discard the crowd"
- **Strongest defense.** The paper never claims faster decay wins, only that C3 ≈ C2. It also explicitly declines to read the numbers as evidence about decay.
- **What I checked.** At 0 h, Brier is 0.0478 for C3 and 0.0361 for prior-only, and it falls monotonically as crowd weight decays. This is confirmed. But the label marks a crowd edge 0 unless an official point is co-located (F18), so the label partly penalises crowd evidence by construction.
- **Verdict.** PARTIAL. Downgrade to Significant. The point attacks a claim the paper does not make. The real residue is an omission: adding crowd evidence worsened Brier relative to the prior alone, and the paper should say so.
- **Confidence.** High.

## F15 [Critical] Every model is worse than climatology
- **Strongest defense.** The paper prints both Brier and the uncertainty term (L214), so negative skill can be derived from what is reported. Against a proxy whose base rate is set by GCC point density (F19), climatology is not a meaningful competitor for a probability of flooding.
- **What I checked.** Brier skill score is −0.697 pooled and −0.660 on the crowd pool for C3, −0.81 for C4 and −13.4 for Beta, all confirmed. Prior-only on the crowd pool at 0 h has Brier 0.0361 against a climatology of 0.0236.
- **Verdict.** PARTIAL. Downgrade to Significant: this is a disclosure omission and should be stated in one sentence. It does not overturn any claim, since the paper already reports calibration as weak.
- **Confidence.** High.

## F16 [Critical] All discrimination comes from coverage and edge-length confounds
- **Strongest defense.** The paper claims only "weak discrimination" and draws no conclusion that depends on it. The confound analysis strengthens the paper's own caveat rather than reversing a claim.
- **What I checked** (crowd pool, n=4,876, 118 positives):
  - Prior AUROC is 0.568 and C3 at 0 h is 0.564.
  - On non-floor edges (n=3,811, 115 positives), prior is 0.460 and C3 is 0.458.
  - A bare non-floor indicator scores 0.599, beating C3.
  - Edge length scores 0.651 overall and 0.660 within non-floor edges.
  - Median length is 141 m for positives and 92 m for negatives.
  - Every fact is confirmed. My floor indicator scores higher than the finding's hull indicator (0.576).
- **Verdict.** DEFENSE FAILS on the facts. The severity can be argued down to Significant, because no paper conclusion relies on discrimination. "Weak discrimination (0.61)" must become "no discrimination beyond coverage and edge-length confounds".
- **Confidence.** High.

## F17 [Critical] AUROC 0.61 is inflated by 5,000 undisclosed easy negatives
- **Strongest defense.**
  - "34,256 rows" is arithmetically correct: 29,256 crowd edge–age rows plus 5,000 no-report rows. The finding's "arithmetically false" is wrong. What is wrong is only the label "edge–age rows".
  - The paper does report the crowd-only AUROC (L214, \CrowdAUC), so the second pool is implicitly signalled.
- **What I checked.** `result.json` has pool sizes of 29,256 and 5,000, and AUROC is 0.609 pooled against 0.566 on the crowd pool. I could not recompute the no-report-only AUROCs because the full prior file is missing.
- **Verdict.** PARTIAL. Downgrade to Significant. Disclose the no-report pool in §V-D, and headline the crowd-pool AUROC (0.57, or none after F16) in the abstract. Drop the "arithmetically false" charge.
- **Confidence.** High.

## F18 [Significant] Selection/collider bias in pool construction
- **Strongest defense.** Conditioning on crowd reports defines a coherent estimand, P(official | crowd-reported edge), which measures crowd precision. That is a deliberate restriction, not a collider. Dropping the 899 official-only edges follows from that estimand.
- **What I checked.** 1,017 − 118 = 899, confirmed. I did not recompute the 100 m and 200 m neighbour counts, because that needs geometry.
- **Verdict.** PARTIAL. The "collider" framing is overstated. The edge-resolution co-location sensitivity is a genuine limitation and stands. Keep at Significant, narrowed to label granularity.
- **Confidence.** Medium.

## F19 [Significant] Calibration-in-the-large reflects the proxy base rate
- **Strongest defense.** The Fig. 3 caption already says "over-predict *relative to the proxy label*", and the text refuses to interpret the result.
- **What I checked.** My 0 h bins were:
  - predicted 0.066 → observed 0.022 [0.017, 0.027]
  - predicted 0.250 → observed 0.028 [0.021, 0.037]
  - predicted 0.449 → observed 0.035 [0.012, 0.098]

  These are nearly flat, with a slight non-significant upward trend. This is confirmed.
- **Verdict.** PARTIAL. Downgrade to Minor. Remove "far above observed frequencies" as a model-level finding, and state that the label rate is flat across bins.
- **Confidence.** High.

## F20 [Significant] Beta baseline is crippled and misdiagnosed
- **Strongest defense.** The paper already says the Beta comparison "is therefore not a test of forgetting as such". No conclusion rests on it.
- **What I checked.**
  - With s=0 everywhere, Beta's minimum p on the crowd pool is 0.5, and its crowd-pool Brier is 0.299. That confirms the misdiagnosis: the 0.5 fallback on no-report edges is not the cause.
  - The forgetting rate of 0.9 per hour is a time constant of about 9.5 h.
  - The [UNVERIFIED DETAIL] tag is present in `result.json`.
- **Verdict.** DEFENSE FAILS on the diagnosis sentence, which is factually wrong. Downgrade to Minor, because the comparison is already disclaimed. Fix the sentence, and either add a base rate or prior to Beta or drop it.
- **Confidence.** High.

## F21 [Significant] No uncertainty quantification; rows pseudo-replicated
- **Strongest defense.** No claim needs three-decimal precision, and the paper states that the variants are indistinguishable.
- **What I checked.**
  - An edge-level bootstrap of C3 AUROC at 0 h gives [0.521, 0.605]. 708 = 118 × 6 positives.
  - Pseudo-replication is confirmed. It inflates the apparent n but does not change any conclusion the paper draws.
- **Verdict.** PARTIAL. Downgrade to Minor. Report edges and positives as 4,876 and 118, add edge-level CIs, and round the reported figures.
- **Confidence.** High.

## F22 [Significant] The "official" label is partly a susceptibility designation
- **Strongest defense.** The paper calls the label a proxy throughout, and the finding itself shows that content leakage against the prior is weak (AUROC about 0.51).
- **What I checked.** The hotspot `raw` fields read `"inundation_level": "Low Vulnerability less than 2 feet"`, `"vulnerability"`, `"inundation_ft_band"`. There are 327 hotspot records and 753 stagnation records, neither with a date. This is confirmed.
- **Verdict.** PARTIAL. Downgrade to Minor. Describe the hotspot layer as GCC vulnerability designations in §V-A and §V-D.
- **Confidence.** High.

---

## Summary table

| ID | Original | Verdict | Suggested severity |
|---|---|---|---|
| F1 | Critical | PARTIAL | Significant |
| F2 | Critical | PARTIAL | Significant |
| F3 | Significant | PARTIAL | Minor |
| F4 | Significant | PARTIAL | Significant (narrowed to the missing hybrid baseline and disconnection reporting) |
| F5 | Significant | PARTIAL | Minor |
| F6 | Significant | PARTIAL | Minor |
| F7 | Significant | PARTIAL | Minor |
| F8 | Significant | PARTIAL | Minor (move the substance to D4) |
| F9 | Significant | PARTIAL | Minor |
| F10 | Significant | PARTIAL | Minor |
| F11 | Significant | DEFENSE SUCCEEDS | Drop or merge |
| F12 | Significant | PARTIAL | Significant |
| F13 | Critical | PARTIAL | Significant |
| F14 | Critical | PARTIAL | Significant |
| F15 | Critical | PARTIAL | Significant |
| F16 | Critical | DEFENSE FAILS | Significant |
| F17 | Critical | PARTIAL | Significant (drop "arithmetically false") |
| F18 | Significant | PARTIAL | Significant (narrowed) |
| F19 | Significant | PARTIAL | Minor |
| F20 | Significant | DEFENSE FAILS | Minor |
| F21 | Significant | PARTIAL | Minor |
| F22 | Significant | PARTIAL | Minor |
