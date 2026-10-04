# S2 — Novelty of the belief / uncertainty layer (CityPulse AI)

Reviewer: S2 (novelty, belief layer only). Scope: log-odds fusion, per-class decay, pessimistic plug-in p~, per-user-class z, the "confidence-multiplied penalties are risk-seeking under ambiguity" argument, ALT consistency, and the proposed traversal-silence evidence. Experiment statistics, code quality and business are out of scope. They appear here only where they change a novelty verdict.

Sources read: `IDEA_AND_FACTS.md`; `drafts/paper.tex` (Sections I–III, plus the conclusion where it states future work); `drafts/plan.tex` (novelty audit, Sections 6–7); `drafts/litreview.tex` (Sections on crowd evidence, belief and synthesis); research notes `uncertain_routing.md` and `crowd_flood_sensing.md`. I also read three repository files, without modifying them, to settle questions of fact: `packages/pulse_belief/lib/src/pessimistic.dart`, `fusion.dart`, `pulse_router/lib/src/cli_io.dart`, `config/hazard_classes.yaml` and `docs/DECISIONS.md` (ADR-002).

Numerical checks: I wrote a short script (scratchpad `ptilde.py`) that reproduces Eq. (1)–(3) of paper.tex. It shows how p~ moves as a single report ages, for priors {0.02, 0.10, 0.25, 0.45}, reliabilities α ∈ {0.6, 0.8, 0.95}, 1 or 3 reports, and z ∈ {0, 1.28, 2}.

---

## Verdict table (claim by claim)

| # | Claim (location) | Closest prior work | Delta | Verdict |
|---|---|---|---|---|
| 1 | Log-odds fusion of a static prior with decaying, source-weighted reports (paper.tex L78–85, Eq. 1–2) | Occupancy-grid log-odds (Elfes 1989, cited); beta reputation with forgetting (Jøsang & Ismail 2002); persistence filter (Rosen et al. 2016) | Applied to road-edge flood belief with a spatial kernel | **Known** (application). It is correctly not claimed as a contribution. |
| 2 | Per-hazard-class decay T_c (L79–82; plan L138; litreview) | Jøsang & Ismail 2002 (forgetting factor "adjusted according to the expected rapidity of change in the observed entity"); Biber & Duckett 2005 (several forgetting timescales); Rosen et al. 2016 (survival-time prior per feature) | Class-specific constants, currently placeholders. Study 2 finds C3 ≈ C2. | **Known** and empirically unsupported. Claim only fitted survival times once time-stamped data exist. |
| 3 | Pessimistic plug-in p~ = min{1, p̄ + z√(p̄(1−p̄)/(n_eff+1))} (L87–92; contribution bullet 1, L58) | Exactly the mean + z·sd of a Beta distribution with mean p̄ and concentration n_eff. This is a normal-approximation Bayes-UCB (Kaufmann et al. 2012) on a forgetting-weighted beta-reputation estimate (Jøsang & Ismail 2002). Related: pessimism/LCB in offline RL (Jin, Yang & Wang 2025); IDM upper probability (Walley 1996); robust routing on confidence intervals (Flajolet et al. 2018); μ+kσ risk costs on planning graphs (Fan et al. STEP 2021) | First use on crowd-fed per-edge flood probability. The specific n_eff construction has defects (see S2, C2). | **Incremental.** It is overclaimed as "a formulation" and as an "upper bound". |
| 4 | Per-user-class z (L92; plan L141) | Lo, Luo & Siu 2006 (multi-class travellers with heterogeneous risk aversion, travel-time budget); Kang, Batta & Kwon 2014 (route depends on chosen confidence level); STEP 2021 (risk level α set by mission/robot role) | Applied to a hazard-probability band rather than to travel time or CVaR level | **Incremental.** For z = 2 it is functionally degenerate on this prior (C2). |
| 5 | "Confidence-multiplied penalties are risk-seeking under ambiguity" (L94; contribution bullet 1; plan L141 "Defensible") | Ellsberg 1961; Gilboa & Schmeidler 1989 (maxmin EU); Walley 1996 (upper probabilities); Jin et al. 2025 (pessimism vs optimism) | Articulated for hazard routing | **Known decision theory, mislabelled, and not true of CityPulse's own decay path** (C1, S1). |
| 6 | ALT consistency under hazard costs (Prop. 1, L103–109) | Delling & Wagner 2007 (abstract: ALT "still performs correct queries as long as an edge weight does not drop below its initial value"); Nannicini et al. 2012 | None | **Known.** paper.tex already credits it. Downgrade to a remark (M1). |
| 7 | Traversal silence as negative evidence (paper L255 future work; plan L151 "the moat… nobody can buy it", L176; litreview L106 "rarely modelled") | Pietrobon et al. 2019 (HERE: closure from improbable probe activity); Song et al. 2015; Kong et al. 2022; She et al. 2019; Hiramoto et al. 2025; Hara, Sasabe & Kasahara 2019 (phone trajectories mark segments passable for offline evacuation routing); Rosen et al. 2016 (missed detections as evidence); Koch 2007 ("negative" sensor evidence); Agostini et al. 2024 (under-reporting as positive-unlabeled data) | Possible delta: a calibrated joint belief with decaying reports and a prior; MNAR handling; and the router-induced censoring loop (S4) | **Known idea; overclaimed as a moat.** The defensible novelty lies in the feedback-loop and calibration problem, not in the signal. |
| 8 | "Combination not addressed" (litreview synthesis; plan L142) | Hara et al. 2019 / Komatsu et al. (offline phone routing on per-segment blockage probabilities from a municipal prior, updated by device trajectories); Rohmann & Bachem 2026 (empirical-Bayes per-edge risk posterior with uncertainty propagated into routing) | Decay, pessimism, verified explanation | **Partly pre-empted.** It remains defensible only with these works cited and the list narrowed. |

---

## Critical

### C1. The central pessimism claim fails on the actual decay path: an ageing positive report lowers p~ at every z
**Location.** paper.tex L92 ("thin evidence produces more caution, not less"); L94 ("Equation (3) reverses the direction of that dependence"); contribution bullet L58; plan.tex L141; repository ADR-002 ("thinner evidence *raises* caution").

**Problem.** The monotonicity statement is a partial derivative at fixed p̄. When a positive flood report ages, ω → 0 moves both terms at once: p̄ falls back toward the prior and n_eff falls toward 0. The fall in p̄ dominates. Representative values from Eq. (1)–(3), with one fresh report of α = 0.8 that then ages (ω = 1 → 0):
- prior 0.02, z = 0: 0.075 → 0.020; z = 1.28: 0.315 → 0.199; z = 2: 0.449 → 0.300.
- prior 0.10, z = 2: 0.960 → 0.700. Prior 0.02 with 3 reports, z = 2: 1.000 → 0.300.

p~ decreases monotonically with age in every tested case with α ≥ 0.8 and every z. The only cases where p~ rises with age are weak reports (α = 0.6), where the report barely moves p̄. For negative reports the claimed direction does hold (prior 0.25, α = 0.8, z = 2: 0.454 → 1.0).

So CityPulse also makes "an unverified or ageing flood report make the road look clear[er]", which is the behaviour the paper attributes to the strawman w = τ0(1 + λRC). The real differences are two:
- An aged report decays to the prior plus an ignorance band instead of to zero.
- For z = 0, the commuter default, it decays to the prior exactly.

**Why it matters.** This is the paper's only conceptual novelty argument for the belief layer (contribution bullet 1). A referee who runs three numbers will find that the system does not have the property the text asserts. Because all 6,132 corpus reports are positive, the claim is also untestable on the paper's own data in the direction it is made.

**Suggested fix.**
- State the property correctly: "for fixed p̄, p~ is non-increasing in n_eff; when evidence decays, p~ relaxes to p0 + z√(p0(1−p0)), not to 0".
- Drop "reverses the direction". Present the comparison as three floors: R·C decays to 0, a Bayesian posterior decays to the prior, and p~ decays to the prior's upper envelope.
- If the team wants caution that does not fall as a positive report ages, it must decay evidence toward ambiguity, not toward the prior mean. One option is the subjective-logic opinion (Jøsang 2001, in refs), where aged evidence moves mass into uncertainty u and a pessimistic base rate keeps the projected probability high. Another is Walley's IDM-style upper probability. Either is a design change, and it should be evaluated.

**Confidence.** High. This is arithmetic on the paper's own equations, and the code computes n_eff exactly as in Eq. 2 (`fusion.dart`: "unsigned").

**Evidence.** paper.tex Eq. (1)–(3); `pessimistic.dart`; scratchpad `ptilde.py` output.

### C2. The z dial saturates. For the emergency class the "belief layer" reduces to a static prior-zone mask
**Location.** paper.tex L90–92 (per-class z); plan L63, L141; `config/hazard_classes.yaml` (emergency z = 2.0, pedestrian z = 1.28).

**Problem.** p~ = 1 whenever p̄ ≥ 1/(1 + z²/(n_eff + 1)). With no evidence the threshold is 1/(1 + z²):
- z = 2: 0.20
- z = 1.28: 0.38
- z = 1: 0.50

All 8,759 prior-only configured edges have p0 ≥ 0.25 (IDEA_AND_FACTS). For the emergency class they are therefore pinned at p~ = 1 with zero evidence. Further positive reports cannot raise caution, so evidence is ignored. A single fresh negative report (α = 0.8, ω = 1) on a 0.25-prior edge brings p~ only to 0.45. ADR-002 itself notes that the unclamped value "routinely exceeds 1" for the emergency class and calls the clamp "load-bearing". The clamp hides the saturation; it does not remove it.

**Why it matters.** "A per-user-class caution parameter" is part of contribution bullet 1. For the class the pessimism argument is built around (ADR-002: "the opposite of what an ambulance needs"), the mechanism behaves like hard blocking of GCC hazard zones. Its novelty over C1 (threshold blocking) is then nil in that regime. This may also explain part of the null z result in Section V-C, which belongs to another reviewer's scope.

**Suggested fix.**
- Replace the Wald band with a Beta posterior quantile that has an explicit prior pseudo-count n0: Beta(n0·p0 + Σ⁺, n0·(1 − p0) + Σ⁻). This is Bayes-UCB (Kaufmann et al. 2012), or a Wilson bound as the conclusion already proposes.
- Report the share of edges with p~ = 1 for each class in a table.
- Present z as a quantile level, not a free multiplier.

**Confidence.** High for the arithmetic. Medium on how much this affects routes, because that depends on λ and the edge mix.

**Evidence.** Closed form derived from Eq. (3); `pessimistic.dart` doc comment; DECISIONS.md ADR-002 ("Verified 2026-09-12" paragraph).

### C3. The pessimistic plug-in is a known construction. Contribution bullet 1 overclaims it as "a formulation"
**Location.** paper.tex L58 (contribution 1), L87–92 ("This mirrors the upper confidence bounds of bandit algorithms [Auer] but is used pessimistically"); plan L141 ("Defensible").

**Problem.**
- The variance of a Beta distribution with mean p̄ and concentration a + b = n_eff is p̄(1 − p̄)/(n_eff + 1), exactly the term inside the root. So p~ is "posterior mean + z posterior s.d." of a moment-matched Beta.
- That is a Gaussian-approximation Bayes-UCB index (Kaufmann, Cappé & Garivier, AISTATS 2012: "Bayesian index policies that rely on quantiles of the posterior distribution") applied to a beta-reputation estimate with forgetting (Jøsang & Ismail 2002: Beta(r + 1, s + 1) with a forgetting factor).
- Using an upper quantile pessimistically in place of optimistically is the PEVI construction of Jin, Yang & Wang (MOR 2025): the penalty "simply flips the sign of the bonus function".
- Walley's imprecise Dirichlet model (JRSS-B 1996) gives upper probabilities that are "initially vacuous… [and] become more precise as the number of observations increases", which is precisely "thin evidence → more caution".
- In planning, risk-aware costs of the form μ + σ·φ(Φ⁻¹(α))/(1 − α) with α chosen per mission or robot role are used with A* by Fan et al. (STEP, RSS 2021).
- Per-class risk aversion in route choice is in Lo, Luo & Siu (TR-B 2006).

The only element not found elsewhere is the specific n_eff = Σω, and that is the weakest part (S2).

**Why it matters.** At the IEEE-conference bar, a first contribution that reviewers can map line for line onto Bayes-UCB plus beta reputation will be judged known. The plan's "Defensible" rating is too generous.

**Suggested fix.** Demote it from a contribution to "Design" and cite the precedents. Suggested wording:
> "Following pessimism under limited data in offline RL [Jin] and Bayesian quantile indices [Kaufmann], we route on an upper quantile of a Beta-approximated edge posterior whose concentration is the decayed evidence weight; the quantile level is set per user class, as in risk-level selection for robot planning [STEP] and multi-class risk-averse route choice [Lo]."

If a contribution is wanted here, make it empirical: show on independent labels that pessimism reduces missed hazards per minute of detour. The paper itself says this cannot yet be shown.

**Confidence.** High. All seven precedents were opened (see Evidence). Jin 2025, Flajolet 2018 and Lo 2006 were also verified in research notes or abstracts.

**Evidence.** proceedings.mlr.press/v22/kaufmann12.html; mn.uio.no/…/ji2002-bled.pdf; pubsonline.informs.org/doi/10.1287/moor.2022.0216 (via notes); exa record of Walley 1996, DOI 10.1111/j.2517-6161.1996.tb02065.x; arxiv.org/abs/2103.02828; ideas.repec.org/a/eee/transb/v40y2006i9p792-806.html.

---

## Significant

### S1. "Risk-seeking under ambiguity" is the wrong term, and the comparison is a strawman
**Location.** paper.tex L94 and contribution bullet 1; plan L141; ADR-002.

**Problem.**
- Risk-seeking is an attitude toward known variance. What the paper describes is shrinking the hazard estimate toward zero as evidence ages, which is an optimistic default prior. The decision-theoretic name for preferring the favourable end of an ambiguous set is ambiguity-seeking. The remedy, evaluating at the upper envelope of a set of priors, is maxmin expected utility (Gilboa & Schmeidler 1989), the Ellsberg (1961) motivation, and Walley's upper probability.
- "A common alternative prices an edge as τ0(1 + λRC)" cites nothing. Per ADR-002, the only documented user of this form is the team's own original pitch.
- CityPulse at z = 0 shrinks to the prior, which is the Bayesian-neutral option. That option is neither of the two the paragraph contrasts.

**Why it matters.** A decision-theory-literate referee will mark the term as incorrect and the claim as uncited. As written, it is presented as an insight when it is a textbook consequence.

**Suggested fix.** Rewrite L94 as:
> "Scaling a penalty by a confidence that decays to zero amounts to an optimistic default: absent evidence the edge is treated as safe. Under ambiguity aversion [Ellsberg; Gilboa–Schmeidler] a safety-critical user should instead evaluate an upper probability [Walley], which Eq. (3) approximates."

Cite one deployed or published instance of confidence-multiplied scoring, or drop "common".

**Confidence.** High.

**Evidence.** uncertain_routing.md Q1 (Gilboa & Schmeidler, Ellsberg verified); Walley 1996 record; DECISIONS.md ADR-002 "Why".

### S2. n_eff is not an effective sample size, so p~ is not a bound
**Location.** paper.tex Eq. (2) L83, Eq. (3) L90 ("the router uses the upper bound"); `fusion.dart` (n_eff "unsigned, so opposing observations cancel in ℓ but still both count as evidence"); plan item 6.

**Problem.**
- n_eff = Σκ·e^(−Δt/T) ignores reliability α. A worthless report (α = 0.5, logit 0) leaves p̄ unchanged but narrows the band, so caution falls on no information.
- Conflicting reports (+ and −) cancel in p̄ but add to n_eff. Conflict therefore reads as confidence, whereas subjective logic and Dempster–Shafer treat it as a signal of ambiguity.
- Kernel weights are not counts. The Kish effective sample size is (Σω)²/Σω², not Σω.
- Correlated duplicates, which the paper acknowledges at L248, inflate n_eff further.

There is thus no model under which p~ has coverage. "Upper bound" and ADR-002's "upper confidence bound" overclaim.

**Why it matters.** The one formula element that is new is the one with no statistical justification. That is the worst combination for a novelty claim.

**Suggested fix.**
- Call p~ an "uncertainty-inflated (pessimistic) plug-in", not a bound.
- If a bound is wanted, derive both mean and width from one generative model: Beta pseudo-counts weighted by ω·(2α − 1), or by ω·logit(α) mapped to counts, plus a conflict-aware uncertainty term.
- Apply a duplicate or cluster discount before counting.

**Confidence.** High.

**Evidence.** `fusion.dart` L32–34; paper Eq. (2)–(3).

### S3. "Thin evidence → more caution" does not hold where evidence is thinnest: unconfigured edges and p̄ → 0
**Location.** paper.tex L92; L175 (14,534 configured edges); `cli_io.dart` ("An edge with no hazard data at all is simply absent from `hazards`").

**Problem.**
- Edges absent from the hazard configuration get no penalty. That is 471,240 − 14,534 ≈ 456,700 directed edges, about 97%, including prior-only edges with p0 < 0.25 that were dropped. Their evidence is zero, yet p~ = 0.
- The Wald band also vanishes as p̄ → 0: with no evidence and p0 = 0.001, z = 2 gives p~ = 0.064.
- The property therefore holds only inside the GCC prior zones, which means it holds where a static map already flags risk.

**Why it matters.** The marketed property is "caution grows as evidence thins". A reader will assume it applies network-wide.

**Suggested fix.** Give every edge a prior and an ignorance band. The IDM upper probability s/(N + s) is non-zero at N = 0. Alternatively, scope the claim explicitly: "within prior hazard zones". State how the app, as opposed to the replay harness, treats unconfigured edges.

**Confidence.** High for the replay configuration. Medium for the shipped app, whose handling I did not trace.

**Evidence.** `cli_io.dart` L66–67; IDEA_AND_FACTS (14,534 / 8,759 split).

### S4. Traversal silence is established prior art; the "moat" and "rarely modelled" claims are overclaimed
**Location.** plan.tex L151 ("the one input… nobody can buy it"), L176 (moat), L219 (Paper 2); litreview L106 ("rarely modelled"), L168; paper L255 (future work, acceptable).

**Problem.**
- Probe absence or anomaly as closure or flood evidence is established. Each of the following was opened:
  - Pietrobon, Lewis & Heverly-Coulson (ACM TSAS 2019, HERE): "compares the likelihood that every road segment… is closed or open… whenever the likelihood of the observed probe activity is too small given a historical model"; precision 92% on lower-volume roads.
  - Kong et al. 2022 (taxi passing-rate drop).
  - She et al. 2019 (GPS density per road).
  - Hiramoto et al. 2025: "presence or absence of vehicle traffic… corresponds to… the inundation area".
  - Song et al. 2015 ("sample losing rate").
- Traversal as positive passability evidence for phone routing appears in Hara, Sasabe & Kasahara (J. Ambient Intell. Humaniz. Comput. 2019): devices that pass a segment mark it passable (p_e ← 0) or blocked (p_e ← 1) and feed reliable path selection, including an offline case.
- Vehicle-class-specific passability maps from truck probe data were produced in Japan, because car trajectories "do not automatically mean that large vehicles can pass" (WCEE 2012 paper; grey literature, authors not read).
- Generic precedents: missed detections as Bayesian evidence with a survival prior (Rosen et al. 2016), and "negative sensor evidence" (Koch 2007).
- The commercial claim is the weakest. HERE, TomTom and Google own far denser probe streams than a student app, and Pietrobon et al. are HERE employees.

**Why it matters.** Paper 2 is planned around this. A referee will cite Pietrobon and Kong in the first paragraph.

**Suggested fix.** Reframe it as: "integrating a probe-traversal likelihood [Pietrobon; Kong; Hiramoto] into the same decaying per-edge belief, with traversals conditioned on vehicle class and with reporting modelled as missing-not-at-random [Agostini], and calibrating the result against independent depth ground truth". No published work in either notes file does that combination with calibration. Remove "nobody can buy it". Change the litreview to "is used in probe-based closure detection but rarely fused with crowd reports in a calibrated belief".

**Confidence.** High.

**Evidence.** doi.org/10.1145/3325912 (abstract opened); crowd_flood_sensing.md Q2 (Kong, She, Hiramoto, Song verified via Crossref); www2.itc.kansai-u.ac.jp/~sasabe/publications/hara19GeographicalRiskAnalysis.pdf; iitk.ac.in/nicee/wcee/article/WCEE2012_5300.pdf; Rosen PDF (david-m-rosen.github.io); DBLP listing for Koch, Inf. Fusion 8:28–39.

### S5. The defensible novelty is the pessimism × traversal-silence feedback loop, which no draft mentions
**Location.** Absent from paper.tex, plan.tex and litreview.tex. Relevant to plan L151, L219 and ADR-002 "Stretch".

**Problem.** A pessimistic router sends its users away from uncertain edges. Those edges then receive no traversals, so silence-based evidence never accrues, n_eff stays low and p~ stays high. The app's own data are censored by its own policy. This is the runaway-feedback structure proved for predictive policing (Ensign et al., FAT* 2018: systems "only observe crime in neighborhoods they patrol"). It is also the exploration problem of online shortest-path learning (Talebi et al. 2018; Lagos et al. 2024). Risk-averse Canadian Traveller policies show "information-seeking detours" (Lamarre & Kelly 2026). Bandits explore with optimism, while CityPulse is deliberately pessimistic. The two goals conflict, and per-class z is the natural lever: commuters at z ≈ 0 act as explorers whose traversals inform the emergency class.

**Why it matters.** Nothing in the two notes files or my searches addresses router-induced censoring of crowd passability evidence for hazard routing. This is a candidate genuine contribution for Paper 2 and much stronger than "traversal silence is evidence".

**Suggested fix.**
- Formalise the propensity of each edge being traversed under the deployed policy.
- Weight silence evidence by inverse propensity, or treat edges the router avoided as unobserved rather than as silent.
- In simulation, show that naive silence-counting under pessimistic routing yields biased beliefs, and that the correction removes the bias.
- Cite Ensign 2018 and the bandit and CTP works.

**Confidence.** Medium-high that it is unaddressed (limited search). High that the mechanism exists.

**Evidence.** proceedings.mlr.press/v81/ensign18a.html (abstract and text opened); uncertain_routing.md (Talebi, Lagos, Lamarre verified).

### S6. Per-class decay is known, and ADR-002's planned "persistence-filter derivation" contains an error
**Location.** paper.tex L79–82; litreview L110; repository ADR-002 "Stretch": "The pitched exponential is the exact observation-free marginal of that model".

**Problem.**
- Precedents for decay rates tuned to how fast the observed entity changes:
  - Jøsang & Ismail 2002: a forgetting factor "adjusted according to the expected rapidity of change in the observed entity".
  - Biber & Duckett 2005: memories that "fade at different rates depending on the timescale".
  - Rosen et al. 2016: a survival-time prior p_T per feature, whose belief "decay[s]… in the absence of any signal".
- Class-specific constants add nothing conceptually, and Study 2 shows C3 ≈ C2.
- ADR-002's derivation claim does not hold. Under a Weibull survival prior, the observation-free persistence belief follows the Weibull survival function, not an exponential. The exponential is the special case of a constant hazard rate. Rosen's filter also decays a persistence probability, not a log-likelihood-ratio weight on a fixed prior, so Eq. (1) is not its marginal for any p_T.

**Why it matters.** It is the most attractive "principled" upgrade the team lists. Presented as a derivation, it will be wrong in print.

**Suggested fix.** In the paper, cite Jøsang, Biber & Duckett and Rosen for class-specific forgetting, and claim nothing about decay until survival times are fitted on time-stamped Chennai data (2023 or 2026). If the persistence filter is adopted, present it as Rosen's model with fitted class-specific survival priors. That model also handles negative evidence natively, which unifies S4 with this item. Do not claim the exponential is its marginal unless the survival prior is exponential.

**Confidence.** High on the precedents and the maths. Medium on whether the team would have printed the ADR wording.

**Evidence.** Rosen ICRA 2016 PDF (Fig. 1 caption and Eq. 1–2 read); roboticsproceedings.org/rss01/p03.html; Jøsang & Ismail PDF §2.6.

### S7. The "combination not addressed" statement must cite and narrow around Hara et al. and Rohmann & Bachem
**Location.** litreview synthesis ("We found no work that simultaneously (i) routes on beliefs that fuse a static prior with sparse, decaying crowd evidence… (v) runs entirely on a phone"); plan L142.

**Problem.** Two works cover parts of items (i) and (v):
- Hara, Sasabe & Kasahara 2019, building on Komatsu et al.'s automatic evacuation guiding. It runs on evacuees' phones. It routes on per-segment blockage probabilities from a municipal static prior (Nagoya). It updates these from device trajectories and shared reports, and it is evaluated in an offline (no-communication) case.
- Rohmann & Bachem (IEEE IV 2026). It fuses a prior with sparse per-edge evidence (Poisson–Gamma empirical Bayes) and propagates uncertainty into risk-aware routing.

Neither has decay, pessimism or verified explanations, so the five-way combination survives, but only narrowly.

**Why it matters.** "We found no work…" without these citations is the sentence most likely to be refuted in review.

**Suggested fix.** Add both. Change (i)–(ii) to "fuses a static prior with *decaying* crowd evidence and routes on an uncertainty-inflated probability". Keep the "limit of our search" hedge.

**Confidence.** High for Hara 2019 (paper body read). Medium for Komatsu, whose metadata came from a secondary reference list (GeoInformatica 22(1):127–141, DOI 10.1007/s10707-016-0270-1), and Rohmann, which was verified in the notes.

**Evidence.** Hara PDF and researchr.org/publication/HaraSK19; uncertain_routing.md (Rohmann & Bachem verified).

---

## Minor

### M1. The ALT "Proposition" is a one-line known lemma
**Location.** paper.tex L103–109, Section V-E L242.

**Problem.** The proposition is correctly credited, but labelling it a Proposition invites a "trivial" or "known" comment. Feasibility of landmark potentials under w ≥ τ0 is reduced-cost non-negativity, stated by Delling & Wagner 2007 and Nannicini et al. 2012 ("if arc costs can only increase… the potential… is still a valid lower bound"). Edge deletion by the chance constraint (w = ∞) is covered as well.

**Suggested fix.** Rename it "Remark (after [Delling & Wagner; Nannicini et al.])" and add Nannicini. If anything new is to be said, report search-space growth (settled nodes) at λ = 20, because Delling & Wagner show ALT efficiency, not correctness, degrades under large increases.

**Confidence.** High.

**Evidence.** link.springer.com/chapter/10.1007/978-3-540-72845-0_5 (abstract opened); uncertain_routing.md (Nannicini preprint quote).

### M2. The analogy to Auer et al. UCB1 is imprecise
**Location.** paper.tex L92.

**Problem.** UCB1 adds √(2 ln t / n). Eq. (3) is a posterior-s.d. index. The closer analogues are Bayes-UCB (Kaufmann 2012) and pessimistic LCB in offline RL (Jin et al. 2025). The litreview's "Safety-critical routing needs the opposite: pessimism" (L113) is also uncited.

**Suggested fix.** Cite Kaufmann and Jin at L92. At litreview L113, cite Jin, Toumazis & Kwon 2016 and Flajolet et al. 2018.

**Confidence.** High.

### M3. Name the fusion rule for what it is
**Location.** paper.tex L81–85.

**Problem.** Kernel- and decay-weighted log-likelihood ratios with logit(α) weights form a tempered (power) naive-Bayes update. The paper already flags the conditional-independence assumption, which is good.

**Suggested fix.** Say "tempered naive-Bayes log-odds update" so that no reader mistakes it for a contribution. Note that decaying a likelihood ratio toward the prior is a heuristic, not the filtering distribution of a hidden Markov hazard state.

**Confidence.** Medium.

### M4. ADR-002's explanation example contradicts the commuter default
**Location.** ADR-002 ("one unverified report, so we routed around it").

**Problem.** At z = 0 and λ = 0.3, one unverified report changes almost no routes: 7 of 100 change, and Proposition 2 caps the penalty. A template that ever emits this sentence for commuters would be unfaithful.

**Suggested fix.** Keep the sentence out of the paper. If it is used, make it conditional on the class.

**Confidence.** Medium (outside S2 scope, noted for consistency).

---

## Questions for the authors

1. Do you intend p~ to carry a frequentist or Bayesian coverage meaning (e.g. "P(hazard) ≤ p~ with 97.7% credibility for z = 2")? If so, which generative model gives Var = p̄(1−p̄)/(n_eff + 1) with n_eff = Σω? If not, please stop calling it an upper bound or UCB.
2. In the shipped app (not the replay CLI), what p̄ and p~ does an edge outside every GCC zone and without reports receive?
3. For traversal silence, what is the realistic traversal density per segment during an alert, from your own users only? A low density means the signal is sparse exactly where the prior-zone edges are, and with z = 2 those edges are already saturated (C2).
4. Will reports be decayed toward the prior mean (current design) or toward ambiguity (C1 fix)? The choice decides whether the "risk-seeking" argument can be kept at all.
5. How will you separate "no traversal because the router avoided the edge" from "no traversal because nobody needed it" (S5)?

---

## Suggested replacement for contribution bullet 1 (paper.tex L58)
> "A cost model that separates slowdown from harm and routes on an uncertainty-inflated hazard probability, an upper posterior quantile in the sense of Bayes-UCB [Kaufmann] used pessimistically [Jin], whose level is set per user class; we show that the commonly used shrink-to-zero alternative corresponds to an optimistic default under ambiguity [Gilboa–Schmeidler], and we characterise when the inflation saturates (p̄ ≥ 1/(1+z²/(n_eff+1)))."

This keeps one small analytical result of the authors' own: the saturation condition, together with the decay-floor statement from C1. It also credits everything else.

---

## Evidence opened in this pass (beyond the two notes files)
- Delling & Wagner 2007, WEA, LNCS pp. 52–65, DOI 10.1007/978-3-540-72845-0_5: https://link.springer.com/chapter/10.1007/978-3-540-72845-0_5 (abstract)
- Pietrobon, Lewis & Heverly-Coulson 2019, ACM TSAS 5(2), DOI 10.1145/3325912: https://doi.org/10.1145/3325912 (abstract)
- Jøsang & Ismail 2002, Bled eCommerce Conf.: https://aisel.aisnet.org/bled2002/41/ ; PDF https://www.mn.uio.no/ifi/english/people/aca/josang/publications/ji2002-bled.pdf (§2.6 forgetting text)
- Rosen, Mason & Leonard 2016, ICRA pp. 1063–1070: https://david-m-rosen.github.io/publication/persistencefilter-icra/PersistenceFilter-ICRA.pdf (abstract, Eq. 1–2, Fig. 1)
- Kaufmann, Cappé & Garivier 2012, AISTATS, PMLR 22:592–600: https://proceedings.mlr.press/v22/kaufmann12.html
- Walley 1996, JRSS-B 58:3–34, DOI 10.1111/j.2517-6161.1996.tb02065.x: https://exa.ai/library/publication/w41h3186yx7 (summary); formulas via https://rdrr.io/cran/imprecise101/src/R/walley1996.R
- Lo, Luo & Siu 2006, TR-B 40(9):792–806: https://ideas.repec.org/a/eee/transb/v40y2006i9p792-806.html (abstract)
- Ensign et al. 2018, FAT*, PMLR 81:160–171: https://proceedings.mlr.press/v81/ensign18a.html
- Koch 2007, Information Fusion 8:28–39 (DBLP listing only): https://www.sigmod.org/publications/dblp/db/journals/inffus/inffus8.html
- Biber & Duckett 2005, RSS, DOI 10.15607/RSS.2005.I.003: https://www.roboticsproceedings.org/rss01/p03.html
- Fan, Otsu, Kubo, Dixit, Burdick & Agha-mohammadi 2021, STEP, RSS: https://arxiv.org/abs/2103.02828 (authors, risk-level-by-mission text)
- Hara, Sasabe & Kasahara 2019, J. Ambient Intell. Humaniz. Comput. 10(6):2291–2300: https://www2.itc.kansai-u.ac.jp/~sasabe/publications/hara19GeographicalRiskAnalysis.pdf ; https://researchr.org/publication/HaraSK19
- Komatsu, Sasabe, Kawahara & Kasahara, GeoInformatica 22(1):127–141, DOI 10.1007/s10707-016-0270-1 (secondary listing only; not opened)
- "Utilization of Probe Vehicle Information in Disasters in Japan", 15th WCEE 2012 (grey literature; authors not read): https://www.iitk.ac.in/nicee/wcee/article/WCEE2012_5300.pdf
- Nam & Mannering 2000, TR-A 34(2):85–102 (metadata only; not used for a claim)
- Relied on the notes files' verification for Nannicini 2012, Jin/Yang/Wang 2025, Flajolet 2018, Kong 2022, She 2019, Hiramoto 2025, Song 2015, Agostini 2024, Gilboa & Schmeidler 1989, Ellsberg 1961, Talebi 2018, Lagos 2024, Lamarre 2026 and Rohmann & Bachem 2026.

Searches that found nothing closer: routing on a Wilson or Beta-quantile upper bound of a per-edge hazard probability from sparse reports (Exa, 1 query); Bayesian per-link passability from probe traversals for routing (Exa, 1 query; results were post-earthquake Bayesian networks and a thesis, none with decay or pessimism). Limited search (~15 queries), not exhaustive.
