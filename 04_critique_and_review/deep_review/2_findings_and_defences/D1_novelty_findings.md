# Findings to defend (D1_novelty)

## F1 [Critical] C1. The related-work claim that prior flood routers treat flood state as known is contradicted by already-cited and recent work
**Location:** paper.tex L66 ("These studies generally treat the flood state as known from a model. We instead treat it as an uncertain belief built from sparse reports."). The same framing appears in abstract L44 and in contribution 1 (L58).

**Claimed problem:** This sentence is the paper's only stated point of departure from flood-routing work, and the record contradicts it:
  - **Safaei-Moghadam et al. 2023**, already in refs.bib as `safaei2023waze` and cited at L72 only as "crowd sensing", estimates *the likelihood* of roadway pluvial flooding by combining a depression-based DEM susceptibility analysis with Waze crowd reports, explicitly "to provide near-real-time navigational warnings". That is a static prior plus crowd reports producing a probability for navigation, which is CityPulse's belief layer in outline.
  - Toathom & Champrasert 2024 route relief vehicles on "the likelihood that each section of the road will flood".
  - Bucar & Hayeri 2022 learn link-level flood risk and benchmark against most-reliable paths.
  - Alabbad et al. 2024 drive routing from probabilistic 10-day forecasts.
  - Lupa et al. 2026 bracket passability uncertainty with two satellite products.
  - Cao et al. 2026 infer probabilistic road inundation from sparse observations with a Bayesian MRF and sequential updating.
  - Most pointedly, **Li, Song & Li 2026** (Research Square preprint, July 2026) fuse crowdsourced road-passability reports under uncertain source credibility and "stale forwarding" into a *distributionally robust credal posterior* and dispatch min-max, with a replay of the 2021 Zhengzhou flood. That is a pessimistic fusion of unreliable, ageing crowd evidence for flood routing. Their companion paper (Discover Artificial Intelligence, Aug 2026) routes trucks on Bayesian road-access beliefs with a CVaR criterion.

## F2 [Critical] C2. The motivation ignores shipped products and Chennai's own systems, and two motivating sentences are inaccurate as written
**Location:** - paper.tex L44: "Navigation apps route drivers into flooded streets because they optimise travel time on a network assumed to be intact, and they often stop working when floods take down cellular service".
  - L54: "cloud-dependent services fail when connectivity does".
  - The related work (L64–75) mentions no product, no patent beyond IBM and Uber, and no Chennai system.

**Claimed problem:** - **Google Maps India** has let users report and receive flooding/waterlogging alerts since October 2024. India had "the highest number of flood-related alerts on Maps globally" in 2025, and Maps takes closures from traffic police in 18 cities and from NHAI.
  - **Mappls** advertises "real-time Waterlogging Alerts ahead on your route while you navigate" (Aug 2026). Its CEO stated in 2023 that users are "alerted about incidents … on their route, and can be suggested alternative routes".
  - Google Maps **does** navigate offline for driving. It loses traffic and alternate routes offline ("If you're offline when you drive, you can't get traffic info or alternate routes"); it does not "stop working".
  - Chennai has the **RTFF & SDSS** (₹107.2 crore, fully operational Oct 2025), which issues street-level inundation forecasts for Velachery, Saidapet, Mudichur and other localities and disseminates through TN-Alert.
  - **RiskMap** (MIT Urban Risk Lab) ran crowd flood reporting in Chennai in 2017–2019 so residents could "navigate to safety".
  - HERE's patent US11691646B2 (filed 2020) warns of and reroutes around active floods at flood-prone locations, and its background states the very motivation the paper uses: maps "may actually define a route that directs a driver to and through a flooded roadway".

## F3 [Critical] C3. The "combination" novelty is threatened by 2026 on-device-LLM flood apps, and the explanation half is unevaluated
**Location:** paper.tex L20 (title "… with Verified Explanations"), L56 ("What we examine is a specific combination"), L60 (contribution 3), L149 ("We have not yet measured the pass rate …"); plan.tex L36 and L142 ("On-device route + confidence + verified explanation: Defensible").

**Claimed problem:** Between April and August 2026, several publicly documented, non-peer-reviewed systems shipped the same architectural pattern: an on-device small LM narrates a deterministically computed, flood-avoiding route; numbers stay in code; and there is a deterministic fallback.
  - **Disha** (Build with Gemma @Bangladesh, July 2026). Gemma 4 runs on-device over LiteRT-LM, with "Dijkstra flood-avoid routing on real OSM road graphs". "Every exact value … is produced by tested code, never by the model. An automation and verification layer sits on both sides of every generation". It runs a rule-based fallback when the model is unavailable, and it adopted "precise values never pass through the model" after observing number corruption.
  - **Bonbibi** (Arm challenge, Aug 2026). Offline flood simulation on a Raspberry Pi with "deterministic BFS" shelter routing per mobility profile and depth limits; "Granite composes personal guidance … The model composes; it never decides."
  - **LIKAS** (Kaggle, Apr–May 2026). "Zero network calls at runtime"; offline Dijkstra on a bundled OSM graph; a grammar-constrained Gemma tool dispatcher; a "deterministic keyword router" fallback.
  - **Nongor** (July 2026). Offline flood-avoiding shelter routing with Gemma on the handset.
  - **CrisisConnect Edge** (May 2026). Offline Gemma grounded in a cached package with "freshness metadata"; it must warn when the package is stale.
  - **RainRoute AI** (Aug 2026). Crowd hazard reports that "decay with distance and expire automatically after two hours" drive an "explainable" flood-aware route.

  All of these predate CityPulse's mid-September 2026 start. In the peer-reviewed literature, T2G2 already does template → LM rewrite, VCP does rule check plus regeneration, and RouteExplainer pairs route explanation with an LLM. Runtime verification of LLM output against domain constraints (RvLLM) and the "deterministic LLM sandwich" are documented patterns.

  What remains distinct in CityPulse:
  - (a) The hazard state is a **probabilistic, evidence-weighted belief** rather than a binary flood polygon.
  - (b) Routing uses an **evidence-dependent pessimistic bound** with a per-class dial.
  - (c) The gate is a **typed post-hoc verifier** (numerals with tolerance and unit conversion, entities, comparatives, data-gap coherence, required hedging, a ban on safety claims) that **fails closed to a template**, rather than keeping numbers out of the model.
  - (d) The router runs on a **193k-node city graph** 

## F4 [Significant] S1. The pessimism and risk-seeking argument lacks its intellectual ancestors, and the "reverses the direction" claim is stronger than the formula supports
**Location:** paper.tex L58, L88–94 ("This mirrors the upper confidence bounds of bandit algorithms … but is used pessimistically"; "A common alternative prices an edge as w=τ0(1+λRC) …"; "Equation (3) reverses the direction of that dependence").

**Claimed problem:** 1. Pessimism-as-sign-flipped-bonus is the core of offline-RL pessimism (Jin, Yang & Wang, MOR 2025). Routing on confidence-interval information is in Flajolet et al. 2018. Worst-case CVaR because "historical data are usually insufficient" is in Toumazis & Kwon 2016. Ambiguity aversion is formalised in Ellsberg 1961 and Gilboa & Schmeidler 1989. Pessimistic fusion of stale crowd flood reports is in Li et al. 2026 [preprint]. None of these is cited.
  2. The "common alternative" is asserted without citation. It *is* common, and saying so strengthens the paper:
     - TomTom US9836486B2: confidence values "age according to a predefined function"; below a threshold, "drivers are no longer informed"; hazards expire by type.
     - HERE US10650670B2: confidence is decreased for "staleness"; road events are cancelled below a lower threshold.
     - Waze alerts are typically removed after about 30 minutes unless confirmed.
     Citing these turns an abstract argument into a critique of deployed practice, which is the most original thing in the paper.
  3. L92 says p̃ decreases with n_eff "for fixed p̄". Under the paper's own fusion, though, decay changes both p̄ and n_eff: as reports age, p̄ reverts toward the prior while the band widens. Whether p̃ rises or falls as a flood report ages therefore depends on the prior and z. The claim that Eq. (3) "reverses the direction of that dependence" holds only at fixed p̄.

     (Out of my scope, flagged for the maths specialist: for prior-only edges, n_eff=0 gives p̃ = p0 + z·sqrt(p0(1−p0)). With z=2 this saturates at 1 for every p0 ≥ 0.2, so the emergency class would treat every medium-or-higher hazard zone as certainly flooded.)

## F5 [Significant] S2. Class-specific report decay is pre-empted by patents, so the plan's fallback claim ("calibrated, class-specific decay") is left with only its calibration part, which Study 2 did not support
**Location:** plan.tex L138; paper.tex contribution framing (decay at L79–83, L186, L214); IDEA_AND_FACTS core idea ("decays … at a hazard-class-specific rate").

**Claimed problem:** TomTom's US9836486B2 describes the Trapster scheme, in which hazards expire after type-specific periods (police trap 1 h, road closure 6 h, construction zone 5 days). It then claims confidences that age by a decay function and are adjusted by positive and negative reports. Microsoft's US8983976B2 claims dynamically learned expiry with confidence and user trust ratings. Intel's US10737698 weights crowd road data by age. "Class-specific decay" is therefore not new. "Calibrated" decay would be new, but Study 2 found C3 indistinguishable from C2.

## F6 [Significant] S3. The cost formulation (slowdown separated from harm, per-class risk) has near-identical precedent
**Location:** paper.tex L58 ("A formulation that separates slowdown from harm … with a per-user-class caution parameter"), L96–101.

**Claimed problem:** - FLOAT (Jao et al., ICNSC 2025) uses λ to trade travel time against flood risk and α as a flood-speed penalty. It sweeps them and reports that high λ and α give odd detours, mirroring CityPulse's sweep.
  - Krumm & Horvitz 2017 and Galbrun et al. 2016 keep time and risk separate.
  - MITRE's US12135218B2 (granted Nov 2024) claims navigation "dynamically assessed based on risk tolerance", with risk scores "weighed based on tolerance level".
  - Kang et al. 2014 make route choice "a function of the level of risk tolerance".
  - Bonbibi uses per-mobility-profile depth limits.

## F7 [Significant] S4. The "bounded deterrence" proposition is elementary and should not be sold as a "new finding"
**Location:** paper.tex L59 (contribution 2), Prop. 2 (L111–117); plan.tex L143 ("New finding").

**Claimed problem:** The bound follows from substituting δ=1 and p̃≤1, which is one line of algebra. Several works already note qualitatively that time-proportional exposure undercounts the harm of short severe segments and inflates the cost of detours:
  - Donaldson et al. 2026: dose reductions are smaller because detours add time.
  - Wang et al. 2022: slower travellers accrue more exposure.
  - Krumm 2017: per-traversal Bernoulli risk, not per-time.
  - Classic hazmat risk models.

  No head-to-head comparison was found (uncertain_routing.md, Q1 table). So the *empirical* demonstration on a city graph, and a fix compared head-to-head (per-edge harm μ·p̃·s), would be the actual contribution.

## F8 [Significant] S5. The plan's "make it unique" items are presented as open white space, but prior art already exists for each
**Location:** plan.tex L124 (forecasting row), L151 (traversal silence), L154 (reservoir-to-corridor causality), L171 (positioning).

**Claimed problem:** - L124 is outdated. Flood Hub has added urban flash-flood forecasts (Mar 2026, area-level), and Chennai's RTFF has given street-level inundation forecasts since Oct 2025.
  - L151 overclaims. Inferring closures from probe absence is published: HERE's Pietrobon et al. 2019 (92% precision on low-volume roads), Kong 2022 (taxi passing-rate drop for floods), Hiramoto 2025 (no traffic or speed below 20 km/h means inundated), She 2019, and Yuan 2023 (INRIX null speed as a flood label). Itoi 2017 infers blocked segments from route deviation.
  - L154 overclaims. RTFF already models lakes, rivers, drains and sea together across the Adyar, Cooum, Kosasthalaiyar and Kovalam sub-basins, with street-level outputs, and CFM-DSS publishes reservoir levels.
  - L171 ignores RiskMap Chennai (2017–19), which had the same city, the same crowd-reporting premise and a stated navigation purpose.

## F9 [Significant] S6. The evaluation protocol is listed as a contribution but is a correction of the team's own harness
**Location:** paper.tex L61; plan.tex L144.

**Claimed problem:** The safest-path literature already scores routes on many OD pairs and reports exposure-versus-detour frontiers (Krumm 2017; Ghoul 2023; Rohmann 2026; Donaldson 2026). Scoring every configuration under one reference belief is ordinary experimental hygiene, and the paper itself shows that the reference is circular (L246). Reproducing the router's paths with an independent implementation is good engineering, not novelty.

## F10 [Critical] C1. The central pessimism claim fails on the actual decay path: an ageing positive report lowers p~ at every z
**Location:** .** paper.tex L92 ("thin evidence produces more caution, not less"); L94 ("Equation (3) reverses the direction of that dependence"); contribution bullet L58; plan.tex L141; repository ADR-002 ("thinner evidence *raises* caution").

**Claimed problem:** .** The monotonicity statement is a partial derivative at fixed p̄. When a positive flood report ages, ω → 0 moves both terms at once: p̄ falls back toward the prior and n_eff falls toward 0. The fall in p̄ dominates. Representative values from Eq. (1)–(3), with one fresh report of α = 0.8 that then ages (ω = 1 → 0):
- prior 0.02, z = 0: 0.075 → 0.020; z = 1.28: 0.315 → 0.199; z = 2: 0.449 → 0.300.
- prior 0.10, z = 2: 0.960 → 0.700. Prior 0.02 with 3 reports, z = 2: 1.000 → 0.300.

p~ decreases monotonically with age in every tested case with α ≥ 0.8 and every z. The only cases where p~ rises with age are weak reports (α = 0.6), where the report barely moves p̄. For negative reports the claimed direction does hold (prior 0.25, α = 0.8, z = 2: 0.454 → 1.0).

So CityPulse also makes "an unverified or ageing flood report make the road look clear[er]", which is the behaviour the paper attributes to the strawman w = τ0(1 + λRC). The real differences are two:
- An aged report decays to the prior plus an ignorance band instead of to zero.
- For z = 0, the commuter default, it decays to the prior exactly.

## F11 [Critical] C2. The z dial saturates. For the emergency class the "belief layer" reduces to a static prior-zone mask
**Location:** .** paper.tex L90–92 (per-class z); plan L63, L141; `config/hazard_classes.yaml` (emergency z = 2.0, pedestrian z = 1.28).

**Claimed problem:** .** p~ = 1 whenever p̄ ≥ 1/(1 + z²/(n_eff + 1)). With no evidence the threshold is 1/(1 + z²):
- z = 2: 0.20
- z = 1.28: 0.38
- z = 1: 0.50

All 8,759 prior-only configured edges have p0 ≥ 0.25 (IDEA_AND_FACTS). For the emergency class they are therefore pinned at p~ = 1 with zero evidence. Further positive reports cannot raise caution, so evidence is ignored. A single fresh negative report (α = 0.8, ω = 1) on a 0.25-prior edge brings p~ only to 0.45. ADR-002 itself notes that the unclamped value "routinely exceeds 1" for the emergency class and calls the clamp "load-bearing". The clamp hides the saturation; it does not remove it.

## F12 [Critical] C3. The pessimistic plug-in is a known construction. Contribution bullet 1 overclaims it as "a formulation"
**Location:** .** paper.tex L58 (contribution 1), L87–92 ("This mirrors the upper confidence bounds of bandit algorithms [Auer] but is used pessimistically"); plan L141 ("Defensible").

**Claimed problem:** .**
- The variance of a Beta distribution with mean p̄ and concentration a + b = n_eff is p̄(1 − p̄)/(n_eff + 1), exactly the term inside the root. So p~ is "posterior mean + z posterior s.d." of a moment-matched Beta.
- That is a Gaussian-approximation Bayes-UCB index (Kaufmann, Cappé & Garivier, AISTATS 2012: "Bayesian index policies that rely on quantiles of the posterior distribution") applied to a beta-reputation estimate with forgetting (Jøsang & Ismail 2002: Beta(r + 1, s + 1) with a forgetting factor).
- Using an upper quantile pessimistically in place of optimistically is the PEVI construction of Jin, Yang & Wang (MOR 2025): the penalty "simply flips the sign of the bonus function".
- Walley's imprecise Dirichlet model (JRSS-B 1996) gives upper probabilities that are "initially vacuous… [and] become more precise as the number of observations increases", which is precisely "thin evidence → more caution".
- In planning, risk-aware costs of the form μ + σ·φ(Φ⁻¹(α))/(1 − α) with α chosen per mission or robot role are used with A* by Fan et al. (STEP, RSS 2021).
- Per-class risk aversion in route choice is in Lo, Luo & Siu (TR-B 2006).

The only element not found elsewhere is the specific n_eff = Σω, and that is the weakest part (S2).

## F13 [Significant] S1. "Risk-seeking under ambiguity" is the wrong term, and the comparison is a strawman
**Location:** .** paper.tex L94 and contribution bullet 1; plan L141; ADR-002.

**Claimed problem:** .**
- Risk-seeking is an attitude toward known variance. What the paper describes is shrinking the hazard estimate toward zero as evidence ages, which is an optimistic default prior. The decision-theoretic name for preferring the favourable end of an ambiguous set is ambiguity-seeking. The remedy, evaluating at the upper envelope of a set of priors, is maxmin expected utility (Gilboa & Schmeidler 1989), the Ellsberg (1961) motivation, and Walley's upper probability.
- "A common alternative prices an edge as τ0(1 + λRC)" cites nothing. Per ADR-002, the only documented user of this form is the team's own original pitch.
- CityPulse at z = 0 shrinks to the prior, which is the Bayesian-neutral option. That option is neither of the two the paragraph contrasts.

## F14 [Significant] S2. n_eff is not an effective sample size, so p~ is not a bound
**Location:** .** paper.tex Eq. (2) L83, Eq. (3) L90 ("the router uses the upper bound"); `fusion.dart` (n_eff "unsigned, so opposing observations cancel in ℓ but still both count as evidence"); plan item 6.

**Claimed problem:** .**
- n_eff = Σκ·e^(−Δt/T) ignores reliability α. A worthless report (α = 0.5, logit 0) leaves p̄ unchanged but narrows the band, so caution falls on no information.
- Conflicting reports (+ and −) cancel in p̄ but add to n_eff. Conflict therefore reads as confidence, whereas subjective logic and Dempster–Shafer treat it as a signal of ambiguity.
- Kernel weights are not counts. The Kish effective sample size is (Σω)²/Σω², not Σω.
- Correlated duplicates, which the paper acknowledges at L248, inflate n_eff further.

There is thus no model under which p~ has coverage. "Upper bound" and ADR-002's "upper confidence bound" overclaim.

## F15 [Significant] S3. "Thin evidence → more caution" does not hold where evidence is thinnest: unconfigured edges and p̄ → 0
**Location:** .** paper.tex L92; L175 (14,534 configured edges); `cli_io.dart` ("An edge with no hazard data at all is simply absent from `hazards`").

**Claimed problem:** .**
- Edges absent from the hazard configuration get no penalty. That is 471,240 − 14,534 ≈ 456,700 directed edges, about 97%, including prior-only edges with p0 < 0.25 that were dropped. Their evidence is zero, yet p~ = 0.
- The Wald band also vanishes as p̄ → 0: with no evidence and p0 = 0.001, z = 2 gives p~ = 0.064.
- The property therefore holds only inside the GCC prior zones, which means it holds where a static map already flags risk.

## F16 [Significant] S4. Traversal silence is established prior art; the "moat" and "rarely modelled" claims are overclaimed
**Location:** .** plan.tex L151 ("the one input… nobody can buy it"), L176 (moat), L219 (Paper 2); litreview L106 ("rarely modelled"), L168; paper L255 (future work, acceptable).

**Claimed problem:** .**
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

## F17 [Significant] S5. The defensible novelty is the pessimism × traversal-silence feedback loop, which no draft mentions
**Location:** .** Absent from paper.tex, plan.tex and litreview.tex. Relevant to plan L151, L219 and ADR-002 "Stretch".

**Claimed problem:** .** A pessimistic router sends its users away from uncertain edges. Those edges then receive no traversals, so silence-based evidence never accrues, n_eff stays low and p~ stays high. The app's own data are censored by its own policy. This is the runaway-feedback structure proved for predictive policing (Ensign et al., FAT* 2018: systems "only observe crime in neighborhoods they patrol"). It is also the exploration problem of online shortest-path learning (Talebi et al. 2018; Lagos et al. 2024). Risk-averse Canadian Traveller policies show "information-seeking detours" (Lamarre & Kelly 2026). Bandits explore with optimism, while CityPulse is deliberately pessimistic. The two goals conflict, and per-class z is the natural lever: commuters at z ≈ 0 act as explorers whose traversals inform the emergency class.

## F18 [Significant] S6. Per-class decay is known, and ADR-002's planned "persistence-filter derivation" contains an error
**Location:** .** paper.tex L79–82; litreview L110; repository ADR-002 "Stretch": "The pitched exponential is the exact observation-free marginal of that model".

**Claimed problem:** .**
- Precedents for decay rates tuned to how fast the observed entity changes:
  - Jøsang & Ismail 2002: a forgetting factor "adjusted according to the expected rapidity of change in the observed entity".
  - Biber & Duckett 2005: memories that "fade at different rates depending on the timescale".
  - Rosen et al. 2016: a survival-time prior p_T per feature, whose belief "decay[s]… in the absence of any signal".
- Class-specific constants add nothing conceptually, and Study 2 shows C3 ≈ C2.
- ADR-002's derivation claim does not hold. Under a Weibull survival prior, the observation-free persistence belief follows the Weibull survival function, not an exponential. The exponential is the special case of a constant hazard rate. Rosen's filter also decays a persistence probability, not a log-likelihood-ratio weight on a fixed prior, so Eq. (1) is not its marginal for any p_T.

## F19 [Significant] S7. The "combination not addressed" statement must cite and narrow around Hara et al. and Rohmann & Bachem
**Location:** .** litreview synthesis ("We found no work that simultaneously (i) routes on beliefs that fuse a static prior with sparse, decaying crowd evidence… (v) runs entirely on a phone"); plan L142.

**Claimed problem:** .** Two works cover parts of items (i) and (v):
- Hara, Sasabe & Kasahara 2019, building on Komatsu et al.'s automatic evacuation guiding. It runs on evacuees' phones. It routes on per-segment blockage probabilities from a municipal static prior (Nagoya). It updates these from device trajectories and shared reports, and it is evaluated in an offline (no-communication) case.
- Rohmann & Bachem (IEEE IV 2026). It fuses a prior with sparse per-edge evidence (Poisson–Gamma empirical Bayes) and propagates uncertainty into risk-aware routing.

Neither has decay, pessimism or verified explanations, so the five-way combination survives, but only narrowly.
