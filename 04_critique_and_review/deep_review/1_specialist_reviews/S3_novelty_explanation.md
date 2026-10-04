# S3 — Novelty and soundness of claims: the explanation layer

Reviewer S3, CityPulse AI deep review. Target bar: IEEE conference paper. Date: 2026-10-01.

**Scope.** DecisionTrace, the Tier-0 templates, the Tier-1 on-device small LM (Gemma 3 270M via flutter_gemma), the Tier-2 cloud rewrite (Groq llama-3.1-8b-instant), the six-rule symbolic verifier, the fail-closed fallback, and how `drafts/paper.tex` presents them (Abstract; Sec. I, contribution 3; Sec. II-D; Sec. IV-A/B; Table I; Fig. 1; Threats; Conclusion).

**Files read.**
- `packages/pulse_explain/lib/src/{verifier,template_renderer,explanation}.dart` and their tests.
- `app/lib/src/explain/*.dart`, `app/lib/src/routing/route_service.dart`, `app/lib/src/ui/home_screen.dart`.
- `packages/pulse_router/lib/src/{query_orchestrator,decision_trace}.dart`.
- `config/hazard_classes.yaml`, `docs/EVALUATION.md` (Study 3), `docs/DECISIONS.md` (ADR-011).
- Study 1 traces `data/results/2026-09-18-study1-route-quality/traces/{C0,C1,C3}.ndjson`.
- `research_notes/.../explanation_llm.md`.

**What was executed, and what was not.** The Dart SDK is not installed here, so **no Dart code was executed**. I wrote a line-by-line Python port of `verify()` and `renderTemplate()` (`scratchpad/s3/verifier_port.py`). It uses `re.ASCII` to match Dart's non-unicode `RegExp` and Dart's round-half-away-from-zero. I validated the port against 25 expectations from the Dart test suite (9 must-pass, 16 must-reject, including the coherence and "100 Feet Road" regressions): **25/25 agree** (`s3/validate.py`).

Every "PASS" or "FAIL" below is the port's verdict, with the code lines that produce it. The Dart code itself should be re-run before anything is quoted in the paper.

Two further analyses:
- The port was run on the 300 Study-1 traces (`s3/run_traces.py`).
- The session's validated SciPy router (`reanalysis/reanalyze.py`, which reproduces Dart's C3 paths on 100/100 pairs) was reused to compute, for each user class, what the Tier-0 headline sentence would say against the true free-flow difference (`s3/delta.py`). For the commuter class this reproduces the Dart traces exactly: 7 alternatives, and 3 shared "avoided" edges.

**Bottom line.**
- **Novelty.** The *combination* is plausibly unpublished: a template, plus an LM paraphrase, gated by a typed deterministic checker with template fallback, for hazard-route explanations on a phone. Every ingredient has close precedent, and the paper cites none of the closest:
  - T2G2 for template-then-rewrite;
  - DataTuner, VCP and CARE for checking or repairing generated data-to-text;
  - NeMo Guardrails for output rails that block;
  - RouteExplainer, SVE and Alsheeb & Brandão for route explanation;
  - Ilyankou et al. 2026, which proposes almost exactly this architecture conceptually.

  The claimable delta is narrow, and it is currently **unevaluated**.
- **Soundness.** The bigger problem is not novelty. The three things the paper asserts about the layer do not hold in the code as it stands:
  1. "Verified against the decision record" does not imply correct. The trace itself mislabels penalty seconds as travel time, and it names "avoided" hazards that lie on the chosen route.
  2. "Fail-closed" is actually fail-crash. The Tier-0 renderer throws, the route is lost, and the unverified text is printed in the error message.
  3. Tiers 1 and 2 have never run.

---

## Critical

### C1. A "verified" explanation can be false: the DecisionTrace that the verifier grounds against has wrong semantics
**Location.**
- Paper: Abstract ("a language-model rewrite that must pass a symbolic check against the router's decision record"); Sec. I ("explanations that are verified against the decision record"); Sec. IV-A.
- Code: `pulse_router/lib/src/query_orchestrator.dart` lines 162–167 (the alternative is the free-flow shortest path), 197 (`chosen.durationSeconds = chosenResult.totalCostSeconds`, i.e. the penalised cost), 277 (`alt.durationSeconds = altResult.totalCostSeconds`, i.e. free-flow time), 241–256 (for `higher_cost`, the "blocking edge" is the max-p̃ hazard edge anywhere on the alternative), and 337–340 (newest-observation age = 0.0 when no observation exists).
- `template_renderer.dart` lines 99–123 (delta sentence) and 125–147 ("It avoids … reported on X, N minutes ago / moments ago").

**Problem.** The verifier can only check that text is consistent with the trace. Three trace fields are not what the template says they are.
1. **Penalty seconds reported as "minutes slower".** `chosen.duration_s` contains λ·p̃·s·τ0 penalty seconds, but the alternative's `duration_s` is pure free-flow time. "Route A is N minutes slower than Route B" therefore compares a cost with a time. This is the same defect the paper criticises in its own earlier harness (Sec. VI-C, "counted penalty seconds as travel time"), reintroduced in the user-facing sentence.
2. **"It avoids X" when the chosen route crosses X.** In the `higher_cost` branch the blocking edge is the worst edge on the *alternative*, even when the chosen route shares it.
3. **A fabricated report for prior-only edges.** For a hazard-configured edge with no observation (8,759 prior-only edges), the age is set to 0.0 and `source_class` to `unknown`. The template then renders "It avoids flooding reported on X, moments ago" although nothing was reported. This case was not exercised in Study 1, where all 55 blocking edges had observations; it follows from lines 337–345 together with template line 142.

**Why it matters.** The verifier passes all three. They are template sentences, and they are the reference that Tier-1/2 rewrites are grounded against. The paper's central claim for the layer — verified, therefore trustworthy — fails at the source.

Measured, Python port and SciPy re-router over the 100 Study-1 OD pairs:

| User class (z, λ) | Routes with an alternative | Headline minutes ≠ true free-flow minutes | "Avoided" edge also on chosen route |
|---|---|---|---|
| Commuter (0, 0.3) — Dart traces | 7 | 0 (penalty ≤ 23 s, rounds to "about the same") | **3 / 7** (C3-0029, -0032, -0046; edge is the chosen route's own worst edge) |
| Emergency (2, 1.0) | 30 | **25 / 30** | **18 / 30** |
| Pedestrian (1.28, 1.2) | 28 | 22 / 28 | 13 / 28 |
| λ = 5 | 31 | 24 / 31 | 7 / 31 |
| λ = 20 | 57 | 47 / 57 | 8 / 57 |

Example (emergency class): the template says "Route A is **2 minutes slower** than Route B" when the true free-flow difference is **17 s**. The other 88 s are penalty.

**Suggested fix.**
1. Add `chosen.travel_time_s` (free-flow × δ), keep the penalty in its own field, and have the template compare like with like.
2. Choose the blocking edge from (alternative edges) minus (chosen edges). The contrastive explanation is about what differs (cf. SVE, Schild et al. 2025).
3. Make `newest_observation_age_s` nullable, and render "the flood-risk map rates X as high-susceptibility" for prior-only edges.
4. Add an invariant test: every "avoids X" edge must be absent from `chosen.geometry_ref`.
5. In the paper, call the property "trace-consistency", not faithfulness (Jacovi & Goldberg's faithfulness is about the model's reasoning, not about agreement with a post-hoc record).

**Confidence.** High. All three are visible in the code. Item 2 was confirmed on the team's own Dart traces by mapping edge IDs to node pairs in the graph JSON; there are no parallel edges at those node pairs.

**Evidence.** `scratchpad/s3/run_traces.py` and `scratchpad/s3/delta.py`, with outputs reproduced above.

### C2. "Fail-closed" is in fact fail-crash at Tier 0, and the crash path displays the unverified text
**Location.**
- `template_renderer.dart` lines 67–80: `throw StateError(... 'text: "$text"' ...)`.
- `route_service.dart` line 99: `renderTemplate` called with no try/catch.
- `home_screen.dart` lines 47–52: `Text('Could not compute a route: ${snapshot.error}')`.
- Paper: Sec. IV-A ("otherwise the Tier 0 text is shown"); Fig. 1 ("Symbolic verifier (fail-closed)"); contribution 3.

**Problem.** Tier 0 verifies itself and throws if it fails. Nothing catches the exception. The app then shows no route at all, and its error banner prints the StateError message, which embeds the failing, unverified text. That inverts both the hazard-routing purpose and rule 5 ("never show an unverified explanation").

Realistic traces make Tier 0 fail through three mechanisms:
1. **A blocking-edge street label equals a data-gap corridor label.** The template's own sentence "It avoids flooding reported on X" then names a data-gap corridor next to "avoids" and a hazard noun, which trips `_checkDataGapContradiction` (verifier.dart 472–504). The app's fallback label for any edge outside the demo label file is the constant `'an unnamed stretch'` (route_service.dart line 87). So for every non-demo OD pair where the alternative has a blocking edge, the blocking edge and the deduplicated data gap share that label. With app-style labels, Tier 0 fails on **30/100 C1 traces and 7/7 C3 traces that have an alternative** (port). With real OSM names this happens whenever both routes use segments of the same street, which is common for arterials (Anna Salai, OMR). Port check: blocking street "Anna Salai" plus data gap "Anna Salai" gives `rule3:data_gap_contradiction`.
2. **Digits in street names hit rule 1.** The fix for "100 Feet Road" (verifier.dart 456–471) strips corridor names only inside the data-gap check; rule 1 (`_checkNumerals`, 201–217) still scans the whole text. The Dart regression test passes only because the fixture's blocking edge has `p_pessimistic = 1`, which grounds "100" as 100 %. With p̃ = 0.95 the same sentence fails with `rule1:numeral:100` (port).
3. **Harness labels.** With the harness label `edge <id>`, Tier 0 fails on **300/300** Study-1 traces (rule 1 on the IDs, plus spurious data-gap hits from prefix matches such as "edge 91" inside "edge 918"). The explanation layer was therefore never run on the evaluation traces.

**Why it matters.** The safety property the paper advertises for the explanation layer does not hold. In the realistic failure case the user loses the route entirely, and the error screen shows unverified text.

**Suggested fix.**
- Never throw from Tier 0 in production. If self-verification fails, drop the failing sentence; if nothing remains, show a fixed minimal string ("Route A is shown. Hazard information could not be summarised.").
- Log the failure and count it.
- Ground street-name tokens (including digits) before running rule 1.
- Use word-boundary matching for corridors.
- Report the **Tier-0 self-pass rate on all evaluation traces with real OSM names** as a number in the paper.

**Confidence.** High for the control flow (read directly). High for the port measurements: the port agrees with the Dart tests 25/25, but the Dart code itself was not run.

**Evidence.** `s3/run_traces.py` output ("tier0 self-verify FAIL … 100/100" for each configuration; "with neutral labels: 30" for C1 and "7" for C3); `s3/adv.py` lines for "100 Feet Road" and "Anna Salai".

### C3. The verifier is claimed as a contribution, but it is unevaluated, and Tiers 1/2 have never executed
**Location.**
- Paper: Abstract; Sec. I, contribution 3 ("a fail-closed explanation verifier"); Sec. IV-B ("We have not yet measured the pass rate … reports the design only"); Threats ("described, not evaluated").
- `flutter_gemma_rewriter.dart` lines 4–31 ("never been run against real model weights").
- `cloud_rewriter.dart` (no API key exists).
- No `FlutterGemmaRewriter(` or `CloudRewriter(` instantiation anywhere in `app/` (grep); `home_screen` calls `computeDemoRoute()` with no rewriter.
- `docs/EVALUATION.md` Study 3: "Report the verification pass rate. This is the number the paper is built around."

**Problem.** Sec. IV-B is honest, but the paper still lists the verifier as a contribution and describes Tiers 1/2 as part of the system. Neither has produced a single output: there is no pass rate, no false-reject rate, and no detection rate on outputs the authors did not write. The only evidence is a 30-case adversarial suite, written by the same team, targeting exactly the patterns the rules check (verifier_test.dart). That shows the code does what it says; it is not evidence that it catches what LMs actually get wrong.

**Is it legitimate to claim it?** Not at an IEEE conference bar. A design is a contribution only when its properties hold by construction. Here they do not: C1, C2 and C4 show that both the guarantee (no misleading text shown) and the availability (Tier 0 always renders) fail. An unmeasured heuristic gate with known false-pass classes is a system component, not a contribution.

**Why it matters.** Reviewers will read contribution 3 as the paper's explainability claim. The keywords put "Explainable artificial intelligence" first, and the title says "with Verified Explanations". With no measurement, the title over-claims.

**Suggested fix.** Either (a) remove "Verified Explanations" from the title and recast contribution 3 as "a trace schema and verifier design (evaluation is future work)", or (b) run a minimal Study 3 before submission. Study 3 is cheap: Groq has a free tier, and Gemma 270M runs on a laptop with llama.cpp or Ollama.
1. Render Tier 0 for all 300 traces with OSM names and report the self-pass rate.
2. Generate rewrites from both models for 300 traces.
3. Two annotators label error types on 100 rewrites using the Thomson & Reiter (INLG 2020) categories; report Cohen's κ.
4. Report the verifier's recall of annotated errors, its precision, and its false-reject rate on correct rewrites.
5. Add a held-out adversarial set written by someone else and generated by perturbation (direction flip, negation, number words, unit swap, cross-sentence anaphora, Tamil).
6. Measure end-to-end Tier-1 latency on a ₹10–15k phone, as Study 4 already specifies.

Those four numbers would turn the layer into a contribution: pre-gate error rate, post-gate error rate, false-reject rate, and Tier-1 hit rate within the deadline. The literature notes (Q3/Q4 gaps) show no route-explanation paper reports them.

**Confidence.** High.

**Evidence.** As cited under Location; grep for constructors in `app/`.

### C4. The verifier does not guarantee what Table I says: adversarial sentences that pass and mislead
**Location.** verifier.dart; paper Table I and Sec. IV-B. The paper discloses only two limitations: numerals are not bound to unit or subject, and capitalised-word matching does not transfer to Tamil.

**Problem.** Below are concrete sentences that pass all checks (port verdict = PASS, no unsupported claims) against the team's own `buildTrace()` fixture. The fixture is the CONTRACTS.md §3 worked example:
- chosen A: 1147 s, 8420 m, worst p̃ 0.31;
- alternative B: 907 s, removed by the chance constraint;
- blocking edge "Kotturpuram Bridge approach": flood, p̄ 0.792, p̃ 1.0, depth 320 mm (above h_max 300 mm), age 179 s;
- z = 0, λ = 0.3, band `moderate`, with the production display nouns.

| # | Sentence (passes) | What is wrong | Why it passes (verifier.dart lines) |
|---|---|---|---|
| A1 | "Route A is 4 minutes **faster** than Route B. It avoids flooding reported on Kotturpuram Bridge approach, 3 minutes ago." | A is 4 min **slower**. Direction flipped. | Rule 3 only checks `alternatives.isNotEmpty` when "faster/slower" appears (404–407). "4" is grounded as the *absolute* delta (261). Table I's "a speed comparison is unsupported" overstates this check. |
| A2 | "There is **no flooding** reported on Kotturpuram Bridge approach." | Polarity flip on the edge the router deleted (p̄ 0.79, 320 mm). | No negation handling. The noun "flooding" is allowed because the class is present (369–391). "There" is a stop word (290–316); "Kotturpuram" and "Bridge" are grounded street words (336–357). Rule 6's denylist (550–572) has no "no flooding" or "no water". |
| A3 | "You can drive through Kotturpuram Bridge approach; standing water there is just 320 mm." | Endorses traversing water above the vehicle threshold. This is exactly ADR-011's prohibited affirmative-passability claim. | 320 is grounded as depth (268). "You" is a stop word. The denylist matches "you can safely", not "you can drive through" (571). |
| A4 | "Route A has only a **1%** chance of flooding at its worst point." (true: 31 %) | Understates risk 31-fold. | `%` is stripped and the bare number compared against *every* grounded value (205–211). "1" matches the raw probability p̃ = 1.0 with tolerance 0.005 (241–243). Units and percent are not bound. For a commuter (z = 0), "**0%** chance of flooding" also passes, because z = 0 and the zero time penalty ground "0" (256, 267). |
| A5 | "No recent hazard data is available for Velachery Main Rd. The water there drained 3 minutes ago, so it beats Route A." (data gap: Velachery Main Rd) | Invents a hazard fact about a corridor with no data — exactly the exploit the coherence check was added for. | The data-gap check is sentence-scoped (184–185, 479); anaphora ("there") in the next sentence escapes. "drained" is neither a numeral claim nor a hazard noun. |
| A6 | (band `low`) "Data is limited, but the water on Kotturpuram Bridge approach has drained, so take Route B." | Recommends the edge the chance constraint deleted. | Rule 4 needs *any* hedge substring anywhere (510–539); "limited" launders the rest. The denylist misses "has drained" and "take Route B". |
| A7 | "Route A is **nine** minutes slower than Route B because of a **ninety percent** flood risk." | Both numbers are wrong (4 min; 79 %/31 %). | `_numeralPattern` (191) matches digits only. Number words are invisible to rule 1, and small LMs often spell out small numbers. |
| A8 | Tamil: "இந்தப் பாதை பாதுகாப்பானது. கோட்டூர்புரம் பாலத்தில் வெள்ளம் இல்லை." ("This route is safe. There is no flood on Kotturpuram bridge.") | An absolute-safety claim plus a polarity flip. | Every rule except rule 4 is ASCII-only: `[A-Z]` (284), English hazard nouns, an English denylist, and Dart's non-unicode `\d`/`\b`. Under band `low`, appending "(limited)" passes too (A8b). Conversely, a *correct* Tamil hedge with no English hedge token is **rejected** by rule 4 (A8c). |

**Why it matters.** These are not exotic. Direction errors, negation, number words and unit confusion are the most common data-to-text errors in the literature (Kasner & Dušek ACL 2024 report >80 % of open-LLM outputs with at least one semantic error; Thomson & Reiter 2020 give the error taxonomy). Ilyankou et al. (CartoAI/AGILE 2025) list "characterising hazardous terrain as suitable" as the dangerous class. A1–A4 are safety-relevant. The paper discloses only the two mildest limitations.

**Suggested fix.**
- Bind each numeral to its unit and to the nearest field type (minutes / % / mm / km), and parse number words.
- Check comparative direction: sign of (chosen − alt) against "slower/faster/longer/shorter/more/less".
- Add a negation and polarity rule: a hazard noun within k tokens of "no/not/without/drained/receded/clear" on a grounded edge fails.
- Make rule 6 an allow-list of sentence frames rather than a deny-list. The strongest option is to constrain the rewriter to fill a slot schema (constrained decoding, Geng et al. EMNLP 2023), which removes most of these classes by construction.
- Do not accept non-ASCII output until a Tamil rule set exists.
- Rewrite Table I to say what each check actually does, and add a "known false-pass classes" row.

**Confidence.** High that each sentence passes the logic in the cited lines (port, validated 25/25). The Dart code was not executed.

**Evidence.** `scratchpad/s3/adv.py` output: A1–A9 "PASS", A8c "REJECT rule4".

---

## Significant

### S1. Novelty is overstated by omission: the closest prior work is not cited
**Location.** Paper Sec. II-D (two sentences on explanation; cites Miller, Jacovi, Reiter, van Deemter, Ji, FActScore, TRUE, Gemma, MobileLLM); `refs.bib` (none of the works below appear; grep).

**Problem.** The design is template-then-rewrite plus a deterministic gate with fallback. Its nearest relatives:

| Work | What it already does | CityPulse delta |
|---|---|---|
| Kale & Rastogi, EMNLP 2020 (T2G2), doi 10.18653/v1/2020.emnlp-main.527 | Concatenated templates, rewritten by T5 into fluent text | Adds a runtime gate and fallback; T2G2 checks faithfulness only offline |
| Harkous et al., COLING 2020 (DataTuner), doi 10.18653/v1/2020.coling-main.218 | Generate, then rerank with a learned semantic-fidelity classifier | Deterministic, not learned; but no measured recall, whereas DataTuner reports it |
| Ren, Zhang & Liu, MMAsia 2025 (VCP), doi 10.1145/3743093.3771022 | Rule-based keyword check, then regenerate (small LMs) | Checks assertions, not omissions; falls back instead of regenerating |
| Kim & Jung, IEEE CAI 2025, pp. 69–74 (CARE) | Detects numerical hallucinations in LLM-generated text and replaces them with source values | Rejects rather than repairs; CARE is evaluated, CityPulse is not |
| Rebedea et al., EMNLP 2023 Demos (NeMo Guardrails), aclanthology 2023.emnlp-demo.40 / arXiv 2310.10501 | Programmable output rails (fact-check, moderation) that block responses before they reach the user | CityPulse's rails are symbolic against a typed record, not LLM-judged |
| Kikuta et al., PAKDD 2024 (RouteExplainer), doi 10.1007/978-981-97-2259-4_3 | Counterfactual route explanation verbalised by GPT-4; text evaluated only qualitatively | Domain (hazard), gate, on-device |
| Schild et al., ACDA 2025 (SVE), doi 10.1137/1.9781611978759.19; Alsheeb & Brandão, ITSC 2023, doi 10.1109/ITSC57777.2023.10422542 | Algorithmic "why this route and not that one": minimal sets of segments that explain a route difference | CityPulse's trace is not minimal or contrastive in this sense (C1(2)); these are the right baselines for *content* |
| Ilyankou, Cavazzi & Haworth, arXiv 2603.14586 (2026) | Proposes a neuro-symbolic navigation architecture: symbolic router, an "LLM Verbaliser" constrained by a policy module enforcing "template-bounded outputs", and uncertainty-aware language "programmatically triggered by the symbolic flags" | **Conceptually anticipates CityPulse's design almost exactly.** CityPulse would be an implementation, which is a valid contribution only if evaluated |
| Ilyankou, Haworth, Cheng & Cavazzi, CartoAI workshop @ AGILE 2025 (abstract) | GIS-to-YAML schema, then an LLM route description; reports hallucinated POIs and safety-relevant mischaracterisation; verification is future work | Closest data-to-text-for-routes pipeline |
| Lei et al., Findings ACL 2025, doi 10.18653/v1/2025.findings-acl.750 | Names "false evacuation routes" as a key LLM risk in disasters; mitigations listed are soft | Motivation citation |
| Fouilhé et al., arXiv 2603.02070 (2026) | Multi-agent LLM explanation of plans, with a user study against a template-based baseline | Shows the expected evaluation: LM versus template, with users |

**Why it matters.** Without these citations a referee will either supply them and judge the paper as not novel, or judge the related work incomplete. The honest claim is roughly: "To our knowledge, the first implementation of the gated-verbaliser architecture proposed in [Ilyankou 2026] for hazard-aware routing, with typed symbolic checks against a structured decision trace and a template floor, running on-device." That claim needs C3's numbers.

**Suggested fix.** Expand Sec. II-D to one paragraph with the table's contents; position against T2G2, Guardrails, CARE and Ilyankou 2026 explicitly; remove any implicit "first" claim.

**Confidence.** High that the omissions are real (grep of `refs.bib`). Medium-high on the absence of a closer published system. Ten searches (Exa/WebSearch) found none beyond those listed; this is an absence-of-evidence claim.

**Evidence.** Search results this session. CARE venue from researchr (IEEE CAI 2025, 69–74). NeMo Guardrails from the ACL Anthology page and arXiv; its author list was not re-read. Ilyankou 2025 from the CartoAI abstract PDF.

### S2. The confidence band carries no information, so rule 4 and the hedge sentence are constant
**Location.**
- `decision_trace.dart` 454–495 (`lowNEffThreshold = 1.0`; low if n_eff < 1).
- `query_orchestrator.dart` 371–396 (route band = the worst edge's band; `low` when the route touches no hazard edge, line 396).
- `verifier.dart` 13–18 (rule 4 is route-level only).
- Paper: Sec. IV-A/B, Table I "Hedging".

**Problem.** A single fresh official report gives n_eff < 1 (spatial kernel κ < 1), so any route touching one observed edge is `low`. A route touching none is also `low`. On the evaluation traces the band is **`low` in 300/300 cases** (C0, C1, C3). The Tier-0 text therefore always says confidence is low, and rule 4 always demands a hedge; the hedge never discriminates. `high` needs three or more full-weight fresh reports on every hazard edge of the route, which the crowd will rarely supply in a flood (council verdict, "the crowd is empty when needed").

**Why it matters.** "Uncertainty-aware explanation" is part of the pitch. A constant hedge is a disclaimer, not a calibrated communication, and automation-bias research suggests users habituate to constant warnings.

**Suggested fix.**
- Calibrate band thresholds against the n_eff distribution in the corpus.
- Make the band per edge on the cited edge, not per route.
- Distinguish "prior-only" from "thin evidence" from "no hazard edge at all".
- Report the band distribution in the paper.

**Confidence.** High.

**Evidence.** Port statistics over the 300 traces: bands {low: 300}.

### S3. "Explicit data gaps" mark every unconfigured edge, which yields unreadable explanations and contradicts the prior
**Location.** `query_orchestrator.dart` 284–293; `template_renderer.dart` 165–173; paper Sec. IV-A ("explicit data gaps").

**Problem.** Every chosen-route edge without a hazard config is a "data gap", including edges the GCC prior rates low (p < 0.25 is excluded from configs). Per trace there are **median 217 data gaps (min 9, max 521)**. The Tier-0 data-gap sentence lists all of them, giving a **median of about 480 words** per explanation in the harness (port). With real names, deduplicated by street, a cross-city route still lists dozens of roads. Saying "no recent hazard data" for a road the prior rates very-low is also misleading: the prior *is* data.

**Why it matters.** Explanations are meant to be read at a glance, a design goal stated in the rewriter prompt. The data-gap list also inflates the prompt for Tier 1 (S4) and multiplies the C2 collision risk.

**Suggested fix.**
- Report gaps only for edges whose prior is at least moderate and which have no observations, aggregated to at most 2–3 named corridors and a count.
- Rename the field `unobserved_susceptible_segments`.

**Confidence.** High.

**Evidence.** `s3/run_traces.py` ("words median 499/493/479"; gap counts).

### S4. Tier 1 is unlikely ever to finish inside the 1.2 s deadline on the target phone
**Location.**
- `flutter_gemma_rewriter.dart` 193–201 (`getActiveModel` and `createChat` run on every call, inside the timed future).
- `rewrite_pipeline.dart` 28 and 57.
- `fact_set.dart` (the full JSON, including every data gap and blocking edge, goes into the prompt).
- Paper Sec. IV-A; `docs/EVALUATION.md` Study 4 (a ₹10–15k phone).

**Problem.** The deadline covers model acquisition, chat creation, prefill of a JSON prompt with hundreds of entries (S3), and decoding. Google's own figures for a fine-tuned Gemma 270M on a **Galaxy S25 Ultra** (flagship, cache warm, LiteRT XNNPACK, 4 threads) are about 1,700–2,200 tok/s prefill, about 126–154 tok/s decode, and TTFT about 0.24–0.3 s (FunctionGemma model card; litert-community model card). An anecdotal user report gives about 10 tok/s for Gemma 3 270M Q8 on a mid-range Motorola G72 via llama.cpp/Termux (LinkedIn comment; not peer-reviewed). On a budget phone, a 40–60-token sentence plus a cold model load is likely to exceed 1.2 s, so Tier 1 would almost always fall back silently. Note also that `maxTokens: 512` is passed to `getActiveModel` (context size), while the fact-set prompt can exceed 512 tokens once data gaps are included.

**Why it matters.** The paper presents an on-device SLM tier as part of the offline story. If its hit rate is about 0, the offline system is in practice Tier 0 only, which is fine but should be stated.

**Suggested fix.**
- Warm the model once per session.
- Prune the fact set to about 200 tokens.
- Generate asynchronously after showing Tier 0, then swap (the code comment already suggests this).
- Report the Tier-1 hit rate within the deadline on a named ₹10–15k device.

**Confidence.** Medium. The structure is certain; the latency is extrapolated, not measured on device.

**Evidence.** ai.google.dev FunctionGemma model card; huggingface.co/litert-community/functiongemma-270m-ft-mobile-actions; the LinkedIn anecdote (cite only as anecdotal, or not at all).

### S5. Tamil is mentioned as if supported, but no Tamil path exists and the verifier inverts under Tamil
**Location.**
- Paper Sec. IV-B ("does not transfer to Tamil script").
- `explanation.dart` line 133 ("Tamil templates are future work").
- `verifyOrFallback` default `locale = 'en'`.
- Both rewriter prompts are English-only and give no language instruction.

**Problem.** Mentioning Tamil only under "entity check limitation" implies the rest works. In fact, under Tamil output:
- rules 1 (only partly: ASCII digits still checked), 2, 3 (comparative and avoidance terms), the hazard-noun part of the data-gap check, and 6 are all vacuous;
- rule 4 rejects correct Tamil hedges;
- Tier 0 has no Tamil.

LLM factuality in Tamil is measurably worse: IndicGenBench (ACL 2024) finds a large generation gap against English across Indic languages, and IndicQuest-based evaluation (arXiv 2504.20022) places Tamil in a "low performance" bucket. TN-ALERT is the incumbent Tamil-language product.

**Suggested fix.** State plainly that the explanation layer is English-only, and list Tamil (Tier 0 templates plus language-specific rules) as future work. Until then, reject any non-ASCII rewrite.

**Confidence.** High.

**Evidence.** Code lines cited; port A8–A8c.

### S6. The false-reject rate is probably high, and the LM tiers may add almost nothing
**Location.** verifier.dart 284–328 (capitalised-word rule with a 25-word stop list), 510–540 (hedge list); `cloud_rewriter.dart` 220–227 and `flutter_gemma_rewriter.dart` 205–212 (the prompts say "used in Chennai" and give no hedge requirement).

**Problem.**
- Any sentence-initial word outside the stop list fails rule 2: "Heavy", "Flooding", "Expect", "Take", "Due", "Please", "Water".
- "Chennai", which the prompt itself introduces, fails.
- So does any contraction such as "It's".
- Port example: "Heavy flooding was reported on Kotturpuram Bridge approach 3 minutes ago, so Route A takes 4 minutes longer." is rejected (`rule2:entity:Heavy`), although it is correct.
- With every band `low` (S2), each rewrite must also contain one of 18 English hedge substrings, and the prompts do not ask for one.
- A 270M model's weak instruction following (IFEval 51.2 for Gemma 3 270M IT, model card) makes compliance less likely still.

**Why it matters.** If the gate rejects most correct rewrites, Tier 1/2 are dead weight, and the remaining fluency benefit cannot justify the safety risk of C4.

**Suggested fix.** Measure the false-reject rate (C3). Pass the required hedge phrase and the allowed vocabulary to the rewriter in the prompt. Use slot-constrained output so that capitalisation and hedging are deterministic.

**Confidence.** Medium-high. The mechanism is certain; the rate is unmeasured.

**Evidence.** Port A10b; Gemma 3 model card (IFEval).

---

## Minor

### M1. Fig. 1 puts the cloud tier inside the "on-device, works offline" box
**Location.** paper.tex line 139: `fit=(cache)(router)(trace)(t0)(ver)(t12)`, where the t12 node is "Tier 1 on-device SLM / Tier 2 cloud rewriter".
**Problem.** Tier 2 is a cloud call.
**Fix.** Split the node and move Tier 2 outside the box.
**Confidence.** High.

### M2. The paper's description of the "alternatives the router rejected" is misleading
**Location.** paper Sec. IV-A; `query_orchestrator.dart` 162–167 and 204–280.
**Problem.** There is at most one alternative, always the free-flow shortest path labelled "B". "Rejected alternatives" in the plural, with "their blocking edges", overstates the contrastive content.
**Fix.** Say "the free-flow route, as a single counterfactual". Consider SVE-style minimal explanations.
**Confidence.** High.

### M3. Hazard-noun check uses exact display strings only
**Location.** verifier.dart 369–391; `config/hazard_classes.yaml` (`"an accident"`, `"a road closure"`, `"debris on the road"`).
**Problem.** "accident", "crash", "the road is closed", "flooded", "waterlogged" and "inundated" all evade the cross-class check. Table I says "a hazard noun names a class absent from the trace", which implies coverage it does not have.
**Fix.** Lemma and synonym lists per class.
**Confidence.** High.

### M4. Rule 6 is a 21-phrase substring denylist with both false passes and false rejects
**Location.** verifier.dart 550–583.
**Problem.**
- Evaded by "it's fine", "go ahead", "the road has drained", "roads are open", "you can drive through".
- Over-triggers on "Route A is safer than B" and "the route is not safe".
- The team's own ADR-011 requires ≥95 % recall validated against human κ before the rule gates anything (verifier.dart 20–28). The paper does not mention that this has not been done.

**Fix.** Disclose this in Sec. IV-B; see the C4 fixes.
**Confidence.** High.

### M5. Grounded numbers include z and λ, which are not in the fact set and are not narratable
**Location.** verifier.dart 256–257.
**Problem.** They give free grounding to "0" (commuter), "2" (emergency), "0.3" and "1" (emergency λ), enabling A4b ("0% chance").
**Fix.** Ground only narratable fields.
**Confidence.** High.

### M6. Comparative lexicons are incomplete
**Location.** verifier.dart 397–398.
**Problem.** Speed: no "longer/shorter/more time/less time/saves/adds". Avoidance: no "bypasses/goes around/steers clear/skips". A rewrite using those words bypasses the rule-3 support check entirely.
**Fix.** Extend the lists and check direction.
**Confidence.** High.

### M7. The sentence splitter breaks on abbreviations
**Location.** verifier.dart 184–185.
**Problem.** "Dr." in "Dr. Radhakrishnan Salai", "St.", "No." (a common token in Indian addresses) split sentences, which both weakens and spuriously triggers sentence-scoped coherence.
**Fix.** An abbreviation-aware splitter, or check against the full text.
**Confidence.** Medium.

### M8. "Faithful" is the wrong term for what the verifier checks
**Location.** paper Sec. II-D cites Jacovi & Goldberg for faithfulness.
**Problem.** Faithfulness in that sense means agreement with the model's reasoning. The verifier checks agreement with a post-hoc record.
**Fix.** Use "trace-grounded" or "trace-consistent".
**Confidence.** Medium.

### M9. The silent fallback should be disclosed as a design choice with its trade-off
**Location.** paper Sec. IV-A.
**Problem.** "Shown without any indication that a rewrite failed" is presented neutrally. For research use the fallback rate is the key metric, and it is already logged (`fallback_used`). For users, silent fallback is fine.
**Fix.** Say so, and report the rate.
**Confidence.** Low (a presentation point).

### M10. The Groq key would ship inside the APK
**Location.** `cloud_rewriter.dart` 29–56 (already self-flagged).
**Problem.** The paper does not mention it.
**Fix.** If Tier 2 stays in the paper, state that it goes through a server proxy.
**Confidence.** High.

---

## Questions for the authors
1. Is `chosen.duration_s` intended to be travel time or optimisation cost? CONTRACTS.md §3 says the free-flow field "lets the explanation say '4 minutes slower' truthfully", which suggests travel time; the orchestrator stores cost.
2. How should a blocking edge that lies on the chosen route be rendered? Is it a known case?
3. Have Tier-0 explanations been rendered for any OD pair other than the bundled demo with real OSM names? If so, what fraction raised StateError?
4. What is the intended semantics of `data_gaps` for edges with a low but non-zero prior?
5. Will the paper report Study 3 (pass, false-reject and detection rates) and the Study 4 Tier-1 latency before submission? If not, will the title drop "Verified Explanations"?
6. Is Tamil output in scope for this paper at all?
7. Who wrote the 30-case adversarial suite, and was any case written before the rule it tests?

## Reproducibility
- `scratchpad/s3/verifier_port.py`: the port.
- `scratchpad/s3/validate.py`: 25/25 agreement with the Dart tests.
- `scratchpad/s3/adv.py`: the C4 sentences.
- `scratchpad/s3/run_traces.py`: the C2/S2/S3 statistics.
- `scratchpad/s3/delta.py`: the C1 table; it reuses `reanalysis/reanalyze.py` and the prior file in `scratchpad/work`.

The scratchpad root is `/tmp/claude-0/-home-claude/aa10ead1-266e-5d6e-9869-ab7db0329f5f/scratchpad/s3/`. None of the Dart code was executed.
