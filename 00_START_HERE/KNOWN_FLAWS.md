# Known flaws register

Every entry below survived an eight-specialist review, a defence round arguing for the authors, and an independent adjudicator (October 2026). The review IDs (D1-F10 and so on) point to `04_critique_and_review/deep_review/`. Paths are relative to `01_code/citypulse-IDP/`. Line numbers refer to the code as copied on 2 October 2026; re-check them before editing.

**Status values:** OPEN, IN PROGRESS, FIXED (date, file), WON'T FIX (reason). When you fix something, update this file and re-run every study the flaw affects.

**Severity:**
- **Critical** — invalidates a headline claim, or is a live safety bug.
- **Significant** — must be fixed or disclosed before publication or deployment.
- **Minor** — hygiene.

---

## Critical

### F-01 · The pessimistic index lowers caution after weak evidence · FIXED (2026-10-02, `pulse_belief/lib/src/beta*.dart`, ADR-015; property tests show a positive report never lowers the index; prior strength n0=2 and evidence scale s=2 are placeholders)
- **Where:**
  - `packages/pulse_belief/lib/src/pessimistic.dart:40`: `band = z*sqrt(p(1-p)/(nEff+1))`
  - `packages/pulse_belief/lib/src/fusion.dart:79-110`: `nEff` is an unsigned sum of weights
- **What:** One report raises `n_eff` by about 1 and moves `p̄` by `logit(α)`. For α below about 0.63 (z = 1.28) or 0.645 (z = 2), the band shrinks more than the mean rises, so `p̃` falls.
  - Crowd α = 0.6, and crowd reports are 82% of the corpus.
  - At p0 = 0.05, z = 1.28: 0.329 with no reports → 0.309 with one → 0.333 with two → 0.380 with three.
  - An ageing report lowers `p̃` at every z.
- **Why it matters:** The headline design claim ("caution grows as evidence thins") is false on real evidence paths. Pedestrian and emergency users get *less* protection after the first crowd report.
- **Fix:**
  - Replace the Wald band with a Beta posterior upper quantile. Model each edge as Beta(a0 + Σ w·α-weighted positives, b0 + Σ w·negatives), with the prior's mean = p0 and a stated prior strength.
  - Add a property test: a positive report never lowers the index, and an ageing report moves the index monotonically toward the prior's quantile.
- **Review IDs:** D1-F10, D4-F1.

### F-02 · Evidence is attached to one direction of two-way streets · FIXED (2026-10-02, harness `load_corpus_both_directions`, on-device `EdgeSnapper.edgesNear`)
- **Where:**
  - `scripts/t31_build_replay_corpus.py` (`snap_to_nearest_edge`, about line 395) snaps each observation to one directed edge.
  - `scripts/t3_2_replay_engine.py:124-137` groups observations strictly by `edge_id`.
  - `packages/pulse_router/lib/src/query_orchestrator.dart` looks up observations by `edge_id`.
- **What:** 5,177 of the 5,775 observed edges have a reverse twin, and only 2 of those twins carry the evidence.
- **Why it matters:**
  - A flooded two-way street is penalised in one direction only. That is a live bug.
  - It contradicts Eq. (1), whose kernel would weight the twin identically.
  - Every exposure figure undercounts.
- **Fix:**
  - Assign each observation to every edge within the kernel radius, both directions at minimum, with the kernel weight.
  - Rebuild the corpus into a **new** dated folder.
  - Re-run Study 1, Study 2 and the re-analysis.
- **Review IDs:** D4-F3.

### F-03 · Nothing credits the crowd-fusion layer · OPEN (evaluation finding; CONFIRMED on the fixed router, ADR-017: with official reports held out, prior + crowd routes cross more official-report edges than prior-only routes, +0.081 [0.039, 0.126] per route at λ=5)
- **Evidence** (see CLAUDE.md §5):
  - Against hard blocking, the soft penalty's gain is −0.28 on prior-only edges and +0.04 (worse) on observed edges.
  - Against held-out official reports, prior-only routing is as good as prior + crowd, or better.
  - Crowd evidence worsens the Brier score relative to the prior alone (0.0478 vs 0.0361 at age 0).
- **Implication:** Any claim that crowd reports help is unsupported on current data. To test the layer properly, use time-stamped, independent passability labels.
- **Review IDs:** D3-F2, F1, F12, F14.

### F-04 · Tier 0 template produces false statements · FIXED (2026-10-02, `pulse_explain/lib/src/template_renderer.dart`, ADR-016)
- **Where:** `packages/pulse_explain/lib/src/template_renderer.dart`
  - `:146` — `"It avoids $noun reported on ${edge.streetName}"` is emitted when the chosen route still crosses part of that corridor.
  - `:120` — the "N minutes slower/faster" delta compares penalised cost with plain travel time.
  - `:143` — `"moments ago"` is printed for prior-only edges that have no report.
- **Fix:**
  - Compute "avoids" from route membership.
  - Compare free-flow with free-flow.
  - Print "no recent report" when there is no observation.
- **Review IDs:** D2-F1 (items 1–3), D2-F14.

### F-05 · The verifier accepts false and unsafe sentences · PARTLY FIXED (2026-10-02, `verifier.dart`; false accepts 71.8% to 0% on the 236-case authored set, which is not independent of the fixes; an independent paraphrase set is still needed)
- **Where:** `packages/pulse_explain/lib/src/verifier.dart`
  - rule 3, comparatives: about lines 394–426;
  - rule 6, safety denylist: about lines 543–556;
  - numeral grounding: rules 1–2.
- **What it passes:**
  - a reversed comparison ("Route A is faster" when it is slower);
  - "the bridge is dry now, go ahead on Route B" for a bridge the router had removed;
  - numbers that match *some* record value but describe the wrong subject.
- **Fix:**
  - Bind each numeral to its subject and unit.
  - Check comparative direction against the record.
  - Make "passable" an entity-level check: no affirmative passability for any edge that is removed or penalised.
  - Build an adversarial test set covering paraphrases, negation and Tamil script.
  - Measure false-accept and false-reject rates.
- **Review IDs:** D2-F4, D2-F13.

### F-06 · "Runs on the phone" is not implemented · PARTLY FIXED (2026-10-02; map pack, any-OD routing and a report that changes routes exist and run in a web build; nothing has run on a phone)
- **Where:** `app/lib/src/routing/route_service.dart`, `app/lib/src/data/demo_route_fixture.dart`
- **What is missing:**
  - The app has never run on a physical device.
  - The prior (`chennai_prior_ell0.json`, 152 MB) is not on the device.
  - There is no code that snaps a new report to an edge, and no report screen.
  - The app runs one fixed origin–destination pair (T. Nagar → Velachery).
  - The Tier 1 and Tier 2 rewriters have never executed.
- **Fix:**
  - Compact the prior: a binary per-edge table, or store only the 14,534 hazard edges.
  - Add origin/destination selection and a report flow.
  - Run on a Rs 10–15k Android phone and record latency and memory.
- **Review IDs:** D2-F12, D2-F3.

---

## Significant

### F-07 · A Tier 0 failure crashes the explanation path · FIXED (2026-10-02, `renderTemplateSafe`)
- **Where:** `template_renderer.dart:73-80` throws `StateError` when its own text fails `verify()`. The caller does not catch it.
- **Effect:**
  - No route is shown.
  - The error banner prints the unverified text.
- **Fix:**
  - Catch the error and show the route with a minimal fixed sentence.
  - Log the failure.
  - Never display the failing text.
- **Review ID:** D2-F2.

### F-08 · Data-gap flags are inverted · FIXED (2026-10-02, data gap = hazard-map edge on the route with no recent report, ADR-016)
- **What:**
  - Low-prior edges are flagged as data gaps.
  - High-prior edges with no observations are not flagged.
- **Fix:** A data gap means "high prior or on-route, and no recent observation". Implement it that way and add a test.
- **Review IDs:** D2-F7, D2-F19.

### F-09 · The static prior is used as P(flooded now) · FIXED (2026-10-02, event state dry/watch/active in `RoutingEngine`; an app banner shows it; the emergency class on dry days follows the same gate)
- **Where:** `query_orchestrator.dart:120-134` applies ℓ0 to every hazard-config edge at every query.
- **Effect:** On a dry day the emergency class still pays about 2 × τ0 on 8,759 edges.
- **Fix:**
  - Gate the prior on an event state, such as an IMD alert, rainfall above a threshold, or a manual switch.
  - Alternatively, redefine the prior explicitly as "probability given an active event".
- **Review ID:** D4-F10.

### F-10 · Sync skips late-uploaded offline reports; HLC is decorative · PARTLY FIXED (2026-10-02/03: server stamps `received_at` and pages on it; `router_api`, `SyncClient.pullReceivedSince` and the app's `ObservationPuller` use it, with tests; the PostGIS SQL is untested (no database here); HLC is still not used for ordering)
- **Where:** `app/lib/src/sync/sync_client.dart:141-153`. `pullSince` filters on `observed_at >= since`, and HLC stamps sit in `raw['_hlc']` without being used for ordering.
- **Effect:** A report made offline at 09:00 and uploaded at 11:00 is never pulled by a client that has already synced past 09:00.
- **Fix:**
  - Page by a server-assigned monotonically increasing sequence number, or by server receive time.
  - Keep the HLC for causal ordering, or drop the claim.
- **Review ID:** D2-F15.

### F-11 · The router does not use ALT · WORDING FIXED (2026-10-02: `pulse_router.dart`, `docs/ARCHITECTURE.md`, ADR-012 item 7; ALT is still not wired in; the README, the paper and `01_code/citypulse-IDP/CLAUDE.md` still need a sweep, PLAN M1.10)
- **Where:**
  - `query_orchestrator.dart:155-168` calls plain `bidirectionalDijkstra` twice (hazard cost and free-flow).
  - `alt_landmarks.dart` is referenced only from tests.
  - `docs/DECISIONS.md` (around line 424) blames CLI time on "ALT landmark rebuild".
- **Fix:** Either wire ALT into `planRoute`, keeping the cost ≥ τ0 invariant, or remove ALT from the README, the architecture docs, ADR-012 and the paper.
- **Review IDs:** D2-F11, D4-F2.

### F-12 · n_eff and the band have further defects · FIXED (2026-10-02, with F-01)
- **What:**
  - `n_eff` ignores reliability.
  - Conflicting positive and negative reports both raise `n_eff`, so conflict reads as certainty.
  - The Wald band collapses near p = 0.
  - At z = 2, p̃ = 1 on all 8,759 prior-only edges (saturation).
  - About 97% of edges carry no hazard entry at all.
- **Review IDs:** D1-F11, D1-F14, D4-F5.

### F-13 · The depth rule is inert and coarse · OPEN
- **What:**
  - No corpus record has depth, so δ = 1 and the chance constraint never fires.
  - When it does fire, it can still leave a commuter routed through reported deep water on a low-prior edge.
  - One car-derived curve and one h_max serve every class.
  - The pedestrian h_max (150 mm) is a placeholder with no source.
- **Fix:**
  - Make a reported depth above h_max remove the edge regardless of p̃.
  - Source per-class thresholds.
- **Review IDs:** D4-F7, D4-F9.

### F-14 · The Study 2 design inflates and confounds results · OPEN
- **What:**
  - 5,000 report-free easy negatives were not disclosed.
  - Discrimination comes from GCC coverage: inside coverage, AUROC is about 0.46 for both prior and C3.
  - Edge length alone scores AUROC 0.651.
  - The label is co-location of official and crowd points on the same directed edge; 899 of 1,017 official edges never enter the pool.
  - The Beta baseline has no base rate, so it predicts ≥ 0.5 on every reported edge.
  - Simulated ages cannot test decay.
- **Fix:**
  - Split the pools.
  - Control for coverage and length.
  - Give the Beta baseline a prior.
  - Report the Brier skill score.
  - Use real timestamps.
- **Review IDs:** D3-F13 to F18, F20, F22.

### F-15 · Decay constants are placeholders · OPEN
- **What:** The `T_c` values in `config/hazard_classes.yaml` are guesses marked PLACEHOLDER. With a single-timestamp corpus they cannot be fitted or compared.
- **Fix:** Fit them on time-stamped data (2023 Michaung posts, field logs, closure posts).

### F-16 · The Groq API is called directly from the client · FIXED (2026-10-03: `router_api` `POST /rewrite` holds the key and a fixed prompt, rate-limited and size-capped, 6 tests with a mocked upstream; `CloudRewriter` posts only the facts to it and cannot carry a key. Never run against live Groq (no key). The rewriters are still not wired into the explanation card)
- **Where:** `app/lib/src/explain/cloud_rewriter.dart`
- **Effect:** Any key placed in the client ships inside the APK.
- **Fix:** Proxy the call through the server, with rate limiting.

### F-17 · The prior is uncalibrated and terrain-free · OPEN
- **What:**
  - Category probabilities 0.02–0.45 are planning defaults.
  - There is no DEM or HAND layer.
  - Prior-only edges dominate routing behaviour (see F-03).
- **Fix:** Calibrate against the 123-location historical flood set (Natarajan 2021) or field labels, and add HAND where available.

### F-18 · Documentation overclaims · OPEN
- **Where:**
  - `README.md` (badges, "verified rationale", "entirely on-device", "ALT")
  - `01_code/citypulse-IDP/CLAUDE.md` §1 and §6 (the "ALT admissibility … not in the literature" claim is wrong: Delling and Wagner 2007)
  - `docs/PROJECT_BRIEF.md`
  - `08_archive_v1/*`
- **Fix:** Use the wording table in the top-level `CLAUDE.md` §6.

---

## Minor

### F-19 · Makefile drift · FIXED (2026-10-02, Makefile rewritten with targets that exist)
- **What:** `study1_replay.py`, `study3_faithfulness.py` and the `bin/` output path do not exist.
- **Fix:** Use the commands in `CLAUDE.md` §4.2 and update the Makefile.

### F-20 · Each CLI call reloads the graph (about 3 s) · FIXED (2026-10-02, `route-batch` CLI mode; Study 1 now runs 1000 pairs per configuration in one process each)
- **Effect:** It limits studies to about 100 OD pairs.
- **Fix:** Add a batch or server mode to `bin/pulse_router.dart`.

### F-21 · `data/MANIFEST.md` is empty · FIXED (2026-10-02, `data/MANIFEST.md`; several licence cells are `[UNVERIFIED]`)
- **What:** It lists "(none yet)" although data files are in use.
- **Fix:** Add the source, licence (ODbL for OSM-derived data, OpenCity terms for GCC layers), snapshot date and attribution for every file.

### F-22 · The Kotlin prototype is not evidence · WON'T FIX (archive only)
- **Where:** `01_code/citypulse-ai-kotlin-prototype/`
- **What:**
  - a 27-node hand-made graph;
  - a confidence badge hard-coded at 94% online / 88% offline;
  - δ = 1 + 3.2·p̃^1.5, wrongly attributed to Pregnolato;
  - a "Tier-1 SLM" that is a second template;
  - a numeral check using `abs()`, so sign errors pass.
- **Use:** UI and pitch reference only.

### F-23 · Remaining minor findings · OPEN
- There are 25 further minor review findings (wording, units, figure labels, plan risk rows).
- See `04_critique_and_review/deep_review/adjudication.md`, "Minor".

### F-24 · Every travel mode used car speeds and car roads · FIXED (2026-10-03, ADR-019)
- **What:** `pedestrian`, `emergency` and `commuter` differed only in the hazard-caution numbers `z` and `λ`. On the same Chennai trip all three returned the same route and the same 14.9 minutes for 10.6 km, so a walker was shown a car time.
- **Fix:** movement profiles (`travel_profiles` in `config/hazard_classes.yaml`): per-mode speeds by road class, roads closed to the mode, one-way handling; a bicycle mode was added. Each mode searches its own graph.
- **Caveat:** every profile number is a placeholder assumption, not a measurement.

### F-25 · Walking and cycling routes can only use roads that cars can use · OPEN
- **What:** the map pack contains only OpenStreetMap's drivable road classes (motorway down to residential). Footways, paths, pedestrian streets, steps, cycle tracks and shortcuts through parks are not in it, so a walking or cycling route follows roads, and may be longer or less pleasant than a real one. Wrong-way walking on one-way streets is modelled; crossings and pavements are not.
- **Fix:** fetch those classes too (a pack format change: new highway codes and a bigger pack), then add profile speeds for them.

### F-26 · Map pack format v1 cannot hold a whole state's streets · OPEN
- **What:** the street-name index in `meta.bin` is 16 bits, so a pack can have at most 65,535 distinct names. `scripts/region_pack.py` refuses to write more. Tamil Nadu main roads have 8,438 names; adding tertiary and smaller roads statewide would exceed the limit.
- **Fix:** pack format v2 with a 32-bit index, then detailed regional packs (ADR-020).

### F-27 · Regions outside Chennai have no flood data, and only main roads · OPEN (by design, ADR-020)
- **What:** the Tamil Nadu pack routes by road speed alone (flat prior). The app says so (no flood banner, no hazard badge). Routes can start or end kilometres from a mapped road.

### F-28 · The merged India flood data is district- and region-level, non-commercial, and linked for Tamil Nadu only · OPEN (by design, ADR-023)
- **What:** no free national source gives street-level passability. IFI has no coordinates; DFO polygons are hand-drawn and miss Chennai for the 2015 event; licences are non-commercial.
- **Fix:** time-stamped passability from GCC, GCTP or IIT Madras (the 15 October gate), and district boundaries for the other states.
