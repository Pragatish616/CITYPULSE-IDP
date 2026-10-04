# D4 formulation: defense report

Defense agent arguing for the authors. Every finding was checked against the paper (`drafts/paper.tex` lines 79–120), the code, and a numpy/scipy recomputation. All numbers quoted in the findings reproduced exactly: F1 table, α*, F5 Wilson/saturation roots, F6 k-table and Jensen gap, F7-5, F9 v(300)/vertex/δ=1 roots, and F3 twin counts 6,132 / 5,775 / 5,177 / 2.

| ID | Verdict | Recommended severity | Confidence |
|---|---|---|---|
| F1 (C1) | DEFENSE FAILS (scope narrowed) | Critical | High |
| F2 (C2) | PARTIAL | Significant | High |
| F3 (C3) | PARTIAL (reclassify as implementation) | Critical, as an implementation/evaluation defect | High |
| F4 (S1) | PARTIAL | Significant → Minor/Moderate | Medium-high |
| F5 (S2) | PARTIAL | Significant (items 1, 2, 6 → Minor) | High |
| F6 (S3) | PARTIAL | Significant → Minor | Medium-high |
| F7 (S4) | PARTIAL | Significant → Minor (items 4–5 stay as code notes) | Medium |
| F8 (S5) | DEFENSE SUCCEEDS on substance | Significant → Minor (presentation) | High |
| F9 (S6) | PARTIAL | Significant → Minor, except item 3 | Medium-high |
| F10 (S7) | PARTIAL | Significant (no change), framed as a modelling choice to justify | Medium |

---

## F1 [C1]: A positive crowd report lowers p̃ for z > 0
- **Strongest defense.** The paper's formal statement is conditioned on fixed p̄ (line 92), and that statement is true. For z = 0 (the default commuter class), p̃ = p̄ rises with every positive report. For every non-crowd source the monotonicity also holds: α_official = 0.92 takes p̃ from 0.329 to 0.816 at z = 1.28, and the same applies to sensor (0.97), responder (0.90) and app_traversal (0.70). All of these sit above α* ≈ 0.62–0.65.
- **What I checked.** I recomputed the table: 0.329/0.309/0.333/0.380 at z = 1.28 and 0.486/0.441/0.461/0.509 at z = 2. α* is 0.635/0.627/0.624 at z = 1.28 and 0.647/0.644/0.647 at z = 2 for p0 = 0.02/0.05/0.10. I also checked what a coherent Bayesian rule does: under a Beta posterior, a positive observation always raises the 97.7% quantile (0.244 → 0.387, 0.180 → 0.253, 0.496 → 0.872). The dip is therefore an artefact of Eq. (3), not "rational narrowing". `pessimistic.dart:40`, `fusion.dart:139–140`.
- **Verdict: DEFENSE FAILS.** Crowd reports make up 5,052 of the 6,132 observations. The interpretive sentence ("thin evidence produces more caution"), the abstract, and contribution 1 all fail for the source type that dominates, under exactly the classes where z matters. The finding should state its scope precisely: z > 0 and α < α*.
- **Confidence:** High.

## F2 [C2]: The production router does not use ALT
- **Strongest defense.** No reported number is wrong. Plain bidirectional Dijkstra is exact, so every route and metric in §VI is unaffected. The lemma inside Proposition 1 (w ≥ τ0) is true, and the empirical minimum ratio of 1.0 checks the cost function, which *is* on the query path. ALT exists (`alt_landmarks.dart:195`), is tested, and the paper credits the property to Delling & Wagner (line 69) rather than claiming it as new.
- **What I checked.** `query_orchestrator.dart:155–168` makes two `bidirectionalDijkstra` calls and no landmark call. Grepping `pulse_router/bin` and `apps` for landmark/AltLandmarks returns nothing; the only consumer is the test. `docs/DECISIONS.md:424` attributes CLI time to "ALT landmark rebuild", which also contradicts the code.
- **Verdict: PARTIAL.** Downgrade from Critical to Significant. This is a false architecture statement (§IV) and makes Proposition 1 non-load-bearing; it is not a correctness failure. Fix: either wire `aStarWithLandmarks` into `planRoute`, or reword §IV and demote Proposition 1 to a remark about future acceleration. The "minimum ratio 1.0 as Proposition 1 requires" sentence should be reworded as a check of the cost lower bound.
- **Confidence:** High.

## F3 [C3]: Nearest-edge snapping means only one direction of a flooded two-way street carries evidence
- **Strongest defense.** Eq. (1) as a formulation is fine. Nearest-edge assignment is a common truncation of a kernel, and κ is still applied to the snap distance. The reference belief used for scoring has the same asymmetry, so C0 and C3 are compared on equal footing.
- **What I checked.** The counts reproduce exactly: 6,132 snaps, 5,775 observed edges, 5,177 with a reverse twin, and only 2 twins that also carry evidence (graph `chennai_graph_cli.json` plus `edge_snap_index.json`). `t3_2_replay_engine.py:124–137` groups observations strictly by `edge_id`. The twin has the same geometry, so d(e_twin, x_i) equals the snap distance, and Eq. (1) would assign it the *same* weight. The implementation therefore contradicts the equation; it is not just a truncation of it.
- **Verdict: PARTIAL.** Reclassify from "formulation" to "implementation/evaluation". Keep the severity high: about 90% of the evidence is one-directional, so every exposure number (Σp̄, the share of routes with p̄ ≥ 0.5) undercounts exposure on reverse traversals for every configuration. The equal-footing argument limits bias in the *comparison* but not in the absolute numbers.
- **Confidence:** High.

## F4 [S1]: "Risk-seeking under ambiguity" is mislabelled and overstated
- **Strongest defense.** Ignoring item 1, the paper's argument is aimed at the specific practice of letting the penalty go to zero as C → 0. Item 2 of the finding concedes the argument is right whenever the no-information default should be the prior. That is exactly the paper's setting, because ageing evidence returns to ℓ0. Item 3 reduces to F1 and should not be counted twice.
- **What I checked.** Lines 94 and 58. With z = 0, p̃ = p̄ → p0 as the report ages; R·C → 0. At z > 0 for official sources p̃ also falls with age, and at that point the difference from R·C is only the floor.
- **Verdict: PARTIAL.** Item 1 (terminology): accept. "Ambiguity-seeking" is correct, and it is a one-word fix. Item 2: narrow to "state that the argument assumes the prior, not 0, is the correct no-information default". Item 3: merge into F1. Downgrade to Minor/Moderate.
- **Confidence:** Medium-high.

## F5 [S2]: The pessimistic bound is not a proper confidence bound
- **Strongest defense.** The paper already names the remedy, "a Wilson-type bound in place of (3)" (line 255), so the Wald weaknesses are acknowledged. Unsigned n_eff is a documented design choice (`fusion.dart:32`). Because the corpus has no negative reports, item 3 cannot affect any reported result. Saturation at z = 2 (item 5) is the intended behaviour, maximum caution with no evidence, for emergency vehicles.
- **What I checked.** Conflict cases: 1.00 → 0.75 at p0 = 0.25, z = 2, and 0.329 → 0.211 at p0 = 0.05, z = 1.28. At p̄ = 0.02, n = 1, z = 2 the bound gives 0.218 against Wilson's 0.680. Saturation roots are 0.2000 (z = 2) and 0.379 (z = 1.28). `pessimistic.dart:40`. ADR-002 gives no rationale for the "+1" (grep found no pseudo-count or Laplace text).
- **Verdict: PARTIAL.**
  - Items 3, 4 and 5 stand on theory. Item 3 is the strongest because it repeats the F1 mechanism.
  - Item 5 is partly defended as intended caution, but the paper should say that under z = 2 the bound carries no information on all 8,759 prior-only edges.
  - Item 1 (the "+1") and item 2 (units) are Minor: state the reading.
  - Item 6 (UCB analogy) is Minor wording.
  - Overall remains Significant.
- **Confidence:** High.

## F6 [S3]: The log-odds sum is a heuristic, not Bayesian
- **Strongest defense.** The paper never claims exact Bayesian conditioning. A grep for "Bayes" in paper.tex finds nothing. It cites the occupancy-grid inverse-sensor model, which is exactly logit(α) as a symmetric-channel LLR (line 86). It states the conditional-independence assumption and revisits correlation in §VII, including the 2,806 duplicates. Tempered or power likelihoods are a recognised generalised-Bayes and forgetting device (power priors; Jøsang's forgetting factor, which the related work cites).
- **What I checked.** Mixture versus power: 1.833 versus 1.221 at α = 0.92, κ = 0.5. The k-table reproduces (0.073/0.151/0.752/0.9999). `fusion.dart:138–140`.
- **Verdict: PARTIAL.** Downgrade to Minor. Ask the authors to (a) state the symmetric-channel assumption, (b) call ω a tempering or discount weight rather than a likelihood, and (c) reference the k-table saturation in the Independence threat. None of these points changes a result.
- **Confidence:** Medium-high.

## F7 [S4]: The point-approximation chance constraint fails open
- **Strongest defense.** The paper's own wording, "a point approximation" (line 101), concedes that this is not the true chance constraint. §VII states that the corpus has no depth, so the constraint is untested, and the T3.2 result.json says it never fires. When depth is unknown the soft λ-penalty still applies, so "fails open" means "falls back to the soft cost", not "no protection". Item 4's premise that "p̃ does not fall below p0" is false in general: app_traversal (α = 0.70) supplies polarity −1 evidence.
- **What I checked.** `edge_cost.dart:101–105`. `query_orchestrator.dart:53–56` confirms depth is the newest reading and is not decayed. For item 5: p̄ = 0.0297, cost 1.41·τ0, δ = 14.46, which reproduces.
- **Verdict: PARTIAL.** Items 1–3 and 6 are presentation issues: say "deterministic depth rule gated by p̃", not an approximation of Pr[h > h_max] ≤ ε. Item 4 should be narrowed to "stale depth persists unless negative evidence arrives". Item 5 stands as a code note (z = 0 commuters keep a reported 320 mm edge open). Downgrade to Minor overall.
- **Confidence:** Medium.

## F8 [S5]: Proposition 2's assumptions and notation
- **Strongest defense.** The finding itself confirms the bound, the necessary-condition reading ("only if"), and the 18 s example. Its item 4 assumption that no edge is removed is *implied* by the premise: removal requires a depth above h_max (≥ 200 mm), while δ = 1 with known depth requires h < 166 mm.
- **What I checked.** δ = 1 roots are 166/131/102/76/53/32 mm for 20–70 km/h, all below 200. `edge_cost.dart:101–110`.
- **Verdict: DEFENSE SUCCEEDS on substance.** Keep as Minor presentation: index s by edge (s_{c(e)}), say H2 ≥ 0 in the proof, consider calling it a Remark, and state the per-traversal harm fix in §III.
- **Confidence:** High.

## F9 [S6]: Pregnolato curve handling
- **Strongest defense.** Depths above h_max are removed by the chance constraint whenever p̃ ≥ ε (flood h_max = 300, waterlogging 200). The "finite δ ≈ 14.5" therefore governs only exactly 300 mm or the low-p̃ case in F7-5. A v_safe of 2.07 km/h is effectively standstill. The code flags the coefficients as [UNVERIFIED DETAIL] and clamps deliberately to the fitted domain.
- **What I checked.** v(300) = 2.075 km/h, vertex at 307.2 mm, δ = 1 roots as above (`depth_disruption.dart:26–33, 49–59`). `vSafe <= 0` is unreachable because the minimum of v on [0, 300] is 2.07. `h_max_mm_pedestrian` is read nowhere, yet `decision_trace.dart:57` claims the pedestrian class "uses a lower depth threshold".
- **Verdict: PARTIAL.** Items 1 and 2 are Minor: mention the removal interaction and describe the δ = 1 region honestly. Item 3 (scope) **stands**: one car-fitted curve and one h_max for all classes, plus a code comment claiming otherwise. This is Moderate.
- **Confidence:** Medium-high.

## F10 [S7]: The static prior is used as P(flooded now)
- **Strongest defense.** The 0.02–0.45 values are documented as "planning defaults", and the system is pitched for monsoon or event use. In that regime susceptibility given an event is the operative quantity, and on the 2015 replay the event is in progress, so the reported results are conditioned on an event.
- **What I checked.** A grep of DECISIONS.md for season, dry, activation or event-mode gating finds nothing. No code path conditions the prior on an active event. `query_orchestrator.dart:120–134` applies ℓ0 to every hazard-config edge at every query.
- **Verdict: PARTIAL.** Results are unaffected because the replay is an event. The deployed system, however, would charge emergency vehicles 2τ0 on every edge with p0 ≥ 0.25 on dry days. The authors must either gate the prior on an event state or redefine it as conditional. Severity stays Significant.
- **Confidence:** Medium.
