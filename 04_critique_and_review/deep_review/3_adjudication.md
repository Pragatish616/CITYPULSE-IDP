# CityPulse AI: Adjudication of review findings vs. author defense

Adjudicator: independent and evidence-only. Inputs were the D1–D5 findings and defenses and IDEA_AND_FACTS, plus spot checks against paper.tex.

I verified three points myself:
- **Abstract wording (L44).** The abstract says "caution grows as evidence thins" and "runs entirely on the phone".
- **Eq. (1)–(3) numbers.** I recomputed the key cases independently, and they reproduce:
  - D4-F1: 0.329 / 0.309 / 0.333 / 0.380 at z = 1.28, and 0.486 / 0.441 / 0.461 / 0.509 at z = 2.
  - D1-F10: 0.449 → 0.356 → 0.300 at z = 2.
  - Conflicting pair: 1.00 → 0.75.
- **D3-F11.** It is empty in findings.json as well.

Severity key: C = Critical, S = Significant, m = Minor. Tags: [paper] means the finding hits the submitted paper; [plan] means it hits only plan.tex or internal documents.

---

## D1: Novelty

| ID | Ruling | Reason |
|---|---|---|
| F1 | DOWNGRADE C→S; hub for related work (absorbs F19, F6, F12-citations, F3 prior-art half, D2-F5) | The defense is right that "these studies" is literally scoped. But the sentence is the paper's only stated point of departure, and Safaei 2023 (already in refs.bib) and Li/Song/Li 2026 falsify the implied generalisation. That makes it a related-work rewrite, not a falsified result. |
| F2 | DOWNGRADE C→S | The defense confirms "often stop working" is wrong as written, and that Google Maps India and Mappls flood alerts, RTFF and RiskMap are omitted. The novelty survives, so this is a framing and accuracy defect. |
| F3 | DOWNGRADE C→S; MERGE: prior art → D1-F1, unevaluated half → D2-F3 | The finding itself concedes that differentiators (a)–(d) survive. The 2026 apps are grey literature, but they must be cited. The title's promise of verified explanations is handled under D2-F3. |
| F4 | MERGE: item 1 → F12, item 2 → m (cite TomTom/HERE/Waze), item 3 → F10 | The defense correctly shows that item 2 vindicates the paper's critique of the "common alternative". Item 3 is subsumed by F10. |
| F5 | DOWNGRADE S→m [plan] | The paper never claims class-specific decay as new (L57–62), and C3≈C2 is disclosed. Only the plan wording needs changing. |
| F6 | DOWNGRADE S→m; MERGE → F1 | The exact combination survives; each component needs a citation and the wording "combines". |
| F7 | DOWNGRADE S→m; MERGE with D4-F8 | Prop. 2 is diagnostic and "New finding" appears only in the plan. The fact that it is elementary is a presentation issue. |
| F8 | DOWNGRADE S→m for paper (S for [plan] via D5-F2/F6) | These are plan-only claims. L151 and L171 overclaim; the RTFF overlap is folded into D5-F6. |
| F9 | DROP | An empirical evaluation contribution is standard. The residual scoping of "reproduces the router's paths" is kept as D3-F10. |
| F10 | KEEP Critical (hub; absorbs D4-F1, D1-F4.3, D4-F4.3) | Reproduced. The abstract (L44), contribution 1 and the conclusion (L255) all assert "caution grows as evidence thins", without the "fixed p̄" qualifier. On the real decay path, an ageing positive report lowers p̃ at every z. With D4-F1, the claim fails in both directions for the dominant source type. The "fixed p̄" defense is rhetorical, because p̄ is never fixed. |
| F11 | DOWNGRADE C→S (hub; absorbs D3-F8, D4-F5 item 5) | Saturation is real and undisclosed: at z = 2, p̃ = 1 on all 8,759 prior-only edges, so positive evidence cannot raise caution. The defense is correct that this is a ×2 soft penalty, not a mask. |
| F12 | DOWNGRADE C→S; MERGE → F1 | The construction is known (moment-matched Beta + z·sd ≈ Bayes-UCB / PEVI / Walley), but the paper cites UCB "used pessimistically". This is overclaiming in contribution 1, fixable by citation and rewording. |
| F13 | DOWNGRADE S→m (absorbs D4-F4 items 1–2) | Correct the term to "ambiguity-seeking". The strawman charge contradicts F4's own patent evidence. |
| F14 | KEEP S (hub; absorbs F15, D4-F5 items 2–4) | The defense fails on substance and concedes it. n_eff ignores α: five worthless reports cut p̃ from 1.0 to 0.60. Conflicting reports read as confidence. "Upper bound" is unearned. |
| F15 | MERGE → F14 (S) | Scope fact: about 97% of edges carry no penalty, and the Wald band collapses near 0 (0.218 vs Wilson 0.680). The defense accepts the scoping fix. |
| F16 | DOWNGRADE S→m for paper; MERGE → D5-F2 [plan] | It appears in the paper only as future work. The plan's moat language overclaims. |
| F17 | DROP as a defect | Traversal silence is not implemented, so this is a recommendation. It is kept as an author question. |
| F18 | DOWNGRADE S→m [plan] | The precedence point is already cited in the paper. The derivation error sits in an internal ADR. |
| F19 | DOWNGRADE S→m; MERGE → F1 | The five-way combination survives; add Hara 2019 and Rohmann 2026. |

## D2: Explanation and code

| ID | Ruling | Reason |
|---|---|---|
| F1 | SPLIT. Item 2 ("avoids X" while the chosen route crosses X) → MERGE into F4 (C). Items 1 and 3 → DOWNGRADE to S (hub; absorbs F14) | The defense confirms all three code paths. Item 1 is a contract-violating cost-vs-time sentence. Item 3 ("reported moments ago" with no report) is reachable in production because there is no depth data. |
| F2 | DOWNGRADE C→S; drop mechanism 3 | Harness labels never render text, so mechanism 3 goes. The uncaught throw that leaks unverified text, and the "unnamed stretch" label collision, are real but latent in a single-OD demo. |
| F3 | DOWNGRADE C→S (hub; absorbs D1-F3 half, F8, F10, F17) | Non-evaluation is disclosed three times. Still, the title ("with Verified Explanations"), the abstract and contribution 3 present it as delivered. Tiers 1/2 have never run, the cited test fixture is missing, and the prompt and verifier are mismatched ("Chennai", no hedge). |
| F4 | KEEP Critical (hub; absorbs F13, F1 item 2) | A1 (direction flip), A3 ("you can drive through … 320 mm") and F13 case 6 ("bridge is dry now, go ahead on Route B") all pass. The paper discloses only unit/subject binding and Tamil, not direction or polarity blindness. Table I's "speed comparison is unsupported" overstates the check. For a system titled "Verified Explanations", passable safety-inverting text is critical. A2, A4 and A5 fall under disclosed limits and are discounted. |
| F5 | MERGE → D1-F1 (S) | The defense concedes the missing citations: T2G2, DataTuner, NeMo, RouteExplainer, and Ilyankou 2026, which anticipates the architecture. |
| F6 | DOWNGRADE S→m | Correct but a one-threshold calibration issue. Report the band distribution. |
| F7 | KEEP S, narrowed (absorbs F19 gap part) | The 480-word median is a harness-label artefact. The inversion stands: low-prior unconfigured edges are flagged as gaps, while high-prior zero-observation edges are not. |
| F8 | DOWNGRADE S→m; MERGE → F3 | The latency figure is a prediction, and the fallback is safe. The point that the fact-set exceeds 512 tokens stands. |
| F9 | DROP | Tamil is mentioned only as a limitation. |
| F10 | MERGE → F3 (S) | The mechanics are confirmed, the magnitude is not measured, and the failure is safe. |
| F11 | DOWNGRADE C→S (hub; absorbs D4-F2) | §IV, Fig. 1, README and ADR-012 misdescribe the router. Routes are still exact. Prop. 1 is not load-bearing. |
| F12 | KEEP Critical | The defense fails. The abstract says "runs entirely on the phone", yet there is no device run, no on-device prior, no report→edge snapping, no reporting UI, and one fixed OD pair. The offline framing is the paper's identity. |
| F13 | MERGE → F4 | Duplicate. The plan L65/L72 inconsistency and the README "ever" claim are noted under F4. |
| F14 | MERGE → F1 items 1/3 (S) | Duplicate. |
| F15 | KEEP S | The defense fails. Late offline reports are skipped, which is the very case offline sync exists for, and paper L120's HLC claim is inaccurate. |
| F16 | DOWNGRADE S→m | Latent until the cache is wired to the router. One clamp fixes it. |
| F17 | MERGE → F3 | Duplicate. The missing `FakeSlmRewriter` is noted under F3. |
| F18 | DOWNGRADE S→m [plan/README] | The paper's only server claim is Fig. 1. |
| F19 | DOWNGRADE S→m; gap part → F7 | Say "context facts unused" and "one alternative". |
| F20 | DOWNGRADE S→m (repo hygiene) | This is the deprecated Kotlin prototype, not the paper. Retract the handoff document's "production-ready / life-saving" claim. |

## D3: Evaluation

| ID | Ruling | Reason |
|---|---|---|
| F1 | DOWNGRADE C→S; MERGE → F2 | The defense's own θ-sweep shows C3 still beats every C1 θ on Σp̄. But the ranking flips on metrics aligned with neither method, so "scored fairly … more than hard blocking" (L255) needs the alignment caveat. |
| F2 | KEEP Critical (hub; absorbs F1, F12, F14) | The defense's own decomposition confirms the C3λ5 − C1 gain is −0.28 on prior-only edges and +0.04 (worse) on observed edges. Add F12: on official-edge holdout, crowd+prior performs the same as prior-only. Add F14: crowd evidence worsens Brier against the prior. No reported number credits the fusion of crowd evidence, which is the method. The headline benefit is avoiding uncalibrated GCC zones, which a static mask could do. |
| F3 | DOWNGRADE S→m | Paired bootstrap CIs exclude 0 (ΔΣp̄ [−0.46, −0.07]). Add them to Table I. |
| F4 | KEEP S, narrowed | Soft beats hard across θ. However, the omitted hybrid (block > 0.5 plus λ = 5) gives 0.79 at 2.14% with 0% threshold crossings, which undercuts the "trade-off is forced" framing. Disconnections need reporting at lower θ. |
| F5 | DOWNGRADE S→m; MERGE → F1 | 356 of 364 edges with p̄ ≥ 0.5 are official-report edges. One sentence fixes it, within the conceded circularity. |
| F6 | DOWNGRADE S→m | Relabel the metric as "believed Σp̄ over configured edges". It affects levels, not the sign of comparisons. |
| F7 | DOWNGRADE S→m | Describe the sampler. Absolute levels are trip-length artefacts. |
| F8 | MERGE → D1-F11 (S) | This is a formulation mechanism. |
| F9 | DOWNGRADE S→m | Scale N; the +0.026 s CI excludes 0 trivially. |
| F10 | DOWNGRADE S→m | The cost is verified identical. Scope the contribution bullet to the three traced configurations. |
| F11 | DROP | The finding is empty. |
| F12 | MERGE → F2 | It is weak evidence given the label limits, but it is the only quasi-independent test, and its direction is negative. |
| F13 | KEEP S (from C) | The paper concedes the point in the body (L178, L214). The abstract and conclusion still state "no advantage of class-specific decay", which implies a test that could not discriminate. Replace with "untestable on this corpus". |
| F14 | DOWNGRADE C→S; MERGE → F2 | The paper does not claim that faster decay wins. The omission (crowd evidence hurts Brier against prior-only) stands. |
| F15 | DOWNGRADE C→S; MERGE → F16 | Negative Brier skill (−0.70) is derivable but unstated. |
| F16 | DOWNGRADE C→S (hub; absorbs F15, F17, F18, F22) | The defense fails on the facts. Within coverage, AUROC is 0.46, and edge length alone gives 0.65. The paper concludes only "weak", but the abstract headlines 0.61. |
| F17 | MERGE → F16; drop the "arithmetically false" charge | The defense is right that 29,256 + 5,000 = 34,256. The undisclosed easy-negative pool inflates the abstract AUROC. |
| F18 | MERGE → F16 | The "collider" framing is overstated. Edge-resolution co-location sensitivity stands. |
| F19 | DOWNGRADE S→m | State that the label rate is flat across bins. |
| F20 | DOWNGRADE S→m | The diagnosis sentence is wrong (no base rate, min p = 0.5), but the comparison is already disclaimed. |
| F21 | DOWNGRADE S→m | Report 4,876 edges / 118 positives with edge-level CIs. |
| F22 | DOWNGRADE S→m; MERGE → F16 | The hotspot layer is a vulnerability designation; describe it as such. |

## D4: Formulation

| ID | Ruling | Reason |
|---|---|---|
| F1 | MERGE → D1-F10 (C) | Reproduced. The defense fails: crowd reports (α = 0.6 < α* ≈ 0.63–0.65) are 82% of the corpus, and a proper Beta quantile does not dip. |
| F2 | MERGE → D2-F11 (S) | Duplicate. |
| F3 | KEEP Critical (reclassified as implementation/evaluation) | Reproduced by both sides. 5,177 of 5,775 observed edges have a reverse twin with no evidence, contradicting Eq. (1), whose kernel would weight the twin identically. Every exposure number undercounts. All studies must be re-run, and a flooded two-way street is penalised one way only in deployment. The defense itself argued to keep it high. |
| F4 | MERGE → D1-F13 (m); item 3 → D1-F10 | Duplicate. |
| F5 | MERGE: items 2–4 → D1-F14 (S), item 5 → D1-F11, items 1 and 6 → m | The "+1" reading and the UCB analogy are wording issues. The conclusion's mention of a Wilson-type bound (L255) does not disclose these defects. |
| F6 | DOWNGRADE S→m | The paper never claims Bayes and discloses independence. State the symmetric-channel and tempering assumptions; cite the k-table in Threats. |
| F7 | KEEP S (hub; absorbs F9 item 3) | Items 1–3 are presentation. Item 5 stands as a safety gap the paper's description hides: a fresh 320 mm report on a p0 = 0.02 edge stays open for commuters at 1.4τ0. Item 3 of F9 also stands: one car-fitted curve and one h_max for all classes, while the code claims a pedestrian threshold. |
| F8 | DOWNGRADE S→m; MERGE with D1-F7 | The defense succeeds on substance. Fix notation (s_{c(e)}, H2 ≥ 0); consider calling it a "Remark". |
| F9 | DOWNGRADE S→m (items 1–2); item 3 → F7 | Above-h_max depths are usually removed, and the δ = 1 region should be described honestly. |
| F10 | KEEP S | Undefended for deployment: there is no event gating, so on dry days emergency vehicles pay 2τ0 on every p0 ≥ 0.25 edge. Replay results are unaffected. |

## D5: Business plan [plan]

| ID | Ruling | Reason |
|---|---|---|
| F1 | DOWNGRADE C→S | There is no evidence any Indian fleet buys passability data, and the team's own notes rank fleets last. Relabel as a hypothesis. Drop the "no segment-level decisions" sub-point (Blinkit blacklisting). |
| F2 | DOWNGRADE C→S (hub; absorbs D1-F16, D1-F8 L151/L171) | "Nobody can buy it" is false as stated. A pooled-aggregate moat is untested. |
| F3 | DOWNGRADE C→S | This is a real contradiction with ADR-011, and the API layer has no verifier. A rename plus API terms fixes it cheaply. |
| F4 | DOWNGRADE C→S, narrowed | The cash-timing defense holds. Placing vendor outreach in weeks 8–12 does not. |
| F5 | KEEP S, narrowed | The "WhatsApp only" description omits Google and Mappls alerts. The "citizen app = sensor network" line contradicts the passive-fleet story. The RiskMap question stands. |
| F6 | DOWNGRADE S→m; MERGE with D1-F8 | Recast RTFF as an input; differentiator #4 overstated. |
| F7 | DOWNGRADE S→m | The insurer path is already labelled a hypothesis; add parking advisories. |
| F8 | KEEP S | WTP after the pilot, about 2 weeks of lead time, monsoon-peak bandwidth and likely exam overlap all stand. The entity/DPA prerequisite is overstated for an unpaid pilot. |
| F9 | DOWNGRADE S→m | DPDP advancement is unconfirmed. Add one risk row. |
| F10 | DOWNGRADE S→m | The narrow uniqueness survives. The table is incomplete. |
| F11 | DOWNGRADE S→m | Lead with resilience, not cost. |
| F12 | KEEP S | The defense fails: no LOI, pilot or conversion metrics, and no non-dilutive track despite the team's own notes. |

---

## Surviving issues, ranked

### Critical
1. **D1-F10 (+D4-F1).** The headline property in the abstract, contribution 1 and the conclusion ("caution grows as evidence thins") is false on the real evidence paths, and I reproduced the numbers. An ageing positive report lowers p̃ at every z. A fresh crowd report (α = 0.6, 82% of the corpus) lowers p̃ for every z > 0 class until about three reports concur.
2. **D4-F3.** Each observation is snapped to one directed edge, so 5,177 of 5,775 observed edges have an unpenalised reverse twin. This contradicts Eq. (1), biases every reported exposure figure, and is a live one-way-penalty bug.
3. **D3-F2 (+F1, F12, F14).** Nothing credits the fusion layer. The soft-over-hard gain comes entirely from prior-only GCC-zone edges (it is worse on observed edges), crowd+prior equals prior-only against held-out official edges, and crowd evidence worsens Brier against the prior alone.
4. **D2-F4 (+F13, F1-item 2).** "Verified" explanations can be false and unsafe yet pass. Tier 0 says "avoids X" while routing through X, and the verifier accepts direction-flipped comparatives and "the bridge is dry now, go ahead on Route B". None of this falls under the paper's disclosed limits.
5. **D2-F12.** "Runs entirely on the phone" is not implemented: there is no device run, no on-device prior, no report-to-edge snapping, no reporting UI, and one fixed OD pair.

### Significant
- **Related work and novelty.** D1-F1 (+F3 prior art, F6, F12, F19, D2-F5): the stated departure point is false, and each component (Bayes-UCB/PEVI-style index, separated costs, template→LM→gate) has uncited precedent. Novelty reduces to the combination.
- **Motivation.** D1-F2: the motivating sentences are inaccurate, and Google Maps India/Mappls flood alerts, RTFF and RiskMap are omitted.
- **Saturation.** D1-F11 (+D3-F8, D4-F5.5): z saturates, giving the emergency class p̃ = 1 on all 8,759 prior-only edges, and this is undisclosed.
- **Validity of Eq. (3) as a bound.** D1-F14 (+F15, D4-F5.2–4): n_eff ignores α, conflict reads as certainty, the Wald band collapses near 0, and about 97% of edges are unpenalised. Eq. (3) is not a bound.
- **Prior semantics.** D4-F10: the static susceptibility prior is used as P(flooded now), with no event gating.
- **Depth rule.** D4-F7 (+F9.3): the depth rule is inert without depth data and leaves reported deep water open for commuters on low-prior edges. One car curve and one h_max are used for all classes.
- **Router description.** D2-F11 (+D4-F2): the router does not use ALT, so §IV, Fig. 1 and ADR-012 misdescribe the system.
- **Explanation evaluation.** D2-F3 (+D1-F3 half, F8, F10, F17): explanation tiers are unevaluated and have never executed, though the title promises them.
- **Trace semantics.** D2-F1 items 1/3 (+F14): "N minutes slower" compares penalised cost with free-flow time, and the template invents "reported moments ago" for prior-only edges.
- **Tier-0 failure.** D2-F2: a Tier-0 failure throws uncaught, so no route is shown and the banner prints the unverified text.
- **Sync.** D2-F15: the HLC is decorative, and late offline reports are skipped by sync.
- **Data gaps.** D2-F7 (+F19): data gaps are inverted, flagging low-prior edges and missing high-prior unobserved ones.
- **Study 2 headline.** D3-F16 (+F15, F17, F18, F22): AUROC 0.61 is driven by coverage and edge-length confounds plus 5,000 undisclosed easy negatives, and Brier skill is negative.
- **Decay wording.** D3-F13: the abstract's "no advantage of class-specific decay" implies a test the corpus cannot perform.
- **Baseline.** D3-F4: the hybrid baseline is missing, and it removes the presented trade-off.
- **Plan.** [plan] D5-F1 (fleet-first revenue is unsupported), D5-F2 (+D1-F16; the moat is overclaimed), D5-F3 ("passability" contradicts ADR-011), D5-F4 (vendor outreach is too late), D5-F5 (consumer segment and RiskMap precedent), D5-F8 (sequencing and exams), D5-F12 (no funding or commercial-validation metrics).

### Minor
- D1-F5 [plan], D1-F7 (+D4-F8), D1-F8 (+D5-F6), D1-F13 (+D4-F4), D1-F18 [plan]
- D2-F6, D2-F16, D2-F18, D2-F19, D2-F20
- D3-F3, D3-F5, D3-F6, D3-F7, D3-F9, D3-F10, D3-F19, D3-F20, D3-F21
- D4-F6, D4-F9 (items 1–2)
- D5-F7, D5-F9, D5-F10, D5-F11

**Dropped:** D1-F9, D1-F17 (kept as a recommendation), D2-F9, D3-F11.

---

## Questions for authors
1. Replace Eq. (3) with a posterior quantile (Beta or Wilson) using an α-weighted, conflict-aware n_eff. Does any Study 1 or sweep conclusion change?
2. After assigning evidence to both directions of two-way streets, do the C3-vs-C1 and share-crossing results still hold?
3. Can you show any setting where crowd evidence beats prior-only routing or calibration against ground truth independent of GCC products, for example time-stamped 2023 Michaung data?
4. Has the app run on a physical Android device? What are the end-to-end latency, memory use and on-device prior footprint (the prior file is 152 MB)?
5. After fixing direction, polarity and trace semantics, what are the verifier's pass, false-reject and detection rates on real Tier 1/2 outputs and on third-party adversarial text?
6. How is the prior conditioned on an active flood event? What does the emergency class do on a dry day?

## Overall assessment
**Recommendation: reject in current form (it would need a major revision to be competitive).**

The paper is unusually candid. It reports weak calibration, a circular reference, deterministic reproduction and an independent router check. But it fails on three fronts:
- **Central claim.** "Caution grows as evidence thins" is arithmetically false along real evidence paths.
- **Evaluation.** The evaluation credits no benefit to fusing crowd evidence: every gain comes from avoiding uncalibrated static prior zones.
- **Implementation.** The implementation departs from the described system: one-directional evidence, no ALT, no device run, and HLC sync that does not work as described.

The "verified explanation" half is unevaluated, and its shipped verifier passes unsafe sentences. Novelty is a narrow combination of known parts. All of these are fixable: a proper posterior quantile, twin-edge evidence, a time-stamped independent corpus, a measured verifier, and honest abstract wording. Together they amount to a new paper.
