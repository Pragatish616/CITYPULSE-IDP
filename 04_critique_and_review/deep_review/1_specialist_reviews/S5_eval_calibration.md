# S5: Evaluation validity of the calibration study (Study 2)

Reviewer: S5 (evaluation validity, calibration). Target bar: IEEE conference paper.
Date: 2026-10-01.

**Scope.** Study 2 as implemented (`scripts/study2_calibration.py`, `scripts/study_common.py`), its result file (`data/results/2026-09-18-study2-calibration/result.json`), ADR-012, and the paper draft (`drafts/paper.tex` Sec. V-D, VI-D, Table III, Fig. 3, abstract and conclusion).

**Reproduction.** I rebuilt the crowd pool with the team's own loaders and scoring functions (`t32.load_corpus`, `study2_calibration.score_crowd_pool`, `compute_metrics_table`). The priors came from the 14,533-edge prior subset recovered in the earlier session (the repo's `chennai_prior_ell0.json` is not in the upload; the subset covers every observed edge). Every crowd-pool number in `result.json["metrics_crowd_pool_only"]` matched to at least six decimals: C3 Brier 0.039189, AUROC 0.566242; Beta Brier 0.299287. I could not rebuild the 5,000-edge no-report pool row by row, because its priors are mostly below 0.25 and are not in the subset. I inferred its contribution from the difference between the pooled and crowd-only aggregates. Scripts are in the session scratchpad (`.../scratchpad/s5/a1.py` to `a6.py`, `rebuild.py`).

**Bottom line.** Study 2 does not measure calibration of a flood probability, and it cannot test decay. The label has no time index. All reports share one age. The crowd pool contains one hazard class, so C3 and C2 differ only by T_c = 7200 s versus 7300 s. The only discrimination the models show comes from two non-hazard confounds: administrative coverage (GCC mapping extent) and edge length. Every model, including the team's, scores worse than a constant base-rate forecast. The paper's 0.61 AUROC is inflated by 5,000 random no-report negatives that the text never mentions. The study should be removed from the paper's evidence base, or rewritten as a negative methods note with the corrections below. Then it should be replaced by the design in the last section.

---

## Critical

### C1. The label is time-invariant, so "report age" cannot be evaluated, and decay variants differ only by construction
- **Location.** `study2_calibration.py` L37–41, L157–176; paper Sec. V-D ("Report ages … were simulated"), Sec. VI-D, abstract ("no advantage of class-specific decay"), conclusion.
- **Problem.**
  - The label y_edge says whether an official point exists on the edge. It is the same at every simulated age. Every crowd report on an edge has the same age, so "age a" means multiplying the whole crowd log-odds shift by one global constant, exp(−a/T).
  - Scoring a time-varying p(t) against a fixed label rewards whichever constant best fits the label's base rate. That tests evidence weighting, not the shape of the decay.
  - With the corpus's single timestamp the three decay models collapse:
    - At 0 h, C2, C3 and C4 are identical.
    - At 24 h and later, all three equal the prior-only prediction.
    - They differ only in the 1 h and 6 h buckets, which are 2 of the 6.
  - The crowd pool is 100% flood class, so "class-specific" C3 uses T = 7200 s against C2's shared T = 7300 s. Those are the same model to within 0.0012 in any row.
- **Why it matters.** The paper's abstract and conclusion present "no advantage of class-specific decay" as an empirical finding. The design guarantees that result, whatever the truth. A referee will read this as a non-test reported as a negative result.
- **Suggested fix.** State that Study 2 cannot test decay, and drop "no advantage of class-specific decay" from the abstract and conclusion. Testing decay needs real heterogeneous report ages and a time-indexed label (see the design section).
- **Confidence.** High.
- **Evidence.**
  - Max |p_C3 − p_C2| per age bucket is 0, 0.0012, 0.0004, 2e-7, 1e-16 and 0. Max |p_C3 − p_C4| is 0, 0.124, 0.258, 1.1e-6, 1e-16 and 0. Max |p_C3 − prior| at ≥24 h is ≤1.1e-6.
  - Decay factor at 1 h: 0.607 (C3) vs 0.611 (C2) vs 1.0 (C4). At 6 h: 0.050 vs 0.052 vs 1.0.
  - Edge-clustered bootstrap (400 resamples): ΔAUROC(C3−C2) has median 0.000 [−0.0002, 0.0000]; ΔBrier(C3−C2) is 0 to four decimals.
  - Config check: `hazard_classes.yaml` sets flood T_c = 7200; `study_common.C2_SHARED_TC_SECONDS` = 7300.

### C2. Crowd evidence lowers skill under this label, so "faster decay wins" just means "discarding the crowd wins"
- **Location.** `result.json["metrics_by_report_age_bucket"]`; paper Sec. VI-D, Table III.
- **Problem.** Brier improves steadily as crowd evidence is decayed away. Once the evidence is gone (the prior alone), the model scores better than with it. This explains the whole ranking: C4 scores worst because it keeps the crowd evidence at full weight for 6 h, and C2 and C3 score better because they discard it sooner. None of this concerns the decay mechanism.
- **Why it matters.** Read naively, Table III ranks decay mechanisms. It really measures how harmful crowd evidence is against a label it barely predicts. The paper does not report a prior-only row, which would expose this at once.
- **Suggested fix.** Add prior-only and climatology rows to Table III, and report Brier skill against both. Explain that the C4 gap comes from the 1 h and 6 h buckets only.
- **Confidence.** High.
- **Evidence.**
  - Per-bucket Brier for C3: 0.0478 (0 h), 0.0424 (1 h), 0.0365 (6 h), and 0.0361 at 24, 72 and 168 h (prior only). Per-bucket AUROC: 0.5639 at 0 h and 0.5683 at 168 h.
  - Sweeping an evidence multiplier c in p = σ(ℓ0 + c·Σκ·logit 0.6) over the crowd pool:

    | c | Brier | AUROC |
    |---|---|---|
    | 0 | 0.03611 | 0.5683 |
    | 0.25 | 0.03845 | 0.5670 |
    | 0.5 | 0.04115 | 0.5668 |
    | 1 | 0.04783 | 0.5639 |

    Both metrics get worse steadily as c rises.

### C3. Every model is worse than a constant forecast, and the paper does not say so
- **Location.** Table III; Sec. VI-D.
- **Problem.**
  - Climatology means always predicting the base rate. Its Brier score equals the uncertainty term: 0.0202 pooled and 0.0236 on the crowd pool.
  - Every reported model scores worse:

    | Model | Brier skill score, pooled | Brier skill score, crowd pool |
    |---|---|---|
    | C3 | −0.70 | −0.66 |
    | C4 | −0.81 | −0.78 |
    | Beta | −13.4 | −11.7 |

  - Prior-only on the crowd pool scores −0.53, the best of the non-trivial predictors, and still worse than climatology.
  - The paper reports reliability and resolution but leaves out the single most interpretable fact: the forecasts have negative skill.
- **Why it matters.** Calling the result "weak discrimination" undersells it. Under this label the system's probabilities are less useful than a constant. Reviewers will compute this from Table III, which prints the uncertainty term, and will ask why it was not stated.
- **Suggested fix.** Report Brier skill against climatology and against prior-only. Recalibration on held-out data (logistic intercept and slope) would show how much of the gap is calibration-in-the-large driven by the proxy's base rate (see S2).
- **Confidence.** High. The arithmetic uses only `result.json`.
- **Evidence.** Brier skill = 1 − Brier/uncertainty, computed from `metrics_overall_all_edges` and `metrics_crowd_pool_only`, plus the rebuilt prior-only predictions.

### C4. All discrimination comes from non-hazard confounds: GCC coverage and edge length
- **Location.** Label construction (`study2_calibration.py` L105–126); paper Sec. VI-D ("weak discrimination").
- **Problem.**
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
- **Why it matters.** The reported AUROC (0.566 crowd pool, 0.61 pooled) is not "weak hazard discrimination". It is jurisdiction plus geometry. The honest statement is that the predictors carry no detectable information about the label once these sampling artefacts are controlled.
- **Suggested fix.**
  - If the proxy is kept at all, restrict the analysis to the label's sampling frame (inside GCC coverage).
  - Define the label at a length-normalised unit, such as a fixed-length segment or "official point within r m of the edge midpoint". Alternatively, report a length-only baseline.
  - Above all, replace the label (see the design section).
- **Confidence.** High for the numbers. Medium on reading "prior = 0.02" as "outside GCC coverage"; it rests on the hull test and the 600 m influence rule in `t1_3_build_graph_and_prior.py` L116 and L356.
- **Evidence.** `a2.py` and `a3.py`: AUROC by subset, convex hull of the 1,080 official points (scipy Delaunay), median distance to the nearest official point (3.57 km for floor edges, 0.24 km for non-floor), and the logistic fit.

### C5. The headline AUROC of 0.61 is inflated by 5,000 random easy negatives that the paper never mentions
- **Location.** Abstract ("area under the ROC curve 0.61"); Sec. V-D ("giving 34,256 edge–age rows with 708 positives"); Table III caption.
- **Problem.**
  - The 34,256 rows are 4,876 crowd edges × 6 ages (29,256 rows) plus 5,000 randomly sampled edges with no observations. Those 5,000 are labelled 0 by construction and predicted by the prior alone.
  - Positives can only arise in the crowd pool, so those negatives are easy. The AUROC implied for positives against the no-report negatives is 0.852 (C3), 0.860 (C4) and 0.987 (Beta). The pooled 0.609 is a mixture of 0.566 and 0.852.
  - The 5,000 rows also pull the pooled Brier down: their mean p is 0.048, so their mean p² is 0.006.
  - Sec. V-D does not mention the no-report pool, and "34,256 edge–age rows" is arithmetically false: 4,876 × 6 = 29,256.
- **Why it matters.** The abstract's only calibration number is driven by a sampling choice that has no population meaning. The mix of 5,000 negatives against roughly 29k is arbitrary, and changing it changes the AUROC at will.
- **Suggested fix.** Report crowd-pool numbers only, at the edge level, with confidence intervals. Or define a proper population (all edges, or a stratified random sample with known weights) and report weighted metrics. Correct the row count and describe both pools in Sec. V-D.
- **Confidence.** High.
- **Evidence.** U-statistic decomposition: U_total − U_crowd = AUROC(positives vs no-report) × 708 × 5,000, using the values in `result.json`. No-report pool mean p is 0.0481 and mean p² is 0.00597, inferred from the pooled and crowd aggregates.

---

## Significant

### S1. Selection and collider bias in pool construction; the label measures co-location at edge resolution
- **Location.** `load_edge_pools` L105–143.
- **Problem.**
  - The crowd pool keeps only edges with at least one crowd report. 899 of the 1,017 edges with an official point have no crowd report, and they are dropped from the study completely; they are in neither pool. So the positives are "official AND crowd on the same directed edge", which is a co-location event.
  - The label is badly sensitive to spatial granularity:
    - 456 negative edges have an official point within 100 m, nearly four times the 118 positives.
    - 1,477 negatives have one within 200 m.
    - 86% of positives have one within 100 m.
  - Each crowd "observation" is one OSM way, placed at its first sub-segment's midpoint (`t31_build_replay_corpus.py` L100–109). A flooded street therefore gives evidence to one edge only. An official point on another edge of the same flooded street yields y = 0.
- **Why it matters.**
  - The y = 0 class is not just "unconfirmed". It is largely "confirmed nearby, on a different edge". This is label noise far larger than ADR-012 admits.
  - Conditioning on "has a crowd report" also removes nearly all predictor variation: 96.7% of crowd edges have exactly one report. So within the pool the crowd evidence cannot discriminate by construction. Kernel-sum AUROC is 0.515; Beta's ranking, which uses crowd counts only, scores 0.494 to 0.515.
  - The informative contrast was the one discarded. Over all edges, P(official | crowd) = 118/4,876 = 2.4%, against P(official | no crowd) = 899/466,364 = 0.19%. That is a risk ratio of about 12.5.
- **Suggested fix.** Build the label at a spatial support that fits both sources (buffer, OSM way, or fixed segment). Evaluate on a population that includes edges with and without crowd reports.
- **Confidence.** High.
- **Evidence.** `a2.py` (official-edge overlap counts) and `a6.py` (KD-tree distances in a local metric projection).

### S2. Calibration-in-the-large reflects the proxy's base rate, not the hazard probability
- **Location.** Sec. VI-D ("predicted probabilities far above observed frequencies"); Fig. 3 caption.
- **Problem.**
  - The proxy's prevalence (2.4% of crowd edges) is set by how many GCC points exist and how they snap. It does not represent P(flooded).
  - The prior's category probabilities (0.02 to 0.45) and the crowd weight α = 0.6 are meant to represent P(flooded). A gap between 0.10 mean prediction and 0.024 observed frequency is therefore uninterpretable; it may be the label, not the model.
  - The reliability diagrams also show something the paper does not state: the observed frequency is flat across predicted bins. At 0 h:

    | Mean predicted p | Observed frequency | 95% Wilson interval |
    |---|---|---|
    | 0.080 | 0.025 | [0.020, 0.030] |
    | 0.277 | 0.023 | [0.016, 0.032] |
    | 0.449 | 0.035 | [0.012, 0.098] |

    A higher predicted p does not mean a higher label rate.
- **Why it matters.** "Over-prediction" is the paper's main qualitative calibration finding, and it does not identify a model defect.
- **Suggested fix.** Say the gap is uninterpretable under a proxy whose prevalence is arbitrary. Show bin counts and confidence bands on Fig. 3, preferably as CORP diagrams with consistency bands (Dimitriadis, Gneiting & Jordan, PNAS 2021).
- **Confidence.** High.
- **Evidence.** `a5.py`: equal-width 5-bin counts and Wilson intervals at ages 0, 6 and 168 h.

### S3. The Beta-reputation baseline is structurally crippled, and the paper and ADR-012 misdiagnose why
- **Location.** `study_common.beta_reputation_p` L382–417; ADR-012 point 6; paper Sec. VI-D ("largely because it falls back to 0.5 where no reports exist").
- **Problem.**
  - The implementation has no base rate. It computes E[Beta(r+1, s+1)] = (r+1)/(r+s+2), and the corpus has only positive reports (s = 0), so p ≥ 0.5 on every row. The minimum p on the crowd pool is exactly 0.5.
  - So the 0.5 fallback on no-report edges is not the main cause. On the crowd-only pool, where every edge has reports, Beta still scores Brier 0.299.
  - Beta also differs from C2/C3 on more than decay:
    - It weights by α linearly rather than by logit(α).
    - Its forgetting rate of 0.9 per hour is a time constant of about 9.5 h, against 2 h for C2/C3.
    - It gets no prior.
  - The comparison therefore does not isolate "the decay mechanism", contrary to the docstring at L389–392.
  - The repo flags the formulation as [UNVERIFIED DETAIL], since the primary paper was not opened. The paper cites it as Jøsang & Ismail without that caveat.
- **Why it matters.** The paper's explanation is factually wrong. And a baseline that cannot express any probability below 0.5 is a straw man.
- **Suggested fix.** Use the subjective-logic form with a base rate, p = (r + W·a)/(r + s + W), with a = the edge's prior probability and W fitted on training data. Match the evidence weighting (logit α) so that only the forgetting function differs. Verify against the primary source before citing.
- **Confidence.** High.
- **Evidence.** `a4.py`: Beta with a = prior and W = 10 gives Brier 0.0398 and AUROC 0.550, against C3's 0.0392 and 0.566. With W = 2 it gives Brier 0.0626. The 0.30 vs 0.04 gap mostly disappears once Beta gets a base rate.

### S4. No uncertainty quantification, and rows are pseudo-replicated
- **Location.** Table III; `compute_metrics_table`.
- **Problem.**
  - Each crowd edge appears in six rows (one per age), and each pooled metric treats the 29,256 rows as independent. The independent units are 4,876 edges with 118 positive edges. 708 "positives" means 118 edges × 6.
  - Half the rows (24 h and later) are identical prior-only predictions for all decay variants.
  - No confidence intervals are reported. The paper prints AUROC to three decimals (0.609, 0.609, 0.609) and Brier to four, which suggests a precision the data cannot support.
- **Why it matters.** With 118 positive edges, the AUROC has a 95% half-width of about ±0.04 to ±0.05. Any C3-vs-baseline difference smaller than that cannot be detected, and the decay comparison is null by construction anyway.
- **Suggested fix.**
  - Report n in edges.
  - Report per-age metrics or a single age, not a pool over ages.
  - Use cluster bootstrap CIs, resampling edges or, better, spatial blocks.
  - Add DeLong or bootstrap tests for paired AUROC differences.
- **Confidence.** High.
- **Evidence.** Edge-clustered bootstrap gives C3 pooled AUROC 0.567 [0.525, 0.609] and prior AUROC 0.569 [0.529, 0.611]. ΔAUROC(C3 at 0 h − prior) is −0.0045 [−0.0108, 0.0013]. The Hanley–McNeil standard error at AUC 0.566 with 118 and 4,758 edges is 0.028.

### S5. The "official" label is partly a susceptibility designation, not an event observation, so it is circular with the prior in kind
- **Location.** Corpus `gcc_flood_hotspots_2015.kml` (327 points); paper Sec. V-A/V-D.
- **Problem.**
  - The hotspot records carry `vulnerability` ("Low Vulnerability") and `inundation_ft_band` ("<2ft", "3 to 5 ft") fields. These look like GCC's designated vulnerable locations, a hazard map, rather than dated 2015 observations. The prior is also a GCC hazard map.
  - Content leakage turned out to be weak in practice. Among all observed edges, prior AUROC for official-vs-crowd-only is 0.511 (0.524 for the hotspot layer, 0.505 for stagnation). But that only shows the two GCC products disagree. It does not make the hotspot layer ground truth.
  - The stagnation layer (753 points, 70 of the 118 positives) has no date either.
- **Why it matters.** The paper calls the label "official observation". For about a third of the positives it may be a planning designation. Separately, the hotspot depth bands are the only depth-like information in the corpus, and they were discarded.
- **Suggested fix.**
  - Describe each layer's provenance precisely. Ask OpenCity or GCC whether the stagnation points are event-dated.
  - If they are, use the stagnation layer alone as a spatial label.
  - Use `inundation_ft_band` as an ordinal depth label for the chance-constraint threshold.
- **Confidence.** Medium. The field names are clear, but the layer's provenance was not checked at source.
- **Evidence.** Corpus `raw` fields (`a1` session listing). Positives by source: 70 stagnation only, 40 hotspot only, 8 both.

---

## Minor

### M1. The Murphy identity gap is a binning artefact, which is correct but unexplained
- **Location.** `brier_murphy_decomposition` L499–538; Table III, and `\CthreeRes` against `\CalUnc` in Sec. VI-D.
- **Problem.** For C3, reliability − resolution + uncertainty = 0.033884, while Brier = 0.034341. The gap is 4.57e-4, or 1.3%. For Beta it is 0.2%. This is expected for continuous forecasts binned into 10 equal-width bins. The gap is exactly the two within-bin terms of Stephenson, Coelho & Jolliffe (Weather and Forecasting 23, 2008): within-bin variance (WBV) minus twice the within-bin covariance (WBC). The code computes `decomposition_check` but never tests or reports it. The paper prints reliability and resolution that do not sum to the printed Brier.
- **Fix.** Either report the two extra terms or use the CORP decomposition (isotonic recalibration), which is exact: MCB − DSC + UNC = Brier.
- **Confidence.** High.
- **Evidence.** On the crowd pool for C3, WBV = 7.032e-4 and −2·WBC = −1.778e-4. Their sum closes the identity to 1e-15. The same holds for C4 and Beta.

### M2. Equal-width bins underestimate resolution by about half
- **Problem.** 81% of predictions fall below 0.2 and 57% below 0.1, so 10 equal-width bins lump most rows together.
- **Evidence.** For C3 on the crowd pool:

  | Method | Resolution |
  |---|---|
  | Equal-width bins (as reported) | 6.8e-5 |
  | Quantile bins | 1.31e-4 |
  | CORP (DSC) | 1.17e-4 |

  CORP's MCB is 0.0157. The qualitative conclusion ("resolution ≈ 0.5% of uncertainty") stands.
- **Fix.** Use CORP or quantile bins and report the binning choice.
- **Confidence.** High.

### M3. Adaptive ECE implementation details
- **Problem.** `bin_size = n // n_bins` produces an 11th bin of n mod 10 rows (6 rows for n = 34,256). Ties are split by a stable sort on input order, so heavily tied predictions straddle bin edges arbitrarily: 23% of crowd edges sit at the 0.02 prior, and all no-report rows sit at prior values. With 118 positive edges, ECE is mostly noise; the reported 0.082 has no interval.
- **Fix.** Use `np.array_split` into exactly k bins, keep ties together, and bootstrap the ECE.
- **Confidence.** High that this is the code's behaviour. It has low impact on conclusions.

### M4. AUROC implementation is correct
- **Evidence.** The midrank Mann–Whitney implementation matches `scipy.stats.mannwhitneyu` exactly for all four models. No action needed beyond adding CIs (S4).

### M5. The p̃ "sanity check" is tautological
- **Problem.** mean p̃ > mean p̄ holds by definition whenever z > 0. It verifies wiring, not calibration. That is harmless if it is kept out of the paper, which it currently is.

### M6. Wording and consistency
- "All exponential-decay variants reached similar Brier scores and an AUROC of 0.609" groups C4 (fixed TTL) with the exponential models. C4's Brier is 7% worse (0.0367 against 0.0343).
- The context pack says "C2 and C4 essentially identical". That is false for Brier.
- The contributions list says "reports a calibration study whose results are weak". "Uninformative by design" would be accurate.
- Sec. VI-D's closing hedge ("we do not read these numbers as evidence for or against class-specific decay") is correct, but the abstract and conclusion contradict it.

### M7. Fig. 3 source and content
- **Problem.** The paper includes `fig_reliability`. The repo figure is `figure4_reliability_diagrams.png`: 5 equal-width bins, no counts, no CIs, and six panels, half of which are identical (24, 72 and 168 h). It shows no information beyond one panel.
- **Fix.** Replace it with one CORP diagram per real age bin once real ages exist. For now, show one panel with counts.

---

## Paper claims audit (sentence by sentence)

| # | Location | Claim | Supported? |
|---|---|---|---|
| 1 | Abstract | "calibration study … found weak discrimination (AUROC 0.61)" | **No.** 0.61 is inflated by easy negatives (C5). Crowd-pool AUROC is 0.566 [0.525, 0.609]. Within the label's coverage it is 0.49 (C4). The accurate phrasing is "no detectable discrimination beyond coverage and edge-length artefacts". |
| 2 | Abstract | "no advantage of class-specific decay over simpler baselines" | **No (untestable).** True by construction (C1). It should read "the study could not test decay". |
| 3 | Contributions | "reports a calibration study whose results are weak" | Partly. The study is uninformative by design. |
| 4 | Sec. V-D | "labelled positive if it has an official observation; predictors see only crowd reports and the prior" | Incomplete. It omits that positives must also have a crowd report on the same edge (899 of 1,017 official edges excluded), the 5,000 random negatives, and the GCC provenance shared with the prior. |
| 5 | Sec. V-D | "34,256 edge–age rows with 708 positives" | **Wrong or misleading.** 29,256 edge–age rows plus 5,000 no-report rows; 118 positive edges. |
| 6 | Sec. V-D | "beta reputation model with forgetting [Jøsang & Ismail 2002]" | Implementation unverified against the source (repo flag) and has no base rate (S3). |
| 7 | Sec. VI-D | "All exponential-decay variants … similar Brier … AUROC 0.609" | Numbers are right, but C4 is not exponential and the similarity is by construction. |
| 8 | Sec. VI-D | "C3 indistinguishable from C2" | True and tautological: T = 7200 vs 7300 s, single class (C1). |
| 9 | Sec. VI-D | "Resolution almost zero (6.9e-5 vs 0.0202)" | Qualitatively yes. Numerically about 2× too low (M2). It omits the negative Brier skill (C3). |
| 10 | Sec. VI-D, Fig. 3 | "predicted probabilities far above observed frequencies" | True but uninterpretable under the proxy (S2). The flat observed frequency (no resolution) is the real signal. |
| 11 | Sec. VI-D | "beta … worst, largely because it falls back to 0.5 where no reports exist" | **Wrong.** Beta is at least 0.5 on every row, including the crowd pool, where Brier is 0.299 (S3). |
| 12 | Sec. VI-D | "On the crowd-only pool, C3 reached 0.566" | Yes. Add a CI and the prior-only (0.568) and edge-length (0.651) baselines. |
| 13 | Sec. VI-D | "we do not read these numbers as evidence for or against class-specific decay" | Correct, but it conflicts with #2 and with the conclusion. |
| 14 | Conclusion | "Calibration against a proxy label was weak and did not favour class-specific decay" | Same as #1 and #2. |
| 15 | Table III caption | "34,256 rows, 708 positives" | Same as #5. Report edges. |

**Suggested replacement paragraph for Sec. VI-D** (if the study is kept as a negative note): "With no time-indexed ground truth, we scored the fused belief against a source-holdout proxy: whether an edge with a crowd report also carries a GCC point. The proxy cannot test decay. All reports share one timestamp, so simulated ages apply one global shrinkage, and the crowd pool contains only the flood class, which makes class-specific and single decay identical to within 0.001. All models scored worse than a constant base-rate forecast (Brier skill −0.66 on 4,876 crowd edges, 118 positive). The prior alone scored better than the prior plus crowd reports. Discrimination (AUROC 0.57 [0.53, 0.61]) disappeared within the GCC-mapped area (0.49) and was exceeded by edge length alone (0.65), so it reflects the proxy's sampling frame, not hazard."

---

## Questions for the authors

1. Are the `gcc_stagnation_2015` points event observations with dates held somewhere (GCC or OpenCity), or a cumulative list? The same question applies to the hotspots layer.
2. Can `chennai_prior_ell0.json` be supplied, so the no-report pool can be reproduced row by row? It is missing from the upload.
3. Which point of a crowd OSM way is snapped? The code comment says the first sub-segment's midpoint. Was way-level (multi-edge) assignment considered?
4. Is `fig_reliability` in the paper the repo's `figure4_reliability_diagrams.png`? Where are its source data and binning documented?
5. Why were the 899 official-only edges excluded rather than included with prior-only predictions?

---

## Design: the minimum valid calibration study on real, time-stamped Chennai data

### What the study must establish
1. The fused p̄(e, t) is calibrated against an independent, time-indexed label, overall and by real report age.
2. Fusing reports adds skill over the prior alone and over climatology.
3. If and only if the data contain repeated observations at varying ages: whether exponential decay (and class-specific T_c) beats TTL or a single T.

### Candidate data (status checked 2026-10-01)

| Source | Time-stamped? | Negatives? | Independent of predictors? | Size | Verdict |
|---|---|---|---|---|---|
| chennaiwaterlogging.org (IIT-M with GCC/PWD), Dec 2023 | Yes, per report | Yes: the depth slider includes shallow or no water | Independent of the GCC prior; same "crowd" type as the predictor, but distinct reports | About 1,200 users on 4–5 Dec 2023, about 2,000 in total (Citizen Matters 2023, per notes). The archive must be requested from Prof. Balaji Narasimhan's group | **Primary.** The only known source with enough timed, graded reports for decay and calibration |
| CFM-DSS `crowdsourced` layer (HF mirror `CashlessConsumer/chennai-flood-history`) | Yes (`imagetimestamp`) | Yes ("No water …") | Yes | **Only 173 reports**, 2022-11 to 2025-12, about 168 in Nov 2025, levels mostly 1–2, rounded coordinates, test entries, licence unstated (HF page, read 2026-10-01) | Too small for calibration. Use as an out-of-event pilot or sanity test only |
| osm-in "Flooded Streets" 2015 | Snapshot only | `is_flooded` field | **No.** It is almost certainly the same source as the corpus's crowd layer: fields `osm_id`, `segment_length_km`, and the `is_flooded=0` exclusion in T3.1 | About 2,500 streets | Not usable as a label |
| NRSC 2015 inundation extent (4,001 polygons, HF `chennai-flood-history`) | One date (early Dec 2015) | Yes (outside the extent) | Yes (satellite, not GCC or crowd) | City-wide | Secondary spatial-only check of the prior and of crowd fusion. Cannot test decay. SAR or optical misses narrow urban streets (Sundaram et al. 2023 caveat) |
| GCC hotspots NEM 2020 (53 points) | Season only | No | Same agency as the prior | 53 | Not adequate |
| Prospective NE monsoon 2026 (Oct–Dec) collection | Yes | Yes, by design | Yes, by design | Depends on effort | **Primary, alongside 2023.** Monsoon onset is weeks away, inside the build window |

### Protocol A: retrospective, prequential, Dec 2023 (chennaiwaterlogging.org archive)
- **Forecast times.** t_k every 3 h from 1 Dec 00:00 to 8 Dec 00:00 IST.
- **Predictor at t_k.** The GCC prior plus all archive reports with timestamp < t_k, snapped to edges with the production kernel, each with its real age. Same-user reports are kept but deduplicated.
- **Verification event.** Any report r with t_k < time(r) ≤ t_k + H (H = 3 h), on edge e (or within 50 m of it). Label y = 1 if depth ≥ h* (fix h* in advance, e.g. 15 cm, or slider level ≥ "ankle"), else 0.
  - Exclude r from its own predictor.
  - Exclude predictor reports by the same user within 30 min of r, to avoid self-confirmation.
  - Collapse multiple verifications of one (edge, window) by majority vote, so the unit is (edge, window).
- **Why this label is valid.**
  - It is time-indexed, so p̄(t) is scored against the state at t.
  - It has real negatives.
  - It is future relative to every predictor input, so there is no leakage.
  - Ages vary naturally, so decay is identifiable.
  - Remaining bias: verification is conditional on someone reporting (missing not at random). State the estimand as "calibration conditional on a report arriving", which is exactly the sensor model the router uses.
- **Splits (pre-registered).**
  - (i) *Temporal*: fit any free parameter (α_crowd, T_c, prior category recalibration, the Beta W) on 1–4 Dec and test on 5–8 Dec.
  - (ii) *Spatial*: leave-one-GCC-zone-out (15 zones), or 2 km blocks, to show the result is not one neighbourhood.
  - (iii) *Event*: 2023-fitted parameters frozen and tested on the 2026 prospective data (Protocol B), plus the 2025 CFM-DSS reports as an extra small test.
  - Never split randomly by row (docs/EVALUATION.md already requires this).

### Protocol B: prospective, NE monsoon 2026 (safe, cheap, pre-registered)
- Freeze the model and parameters before the first heavy-rain day, and publish the hash.
- On each rain day (IMD orange or red alert), sample about 40 edges at 3 fixed times. Stratify by predicted p̄ in quartiles, oversampling the top quartile so that positives are not rare, and record the inclusion probabilities.
- Verify from public safe vantage points or with volunteers' timestamped photos: walk-by, a team member's own commute, or residents' WhatsApp groups with a structured form. Record depth band, including "no water". Never verify by driving into water.
- Optionally add Chennai Traffic Police or GCC subway-closure announcements as a binary closure label for the about 20 subways. Collect them with their timestamps; their completeness needs checking.
- Weight metrics by inverse inclusion probability.

### Metrics (all with cluster bootstrap CIs, resampling (spatial block × day) clusters)
- **Proper scores.** Brier, and log score with clipping stated.
- **Skill against references.** Brier skill against climatology (the base rate of the test window) and against prior-only. Skill against prior-only is the key result: does fusing reports help?
- **Calibration.** CORP reliability diagram with consistency bands, and the exact CORP decomposition (MCB, DSC, UNC). Logistic recalibration intercept and slope, with the ideal being (0, 1).
- **Discrimination.** AUROC and AUPRC (positives may be rare), reported separately.
- **Decay test.** All of the above stratified by real age of the newest contributing report: [0, 1), [1, 3), [3, 6), [6, 12), [12, 24) and ≥24 h. Model comparison by paired score differences per verification unit (Diebold–Mariano style, or a cluster bootstrap of ΔBrier and Δlog-score).
- **Router-relevant check.** Calibration of p̄ in the region the router acts on (p̄ ≥ 0.3), and the rate of verified "deep water" (≥ h_max) on edges with p̄ < ε, which is the chance constraint's failure mode.

### Baselines (each given the same inputs and a fair fit on the training split)
1. Climatology: constant base rate from training.
2. Prior only, plus a recalibrated prior (logistic on ℓ0, fitted on training data).
3. Crowd only: Beta with base rate (r + W·a)/(r + s + W), with a = training base rate and W fitted.
4. Fused with a single T, fitted (C2).
5. Fused with TTL, fitted (C4).
6. Fused, class-specific (C3). Only if at least 2 hazard classes have ≥50 verifications in the test set; otherwise declare it untestable and drop the claim.
7. A nuisance-control reference: logistic on (ℓ0, Σ weighted reports by age bin, edge length, road class). This shows how much skill comes from structure the belief ignores, and guards against an edge-length artefact like C4 above.
8. Beta with forgetting per Jøsang & Ismail, verified against the primary source.

### Sample size and go/no-go
- **Calibration validation needs about 100 events and 100 non-events at minimum, preferably 200 or more events.** Vergouwe et al. 2005 (J. Clin. Epidemiol.) and Collins, Ogundimu & Altman 2016 (Stat. Med.) give this rule for validating binary prediction models; Riley et al. 2021 (Stat. Med.) give a formal method. The references are from memory and need verifying before citing. These counts are of *independent* units. With m verifications per cluster and intra-cluster correlation ρ, the effective n is n / (1 + (m−1)ρ).
- **AUROC precision.** Hanley–McNeil at AUC 0.70 gives a 95% half-width of ±0.084 with 50 positives and 450 negatives, ±0.059 with 100 and 900, and ±0.042 with 200 and 1,800. The current study's 118 positive edges give ±0.054 at AUC 0.57.
- **Reliability bins.** A per-bin observed frequency near 0.3 has a standard error of 0.072 with n = 200 (5 bins) and 0.046 with n = 500. Bin-level claims need n of 500 or more.
- **Decay comparison.** To estimate age-stratified calibration, have at least about 50 verifications with ≥20 positives in each of at least 4 real-age bins of the *test* split. That is about 200 to 300 test verifications, plus a training split of similar size.
- **Go/no-go rules.**
  - Before analysis, count verification units in the 2023 archive.
  - Fewer than 200 test units with ≥100 positives and ≥100 negatives: report Protocol A as a pilot only.
  - Fewer than 4 age bins meeting the per-bin minimum: make no decay claim at all.
  - CFM-DSS (173 reports) alone fails these thresholds; use it only as an extra out-of-event check.

### What the paper can claim after this
- With Protocol A or B passing the thresholds: "p̄ is (or is not) calibrated on independent, time-indexed Chennai reports. Fusing reports improves (or does not improve) the Brier score over the prior by X [CI]. Decay variant D is preferred by Δ [CI]."
- Until then the paper should claim nothing about calibration or decay beyond: "the proxy study could not test them".
