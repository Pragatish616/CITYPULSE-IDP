# D1 Novelty: Defense Report (arguing for the CityPulse AI authors)

Artifacts checked: paper.tex (L44-117, L145-149, L170-255), plan.tex (L118-176, L216-222), the literature notes (flood_routing.md, uncertain_routing.md, crowd_flood_sensing.md, chennai_india.md, market.md), the repo (config/hazard_classes.yaml, research/SYNTHESIS.md, docs/DECISIONS.md ADR-002, pulse_belief/fusion.dart and README). I recomputed Eqs. (1)-(3) in Python. I opened three sources with Exa: Li, Song & Li 2026 (Research Square rs-10104632), the Safaei-Moghadam 2023 NHESS abstract, and the Google Maps offline help page.

A cross-cutting defense applies throughout. Many findings target **plan.tex, the litreview or SYNTHESIS/ADR-002**, which are internal strategy or design documents and not the submitted paper. The paper itself is noticeably more hedged. It already concedes that flood-aware routing is not new (L56), cites UCB as the source of the bound (L92), cites Jøsang and Rosen for decay (L72), and reports C3≈C2, the circular reference and the unevaluated verifier (L149, L214, L246, L251). Where a finding's target is only an internal document, I downgrade it.

---

## F1 [Critical]: "Prior flood routers treat flood state as known" is contradicted
**Strongest defense:** The sentence is scoped to "These studies", meaning the five works cited immediately before it (Li 2023, Liang 2025, Li 2025 DRL, An 2025, Bayram 2016), and for those it is true (plan L121 and flood_routing.md agree). The team's own notes also show that each newly cited work differs in a specific way. Toathom uses an expected value on synthetic likelihoods. Alabbad uses forecast probabilities only to *select* deterministic open/closed scenarios. Lupa brackets with two scenarios. Bucar uses static risk with no real-time update. Safaei 2023 (abstract opened) estimates historical per-segment flood *frequency/susceptibility* from 150 storms with empirical Bayes, which is closer to CityPulse's prior ℓ0 than to a real-time routing belief. Li, Song & Li 2026 (opened) is a robust credal fusion of crowd passability reports, but it works on ~3 km grid cells and targets adversarial contamination for agency UAV/bus dispatch. It has no report-age decay, no evidence-count-dependent bound and no on-device navigation.
**What I checked:** paper L56, L66, L72; flood_routing.md L107-108, L133, L158, L241-254; Exa: NHESS abstract and Research Square rs-10104632.
**Verdict: PARTIAL. Downgrade from Critical to Significant.** The literal sentence is defensible, but it is the paper's *only* stated point of departure, and Safaei 2023 (already in refs.bib) plus Li et al. 2026 make the implied generalisation ("we, unlike prior work, treat flood state as an uncertain belief from sparse reports") false. The fix is a related-work rewrite: cite Safaei 2023/2024, Toathom, Bucar, Alabbad 2024, Lupa and Li 2026, and move the departure point to an "evidence-count- and age-dependent pessimistic bound on an on-device router" (flood_routing.md gap 1). This is not a falsified result.
**Confidence:** High.

## F2 [Critical]: Motivation ignores shipped products; two motivating sentences are inaccurate
**Strongest defense:** Google's own help page confirms that offline driving loses traffic info and alternate routes, and only works within a *pre-downloaded* area. A navigator that cannot reroute around a new flood is functionally "hazard-blind offline". Police reports (Hyderabad 2025, chennai_india.md L144) say Maps does not detect waterlogging itself. The team's notes find no product with per-segment probabilities, decay, offline routing or per-class risk (chennai_india.md L134, L150). RTFF is a forecast and dissemination system, not a router, and RiskMap was a reporting map whose pilot ended in 2019. The plan already lists Google Maps, Waze, TomTom and TN-ALERT (plan L125).
**What I checked:** paper L44, L54, L64-75; plan L125; market.md L15-41, L82, L121, L376; chennai_india.md L58-63, L134-162; the Google Maps offline help page (Exa).
**Verdict: PARTIAL. Downgrade from Critical to Significant.** "Often stop working" is wrong as written and should become "cannot reroute or receive hazard updates offline". "Route drivers into flooded streets because… network assumed intact" ignores the crowd flood alerts Google Maps India has offered since Oct 2024 and Mappls' on-route alerts. Whether those alerts change the route is unverified in the notes, so the sentence should become "display crowd alerts but do not model their uncertainty or age". The paper also omits every product, RTFF and RiskMap, which the team already knew about (market.md). The novelty itself survives these omissions, so this is a framing and citation defect, not a critical one.
**Confidence:** High.

## F3 [Critical]: "Combination" novelty threatened by 2026 on-device-LLM flood apps; explanation half unevaluated
**Strongest defense:** The paper's claimed combination (L56) is *belief fusion with decaying crowd evidence + caution that grows with thin evidence + verified explanations + on-device*. The finding itself concedes (a)-(d): no listed app has probabilistic beliefs, an evidence-dependent bound, a typed post-hoc fail-closed verifier, or city-scale (193k-node) routing. The apps are hackathon or GitHub projects, not peer-reviewed, and the team's notes already flagged Nongor, LIKAS, Disha and Bonbibi (flood_routing.md L75, L162). The paper is transparent that the verifier is design-only (L149, L251), and the plan's "Defensible" verdict is explicitly conditional on measuring pass rate (plan L142).
**What I checked:** paper L20, L56, L60, L149, L251; plan L142; flood_routing.md L75, L162, L257.
**Verdict: PARTIAL. Downgrade from Critical to Significant.** The combination survives. Two problems remain. (i) The "verified explanation on device with numbers kept deterministic" sub-pattern is now common practice and must be cited, including the grey literature. (ii) The title's "with Verified Explanations" promises an evaluated contribution that the paper says it does not deliver, so either evaluate the pass rate or retitle and demote the claim to "design".
**Confidence:** High.

## F4 [Significant]: Pessimism argument lacks ancestors; "reverses the direction" too strong
**Strongest defense:** The paper does name its ancestor (UCB, Auer 2002, "used pessimistically", L92) and does not claim the bound is new. On point 2, the finding's own evidence (the TomTom and HERE confidence-ageing patents and Waze expiry) shows that the "common alternative" really is common, which *vindicates* the paper's critique. The only defect there is a missing citation. On point 3, L92 explicitly says "for fixed p̄", which is mathematically correct.
**What I checked:** paper L58, L88-94; uncertain_routing.md L105, L124, L137-148 (the team's notes already recommend Jin et al., Flajolet, Toumazis and Gilboa-Schmeidler framing); SYNTHESIS.md L22-27 and L224 (the claimed literature source for the multiplicative form, Xue et al. arXiv:2601.13632, is marked NOT VERIFIED).
**Verdict: PARTIAL. Narrow to a citation gap plus a wording fix (Minor-Significant).** Point 1 stands as a citation gap. Point 2 is a quick win: cite the TomTom and HERE patents and Waze expiry. Point 3 merges into F10. Keep "reverses" only with the "at fixed p̄" qualifier, or replace it (see F10).
**Confidence:** High.

## F5 [Significant]: Class-specific decay pre-empted; plan's fallback claim left with only the unsupported calibration part
**Strongest defense:** The paper never claims class-specific decay as a contribution (L57-62). The plan already rates decay "Not novel" and makes "calibrated, class-specific" conditional on fitting it to time-stamped data (L138). The paper honestly reports C3≈C2 (L214) and that one timestamp makes decay variants identical (L178). The finding therefore attacks a claim the authors have not yet made.
**What I checked:** paper L57-62, L178, L186, L214; plan L138; hazard_classes.yaml (T_c labelled "PLACEHOLDER - fit from data").
**Verdict: DEFENSE MOSTLY SUCCEEDS. Downgrade to Minor.** The plan should drop "class-specific" from the conditional claim and cite the Trapster/TomTom type-specific expiry. Calibrated decay remains a legitimate *future* claim. I did not open the patents.
**Confidence:** Medium-High.

## F6 [Significant]: Cost formulation has near-identical precedent
**Strongest defense:** The team's notes show that no paper combines a multiplicative depth–disruption slowdown weighted by p̃ with a separate p̃-weighted harm term and a per-class uncertainty dial (uncertain_routing.md L126). FLOAT treats depths as known and has no uncertainty term (flood_routing.md L241). Krumm and Galbrun keep time and risk as separate criteria but do not model slowdown.
**What I checked:** paper L58, L96-101; flood_routing.md L86, L241; uncertain_routing.md L125-127.
**Verdict: PARTIAL. Downgrade to Minor.** The exact combination survives, but each component has precedent: FLOAT for λ/α, Krumm/Galbrun for separate criteria, Kang 2014 and Lo 2006 for per-class risk tolerance. Contribution 1 must cite them and say "combines" rather than present "a formulation" as new.
**Confidence:** High.

## F7 [Significant]: "Bounded deterrence" is elementary
**Strongest defense:** The paper does not oversell it. It is stated as a Proposition with a one-line proof, and its value is diagnostic: it explains the empirical finding that commuter defaults changed only a few routes (L117, L190). The finding concedes that no head-to-head precedent exists. The phrase "New finding" appears only in the internal plan (L143).
**What I checked:** paper L59, L111-117, L190; plan L143; uncertain_routing.md L127, L180.
**Verdict: PARTIAL. Downgrade to Minor.** Re-label it in the plan as a "diagnostic observation", and cite Donaldson 2026, Wang 2022 and Krumm 2017 for the qualitative point. The suggested per-edge harm comparison is an improvement, not a defect in the current paper.
**Confidence:** High.

## F8 [Significant]: Plan's "make it unique" items are not open white space
**Strongest defense:** These items are in the internal plan, not the paper. L124's literal claim concerns *global* products (GloFAS, Flood Hub), and Flood Hub's 2026 urban forecasts are area-level, so "not streets" still holds for them. L154 likewise contrasts with "global products". RTFF is not an offline on-device reasoner, and RiskMap had no routing and ended as a pilot.
**What I checked:** plan L124, L151, L154, L171; market.md L82, L121, L148; crowd_flood_sensing.md L120, L135.
**Verdict: PARTIAL. Narrow the finding.** L151 ("nobody can buy it") and L171 (ignoring RiskMap Chennai) stand. The team's own notes (crowd_flood_sensing.md L135) already say probe-absence evidence is pre-empted. L124 and L154 must add RTFF, which the team knew about (market.md), but their literal wording about global products is defensible. The finding is Significant for the plan and Minor for the paper.
**Confidence:** Medium-High.

## F9 [Significant]: Evaluation protocol listed as a contribution
**Strongest defense:** Contribution 4 is an *empirical evaluation* contribution (a replay on the full city graph, independent re-implementation and a calibration study), which is standard in IEEE application papers. It does not claim the protocol is methodologically novel. The plan calls it "Useful", not novel (L144), and the notes say it "matches the field's norm" (uncertain_routing.md L200). The paper also flags the circular reference itself (L246).
**What I checked:** paper L61, L180-183, L211, L246; plan L144.
**Verdict: DEFENSE SUCCEEDS. Drop, or keep at most as a Minor wording note** (de-emphasise the "our earlier harness was wrong" framing in the contribution bullet).
**Confidence:** Medium-High.

## F10 [Critical]: An ageing positive report lowers p̃ at every z
**Strongest defense:** L92 states the monotonicity explicitly "for fixed p̄", which is correct. The substantive contrast with τ0(1+λRC) also survives in a weaker form. Under the strawman, an aged report sends the penalty to zero. Under Eq. (3) it sends it to the prior plus an ignorance band. For example, with prior 0.02 and z=2, p̃ goes from 0.449 to 0.300, not to 0, and with prior 0.10 and z=2 it goes from 0.96 to 0.70. So the road never "looks clear" unless the prior is near 0.
**What I checked:** Recomputed Eqs. (1)-(3) with α=0.8 and ω=1→0. Every case reproduced: 0.075→0.020 (z=0), 0.315→0.199 (z=1.28), 0.449→0.300 and 0.96→0.70 (z=2). The α=0.6 case does rise (0.27→0.30). A negative report on a 0.25 prior gives 0.454, rising to 1.0 as it ages.
**Verdict: PARTIAL. Downgrade from Critical to Significant.** The arithmetic is right, and the abstract ("caution grows as evidence thins") and "reverses the direction" (L94) mislead on the actual decay path of a positive report. The true property is a *floor* ("decays to prior + band, not to zero"), plus the reversal for negative and weak evidence. That is a rewording of the central claim, not a broken method.
**Confidence:** High.

## F11 [Critical]: z saturates; for the emergency class the belief layer reduces to a static prior-zone mask
**Strongest defense:** "Reduces to a mask" is overstated. With δ=1 and no depth in the corpus, p̃=1 gives w=τ0(1+λs), a uniform ×2 soft penalty for emergency (λ=1, s=1). It is not removal, because removal needs reported depth above h_max (L101). "Evidence is ignored" is also overstated. Negative evidence still moves the belief (one α=0.8 report gives 0.454 and two give 0.184), and edges with observations but low priors are not saturated. For an ambulance, maximal caution on GCC-flagged zones with no evidence is arguably the *intended* conservative behaviour, and the clamp is documented as deliberate (ADR-002, pulse_belief README).
**What I checked:** Recomputed: with no evidence, z=2 gives 1.116, 1.304 and 1.445 unclamped for priors 0.25, 0.35 and 0.45 (all saturated), and z=1.28 gives 0.804, 0.961 and 1.087. hazard_classes.yaml (emergency z=2, λ=1; pedestrian z=1.28, λ=1.2); paper L101, L175; README L13-14.
**Verdict: PARTIAL. Downgrade from Critical to Significant.** The saturation is real and undisclosed. Positive evidence cannot raise caution on any configured prior-only edge for emergency vehicles, so the dial is coarse. The paper must disclose this or switch to a bounded quantile (for example a Beta quantile). The "mask" and "evidence ignored" wording should be dropped.
**Confidence:** High.

## F12 [Critical]: The pessimistic plug-in is a known construction; contribution 1 overclaims
**Strongest defense:** The paper credits UCB and says "used pessimistically" (L92). Contribution 1 claims a *formulation* that bundles slowdown/harm separation, the bound and the per-class dial, plus a design argument. It does not claim the bound itself is new. The team's notes already identify p̃ as an LCB-style pessimism penalty and say not to claim novelty for it (uncertain_routing.md L148).
**What I checked:** paper L58, L87-92; plan L141; uncertain_routing.md L105, L124-125, L137, L148.
**Verdict: PARTIAL. Downgrade from Critical to Significant (citation and wording).** Add the Beta-moment and Bayes-UCB reading, PEVI, Walley's IDM, STEP and Lo 2006, and reword contribution 1 as "an instance of pessimism-under-uncertainty applied to crowd hazard beliefs". The construction is known, but the paper does not falsely claim it, so this is not critical.
**Confidence:** High.

## F13 [Significant]: "Risk-seeking under ambiguity" is the wrong term; the comparison is a strawman
**Strongest defense:** The strawman charge contradicts F4, which documents that confidence-ageing suppression is deployed practice (the TomTom, HERE and Waze expiry rules). The paper's phrase "risk-seeking *under ambiguity*" already signals ambiguity attitude, so the precise term "ambiguity-seeking" is a terminology refinement. The z=0 point is not a contradiction either: the paper's commuter default *is* z=0 (decay to prior), which is still not "penalty→0".
**What I checked:** paper L94; ADR-002 (docs/DECISIONS.md L43-45 cites only the team's pitch); SYNTHESIS L24 and L224 (Xue et al. is unverified).
**Verdict: PARTIAL. Drop the strawman charge and keep the terminology fix. Downgrade to Minor.** Rename to "ambiguity-seeking", cite Ellsberg, Gilboa-Schmeidler and Walley, and cite the patents for the "common alternative".
**Confidence:** High.

## F14 [Significant]: n_eff is not an effective sample size, so p̃ is not a bound
**Strongest defense:** The paper never claims frequentist coverage. It calls Eq. (3) a "pessimistic plug-in" (subsection title) and discloses correlated duplicates (L248). fusion.dart documents the unsigned n_eff as a deliberate choice.
**What I checked:** paper L83, L88, L248; fusion.dart L32-34 and L96. Recomputed: five worthless reports (α=0.5) on a 0.25 prior with z=2 lower p̃ from 1.0 to 0.604 with no information.
**Verdict: DEFENSE FAILS on substance (narrow only the "coverage" point).** Two problems stand as real methodological flaws: the α-blind n_eff, where worthless reports reduce caution, and conflicting reports being read as confidence. "Upper bound" should become "pessimistic index". Remains Significant.
**Confidence:** High.

## F15 [Significant]: "Thin evidence → more caution" fails on unconfigured edges and as p̄→0
**Strongest defense:** This is a property of the evaluated *configuration*, not of Eqs. (1)-(3), and L175 discloses it (only edges with observations or prior ≥ 0.25 are configured). Excluding low-prior edges is arguably necessary. Under Eq. (3) with z=2, every very-low edge (p0=0.02) would get p̃=0.30, putting a 30% hazard on most of the city. The Wald band vanishing as p̄→0 is the standard behaviour of that interval.
**What I checked:** paper L173-175; recomputed p0=0.001 → 0.064 and p0=0.02 → 0.30 at z=2.
**Verdict: PARTIAL. Downgrade to Minor-Significant.** The paper must scope the property ("within configured hazard zones") and acknowledge that ~97% of edges carry no penalty. The finding's framing that the property "holds only where a static map already flags risk" is accurate and should be stated in the paper.
**Confidence:** High.

## F16 [Significant]: Traversal silence is established prior art; "moat" and "rarely modelled" overclaim
**Strongest defense:** The paper mentions it only as future work, which the finding accepts. The plan's specific angle, *missing-not-at-random* modelling inside a fused log-odds belief with decay and a prior, is not covered by Pietrobon, Kong or Hiramoto. The team's notes already state this narrower framing (crowd_flood_sensing.md L135).
**What I checked:** plan L151, L176, L219; crowd_flood_sensing.md L120, L135-136.
**Verdict: PARTIAL.** The overclaims in the plan and litreview ("moat", "nobody can buy it", "rarely modelled") stand. The MNAR-in-belief framing survives for Paper 2. The finding is Minor for the paper and Significant for the plan. I did not open Hara 2019.
**Confidence:** Medium-High.

## F17 [Significant]: The defensible novelty (pessimism × traversal-silence feedback loop) is not mentioned
**Strongest defense:** This is a research suggestion, not a defect. Traversal silence is not implemented in the evaluated system (app_traversal exists only as a config entry for improvement I-02), so the paper cannot be faulted for omitting a loop that does not yet run. The suggestion helps the authors.
**What I checked:** hazard_classes.yaml (app_traversal "see improvement I-02"); paper L255; plan L219.
**Verdict: DEFENSE SUCCEEDS as a defect claim. Reclassify as a recommendation** for Paper 2 and the threats-to-validity section.
**Confidence:** High.

## F18 [Significant]: Per-class decay is known; ADR-002's persistence-filter derivation is wrong
**Strongest defense:** The paper already cites Jøsang 2002 and Rosen 2016 for decay (L72) and does not claim per-class decay as new. The derivation claim lives only in an internal design document under "Stretch" and never reaches the paper. The exponential is the Weibull special case with shape 1, so the sentence is loose rather than baseless.
**What I checked:** paper L72; SYNTHESIS.md L75-80 ("under a Weibull survival prior… the pitched exponential is the exact observation-free marginal").
**Verdict: PARTIAL.** Drop the precedence part, which is already acknowledged. The derivation error stands: an exponential marginal arises only for constant hazard, and Eq. (1) decays an LLR weight rather than a persistence probability. It affects an internal doc only, so downgrade to Minor.
**Confidence:** High.

## F19 [Significant]: "Combination not addressed" must cite and narrow around Hara et al. and Rohmann & Bachem
**Strongest defense:** The paper does not say "we are not aware of any work…". It says "What we examine is a specific combination" (L56), and that phrase is not an absence claim. The finding concedes that the five-way combination survives. Rohmann is in the team's notes as a verified close analogue without pessimism (uncertain_routing.md L131).
**What I checked:** paper L56; plan L142; uncertain_routing.md L38, L88, L131 (Hara 2019 is not in the notes and I did not verify it).
**Verdict: PARTIAL. Downgrade to Minor.** Add Rohmann & Bachem 2026 and Hara et al. 2019 to the litreview synthesis and to the paper's related work, and narrow the litreview's "no work simultaneously…" sentence.
**Confidence:** Medium (Hara is unverified).

---

## Summary table
| ID | Title (short) | Verdict | Suggested severity |
|---|---|---|---|
| F1 | Known-flood-state claim | PARTIAL | Critical → Significant |
| F2 | Products and Chennai systems ignored; motivation wording | PARTIAL | Critical → Significant |
| F3 | On-device LLM flood apps; verifier unevaluated | PARTIAL | Critical → Significant |
| F4 | Missing pessimism ancestors; "reverses" | PARTIAL | Significant → Minor-Significant |
| F5 | Class-specific decay pre-empted | DEFENSE MOSTLY SUCCEEDS | → Minor |
| F6 | Cost formulation precedent | PARTIAL | → Minor |
| F7 | Bounded deterrence elementary | PARTIAL | → Minor |
| F8 | Plan "unique" items | PARTIAL (L151, L171 stand) | Minor (paper) / Significant (plan) |
| F9 | Protocol as contribution | DEFENSE SUCCEEDS | Drop / Minor wording |
| F10 | Ageing report lowers p̃ | PARTIAL | Critical → Significant |
| F11 | z saturation | PARTIAL | Critical → Significant |
| F12 | Pessimistic plug-in known | PARTIAL | Critical → Significant |
| F13 | "Risk-seeking"; strawman | PARTIAL (strawman dropped) | → Minor |
| F14 | n_eff not ESS | DEFENSE FAILS | Significant (stands) |
| F15 | Unconfigured edges, p̄→0 | PARTIAL | → Minor-Significant |
| F16 | Traversal silence prior art | PARTIAL | Minor (paper) / Significant (plan) |
| F17 | Feedback-loop novelty unmentioned | DEFENSE SUCCEEDS | Reclassify as recommendation |
| F18 | Decay known; ADR derivation error | PARTIAL | → Minor |
| F19 | Cite Hara and Rohmann | PARTIAL | → Minor |
