# S8: Code-versus-claims and classification

Reviewer: S8 (code vs claims, classification). Date: 2026-10-01.
Scope: paper.tex Sections III–IV and VI-E (engineering checks), plan.tex Sections 2–3, research repo `citypulse-IDP` (read-only staged copy), Kotlin prototype `citypulse-ai`.
Method: read every source file on the claimed paths, traced call graphs with grep, counted tests statically, and re-ran the Python suites on a scratch copy (server 33/33 pass; scripts 41/42 pass, and the one failure needs the Dart CLI binary). There is no Dart SDK here (storage.googleapis.com is blocked by the proxy), so the Dart suites were **not** executed. I ported the verifier's rules 1, 2, 3, 4 and 6 line by line to Python and ran them on the test suite's default trace (`/tmp/.../scratchpad/verifier_port.py`).

Paths: `IDP/` = `/mnt/user-data/uploads/citypulse-IDP/citypulse-IDP/`, `KT/` = `/mnt/user-data/uploads/citypulse-ai/`.

---

## Claim-by-claim table

| # | Claim (where) | Verdict | Evidence |
|---|---|---|---|
| 1 | One router shared by app and harness (paper l.120; plan l.103) | **Implemented** at the source level. The stored results have **no provenance** linking them to that source | Both call `planRoute`: `IDP/packages/pulse_router/bin/pulse_router.dart:80`, `IDP/app/lib/src/routing/route_service.dart:75`. The harness shells out to `data/bin/pulse_router.exe` (`IDP/scripts/study_common.py:17`). No commit or binary hash is recorded in `data/results/*/result.json`. Study 2 uses a Python replica of `fuse`/`pessimistic` with parity tests (`study_common.py:6-25`) |
| 2 | Bidirectional Dijkstra **with ALT landmarks** (paper l.120, Fig.1 "landmarks"; plan l.62; README l.46; ADR-001) | **Partial. ALT is not in the shipped or evaluated path** | `planRoute` calls plain `bidirectionalDijkstra` twice (`query_orchestrator.dart:155,163`). `aStarWithLandmarks` (`alt_landmarks.dart:195`) is **unidirectional** A* and is referenced only from tests. No script or CLI builds landmarks (grep "landmark" across `scripts/*.py` and `bin/` finds nothing) |
| 3 | Runtime validation instead of asserts (paper l.120; plan l.103) | **Partial.** True in `pulse_belief` and `edgeCost`. Asserts remain elsewhere | Belief: `fusion.dart:88`, `observation.dart`, `kernel.dart`, `pessimistic.dart` all throw. Asserts remain in `csr_graph.dart:26-35` (τ0>0, ids≥0), `alt_landmarks.dart:65-70,142`, `decision_trace.dart:102` (UTC), `math_utils.dart:11` (logit). `hMaxMm` is never validated in `edge_cost.dart:57-102` |
| 4 | SQLite + R*-tree cache, outbox (paper l.120; plan l.67) | **Implemented as a module, not integrated** | `hazard_database.dart:61-63` (`USING rtree`), outbox DAO at `:209-228`. No caller in `lib/` outside storage and sync (grep `HazardCache\|HazardDatabase`). `app/README.md:50-53` says it is "not yet wired into route_service.dart or the UI" |
| 5 | Outbox + HLC + G-Set sync (paper l.120; plan l.67) | **Partial.** Outbox and id-dedup exist. HLC is stamped but never used for ordering | HLC written into `raw._hlc` (`sync_client.dart:114,200`). The server never reads it (grep `hlc` in `server/app` finds nothing). The pull cursor is `observed_at` (`sync_client.dart:151-153`; `postgis.py:80,93`; `memory.py:45`). `ON CONFLICT (id) DO NOTHING` at `postgis.py:64`. `SyncClient` is never constructed in `lib/` |
| 6 | Tier-1 flutter_gemma + Tier-2 Groq behind a 1.2 s deadline (paper l.146; plan l.65) | **Code exists; unwired, never executed, untested** | `rewrite_pipeline.dart:28,57`, `cloud_rewriter.dart:77`. `computeDemoRoute` defaults to `rewriter == null` (`route_service.dart:104`), and `HomeScreen` never passes one (`home_screen.dart:23`). `flutter_gemma_rewriter.dart:12-22` states it was "never been run against real model weights". The `FakeSlmRewriter` test fixture it cites does not exist in `app/test/` |
| 7 | Six verifier checks (paper Table I; plan l.65) | **Implemented as described. Fails open on easy adversarial inputs** | `verifier.dart:96-110` (7 check functions mapped to rules 1/2/3/4/6). See Critical-3 |
| 8 | "~250 tests" (paper l.242; plan l.103; README badge) | **Undercounted. ~291 test cases are defined.** Only the Python share was re-verified | Dart: 174 static `test(`/`testWidgets(` calls, about 216 at runtime (42 `_expectRejected` helper calls in `verifier_test.dart`, 1 two-iteration loop in `template_renderer_test.dart`). Python: 68 `def test_`, 75 after parametrize. Re-run here: server 33/33, scripts 41/42. Dart 216 not run |
| 9 | Decision trace holds alternatives, contextual facts, data gaps (paper l.146) | **Partial** | `contextFacts: const []` is hard-coded (`query_orchestrator.dart:312`). The only alternative is the free-flow path (`:163,276`). Data gaps cover only edges with no hazard config (`:284-294`) |
| 10 | Server ingest (GDACS / Open-Meteo) (plan l.67; README "live rainfall + flood-alert workers") | **Not live** | No scheduler (`server/app/ingest/__init__.py:3-5`; `main.py` starts none). Open-Meteo ingests **temperature** only (`open_meteo.py:77`). River discharge is returned, not stored (`:93`). The GDACS GeoRSS schema was never checked against a live fetch (`gdacs.py` docstring). CMWSSB, OpenAQ and TomTom raise `NotImplementedError` |
| 11 | App routes offline on the real graph (paper abstract, Fig.1; README) | **Partial.** It searches the real graph, but only for one hard-coded query against a 60-edge hand-made hazard fixture | See Critical-2 |

---

## Critical

### C1. The router that ships and is evaluated does not use ALT; the paper's only surviving theory claim is about code that is never run
- **Location:** `IDP/packages/pulse_router/lib/src/query_orchestrator.dart:155-168`; `alt_landmarks.dart:195-245`; `bin/pulse_router.dart:73-80`; paper.tex l.103-109, l.120, l.128 (Fig.1 "landmarks"), l.242; plan.tex l.62; `docs/DECISIONS.md:424,439`; `docs/ARCHITECTURE.md:24,52` ("bidir A* + ALT").
- **Problem:** `planRoute`, the one function both consumers call, runs plain bidirectional Dijkstra. The ALT code is a separate unidirectional A* (`aStarWithLandmarks`) that only tests call. No landmarks are computed in the graph build, the CLI or the app. ADR-012 point 7 blames the 3.07 s CLI time on "graph load + ALT landmark rebuild", but the CLI never builds landmarks. ADR-012(b) also says the paper's "honest claim … is limited to the ALT-admissibility result". The paper's Section IV sentence "compressed-sparse-row graph, bidirectional Dijkstra with ALT landmarks" is therefore false as a description of the system. The VI-E check ("minimum ratio w/τ0 was exactly 1.0, as Proposition 1 requires") was computed on the SciPy re-implementation. With δ=1 on every edge (no depth data), that check holds trivially.
- **Why it matters:** Proposition 1 has no bearing on the evaluated system. A referee who opens the code will see a false architecture claim and an ADR whose timing explanation is wrong. That damages trust in the parts that are honest.
- **Suggested fix:** Pick one of two options. (a) Wire ALT into `planRoute`: precompute landmarks offline, ship them with the graph, and implement bidirectional ALT with consistent average potentials, or call the unidirectional A*. Then report query-latency speedups on the Chennai graph and run the T2.3 ≥10k-configuration equivalence test on the real graph, not the 40-node toy (`alt_landmarks_test.dart:260-296`). (b) Remove "ALT" from paper l.120 and Fig.1. Keep Proposition 1 only as a remark that ALT *would* stay exact, credited to Delling & Wagner. Correct ADR-012 points 7 and (b).
- **Confidence:** High.
- **Evidence:** `grep -rn "aStarWithLandmarks\|AltLandmarks" --include=*.dart` outside tests returns only the definitions. `grep landmark scripts/*.py` returns nothing. `query_orchestrator.dart:3` imports only `bidirectional_dijkstra.dart`.

### C2. "Runs entirely on the phone" is not implemented: the app is one fixed demo query on a hand-made hazard slice, with no on-device prior or report pipeline, and it has never been shown running on a phone
- **Location:** `IDP/app/lib/src/routing/route_service.dart:65-104`; `app/lib/src/data/demo_route_fixture.dart:1-59`; `app/assets/demo/demo_hazards.json` (60 entries); `app/lib/src/ui/home_screen.dart:23`; paper.tex l.43-44 (abstract "runs entirely on the phone"), l.120, l.139-141 (Fig.1 dashed box "runs on the phone without connectivity"); plan.tex l.42, l.62-67.
- **Problem:**
  - **Routing is live, but on a fixed fixture.** The graph is the real 193k/471k graph, loaded from a 46 MB JSON asset and searched at runtime. But origin and destination are hard-coded (nodes 31140 → 47036, T. Nagar → Velachery), as are the clock (`2026-09-17T06:00Z`), z=0 and λ=0.3.
  - **The hazard input is hand-built.** It is a 60-edge slice with real ℓ0 values plus one synthetic crowd report (`demo-obs-mambalam-1`, depth 350 mm, 8 minutes old). That report exists to make the chance constraint fire.
  - **No city-wide prior on the device.** The 152 MB `chennai_prior_ell0.json` is not bundled, so the phone has no prior for the other ~471k edges.
  - **No report-to-edge path.** No Dart code snaps an observation to an edge or computes `distance_m` (grep for snap, nearest-edge and haversine in `app/lib` and `packages/*/lib` finds only grid coarsening). A report in the SQLite cache therefore cannot reach the router even after wiring.
  - **No reporting UI.** There is no OD picker and no way to submit a report.
  - **No device run.** Nothing in the repo shows the app on an Android device or emulator (`flutter_gemma_rewriter.dart:13`; CLAUDE.md §4 item 1). The only test that loads the real graph runs in the host VM (`app/test/route_service_integration_test.dart`). The staged copy also has no `android/` directory and no `hazard_database.g.dart`; see Q1.
- **Why it matters:** "Everything runs on the phone" is the paper's main systems claim and the product's differentiator. As built, the phone holds a demo that cannot use real or new hazard data.
- **Suggested fix:** Narrow the paper's wording now, e.g. "the routing, belief and explanation packages are pure Dart and run in-process in a Flutter client; end-to-end on-device integration is future work". To make the claim true, ship a packed per-edge prior and class table, add on-device snapping (an edge R-tree or grid over edge midpoints), connect `HazardCache` to `planRoute`, add OD selection and a report form, and report cold-start time and RSS on a ₹10–15k phone.
- **Confidence:** High.
- **Evidence:** `route_service.dart:70` (`loadDemoHazardInput()`), `:77-82`; `demo_route_fixture.dart:6-29` ("**This is not the T-W1 watchlist** … a small, real-data-grounded slice assembled for this task only"); `app/README.md:41-46,50-53`.

### C3. The verifier fails open on route direction, number words and unlisted safety phrasing. The plan blames this defect only on the Kotlin prototype.
- **Location:** `IDP/packages/pulse_explain/lib/src/verifier.dart:191` (digits-only regex), `:261` (`(chosen − alt).abs()` grounded), `:397-406` (speed comparatives need only *some* alternative to exist), `:550-575` (substring denylist); paper.tex Table I (l.151-168) and l.146 ("fail-closed"); plan.tex l.65 and l.72; README l.48 ("no hallucinated facts … ever").
- **Problem:** On the suite's own default trace (`test/helpers.dart`: chosen route A 1147 s, alternative B 907 s with a chance-constraint-removed bridge, confidence moderate), my line-by-line port of rules 1, 2, 3, 4 and 6 **accepts** all of these:
  1. "Route A is 4 minutes faster than Route B." (A is 4 minutes *slower*)
  2. "Route A saves you 4 minutes."
  3. "Route A is twenty minutes slower than Route B." (number words are not checked)
  4. "Route A takes 4 km longer." (unit swap, which the paper does acknowledge)
  5. "Route B is flooded to waist depth; Route A has no water at all."
  6. "The bridge is dry now, so go ahead on Route B." (tells the user to take the route whose bridge the chance constraint removed)

  Case 6 is the dangerous one. Plan l.72 says the Kotlin verifier "would pass 'saves 3 minutes' when the trace says the route is 3 minutes slower". The IDP verifier has the same direction blindness. The plan's comparison table (l.65) presents the IDP verifier as free of this flaw.
- **Why it matters:** The "verified, fail-closed explanation" is one of the four listed contributions and the main safety argument for allowing an LLM in the loop. A referee or red-teamer will find these cases in minutes. Under ADR-011, case 6 is exactly the failure the system exists to prevent.
- **Suggested fix:**
  - Bind direction: ground `chosen − alt` with its sign, and require "slower", "longer" or "more" when the sign is positive; reject "saves", "faster", "quicker" or "shorter".
  - Spell out number words and fractions before rule 1 ("twenty", "half an hour", "a few").
  - Turn rule 6 into an allowlist. Rewrites should only reorder or paraphrase template slots, using slot-filled templates or constrained decoding. Reject any passability or condition predicate ("dry", "open", "no water", "go ahead", "take Route B") about a removed or blocking edge.
  - Add these cases to the adversarial suite. Fix plan l.65/l.72 so the flaw is attributed to both codebases.
  - In the paper, report the verifier's measured precision and recall on a red-team set rather than calling it fail-closed.
- **Confidence:** High for 1–3 and 6. The port is mechanical, but the Dart was not executed, so a 30-second `dart test` confirmation is advised.
- **Evidence:** `/tmp/claude-0/-home-claude/aa10ead1-266e-5d6e-9869-ab7db0329f5f/scratchpad/verifier_port.py` prints `PASS` for all 7 inputs, including the truthful control. The Dart logic is quoted in `verifier.dart:201-217, 400-430, 574-583`.

---

## Significant

### S1. The user-facing "N minutes slower" sentence mixes objective cost with travel time
- **Location:** `pulse_explain/lib/src/template_renderer.dart:113-120`; `pulse_router/lib/src/query_orchestrator.dart:197` (chosen `durationSeconds = totalCostSeconds` under hazard cost) vs `:277` (alternative `durationSeconds` = free-flow cost); `docs/CONTRACTS.md:146-147`.
- **Problem:** `chosen.duration_s` includes λ·p̃·s·τ0 penalty seconds. When depth is unknown, which in this corpus is always, those seconds are not travel time. `alternatives[0].duration_s` is pure free-flow time. The template's "Route A is N minutes slower than Route B" therefore overstates the detour by the penalty. The verifier passes it because both numbers are in the trace. Plan finding #2 covers this conflation only in the harness detour metric, not in the explanation users see.
- **Why it matters:** The "verified" text is internally consistent but physically wrong. It is a faithfulness failure that a symbolic check cannot catch, and a good example for the paper's own threats section.
- **Suggested fix:** Put `travel_time_s` (τ0·[1+p̃(δ−1)]) and `objective_s` in the trace separately for chosen and alternatives, and have the template compare travel times only.
- **Confidence:** High.
- **Evidence:** Code lines above. `ChosenRoute.hazardTimePenaltySeconds = durationSeconds − freeFlowDurationSeconds` (`decision_trace.dart:295-296`).

### S2. HLC is decorative: sync orders and pages on device-reported `observed_at`, so late offline reports are silently skipped
- **Location:** `app/lib/src/sync/sync_client.dart:114,151-153,200`; `server/app/storage/postgis.py:80,93`; `server/app/storage/memory.py:45`; paper.tex l.120 ("append-only log ordered by hybrid logical clocks").
- **Problem:** The HLC is put into an opaque `raw._hlc` field. The server never parses or indexes it, and `GET /observations?since=` filters on `observed_at`. Suppose phone X records a report at 10:00 while offline and uploads it at 12:00. Peer Y's cursor has already moved past 10:00, so Y never pulls it. This is the scenario offline-first sync exists for, and HLCs (or a server-assigned sequence or `received_at` cursor) are the standard fix. G-Set dedup by id is implemented correctly.
- **Why it matters:** In an outage the reports that matter most arrive late. As written, peers lose them.
- **Suggested fix:** Page on a server-monotonic key (a `received_at` sequence or log offset) or on the HLC, and keep `observed_at` only for decay. Add an integration test with a late-arriving old report.
- **Confidence:** High.
- **Evidence:** grep for "hlc" in `server/app` returns nothing.

### S3. One future-dated report anywhere in the city makes every query throw
- **Location:** `pulse_belief/lib/src/fusion.dart:88-93`; `pulse_router/lib/src/query_orchestrator.dart:120-134`; `server/app/models.py:70-77`.
- **Problem:** `fuse` throws if any observation postdates the query time, which is correct for one belief. But `planRoute` fuses **every** configured edge before searching, so a single future-dated observation on any edge aborts every route. The server accepts future `observed_at`, so one phone with a fast clock poisons every client after sync. This is latent today because the cache is not wired to the router (C2), but the design ensures it once wiring happens.
- **Why it matters:** The system fails safe for that one edge but fails *stopped* for the whole service. A routing app that refuses all routes during a flood is a safety problem too.
- **Suggested fix:** Clamp or quarantine future observations per edge (reject at server ingest beyond a tolerance; on the client, clamp age at 0 and flag a data gap) instead of throwing from the whole-query path. Fuse lazily, only for edges the search touches.
- **Confidence:** High on the mechanism, medium on real-world frequency.
- **Evidence:** Code above. No future-time validator exists in `models.py`.

### S4. Tier-1 and Tier-2 are unrunnable as claimed. The 1.2 s deadline is likely unreachable as written.
- **Location:** `app/lib/src/explain/flutter_gemma_rewriter.dart:12-22,58-60`; `rewrite_pipeline.dart:28,57`; `route_service.dart:104`; paper.tex l.146; plan.tex l.65.
- **Problem:** No model asset, no install flow and no device run exist. `generate()` calls `FlutterGemma.getActiveModel` on **every** query, so model load sits inside the 1.2 s budget. `.timeout()` abandons but does not cancel the native generation, which keeps burning CPU and battery. No test exercises `attemptRewrite` (the cited `app/test/fixtures/fake_slm_rewriter.dart` is missing). The Groq path needs a key compiled into the APK (`cloud_rewriter.dart:26-33`, already flagged by the authors).
- **Why it matters:** The paper describes a three-tier design as implemented. In practice only Tier 0 exists.
- **Suggested fix:** In the paper, say "Tier 1/2 integration is written against the published API but has not been executed". Load the model once per session, measure time to first token on the target phone (T0.1), add the missing fake-rewriter test, and route Groq through the server.
- **Confidence:** High.
- **Evidence:** Lines above; `find app/test` lists no rewrite tests.

### S5. Server "live ingest" is not live, and nothing it ingests is flood evidence
- **Location:** `server/app/ingest/__init__.py:3-5`; `server/app/main.py:12-26`; `open_meteo.py:77,93`; `gdacs.py` docstring; `cmwssb.py`, `openaq.py`, `tomtom.py` (`NotImplementedError`); `server/app/storage/factory.py:37`; README l.13-15, l.50; plan.tex l.67.
- **Problem:** No scheduler or lifespan task runs any worker. Open-Meteo ingests `temperature_2m` as `heat` observations; flood discharge is returned as a context dict and dropped. GDACS is country-level and its element names are unverified. The README's "live rainfall + flood-alert workers" and "fuses live signals (rainfall, reservoir levels, citizen reports)" are not true: no precipitation is fetched and the reservoir scraper is a stub. The PostGIS DSN fallback uses `SUPABASE_SERVICE_KEY` (an API JWT) as the Postgres password, which will fail to authenticate. The server runs in memory by default and has never been deployed.
- **Why it matters:** Reviewers and investors read the README as the status report. The project's own council named the empty live signal as its biggest risk.
- **Suggested fix:** Rewrite the README status table. Add a lifespan or APScheduler job, a precipitation ingest (Open-Meteo `precipitation`), and a live-fetch smoke test for GDACS. Require an explicit DB URL instead of deriving one.
- **Confidence:** High.
- **Evidence:** Lines above. The 33 server tests pass with respx-mocked feeds.

### S6. The decision trace is thinner than described
- **Location:** `query_orchestrator.dart:204-205,276,284-294,312`; paper.tex l.146.
- **Problem:** `context_facts` is always empty. "The alternatives the router rejected" is always at most one: the free-flow path, labelled B. Edges with a prior-only config and zero observations are not reported as data gaps, even though "no recent evidence" is exactly what a user should be told. The confidence band is the worst band over configured edges and defaults to `low` when none are configured. That is reasonable, but it is undocumented in any ADR (comment at `:398-403`).
- **Why it matters:** The verifier's grounding set *is* the trace, so a thin trace means thin explanations. The paper should describe what exists.
- **Suggested fix:** Either implement k-alternatives (penalty or plateau method), prior-only data gaps and context facts, or change paper l.146 to "one free-flow alternative; contextual facts reserved".
- **Confidence:** High.

### S7. Kotlin prototype: the "Tier-1 SLM" makes the exact absolute-safety claim the project forbids, its own verifier passes it, and the handoff doc claims production readiness
- **Location:**
  - `KT/app/src/main/java/com/example/engine/SymbolicExplanationEngine.kt:56-69` ("CityPulse **safely** redirected your journey…")
  - `:78-139` (numeral-only check, `abs()`, tolerance 0.15, and 0/1/2 always allowed)
  - `engine/PulseRouter.kt:165` (edges with no belief get an invented p̃=0.1), `:239` (badge 94/88)
  - `engine/BeliefFusionEngine.kt:94-100` (n0=3; clamp to [0.01,0.99]; δ=1+3.2·p̃^1.5 attributed to Pregnolato)
  - `app/build.gradle.kts:103` (`firebase.ai` dependency present but unused)
  - `AGENT_HANDOFF_CITYPULSE_AI.md:412-414` ("fully operational … production readiness … life-saving")
- **Problem:** The Tier-1 text is a fixed string template, not a model. It asserts safety, which violates ADR-011, and the verifier passes it because it only checks numerals. There are 3 substantive tests (`ExampleRobolectricTest.kt`). The rest are boilerplate.
- **Why it matters:** If this app is shown at a demo or hackathon, its numbers and claims contradict the research repo's own safety rules.
- **Suggested fix:** Archive it as a UI mock-up. Do not present its badge, "risk reduction %" or Tier-1 text as system outputs. Remove "production readiness" from the handoff.
- **Confidence:** High.

---

## Minor

### M1. Test count is understated and the README breakdown is stale
- **Location:** paper.tex l.242; plan.tex l.103; `IDP/README.md:9,46-51`; `app/README.md:103` ("72 passing tests").
- **Problem:** About **291** test cases are defined (216 Dart at runtime, 75 Python after parametrize) against "~250". The README's per-component numbers are stale (app 23 vs 35 defined; scripts 15 vs 42). Most Dart tests use toy graphs. Only `route_service_integration_test.dart` touches the real graph, and it checks shape, not optimality.
- **Suggested fix:** Say "about 290 automated test cases (216 Dart, 75 Python); the Python suites were re-run independently". Add a CI badge that reflects real runs.
- **Confidence:** High for static counts. Dart pass status is unverified.
- **Evidence:**

  | Package | Defined test cases |
  |---|---|
  | router | 80 |
  | belief | 26 |
  | explain | 75 (33 static + 42 helper-generated) |
  | app | 35 |
  | server | 33 (pass) |
  | scripts | 42 (41 pass, 1 needs the Dart CLI) |

### M2. plan.tex states the wrong size for the Kotlin toy graph
- **Location:** plan.tex l.62 ("18-node, 26-edge"); IDEA_AND_FACTS l.19; `KT/.../data/ChennaiGraphData.kt:11-37,60+`.
- **Problem:** The staged code has **27 nodes** and **36 bidirectional links (72 directed edges)** via `createBiEdges`.
- **Fix:** Correct the number, or say "a hand-made graph of a few dozen nodes".
- **Confidence:** High.

### M3. Figure 1 puts the cloud rewriter inside the offline box
- **Location:** paper.tex l.134, l.139.
- **Problem:** The "Tier 1 on-device SLM / Tier 2 cloud rewriter" node sits inside the dashed "runs on the phone without connectivity" region.
- **Fix:** Move Tier 2 outside, next to the server node.
- **Confidence:** High.

### M4. The Proposition 1 sanity check is vacuous on this corpus
- **Location:** paper.tex l.242.
- **Problem:** With no depth anywhere, δ≡1, so w/τ0 ≥ 1 holds by arithmetic. The check also ran in SciPy, not Dart.
- **Fix:** Say so, or test with injected depths through the Dart CLI.
- **Confidence:** High.

### M5. Some asserts remain on untrusted-input paths, and `hMaxMm` is unchecked
- **Location:** `csr_graph.dart:26-35`; `decision_trace.dart:102`; `alt_landmarks.dart:65-70,142`; `edge_cost.dart:57-102`.
- **Problem:** A graph JSON with τ0=0 passes release builds (Dijkstra accepts cost 0). A negative `h_max_mm` removes every edge that has a depth reading; a huge one disables the chance constraint. JSON cannot carry NaN, so the risk is low.
- **Fix:** Convert these asserts to `ArgumentError` and validate `hMaxMm ≥ 0` and finite.
- **Confidence:** High.

### M6. The Pregnolato coefficients are flagged "[UNVERIFIED DETAIL]" in code but cited without caveat in the paper
- **Location:** `depth_disruption.dart:117-121`; paper.tex l.101.
- **Fix:** Check the coefficients against the primary paper (S-reviewer for references) and remove the flag, or carry the caveat into the paper.
- **Confidence:** High that the flag exists. The coefficient values themselves were not checked here.

### M7. "G-Set" semantics are bent by coarsening
- **Location:** `hazard_database.dart:169-205` (ADR-010 in-place `UPDATE` of lat/lon and the rtree).
- **Problem:** A pure G-Set has no in-place mutation. Coarsening is a local, privacy-motivated mutation that sync does not propagate.
- **Fix:** Call it "an append-only log with local coarsening" in the paper, or model coarsening as a tombstone plus re-add.
- **Confidence:** Medium.

### M8. Stored results cannot be tied to a code version
- **Location:** `data/results/2026-09-18-study1-route-quality/result.json` (no commit or binary hash); `scripts/study_common.py:17` (`data/bin/pulse_router.exe`).
- **Fix:** Record `git rev-parse HEAD` and the SHA-256 of the CLI binary in every `result.json`.
- **Confidence:** High.

---

## Questions for the authors

1. **Q1.** The staged app has no `android/` directory, no `.gitignore` and no `hazard_database.g.dart`, although `app/README.md:72` says the codegen file is committed. Are these in the real repo? Without them, `flutter build apk` and `flutter test` (for storage) fail.
2. **Q2.** Has the Flutter app ever run on an Android device or emulator? What are the cold-start time (46 MB JSON decode in an isolate) and peak RSS?
3. **Q3.** Which commit built `data/bin/pulse_router.exe` for the 2026-09-18 studies?
4. **Q4.** T0.2 (bidirectional Dijkstra p50/p95 on the Chennai graph) has a script (`scripts/t0_2_graph_timing.py`) but no `data/results/*t02*`. Was it run? Its result decides whether ALT is needed at all (ADR-001: "10–40 ms expected").
5. **Q5.** Will the T-W1 watchlist (`data/results/2026-09-14-tw1-watchlist`) replace the 60-edge demo fixture? If so, when?

---

## Classification

### TRL definitions used
- **EU Horizon 2020 Work Programme, General Annex G:**
  - TRL 2: technology concept formulated
  - TRL 3: experimental proof of concept
  - TRL 4: technology validated in lab
  - TRL 5: technology validated in relevant environment
  - TRL 6: technology demonstrated in relevant environment
  - TRL 7: system prototype demonstration in operational environment
  - TRL 8–9: qualified and proven in operation
- **Cross-checked against NASA NPR 7123.1 (Appendix E):**
  - TRL 3: analytical and experimental critical-function proof-of-concept
  - TRL 4: component and/or breadboard validation in a laboratory environment
  - TRL 5: component and/or breadboard validation in a relevant environment
  - TRL 6: system/subsystem prototype demonstration in a relevant environment
- **What counts as what here:**
  - **Relevant environment:** live Chennai monsoon data on a ₹10–15k Android phone.
  - **Lab:** historical replay on a workstation.

### (a) `citypulse-IDP` (research repo)

| Component | TRL | Justification |
|---|---|---|
| `pulse_router` + `pulse_belief` | **4** | Validated as components on the full-scale real graph with a deterministic replay harness (byte-identical reruns) and an independent SciPy reproduction (100/100 paths). The data are historical with one timestamp, no depth and no negatives, so this is lab, not relevant environment. ALT is TRL 3 (toy-graph tests only, not integrated). |
| `pulse_explain` (Tier 0 + verifier) | **3–4** | The template and verifier are unit-validated with an adversarial suite. Robustness against real model output is unmeasured and has easy fail-open cases (C3). |
| Tier 1 / Tier 2 rewriters | **2–3** | Code written against the API; never executed. |
| Flutter client | **3** | Proof of concept: one fixed query in the host VM; cache, sync and rewriters not integrated; no device run (C2). |
| Server | **3** | API and in-memory store tested; workers unscheduled; feeds unverified live; never deployed. |
| **Whole system** | **3** | Critical functions are proven separately, but no integrated system has been demonstrated, even in the lab. |

- **Software maturity: research artifact** (a well-engineered research prototype). It is above "prototype": there are ADRs, contracts, about 290 tests, determinism checks and recorded negative results. It is below "MVP": no end-user can choose a route, submit a report or receive live data. It is not production: no deployment, no CI evidence, no device validation, no licence.
- **Architecture style:**
  - A modular monorepo with a **shared-core library architecture**, where one pure-Dart core has two consumers: in-process in Flutter, and as an AOT CLI for the Python harness.
  - The core follows **functional core / imperative shell**: pure fusion, cost and trace functions, with I/O kept at the edges.
  - The query runs as a **pipeline**: belief → pessimistic plug-in → cost → search → trace → NLG → verifier.
  - The client is **offline-first, thick-client and local-first**: SQLite/R*-tree cache plus outbox.
  - The server is **thin event-sourced ingest**: an append-only observation log with G-Set dedup and SSE pub/sub, plus a repository (ports-and-adapters) pattern for memory or PostGIS.
  - The evaluation layer is **batch scripts** around a subprocess CLI.

### (a) `citypulse-ai` (Kotlin)
- **TRL 2** (concept formulated and illustrated). It does not reach TRL 3: the "experiment" runs on a 27-node hand-made graph with invented priors, hard-coded confidence (94/88), a misattributed slowdown curve and a templated "SLM".
- **Maturity: UI/design mock-up (demo prototype)**, generated with an AI app builder (`metadata.json` declares `MAJOR_CAPABILITY_SERVER_SIDE_GEMINI_API`; the handoff doc is an agent transcript).
- **Architecture: single-module Android MVVM.** Compose UI, a ViewModel, a Repository, Room, and singleton `object` engines. The data layer is fixtures compiled into code.

### (b) The core idea

**Contribution type: primarily systems integration with an application case study.** It also has a modest modelling and analysis component.
- **Not a new algorithm.** Bidirectional Dijkstra and ALT are textbook. ALT's correctness under increasing weights is Delling & Wagner 2007.
- **Not a new model.**
  - Log-odds fusion follows the occupancy-grid tradition.
  - The pessimistic plug-in is a one-sided Wald/UCB band.
  - Separating slowdown from harm, and the "confidence-multiplied penalties are risk-seeking under ambiguity" argument, are useful modelling points but small.
  - Proposition 2 (the 1+λs cap) is an elementary but practically important bound.
- **Not a dataset or benchmark.** The 6,132-observation corpus is derived from OpenCity layers, has one timestamp, and has no labels independent of the belief. The deterministic replay harness could be released as a minor artifact.
- **HCI** is a stated future component (confidence UI, ADR-011 disclaimers, the Study 5 human study) with no results yet.
- **The publishable core** is the *combination*: offline belief-aware routing, a fail-closed explanation contract and an honest replay evaluation on a real city graph. This is an applied systems / ICT4D paper, not an algorithms paper.
- **Venue fit:** ACM COMPASS, ACM SIGSPATIAL (short or demo), IEEE ITSC or GHTC, ISCRAM.

**ACM CCS 2012 concepts** (best-effort paths):
- Applied computing → Operations research → Transportation *(primary)*
- Information systems → Information systems applications → Spatial-temporal systems → Geographic information systems / Location based services
- Theory of computation → Design and analysis of algorithms → Graph algorithms analysis → Shortest paths
- Computing methodologies → Artificial intelligence → Knowledge representation and reasoning → Probabilistic reasoning
- Computing methodologies → Modeling and simulation → Model development and analysis → Uncertainty quantification
- Computing methodologies → Artificial intelligence → Natural language processing → Natural language generation
- Human-centered computing → Ubiquitous and mobile computing
- Social and professional topics → Computing / technology policy (secondary, for the DPDP and disaster-response context)

**Product category:**
- **Primary: civic tech / public-good resilience tool, delivered as a consumer navigation feature** (an offline flood-aware route explainer for residents). This is what the code does: a single user, the commuter class as default, open government data, no accounts or billing.
- **Credible second market: an emergency-services decision-support tool.** The z=2 emergency class and chance constraint fit, but nothing for dispatch, fleets or multi-vehicle routing exists.
- **B2B data API** (the council's fleet "passability API"): **not supported by any code.** The server exposes raw observations only. There is no edge-level passability product, SLA or traversal-silence ingestion.
- **As a stand-alone consumer navigation app:** it competes directly with Google Maps and Waze closures. It is defensible only through offline operation plus local Chennai data, which is the claim C2 shows is not yet built.
