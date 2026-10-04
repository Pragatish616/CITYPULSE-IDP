# Findings to defend (D2_explanation_code)

## F1 [Critical] C1. A "verified" explanation can be false: the DecisionTrace that the verifier grounds against has wrong semantics
**Location:** .**
- Paper: Abstract ("a language-model rewrite that must pass a symbolic check against the router's decision record"); Sec. I ("explanations that are verified against the decision record"); Sec. IV-A.
- Code: `pulse_router/lib/src/query_orchestrator.dart` lines 162–167 (the alternative is the free-flow shortest path), 197 (`chosen.durationSeconds = chosenResult.totalCostSeconds`, i.e. the penalised cost), 277 (`alt.durationSeconds = altResult.totalCostSeconds`, i.e. free-flow time), 241–256 (for `higher_cost`, the "blocking edge" is the max-p̃ hazard edge anywhere on the alternative), and 337–340 (newest-observation age = 0.0 when no observation exists).
- `template_renderer.dart` lines 99–123 (delta sentence) and 125–147 ("It avoids … reported on X, N minutes ago / moments ago").

**Claimed problem:** .** The verifier can only check that text is consistent with the trace. Three trace fields are not what the template says they are.
1. **Penalty seconds reported as "minutes slower".** `chosen.duration_s` contains λ·p̃·s·τ0 penalty seconds, but the alternative's `duration_s` is pure free-flow time. "Route A is N minutes slower than Route B" therefore compares a cost with a time. This is the same defect the paper criticises in its own earlier harness (Sec. VI-C, "counted penalty seconds as travel time"), reintroduced in the user-facing sentence.
2. **"It avoids X" when the chosen route crosses X.** In the `higher_cost` branch the blocking edge is the worst edge on the *alternative*, even when the chosen route shares it.
3. **A fabricated report for prior-only edges.** For a hazard-configured edge with no observation (8,759 prior-only edges), the age is set to 0.0 and `source_class` to `unknown`. The template then renders "It avoids flooding reported on X, moments ago" although nothing was reported. This case was not exercised in Study 1, where all 55 blocking edges had observations; it follows from lines 337–345 together with template line 142.

## F2 [Critical] C2. "Fail-closed" is in fact fail-crash at Tier 0, and the crash path displays the unverified text
**Location:** .**
- `template_renderer.dart` lines 67–80: `throw StateError(... 'text: "$text"' ...)`.
- `route_service.dart` line 99: `renderTemplate` called with no try/catch.
- `home_screen.dart` lines 47–52: `Text('Could not compute a route: ${snapshot.error}')`.
- Paper: Sec. IV-A ("otherwise the Tier 0 text is shown"); Fig. 1 ("Symbolic verifier (fail-closed)"); contribution 3.

**Claimed problem:** .** Tier 0 verifies itself and throws if it fails. Nothing catches the exception. The app then shows no route at all, and its error banner prints the StateError message, which embeds the failing, unverified text. That inverts both the hazard-routing purpose and rule 5 ("never show an unverified explanation").

Realistic traces make Tier 0 fail through three mechanisms:
1. **A blocking-edge street label equals a data-gap corridor label.** The template's own sentence "It avoids flooding reported on X" then names a data-gap corridor next to "avoids" and a hazard noun, which trips `_checkDataGapContradiction` (verifier.dart 472–504). The app's fallback label for any edge outside the demo label file is the constant `'an unnamed stretch'` (route_service.dart line 87). So for every non-demo OD pair where the alternative has a blocking edge, the blocking edge and the deduplicated data gap share that label. With app-style labels, Tier 0 fails on **30/100 C1 traces and 7/7 C3 traces that have an alternative** (port). With real OSM names this happens whenever both routes use segments of the same street, which is common for arterials (Anna Salai, OMR). Port check: blocking street "Anna Salai" plus data gap "Anna Salai" gives `rule3:data_gap_contradiction`.
2. **Digits in street names hit rule 1.** The fix for "100 Feet Road" (verifier.dart 456–471) strips corridor names only inside the data-gap check; rule 1 (`_checkNumerals`, 201–217) still scans the whole text. The Dart regression test passes only because the fixture's blocking edge has `p_pessimistic = 1`, which grounds "100" as 100 %. With p̃ = 0.95 the same sentence fails with `rule1:numeral:100` (port).
3. **Harness labels.** With the harness label `edge <id>`, Tier 0 fails on **300/300** Study-1 traces (rule 1 on the IDs, plus spurious data-gap hits from prefix matches such as "edge 91" inside "edge 918"). The explanation layer was therefore never run on the evaluation traces.

## F3 [Critical] C3. The verifier is claimed as a contribution, but it is unevaluated, and Tiers 1/2 have never executed
**Location:** .**
- Paper: Abstract; Sec. I, contribution 3 ("a fail-closed explanation verifier"); Sec. IV-B ("We have not yet measured the pass rate … reports the design only"); Threats ("described, not evaluated").
- `flutter_gemma_rewriter.dart` lines 4–31 ("never been run against real model weights").
- `cloud_rewriter.dart` (no API key exists).
- No `FlutterGemmaRewriter(` or `CloudRewriter(` instantiation anywhere in `app/` (grep); `home_screen` calls `computeDemoRoute()` with no rewriter.
- `docs/EVALUATION.md` Study 3: "Report the verification pass rate. This is the number the paper is built around."

**Claimed problem:** .** Sec. IV-B is honest, but the paper still lists the verifier as a contribution and describes Tiers 1/2 as part of the system. Neither has produced a single output: there is no pass rate, no false-reject rate, and no detection rate on outputs the authors did not write. The only evidence is a 30-case adversarial suite, written by the same team, targeting exactly the patterns the rules check (verifier_test.dart). That shows the code does what it says; it is not evidence that it catches what LMs actually get wrong.

## F4 [Critical] C4. The verifier does not guarantee what Table I says: adversarial sentences that pass and mislead
**Location:** .** verifier.dart; paper Table I and Sec. IV-B. The paper discloses only two limitations: numerals are not bound to unit or subject, and capitalised-word matching does not transfer to Tamil.

**Claimed problem:** .** Below are concrete sentences that pass all checks (port verdict = PASS, no unsupported claims) against the team's own `buildTrace()` fixture. The fixture is the CONTRACTS.md §3 worked example:
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
| A5 | "No recent hazard data is available for Velachery Main Rd. The water there drained 3 minutes ago, so it beats Route A." (data gap: Velachery Main Rd) | Invents a hazard fact about a corridor with no data — exactly the exploit the coherence check was added for. | The data-gap check is sentence-scoped (184–185, 479); anaphora ("there")

## F5 [Significant] S1. Novelty is overstated by omission: the closest prior work is not cited
**Location:** .** Paper Sec. II-D (two sentences on explanation; cites Miller, Jacovi, Reiter, van Deemter, Ji, FActScore, TRUE, Gemma, MobileLLM); `refs.bib` (none of the works below appear; grep).

**Claimed problem:** .** The design is template-then-rewrite plus a deterministic gate with fallback. Its nearest relatives:

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
| Ilyankou, Haworth, Cheng & Cavazzi, CartoAI workshop @ AGILE 2025 (abstract) | GIS-to-YAML schema, then an LLM route description; reports hallucinated POIs and safety-relevant mischaracterisa

## F6 [Significant] S2. The confidence band carries no information, so rule 4 and the hedge sentence are constant
**Location:** .**
- `decision_trace.dart` 454–495 (`lowNEffThreshold = 1.0`; low if n_eff < 1).
- `query_orchestrator.dart` 371–396 (route band = the worst edge's band; `low` when the route touches no hazard edge, line 396).
- `verifier.dart` 13–18 (rule 4 is route-level only).
- Paper: Sec. IV-A/B, Table I "Hedging".

**Claimed problem:** .** A single fresh official report gives n_eff < 1 (spatial kernel κ < 1), so any route touching one observed edge is `low`. A route touching none is also `low`. On the evaluation traces the band is **`low` in 300/300 cases** (C0, C1, C3). The Tier-0 text therefore always says confidence is low, and rule 4 always demands a hedge; the hedge never discriminates. `high` needs three or more full-weight fresh reports on every hazard edge of the route, which the crowd will rarely supply in a flood (council verdict, "the crowd is empty when needed").

## F7 [Significant] S3. "Explicit data gaps" mark every unconfigured edge, which yields unreadable explanations and contradicts the prior
**Location:** .** `query_orchestrator.dart` 284–293; `template_renderer.dart` 165–173; paper Sec. IV-A ("explicit data gaps").

**Claimed problem:** .** Every chosen-route edge without a hazard config is a "data gap", including edges the GCC prior rates low (p < 0.25 is excluded from configs). Per trace there are **median 217 data gaps (min 9, max 521)**. The Tier-0 data-gap sentence lists all of them, giving a **median of about 480 words** per explanation in the harness (port). With real names, deduplicated by street, a cross-city route still lists dozens of roads. Saying "no recent hazard data" for a road the prior rates very-low is also misleading: the prior *is* data.

## F8 [Significant] S4. Tier 1 is unlikely ever to finish inside the 1.2 s deadline on the target phone
**Location:** .**
- `flutter_gemma_rewriter.dart` 193–201 (`getActiveModel` and `createChat` run on every call, inside the timed future).
- `rewrite_pipeline.dart` 28 and 57.
- `fact_set.dart` (the full JSON, including every data gap and blocking edge, goes into the prompt).
- Paper Sec. IV-A; `docs/EVALUATION.md` Study 4 (a ₹10–15k phone).

**Claimed problem:** .** The deadline covers model acquisition, chat creation, prefill of a JSON prompt with hundreds of entries (S3), and decoding. Google's own figures for a fine-tuned Gemma 270M on a **Galaxy S25 Ultra** (flagship, cache warm, LiteRT XNNPACK, 4 threads) are about 1,700–2,200 tok/s prefill, about 126–154 tok/s decode, and TTFT about 0.24–0.3 s (FunctionGemma model card; litert-community model card). An anecdotal user report gives about 10 tok/s for Gemma 3 270M Q8 on a mid-range Motorola G72 via llama.cpp/Termux (LinkedIn comment; not peer-reviewed). On a budget phone, a 40–60-token sentence plus a cold model load is likely to exceed 1.2 s, so Tier 1 would almost always fall back silently. Note also that `maxTokens: 512` is passed to `getActiveModel` (context size), while the fact-set prompt can exceed 512 tokens once data gaps are included.

## F9 [Significant] S5. Tamil is mentioned as if supported, but no Tamil path exists and the verifier inverts under Tamil
**Location:** .**
- Paper Sec. IV-B ("does not transfer to Tamil script").
- `explanation.dart` line 133 ("Tamil templates are future work").
- `verifyOrFallback` default `locale = 'en'`.
- Both rewriter prompts are English-only and give no language instruction.

**Claimed problem:** .** Mentioning Tamil only under "entity check limitation" implies the rest works. In fact, under Tamil output:
- rules 1 (only partly: ASCII digits still checked), 2, 3 (comparative and avoidance terms), the hazard-noun part of the data-gap check, and 6 are all vacuous;
- rule 4 rejects correct Tamil hedges;
- Tier 0 has no Tamil.

LLM factuality in Tamil is measurably worse: IndicGenBench (ACL 2024) finds a large generation gap against English across Indic languages, and IndicQuest-based evaluation (arXiv 2504.20022) places Tamil in a "low performance" bucket. TN-ALERT is the incumbent Tamil-language product.

## F10 [Significant] S6. The false-reject rate is probably high, and the LM tiers may add almost nothing
**Location:** .** verifier.dart 284–328 (capitalised-word rule with a 25-word stop list), 510–540 (hedge list); `cloud_rewriter.dart` 220–227 and `flutter_gemma_rewriter.dart` 205–212 (the prompts say "used in Chennai" and give no hedge requirement).

**Claimed problem:** .**
- Any sentence-initial word outside the stop list fails rule 2: "Heavy", "Flooding", "Expect", "Take", "Due", "Please", "Water".
- "Chennai", which the prompt itself introduces, fails.
- So does any contraction such as "It's".
- Port example: "Heavy flooding was reported on Kotturpuram Bridge approach 3 minutes ago, so Route A takes 4 minutes longer." is rejected (`rule2:entity:Heavy`), although it is correct.
- With every band `low` (S2), each rewrite must also contain one of 18 English hedge substrings, and the prompts do not ask for one.
- A 270M model's weak instruction following (IFEval 51.2 for Gemma 3 270M IT, model card) makes compliance less likely still.

## F11 [Critical] C1. The router that ships and is evaluated does not use ALT; the paper's only surviving theory claim is about code that is never run
**Location:** `IDP/packages/pulse_router/lib/src/query_orchestrator.dart:155-168`; `alt_landmarks.dart:195-245`; `bin/pulse_router.dart:73-80`; paper.tex l.103-109, l.120, l.128 (Fig.1 "landmarks"), l.242; plan.tex l.62; `docs/DECISIONS.md:424,439`; `docs/ARCHITECTURE.md:24,52` ("bidir A* + ALT").

**Claimed problem:** `planRoute`, the one function both consumers call, runs plain bidirectional Dijkstra. The ALT code is a separate unidirectional A* (`aStarWithLandmarks`) that only tests call. No landmarks are computed in the graph build, the CLI or the app. ADR-012 point 7 blames the 3.07 s CLI time on "graph load + ALT landmark rebuild", but the CLI never builds landmarks. ADR-012(b) also says the paper's "honest claim … is limited to the ALT-admissibility result". The paper's Section IV sentence "compressed-sparse-row graph, bidirectional Dijkstra with ALT landmarks" is therefore false as a description of the system. The VI-E check ("minimum ratio w/τ0 was exactly 1.0, as Proposition 1 requires") was computed on the SciPy re-implementation. With δ=1 on every edge (no depth data), that check holds trivially.

## F12 [Critical] C2. "Runs entirely on the phone" is not implemented: the app is one fixed demo query on a hand-made hazard slice, with no on-device prior or report pipeline, and it has never been shown running on a phone
**Location:** `IDP/app/lib/src/routing/route_service.dart:65-104`; `app/lib/src/data/demo_route_fixture.dart:1-59`; `app/assets/demo/demo_hazards.json` (60 entries); `app/lib/src/ui/home_screen.dart:23`; paper.tex l.43-44 (abstract "runs entirely on the phone"), l.120, l.139-141 (Fig.1 dashed box "runs on the phone without connectivity"); plan.tex l.42, l.62-67.

**Claimed problem:** - **Routing is live, but on a fixed fixture.** The graph is the real 193k/471k graph, loaded from a 46 MB JSON asset and searched at runtime. But origin and destination are hard-coded (nodes 31140 → 47036, T. Nagar → Velachery), as are the clock (`2026-09-17T06:00Z`), z=0 and λ=0.3.
  - **The hazard input is hand-built.** It is a 60-edge slice with real ℓ0 values plus one synthetic crowd report (`demo-obs-mambalam-1`, depth 350 mm, 8 minutes old). That report exists to make the chance constraint fire.
  - **No city-wide prior on the device.** The 152 MB `chennai_prior_ell0.json` is not bundled, so the phone has no prior for the other ~471k edges.
  - **No report-to-edge path.** No Dart code snaps an observation to an edge or computes `distance_m` (grep for snap, nearest-edge and haversine in `app/lib` and `packages/*/lib` finds only grid coarsening). A report in the SQLite cache therefore cannot reach the router even after wiring.
  - **No reporting UI.** There is no OD picker and no way to submit a report.
  - **No device run.** Nothing in the repo shows the app on an Android device or emulator (`flutter_gemma_rewriter.dart:13`; CLAUDE.md §4 item 1). The only test that loads the real graph runs in the host VM (`app/test/route_service_integration_test.dart`). The staged copy also has no `android/` directory and no `hazard_database.g.dart`; see Q1.

## F13 [Critical] C3. The verifier fails open on route direction, number words and unlisted safety phrasing. The plan blames this defect only on the Kotlin prototype.
**Location:** `IDP/packages/pulse_explain/lib/src/verifier.dart:191` (digits-only regex), `:261` (`(chosen − alt).abs()` grounded), `:397-406` (speed comparatives need only *some* alternative to exist), `:550-575` (substring denylist); paper.tex Table I (l.151-168) and l.146 ("fail-closed"); plan.tex l.65 and l.72; README l.48 ("no hallucinated facts … ever").

**Claimed problem:** On the suite's own default trace (`test/helpers.dart`: chosen route A 1147 s, alternative B 907 s with a chance-constraint-removed bridge, confidence moderate), my line-by-line port of rules 1, 2, 3, 4 and 6 **accepts** all of these:
  1. "Route A is 4 minutes faster than Route B." (A is 4 minutes *slower*)
  2. "Route A saves you 4 minutes."
  3. "Route A is twenty minutes slower than Route B." (number words are not checked)
  4. "Route A takes 4 km longer." (unit swap, which the paper does acknowledge)
  5. "Route B is flooded to waist depth; Route A has no water at all."
  6. "The bridge is dry now, so go ahead on Route B." (tells the user to take the route whose bridge the chance constraint removed)

  Case 6 is the dangerous one. Plan l.72 says the Kotlin verifier "would pass 'saves 3 minutes' when the trace says the route is 3 minutes slower". The IDP verifier has the same direction blindness. The plan's comparison table (l.65) presents the IDP verifier as free of this flaw.

## F14 [Significant] S1. The user-facing "N minutes slower" sentence mixes objective cost with travel time
**Location:** `pulse_explain/lib/src/template_renderer.dart:113-120`; `pulse_router/lib/src/query_orchestrator.dart:197` (chosen `durationSeconds = totalCostSeconds` under hazard cost) vs `:277` (alternative `durationSeconds` = free-flow cost); `docs/CONTRACTS.md:146-147`.

**Claimed problem:** `chosen.duration_s` includes λ·p̃·s·τ0 penalty seconds. When depth is unknown, which in this corpus is always, those seconds are not travel time. `alternatives[0].duration_s` is pure free-flow time. The template's "Route A is N minutes slower than Route B" therefore overstates the detour by the penalty. The verifier passes it because both numbers are in the trace. Plan finding #2 covers this conflation only in the harness detour metric, not in the explanation users see.

## F15 [Significant] S2. HLC is decorative: sync orders and pages on device-reported `observed_at`, so late offline reports are silently skipped
**Location:** `app/lib/src/sync/sync_client.dart:114,151-153,200`; `server/app/storage/postgis.py:80,93`; `server/app/storage/memory.py:45`; paper.tex l.120 ("append-only log ordered by hybrid logical clocks").

**Claimed problem:** The HLC is put into an opaque `raw._hlc` field. The server never parses or indexes it, and `GET /observations?since=` filters on `observed_at`. Suppose phone X records a report at 10:00 while offline and uploads it at 12:00. Peer Y's cursor has already moved past 10:00, so Y never pulls it. This is the scenario offline-first sync exists for, and HLCs (or a server-assigned sequence or `received_at` cursor) are the standard fix. G-Set dedup by id is implemented correctly.

## F16 [Significant] S3. One future-dated report anywhere in the city makes every query throw
**Location:** `pulse_belief/lib/src/fusion.dart:88-93`; `pulse_router/lib/src/query_orchestrator.dart:120-134`; `server/app/models.py:70-77`.

**Claimed problem:** `fuse` throws if any observation postdates the query time, which is correct for one belief. But `planRoute` fuses **every** configured edge before searching, so a single future-dated observation on any edge aborts every route. The server accepts future `observed_at`, so one phone with a fast clock poisons every client after sync. This is latent today because the cache is not wired to the router (C2), but the design ensures it once wiring happens.

## F17 [Significant] S4. Tier-1 and Tier-2 are unrunnable as claimed. The 1.2 s deadline is likely unreachable as written.
**Location:** `app/lib/src/explain/flutter_gemma_rewriter.dart:12-22,58-60`; `rewrite_pipeline.dart:28,57`; `route_service.dart:104`; paper.tex l.146; plan.tex l.65.

**Claimed problem:** No model asset, no install flow and no device run exist. `generate()` calls `FlutterGemma.getActiveModel` on **every** query, so model load sits inside the 1.2 s budget. `.timeout()` abandons but does not cancel the native generation, which keeps burning CPU and battery. No test exercises `attemptRewrite` (the cited `app/test/fixtures/fake_slm_rewriter.dart` is missing). The Groq path needs a key compiled into the APK (`cloud_rewriter.dart:26-33`, already flagged by the authors).

## F18 [Significant] S5. Server "live ingest" is not live, and nothing it ingests is flood evidence
**Location:** `server/app/ingest/__init__.py:3-5`; `server/app/main.py:12-26`; `open_meteo.py:77,93`; `gdacs.py` docstring; `cmwssb.py`, `openaq.py`, `tomtom.py` (`NotImplementedError`); `server/app/storage/factory.py:37`; README l.13-15, l.50; plan.tex l.67.

**Claimed problem:** No scheduler or lifespan task runs any worker. Open-Meteo ingests `temperature_2m` as `heat` observations; flood discharge is returned as a context dict and dropped. GDACS is country-level and its element names are unverified. The README's "live rainfall + flood-alert workers" and "fuses live signals (rainfall, reservoir levels, citizen reports)" are not true: no precipitation is fetched and the reservoir scraper is a stub. The PostGIS DSN fallback uses `SUPABASE_SERVICE_KEY` (an API JWT) as the Postgres password, which will fail to authenticate. The server runs in memory by default and has never been deployed.

## F19 [Significant] S6. The decision trace is thinner than described
**Location:** `query_orchestrator.dart:204-205,276,284-294,312`; paper.tex l.146.

**Claimed problem:** `context_facts` is always empty. "The alternatives the router rejected" is always at most one: the free-flow path, labelled B. Edges with a prior-only config and zero observations are not reported as data gaps, even though "no recent evidence" is exactly what a user should be told. The confidence band is the worst band over configured edges and defaults to `low` when none are configured. That is reasonable, but it is undocumented in any ADR (comment at `:398-403`).

## F20 [Significant] S7. Kotlin prototype: the "Tier-1 SLM" makes the exact absolute-safety claim the project forbids, its own verifier passes it, and the handoff doc claims production readiness
**Location:** - `KT/app/src/main/java/com/example/engine/SymbolicExplanationEngine.kt:56-69` ("CityPulse **safely** redirected your journey…")
  - `:78-139` (numeral-only check, `abs()`, tolerance 0.15, and 0/1/2 always allowed)
  - `engine/PulseRouter.kt:165` (edges with no belief get an invented p̃=0.1), `:239` (badge 94/88)
  - `engine/BeliefFusionEngine.kt:94-100` (n0=3; clamp to [0.01,0.99]; δ=1+3.2·p̃^1.5 attributed to Pregnolato)
  - `app/build.gradle.kts:103` (`firebase.ai` dependency present but unused)
  - `AGENT_HANDOFF_CITYPULSE_AI.md:412-414` ("fully operational … production readiness … life-saving")

**Claimed problem:** The Tier-1 text is a fixed string template, not a model. It asserts safety, which violates ADR-011, and the verifier passes it because it only checks numerals. There are 3 substantive tests (`ExampleRobolectricTest.kt`). The rest are boilerplate.
