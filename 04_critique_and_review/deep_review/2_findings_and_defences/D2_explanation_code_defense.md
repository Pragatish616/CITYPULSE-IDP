# D2 Explanation / Code — Defense Report

Defense agent for the CityPulse AI authors. I read the code directly. Dart was not available, so I traced the verifier, template and orchestrator logic by hand and did not run a port. One web search confirmed that arXiv 2603.14586 exists.

Paths: `IDP` = /mnt/user-data/uploads/citypulse-IDP/citypulse-IDP, `KT` = /mnt/user-data/uploads/citypulse-ai.

---

## F1 [Critical] C1 — The trace that the verifier grounds against has the wrong semantics
**Strongest defense:** The paper claims only that the text is checked "against the router's decision record". That is literally true: the verifier is faithful to the trace. Part 1's size is bounded. The chosen route is the one that minimises λ·p̃·s·τ0, so its penalty is usually small (λ = 0.3 in the commuter default). The authors' own contract (CONTRACTS.md §3: "`free_flow_duration_s` lets the explanation say '4 minutes slower' truthfully") shows they meant a free-flow comparison, so this is a one-line template bug, not a design flaw. Part 3 cannot be reached in the shipped demo, where the blocking edge has an observation, or in the harness, which never renders text.
**Checked:** query_orchestrator.dart:197 (`durationSeconds: chosenResult.totalCostSeconds`) and :277 (alternative = free-flow `totalCostSeconds`). edge_cost.dart:108–110 (cost = τ0[1+p̃(δ−1)] + λp̃sτ0, so the second term is not time). template_renderer.dart:113–122. Orchestrator :241–256: the `higher_cost` worst edge is taken over `altEdges` with no exclusion of edges shared with the chosen route. Orchestrator :333–335 (age = 0.0 when there is no observation) and template :142–143 (age 0 renders as "moments ago"). edge_cost.dart:101–102: the chance constraint needs `depthMm != null`, so with no depth data every alternative goes through the `higher_cost` branch, where a prior-only worst edge is possible.
**Verdict:** PARTIAL. All three defects are real in code. Narrow as follows. (1) A one-line fix that the contract already prescribes; its size is unmeasured. (2) Stands. Saying "avoids X" while the chosen route crosses X is the most serious of the three. (3) Latent: not reachable in the shipped demo or in Study 1, but reachable in production because there is no depth data. Keep at Critical only on the strength of (2); otherwise Significant. Merge with F14.
**Confidence:** High.

## F2 [Critical] C2 — Tier 0 fails by crashing, and the crash path shows unverified text
**Strongest defense:** The `StateError` is a deliberate invariant assertion ("this must never happen"). The fail-closed claim in the paper is about Tier 1/2 → Tier 0, and `verifyOrFallback` implements that correctly. The shipped app runs one OD pair. Its integration test asserts `explanation.verification.passed == true` against the real graph, with blocking edge "Mambalam Canal Bridge", which has its own unique label. Mechanism 3 ("edge <id>" labels, 300/300) is not a system failure at all: the CLI does not depend on `pulse_explain` and never renders text.
**Checked:** template_renderer.dart:67–80 (the message embeds the text). route_service.dart:87 (`'an unnamed stretch'` fallback) and :99 (no try/catch). home_screen.dart:47–52 (prints `snapshot.error`). verifier.dart:472–504: with blocking street == data-gap corridor, the stripped remainder still holds "avoids"/hazard noun/age digit, so I hand-traced this to `rule3:data_gap_contradiction`. verifier.dart:201–217 (rule 1 scans the whole text, including corridor digits). app/test/route_service_integration_test.dart:32,44. pulse_router/bin/pulse_router.dart has no renderTemplate.
**Verdict:** PARTIAL. Drop mechanism 3: the harness never claims to render explanations, and the paper says the explanation layer is not evaluated. Mechanisms 1 and 2 are real but latent. The shipped single-OD demo passes, and both trigger as soon as an OD picker or more real labels exist. The demo label file includes "100 Feet Road", "70 Feet Road", "2nd Border Street" and "Vijayanagar 1st Main Road", so whether the demo passes rule 1 depends on which of these are on the chosen route; I could not confirm this without Dart. The design defects stand: the uncaught throw, the error banner that leaks the failing text, and the absence of any last-resort fallback. Downgrade to Significant (latent, one try/catch plus a constant safe string fixes it).
**Confidence:** High on the code paths; medium on how often it happens.

## F3 [Critical] C3 — The verifier is claimed as a contribution but is unevaluated; Tiers 1/2 never ran
**Strongest defense:** Contribution 3 claims "the *design* of an offline-first system with … a fail-closed explanation verifier". Sec. IV-B says "this paper reports the design only", and Threats says "described, not evaluated". A design contribution with disclosed non-evaluation is legitimate in a systems paper. The rewriter file itself has a prominent "never been run against real model weights" banner.
**Checked:** paper.tex:60, :149, :251. flutter_gemma_rewriter.dart:5–22. A grep finds no `FlutterGemmaRewriter(`/`CloudRewriter(` instantiation in app/lib. route_service.dart:104–112 shows that rewriter defaults to null.
**Verdict:** PARTIAL. Downgrade to Significant. The disclosure is honest and appears in three places. The remaining problem is the abstract (paper.tex:44: "explains each route through … a language-model rewrite that must pass a symbolic check"), which presents Tier 1/2 as working. The fix is wording ("is designed to") plus moving the verifier from contribution to design. The point that a 30-case self-authored suite is not a detection-rate measurement stands.
**Confidence:** High.

## F4 [Critical] C4 — Adversarial sentences pass the verifier
**Strongest defense:** The paper says the checks are "deliberately incomplete" and "the numeral check does not bind a number to its unit or subject". That disclosure covers A4 (1% matching p̃ = 1.0; 0% matching z = 0) and the absolute-delta grounding in A1. Table I's safety row says "(denylist)". The verifier's header comment cites ADR-011, which says the denylist "will both over- and under-trigger" and must not be read as meeting the recall bar (A2, A3). The header also discloses that "neither check performs general claim-to-fact binding" (A5).
**Checked:** verifier.dart:191 (digit-only regex, `%` stripped at :205–211). :261 (`(chosen − alt).abs()`). :397–400: the speed comparative checks only `alternatives.isEmpty`, so the direction is never checked. :550–572 (substring denylist with no "drive through" or "no flooding"). :290–316 (stop words include "There" and "You"). verifier.dart:63–72 (disclosed binding gap). Hand-traced A1 and A3 against `buildTrace()` (band moderate, so rule 4 is inactive): both pass.
**Verdict:** PARTIAL. Partly overstated: A2 to A5 fall under limitations the authors already disclosed (numeral unbinding, denylist, no claim binding), though the paper should list them concretely. A1 stands: direction-blindness is not disclosed, and Table I's "a speed comparison is unsupported" over-describes a check that only tests whether an alternative exists. The fix is cheap: compare the comparative word with `sign(chosen − alt)`. Downgrade to Significant, keeping A1 and A3 as headline examples. Merge with F13.
**Confidence:** High.

## F5 [Significant] S1 — Novelty overstated; closest prior work not cited
**Strongest defense:** The claimed novelty is the combination: belief routing with pessimism, an offline-first design, a typed decision trace, and a symbolic gate. It is not "template-then-rewrite" on its own. arXiv 2603.14586 ("The Scenic Route to Deception…") appears to be a position/pitfalls paper that proposes an architecture, not a built system. That makes CityPulse a concrete instance, which is still a contribution once evaluated.
**Checked:** paper.tex:56 and Sec. II-D. A web search confirmed that arXiv 2603.14586 exists. I did not verify the other DOIs.
**Verdict:** PARTIAL. The missing citations stand and should be added, especially T2G2, DataTuner, NeMo Guardrails, RouteExplainer, the contrastive route-explanation work and 2603.14586. The novelty framing should be narrowed to "implementation + routing integration". Keep at Significant, but this is a related-work fix, not a correctness issue.
**Confidence:** Medium; the citations were not all verified.

## F6 [Significant] S2 — The confidence band carries no information
**Strongest defense:** Reporting the worst band, with `low` as the default when no hazard edge is touched, is a deliberate conservative policy (ADR-011: no single-colour all-clear). In a sparse-evidence regime, "low" is the truthful answer, not a defect. The band varies when evidence varies: the fixture case is `moderate`.
**Checked:** decision_trace.dart:440–495 (`lowNEffThreshold = 1.0`). query_orchestrator.dart:371–396 (`worst ?? ConfidenceBand.low`) and the comment at :398–403, which admits it is "not yet in any ADR". The integration test expects `low` for the demo.
**Verdict:** PARTIAL. The observation is correct: the band is constant in practice, so rule 4's hedge never discriminates. The underlying cause is one threshold (n_eff < 1 with κ < 1) and is easy to recalibrate. Downgrade to Minor/Significant. Ask the authors to report the band distribution and justify or retune the threshold.
**Confidence:** Medium. I did not recompute the 300/300 figure.

## F7 [Significant] S3 — Data gaps mark every unconfigured edge
**Strongest defense:** CONTRACTS.md makes `data_gaps` mandatory ("absence of data is not absence of hazard"). The 480-word median is an artefact of the harness's per-edge `edge <id>` labels, which defeat the street-level deduplication. With real labels, gaps are deduplicated by street, and in the app every unlabeled edge collapses to the single string "an unnamed stretch". "No recent hazard data" is literally true of a prior-only edge, because the prior is not recent.
**Checked:** query_orchestrator.dart:284–293 (gaps only for edges *without* a config; dedup by label). template_renderer.dart:165–173 (lists all of them).
**Verdict:** PARTIAL. Narrow it: the word-count number reflects the harness labels, not production. One real inversion stands. Low-prior, unconfigured edges are flagged as gaps, while high-prior configured edges with zero observations are not (see F19). That is the opposite of what a user needs. A cap or summary on the gap sentence is also needed. Keep at Significant only for the inversion.
**Confidence:** Medium-high.

## F8 [Significant] S4 — Tier 1 is unlikely to meet 1.2 s on the target phone
**Strongest defense:** This is a prediction, not an observed defect. The paper discloses "no on-device timing on a low-cost phone is reported". By design, missing the deadline falls back silently to the correct Tier 0 text, so the cost is fluency, not safety. `getActiveModel` may return an already-loaded instance after the first call; this is unverified.
**Checked:** flutter_gemma_rewriter.dart:47–60 (`maxTokens = 512`; `getActiveModel` + `createChat` on every call). rewrite_pipeline.dart:38 (`.timeout(timeout)` inside a try/catch).
**Verdict:** PARTIAL. Downgrade to Minor ("risk to flag"), except for the concrete point that the fact-set prompt can exceed the 512-token context. That point stands and interacts with F7.
**Confidence:** Medium.

## F9 [Significant] S5 — Tamil mentioned as if supported
**Strongest defense:** The paper mentions Tamil exactly once, as a limitation: "does not transfer to Tamil script". The code says "Tamil templates are future work". Nothing claims Tamil output exists. Rule behaviour under Tamil output is hypothetical because no Tamil path exists.
**Checked:** paper.tex:149 is the only "Tamil" hit. explanation.dart:133.
**Verdict:** DEFENSE SUCCEEDS. Drop it, or reduce it to a one-line Minor wording fix: state "the explanation layer is English-only".
**Confidence:** High.

## F10 [Significant] S6 — False-reject rate probably high; LM tiers may add nothing
**Strongest defense:** False rejects are the intended safe failure mode. A rejected rewrite falls back to a correct Tier 0 text, so the system gives up fluency, never safety. The paper does not claim any rewrite pass rate.
**Checked:** verifier.dart:282–328 (25 stop words; "Heavy", "Chennai" and "It's" are not grounded). :510–540 (hedge list). flutter_gemma_rewriter.dart:72: the prompt itself says "used in Chennai" and asks for no hedge, while every band is `low` (F6).
**Verdict:** PARTIAL. The mechanics are confirmed, but the size is a prediction. Keep as Significant only as "the prompt and the verifier are mismatched (Chennai, hedge), so LM tiers will mostly be rejected". The fix is a prompt change. This should be measured in Study 3.
**Confidence:** Medium-high.

## F11 [Critical] C1 — The shipped router does not use ALT
**Strongest defense:** Proposition 1 is a true statement about the deployed cost function: w ≥ τ0 by edge_cost.dart:108–110 with δ clamped ≥ 1. Bidirectional Dijkstra is exact, so no route is wrong. ALT is implemented and unit-tested; it is just not wired in.
**Checked:** query_orchestrator.dart:155–168 (two plain `bidirectionalDijkstra` calls). A grep for landmark use outside alt_landmarks.dart finds only tests. bin/pulse_router.dart:60–95 (no landmarks). DECISIONS.md:424–425 blames 3.07 s on an "ALT landmark rebuild" that does not exist. paper.tex:120 and Fig. 1:128. README:46.
**Verdict:** PARTIAL. The misdescription stands: paper l.120, Fig. 1, README and ADR-012 are all false about the system. The "minimum ratio = 1.0" check (paper:242) is trivial, because any p̃ = 0 edge achieves it. Downgrade to Significant: this is a text/correctness-of-description issue, not a routing error, fixable either by deleting the ALT claims or by wiring ALT in.
**Confidence:** High.

## F12 [Critical] C2 — "Runs entirely on the phone" is not implemented
**Strongest defense:** The routing core makes no network calls. It runs in-process inside the Flutter app on the full 193k/471k graph, which the host-VM integration test demonstrates. The paper's contribution is framed as the "design of an offline-first system".
**Checked:** route_service.dart:65–104 (fixed OD, clock, z, λ). The IDP `app/` has no `android/` directory (ls: `README.md assets lib pubspec.yaml scripts test`). A grep finds no snap-to-edge code (only `_snapToGrid` coarsening in hazard_database.dart:177–302). demo assets have 60 hazard entries.
**Verdict:** DEFENSE FAILS (narrowed). The abstract's present-tense "runs entirely on the phone" is not supported: there has been no device run, no on-device prior, no report→edge path and no reporting UI. Rewording to "is designed to run on the phone; the routing core runs in-process in a Flutter host test on one fixed query" would resolve it. It stays Critical only because it is a headline claim in the abstract.
**Confidence:** High.

## F13 [Critical] C3 — The verifier fails open; the plan blames this only on Kotlin
**Strongest defense:** Same as F4: the authors already disclose that numbers are not bound to subject or unit, that the denylist is incomplete, and that claims are not bound to facts. Cases 3 to 6 sit inside those disclosed limits.
**Checked:** verifier.dart:191, :261, :397–400, :550–575. plan.tex:65 (the IDP column lists the verifier without caveat). plan.tex:72 says the Kotlin verifier "would pass 'saves 3 minutes'", but the IDP verifier also passes "Route A saves you 4 minutes" (no comparative word, and 4 is grounded as the absolute delta). README:48 says "no hallucinated facts … ever".
**Verdict:** PARTIAL. This is a duplicate of F4; merge them. The plan inconsistency (l.65 and l.72) and the README "ever" overclaim stand and are new here. Case 6 is the most persuasive example. Merged severity: Significant.
**Confidence:** High.

## F14 [Significant] S1 — "N minutes slower" mixes cost with time
**Strongest defense:** See F1(1). The size is bounded by the chosen route's own penalty, and the contract shows the intended free-flow comparison.
**Checked:** As F1. edge_cost.dart:108–110 and template_renderer.dart:113–122.
**Verdict:** PARTIAL. Duplicate of F1 item 1; merge. Real but a one-line fix.
**Confidence:** High.

## F15 [Significant] S2 — HLC is decorative; sync pages on `observed_at`
**Strongest defense:** The G-Set merge by id is correct. A peer that re-pulls with an older `since` converges. HLC stamping exists for future causal ordering. Sync is not wired or evaluated, and the paper does not report sync results.
**Checked:** sync_client.dart:114 and :196–202 (HLC put into `raw._hlc`). :151–153 (`since` = device time). postgis.py:80,82 and :93 (`observed_at >= since`, ORDER BY observed_at). memory.py:45.
**Verdict:** DEFENSE FAILS. The late-offline-report skip is real, and it is exactly the scenario offline-first sync exists for. The paper's "append-only log ordered by hybrid logical clocks" (l.120) is inaccurate. Keep at Significant.
**Confidence:** High.

## F16 [Significant] S3 — One future-dated report makes every query throw
**Strongest defense:** Throwing on a future observation is correct for one belief. The path is latent, because the cache is not wired to the router (F12). The server validates timestamps, though only for timezone awareness.
**Checked:** fusion.dart:87–93 (throws). query_orchestrator.dart:120–134 (fuses every configured edge before searching). models.py:70–77 (no future check).
**Verdict:** PARTIAL. The mechanism is confirmed but latent today. Downgrade to Minor/Significant. Clamp or drop future observations at ingest and in `planRoute`.
**Confidence:** High.

## F17 [Significant] S4 — Tier 1/2 cannot run as claimed
**Strongest defense:** The authors disclose this in code (flutter_gemma_rewriter.dart:5–22) and in the paper (l.251). Silent fallback on timeout is the designed behaviour.
**Checked:** flutter_gemma_rewriter.dart:59–60 (model acquired per call). rewrite_pipeline.dart:38 (`.timeout` does not cancel native work). `app/test/fixtures/` does not exist (ls error), so the cited `FakeSlmRewriter` is missing, and a grep for `attemptRewrite` in tests returns nothing.
**Verdict:** PARTIAL. This largely duplicates F3 and F8; merge. One new, unrebutted point: the code comment cites a test fixture that does not exist, so the rewrite pipeline has no test. Significant as part of the merged F3.
**Confidence:** High.

## F18 [Significant] S5 — Server "live ingest" is not live
**Strongest defense:** The paper's only server claim is Fig. 1's "Server: ingest, sync (when online)". No result depends on the server. The overclaims are in README and plan.tex, not in the paper.
**Checked:** paper.tex:135 is the only server mention. server/app/main.py has no lifespan or scheduler (grep). README:50 ("live rainfall + flood-alert workers").
**Verdict:** PARTIAL. Valid against README and plan.tex. For the paper, downgrade to Minor (Fig. 1 wording).
**Confidence:** Medium-high. I did not open open_meteo.py.

## F19 [Significant] S6 — The decision trace is thinner than described
**Strongest defense:** The paper describes the schema. `context_facts` exists as a channel, and one alternative is enough for a contrastive "why not B". The worst-band default is explicitly documented in a code comment.
**Checked:** query_orchestrator.dart:309 (`contextFacts: const []`). :204–281 (at most one alternative, "B"). :284–293 (prior-only no-observation edges are not gaps). :398–403 ("not yet in any ADR").
**Verdict:** PARTIAL. Downgrade to Minor, except for the prior-only gap inversion, which is substantive; merge that into F7. The paper should say "contextual facts (currently unused)" and "one alternative".
**Confidence:** High.

## F20 [Significant] S7 — The Kotlin prototype asserts safety and the handoff doc claims production readiness
**Strongest defense:** The plan already recommends that the Kotlin app be kept "only for its visual design ideas; do not demo its numbers" (plan.tex:72), and the paper is about the IDP repo. Criticising a deprecated prototype is out of scope for the paper.
**Checked:** KT SymbolicExplanationEngine.kt:70 ("CityPulse safely redirected your journey…"). AGENT_HANDOFF_CITYPULSE_AI.md:412–414 ("fully operational … life-saving").
**Verdict:** PARTIAL. The facts are confirmed. For the paper, downgrade to Minor, or move it to a repo-hygiene note. Retract or label the handoff doc if anyone circulates it.
**Confidence:** High.

---

## Summary table

| ID | Verdict | Recommended severity |
|---|---|---|
| F1 | PARTIAL | Critical on (2) only; otherwise Significant; merge F14 |
| F2 | PARTIAL | Significant; drop mechanism 3 |
| F3 | PARTIAL | Significant; merge F17 |
| F4 | PARTIAL | Significant; A1 stands; merge F13 |
| F5 | PARTIAL | Significant (related-work fix) |
| F6 | PARTIAL | Minor/Significant |
| F7 | PARTIAL | Significant (gap inversion only) |
| F8 | PARTIAL | Minor (512-token point stands) |
| F9 | DEFENSE SUCCEEDS | Drop, or Minor wording |
| F10 | PARTIAL | Significant (prompt/verifier mismatch) |
| F11 | PARTIAL | Significant |
| F12 | DEFENSE FAILS | Critical (abstract claim) |
| F13 | PARTIAL | Duplicate of F4; plan/README inconsistency new |
| F14 | PARTIAL | Duplicate of F1(1) |
| F15 | DEFENSE FAILS | Significant |
| F16 | PARTIAL | Minor/Significant (latent) |
| F17 | PARTIAL | Merge into F3; missing test fixture stands |
| F18 | PARTIAL | Minor for the paper |
| F19 | PARTIAL | Minor; gap inversion → F7 |
| F20 | PARTIAL | Minor / out of scope |
