# Implementation Plan

Task-by-task, with the reasoning behind the sequencing. An agent should be able to pick any
task, read only what it names, and produce something mergeable.

**Read first:** `CLAUDE.md`, `docs/DECISIONS.md`, `docs/CONTRACTS.md`, and
**`docs/CHENNAI_PROTOTYPE_SPEC.md`** — the spec scopes v0 to a bounded Chennai watchlist
(ADR-009) and overrides anything below that assumes city-wide sensing. In particular, T3.1's
corpus is now a curated watchlist with per-point event history, sourced by T-W1 (build and
validate the watchlist, Phase 1 below), gated on the T0.5 feasibility spike in week 1
(added 2026-09-12 review — T-W1 previously had no task card of its own).

## Why this order

Three principles drive the sequencing, and they override any instinct to build the app first:

1. **Test the assumptions that can kill the project before building on them.** Three
   assumptions are currently unvalidated — that a quantized model is usable on a cheap phone,
   that the Chennai graph routes fast enough, and that ethics approval arrives in time. Each
   costs a day to test now and costs the project in week 5.
2. **The evaluation harness is infrastructure, not a final step.** Studies 1 and 2 run in
   week 3 on deliberately incomplete data. Ugly early numbers tell you what the harness is
   missing while there is still time.
3. **Build the trace before the things that consume it.** Four components depend on
   `DecisionTrace`. Changing it later means changing all four plus any results already computed.

The client comes late on purpose. It is the least uncertain part and the most visible — which
makes it the easiest thing to hide behind instead of doing the research.

---

## Phase 0 — De-risking spikes (week 1, all parallel)

Each spike is a throwaway script and a written number. **The output is a decision, not code.**

### T0.1 — SLM on cheap hardware
- **Goal:** know whether on-device generation is usable on a ₹10–15k Android.
- **Do:** minimal Flutter app, `flutter_gemma`, Gemma 3 270M INT4-QAT. Generate 50
  explanations from canned traces.
- **Measure:** TTFT, decode tok/s, peak RSS, battery delta per 25 generations, temperature
  over a 10-minute sustained run, and behaviour when the app is backgrounded.
- **Acceptance:** a table in `data/results/<date>-t01-slm/`, naming the exact device and SoC.
- **Decision it forces:** if TTFT > ~3 s, the SLM cannot sit in the interactive path. That
  does not kill the project — it moves the SLM to a post-hoc "explain in detail" action and
  makes Tier 0 the sole interactive path. Write the outcome into `DECISIONS.md` either way.
- **Trap:** do not benchmark on a flagship. It invalidates the core claim and the team will be
  tempted, because flagships are what they own.

### T0.2 — Graph build and query time
- **Do:** Geofabrik Southern-Zone extract pinned by date → filter drivable ways → CSR
  adjacency → bidirectional Dijkstra over 1 000 random OD pairs.
- **Measure:** node/edge counts, on-disk size, p50/p95/p99 query latency.
- **Acceptance:** `data/results/<date>-t02-graph/` with the numbers and the pinned extract date.
- **Decision it forces:** if p95 > ~150 ms, add ALT landmarks immediately (T2.3); if it is
  10–40 ms as expected, ALT is an optimisation and a paper result, not a necessity.

### T0.3 — Ethics application submitted
- Draft the Study 5 protocol against `docs/EVALUATION.md` §Study 5 and submit to the IEC.
- **Acceptance:** submission acknowledgement filed in `docs/ethics/`.

### T0.4 — Accounts and data claimed
- Free-tier accounts per `docs/APIS_AND_COSTS.md`. Tier 2 data applications filed the same
  week (IMD, SACHET, IIT-M dataset) since they have lead time and a low success rate.
- **Acceptance:** `docs/data-access-log.md` listing each request, date, and status.

### T0.5 — Watchlist feasibility spike (added 2026-09-12, review pass)
- **Goal:** know whether ≥100 watchlist points can actually be sourced, cross-checked and
  edge-resolved from open data — before committing week 2 to it. This is ADR-009's own
  "Reconsider if" clause, tested now instead of discovered in week 2.
- **Do:** pull the OpenCity/GCC flood-hazard-zone and 2015-inundation KML (`research/raw/C`
  C12/C13 — confirmed downloadable, public domain), extract 20–30 candidate points, and
  separately try reaching `cmwssb.tn.gov.in/lake-level` from a normal Indian residential or
  mobile connection (it has failed from two different research/review environments so far —
  find out if that's geo-blocking or bad luck). Cross-check 3–5 of the candidate points against
  the real Michaung (4 Dec 2023) press reporting gathered in `research/SYNTHESIS.md` §9's
  addendum (Pallikaranai's 200 ft radial road / Narayanapuram Lake; the
  Mudichur–Varadharajapuram–Perungalathur corridor).
- **Measure:** how many candidate points survive cross-checking against two independent
  sources; whether the CMWSSB page is reachable at all from inside India.
- **Acceptance:** `data/results/<date>-t05-watchlist/` with a point count and a go/no-go.
- **Decision it forces:** if the extrapolated full-build count is well short of 100, that is
  the same finding as ADR-009's reconsideration clause — surface it in week 1, not week 2,
  while there's still time to rescope to a research contribution rather than a product claim.
  If CMWSSB is unreachable from India too, treat "30-line scraper" as dead and remove the
  reservoir-escalation demo beat rather than build toward it.
- **Trap:** do not substitute the press-sourced Michaung list (SYNTHESIS.md §9 addendum) for
  the actual GCC/OpenCity primary source — it's a prioritisation aid, not the watchlist itself.

---

## Phase 1 — Belief and the watchlist (week 2, first half)

### T-W1 — Build and validate the watchlist (task card added 2026-09-12, review pass)
- **Owner:** the data-wrangler role; this is a full-time week-2 workstream for at least one
  person, run in parallel with T1.x/T2.x, not squeezed into spare time around them.
- **Precondition:** T0.5's go/no-go was "go."
- **Goal:** ≥100 (target 150–200) watchlist points, each resolved to a specific OSM edge, with
  a validated basin label and a resident sign-off — the thing ADR-009 and
  `docs/CHENNAI_PROTOTYPE_SPEC.md` §4 already call the foundational week-2 deliverable, now
  actually scoped as a task.
- **Do, in order (per spec §4):**
  1. Load the OpenCity/GCC hazard-zone + 2015 inundation-depth KML (`research/raw/C` C12/C13)
     into PostGIS.
  2. Cross-check candidates against the 2015 stagnation corpus and the Michaung press-sourced
     leads (`research/SYNTHESIS.md` §9 addendum) — a point appearing in both years is
     high-confidence.
  3. Snap each surviving point to the nearest OSM edge(s) from the T0.2 graph build.
  4. Assign each point a basin label using the four-basin definitions now in
     `docs/CHENNAI_PROTOTYPE_SPEC.md` (Kosasthalaiyar / Adyar / Cooum / Kovalam) — this is a
     manual/GIS join, not yet automatable, since no basin-boundary shapefile was found.
  5. Name each point as a resident would say it (not a GCC zone code).
- **Measure:** final point count; how many survive the two-year cross-check; how many resolve
  cleanly to a single OSM edge vs. requiring manual disambiguation.
- **Acceptance:** the resident-review test already named in the spec — **book this now, with
  a named person and a date, not as an open aside.** A map a Chennai resident looks at and
  confirms.
- **Decision it forces:** if the point count lands well under 100 even after T0.5 said "go,"
  that's a second, harder confirmation of ADR-009's reconsideration clause — write it into
  `docs/DECISIONS.md` immediately, don't quietly patch around it.
- **Trap:** do not let this slip past week 2 — T3.1 (the replay corpus) and the entire Study
  1/2 chain in week 3 are gated on it.

## Phase 1b — Belief (week 2, first half, parallel with T-W1)

### T1.1 — `config/hazard_classes.yaml`
Per class: `T_c`, severity `s`, `α_c` per source class, `h_max`, display noun. Every study
varies these. **Write this before any belief code.**

### T1.2 — `packages/pulse_belief`
Pure functions, no I/O, fully unit-testable. Test-first.
- `fuse(observations, edge, t) -> EdgeBelief` — log-odds accumulation with spatial kernel `κ`
  and per-class exponential decay, over `prior_logodds`.
- `pessimistic(p_mean, n_eff, z) -> p̃`.
- **Tests that must exist:** decay monotonicity; opposing observations cancel correctly;
  `n_eff → 0` widens the band; `z = 0` reduces `p̃` to `p̄`; a single stale crowd report yields
  `p̃` *above* `p̄` (this is the property the whole ADR-002 argument rests on — if it fails, the
  design is wrong); **`p̃ ≤ 1` always, including `emergency` class (`z = 2.0`) with a single
  fresh report at `p̄ ≈ 0.5` — this must exercise the `min{1, …}` clamp, not just assert it
  exists (added 2026-09-12 review; see ADR-002).**
- **Acceptance:** 100% branch coverage on the fusion path. This is cheap here and impossible later.

### T1.3 — Static prior `ℓ₀(e)`
Build per-edge prior log-odds from OpenCity GCC flood hazard zones + inundation depth points +
elevation/HAND. Ship as a packed array aligned to the CSR edge index.
- **Acceptance:** a choropleth of `σ(ℓ₀)` over Chennai that a local human recognises as
  plausible. Show it to someone who knows the city — this catches coordinate-system errors
  that no unit test will.

---

## Phase 2 — Router (week 2, second half)

### T2.1 — `packages/pulse_router` core
CSR graph loader, bidirectional Dijkstra, the ADR-003 cost function, chance-constraint edge
removal. Test-first against hand-built toy graphs with known answers.
- **Required test (added 2026-09-12 review; see ADR-003's invariant):** `w_λ(e,t) ≥ τ₀(e,t)`
  on an edge with `v_free(e) ≈ 30 km/h` (an ordinary Chennai arterial, not a highway) and
  `p̃ > 0`. This is the case that breaks without the `δ = max(1, v_free(e)/v_safe(h))` clamp —
  it must be in the suite before T2.3's admissibility check is trusted, since the admissibility
  proof assumes this invariant holds.

### T2.2 — `DecisionTrace` emission
Implement `docs/CONTRACTS.md` §3 exactly, including `data_gaps` and `rejected_because`.
- **Acceptance:** a golden-file test — fixed graph + fixed observations + fixed clock ⇒
  byte-identical trace. This golden file is what protects every downstream component.

### T2.3 — ALT landmarks + the admissibility check
Landmark selection on the free-flow metric, potentials precomputed once.
- **Acceptance:** over ≥10 000 randomised hazard configurations, no ALT-guided query returns a
  path costlier than plain Dijkstra. **This is the empirical half of the paper's §5 claim** —
  treat a single counterexample as a finding, not a bug to paper over.

### T2.4 — Dart AOT CLI
`pulse_router route --graph … --observations … --at … --z … --lambda …` emitting a trace as
JSON on stdout. This is how Python calls the *same* code the app runs. Never fork the
algorithm into a second language.

---

## Phase 3 — Replay harness and the first two studies (week 3)

### T3.1 — Replay corpus
Normalise OpenCity 2015 stagnation records, GCC inundation points and crowd-sourced flooding
into `HazardObservation` (`docs/CONTRACTS.md` §1). Target ≥200 geolocated events.
- **Acceptance:** `data/corpus/<date>/` + a manifest with counts by class and a time histogram.

### T3.2 — Deterministic replay engine
Feeds observations at their real timestamps into the belief state, samples OD pairs with a
fixed seed, invokes the router CLI, collects traces.
- **Acceptance:** two runs with the same seed produce identical output. Non-determinism here
  silently destroys every comparison.

### T3.3 — Study 1 (route quality) and T3.4 — Study 2 (calibration)
Configurations C0–C4 plus the oracle; metrics and stratified reliability diagrams per
`docs/EVALUATION.md`. **Split by event and monsoon episode, never randomly.**
- **Acceptance:** figures 3 and 4 emitted by script into `data/results/`.

---

## Phase 4 — Explanation (week 4)

### T4.1 — Tier 0 template renderer
Pure function `DecisionTrace -> Explanation`. Covers: chosen-vs-best-alternative delta,
the top blocking edge, confidence band, and a data-gap sentence when `data_gaps` is non-empty.
- **Acceptance:** every trace in the golden set renders without a missing-field crash, and
  every rendered string passes the verifier by construction.

### T4.2 — Verifier
`docs/CONTRACTS.md` §4 rules 1–5, as a standalone pure function. Test-first with deliberately
hallucinated inputs: invented street names, wrong numbers, an unhedged claim on stale data,
and a contrastive claim about a route with no blocking edges.
- **Acceptance:** 100% detection on a hand-written adversarial suite of ≥30 cases.
- **Build this before T4.3.** The verifier is the contribution; the SLM is the thing being
  measured by it.

### T4.3 — Tier 1 SLM rewriter
Prompt = the fact set only. Constrained decoding where the runtime supports it. Output goes
through the verifier; on failure, silently emit Tier 0.

### T4.4 — Cloud path
Same fact set, no raw coordinates, no user id (ADR-007). Deadline-bounded; on timeout the
local tier already has an answer.

### T4.5 — Study 3
300 traces × {cloud, on-device, template}. Report the verification pass rate. Human agreement
(κ) on a 50-item subsample to validate the automatic checker — an unvalidated checker is not
evidence.

---

## Phase 5 — Client and live ingest (week 5)

### T5.1 — Flutter shell
MapLibre + PMTiles from local storage; route display; **confidence badge and the data-gap
state as first-class UI**, not a tooltip.
- **Required, added 2026-09-12 (ADR-011; gap caught by skeptic review — this ADR previously
  wasn't wired into the one task that ships UI):** the unavoidable first-use disclaimer
  ("CityPulse is a research prototype... it does not guarantee any road is safe"), shown again
  on app-version change; no single-color "all clear" badge — only the four confidence bands
  with their hedge text; a shorter disclaimer repeats on any card whose `confidence_band` is
  `low` or `stale`. **Acceptance:** a UI review against ADR-011 before this task is called
  done, not just a functional pass.

### T5.2 — Local hazard cache
SQLite via Drift with the built-in R*Tree. Observations append-only; outbox table for pending
reports.

### T5.3 — Server ingest
FastAPI async workers: Open-Meteo, GDACS, TomTom incidents, OpenAQ, CMWSSB reservoir scraper.
Normalise to `HazardObservation`. PostGIS + GiST; Redis `GEOSEARCH` with the parallel ZSET
decay sweeper (ADR-005). SSE push.

### T5.4 — Sync
Outbox replay with `ON CONFLICT DO NOTHING`, HLC stamps (ADR-008).
- **Acceptance:** an integration test that kills connectivity mid-report, restores it, and
  asserts exactly-once arrival and unchanged local state.

---

## Phase 6 — Studies 4 and 5, hardening (week 6)

### T6.1 — Connectivity ladder (Study 4)
`netem`-shaped rungs: full → high latency → lossy → captive portal → offline. Record route
delta, tier reached, end-to-end latency at each.
- **The captive-portal rung is the important one** — it is the case that breaks naive
  connectivity detection and the reason ADR-005 exists.

### T6.2 — Human study (Study 5)
n ≈ 40 within-subjects, with **manipulated ground truth** so appropriate reliance is
measurable. Approval from T0.3 must have landed.

### T6.3 — Demo insurance
Cloudflare Tunnel fallback; a cached scenario that runs with the network physically off.
Rehearse in aeroplane mode.

---

## Phase 7 — Write-up (week 7)

Paper per `paper/OUTLINE.md`. Every figure regenerated from `data/results/` by script. Final
pass against the rules in `CLAUDE.md` §3: no live-flood-depth claim, no LLM-generates-geometry
claim, no inflated novelty.

---

## Definition of done, for any task

1. Tests written before implementation, and they failed first.
2. `dart format` / `ruff` + `black` clean.
3. If it changes belief or cost behaviour: Studies 1–3 re-run, commit tagged `exp:`.
4. If it contradicts an ADR: a new ADR, not a silent deviation.
5. If it disproved an assumption: written into `DECISIONS.md` **before** moving on.
