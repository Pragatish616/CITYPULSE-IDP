# Project status (as of 2 October 2026, updated after the build session)

A build session on 2 October 2026 closed F-01, F-02, F-04, F-07, F-08, F-09, F-12, F-19, F-20 and F-21, and partly closed F-05, F-06 and F-11. It also added a working web app, a router service and a rewritten Flutter app. Rows below reflect that. Nothing had run on a phone then; see the 5 October paragraph at the end.

Status words used below:
- **Works:** tested and reproducible.
- **Partial:** exists but is incomplete, or has a confirmed flaw.
- **Missing:** not built.
- **Untested:** written but never executed.

## Components

| Component | Status | TRL | Evidence | Open flaws |
|---|---|---|---|---|
| Road graph (193,191 nodes, 471,240 directed edges) | Works | 4 | `data/graph/2026-09-14/chennai_graph_cli.json`; SciPy port reproduces 100/100 paths | — |
| Static prior ℓ0 from 7,453 GCC zones | Partial | 3–4 | `data/graph/2026-09-14/chennai_prior_ell0.json` (152 MB) | F-09, F-17 |
| Belief fusion (`pulse_belief`) | Works | 4 | Beta posterior (ADR-015), 44 tests, SciPy parity vectors; Python replica parity-tested | F-15 (placeholder constants) |
| Pessimistic index | Works (Beta upper quantile) | 4 | Monotone: a positive report never lowers it (property tests). n0 = 2 and s = 2 are placeholders | F-15 |
| Edge cost and depth rule (`pulse_router`) | Partial | 4 | (1 + λs) cap confirmed; depth rule inert; crowd-only depth cannot hard-block | F-13 |
| Search and engine | Works | 4 | Bidirectional Dijkstra; ALT unused (wording corrected); `RoutingEngine`, `MapPack`, `EdgeSnapper`, `PlaceIndex`, event state; 118 router tests | F-11 |
| Decision trace | Works | 4 | Golden-file test | F-04 (semantics) |
| Tier 0 template | Works | 4 | Free-flow deltas, edge-level avoidance wording, safe wrapper; 82 explain tests | — |
| Verifier | Partial | 3–4 | 0 of 209 false accepts and 0 of 27 false rejects on the authored case set (71.8% false accepts before). The set was written by the fixers; an independent paraphrase set is needed | F-05 |
| Tier 1 (`flutter_gemma`, Gemma 270M) | Untested | 2 | Never executed | F-06 |
| Tier 2 (Groq, `llama-3.1-8b-instant`) | Untested | 2 | Never executed; key exposure | F-06, F-16 |
| Flutter client (Android and web) | Partial | 3 | Any-OD routing in a background isolate, map, report flow, explanation card, licence screens, outbox, puller and city tests, 129 tests; web build run end to end in a browser; Android never built or run | F-06 |
| Local cache (SQLite + R*-tree) and outbox | Works (tests) | 3 | `app/test/storage` | — |
| Sync (HLC, G-Set) | Partial | 3 | Pulls by `observed_at`; the Drift outbox is not wired into the new app | F-10 |
| FastAPI server and ingest adapters | Works (in-memory) | 3 | `server/tests`, 35 tests (CORS opt-in added) | Never deployed |
| Volunteer field log (`/fieldlog`, `scripts/fieldlog_ops.py`) | Built and tested locally; not deployed; no data | 3 | ADR-028, `docs/field/FIELD_PROTOCOL.md`; 51 server tests for it (including one that runs the browser logic tests), 21 browser-logic tests, 14 operator-tool tests; walked through in a real browser at desktop and phone width. Separate from the router and the belief | F-37 |
| Route question answerer (`pulse_explain/lib/src/route_qa.dart`, D0 without a language model) | Built and tested on the laptop in English and Tamil, and in the app as an "Ask about this route" box; **no measured accuracy, Tamil unreviewed, not run on a phone** | 2 | ADR-035; 734 package tests and 197 app tests; version 2 (briefing, two-part questions, follow-ups) and a verified training-data generator (20,046 answers); base model downloaded; **first LoRA adapter trained (run1, 15 Oct, 3.7 h on the laptop GPU): labelling 0.997 on 300 same-bank validation questions, answer writing 88.3% verifier pass against a pre-declared 90% (not met; all failures are unsupported numerals), safety questions all refused; mostly reproduces D0 styles; not adopted, no sealed test, no phone measurement**; 432 situation-by-intent-by-language answers pass the verifier; about 0.37 ms per answer; pre-registered, sealed test set still to be written by the team | F-43 |
| Event miner (`ml/event_miner/`, local `qwen3.5:0.8b`) | Built; **not evaluated**; paste-in only | 2 | ADR-030, `docs/field/EVENT_MINER.md`; 27 tests with a fake model; four made-up development sentences run live. Review queue only; never feeds routes | F-38 | Accident extraction added 11 Oct (ADR-030 addendum 2; 42 tests; unmeasured).
| Subway watchlist (`data/watchlist/2026-10-09`, `scripts/build_subway_list.py`, `scripts/subway_board.py`) | Built; **positions unconfirmed**; no volunteer data | 2 | ADR-031; 31 candidates from GCC's table, 21 with an OSM position and 10 without; 11 data tests and 9 board tests; internal board, check sheet and `docs/field/PILOT_PLAN.md`. Not linked to the router | F-39 |
| Router service (`services/router_api`) | Works locally | 3 | 23 tests, including the Groq proxy and a second-city check; `/route`, `/risk`, `/places`, event state | Never deployed |
| Travel modes (car, bicycle, on foot, emergency) | Works; placeholder speeds | 3 | ADR-019; own graph, speeds, closed roads and route per mode; footpaths and cycle tracks not in the pack | F-25 |
| Accident avoidance and mode limits (`restrictions.dart`, app switch and report) | Built and tested on the laptop; not on a phone or the live site | 3 | ADR-032; 16 router tests on the Chennai pack and small graphs, 1 template test, 1 API test, 4 app tests. Placeholder numbers; no accident history data | F-40 |
| Tamil Nadu main-road region (server and web) | Works on a laptop; routing only | 3 | ADR-020; 257,249 edges / 9.0 MB, 25,144 searchable places, 693 km route in about 0.3 s; flat prior, no flood data; never run on a phone | F-26, F-27 |
| One app for Chennai and Tamil Nadu | Works in the web build; advice and flood layer inside Chennai only | 3 | ADR-022; routes with both ends in Chennai use the Chennai pack, all others the main-road pack with no advice; 7 API tests; never run on a phone | F-27 |
| Merged India flood events | Built; research-only licences; not used by the router | 3 | ADR-023; 7,172 events, district and region level, Tamil Nadu linked; no street-level data | F-28 |
| Nationwide district flood-event model | Trained; **no added value over two simple rules** (pre-registered rule) | 2 | ADR-025; 592 districts, 29 states, 77% of events; test AP 0.090 vs baselines 0.097 and 0.066 | F-29 |
| Terrain and past-flood susceptibility model | Nationwide terrain model beats the best single feature on 91 India flood maps (held-out regions); Chennai-local and routing tests not met; nothing in the app | 2 | ADR-026; AUC 0.930 vs 0.866 nationwide; no prior reduces route exposure to the 2015 flood | F-30 Scored 11 Oct (ADR-033): AP skill 0.15 (modest), holds at 5 and 10 degree blocks and on untouched lock blocks; no advantage below 10 m elevation; probabilities do not transfer to a new region; four times the maps adds 0.012 AP. |
| City pipeline (`config/cities.yaml`, `scripts/city_pipeline.py`) | Works on a synthetic city; no real second city fetched | 3 | ADR-018; routing-only for any city without a verified hazard source | — |
| Map pack (`data/packs/2026-10-02`) | Works | 4 | Prior for all 471,240 edges, 7,808 street names, 15 MB | — |
| Replay corpus (6,132 observations) | Works, weak | — | One timestamp, no depth, positives only | F-02, F-14 |
| Study 1 (route quality) | Re-run on the fixed router; the crowd layer still adds nothing (ADR-017) | — | `data/results/2026-10-02-study1-route-quality/` and `...-study1-rescored/`; the 2026-09-18 folder and `07_reanalysis/` are the earlier record | F-03 |
| Study 2 (calibration) | Re-run, still confounded | — | `data/results/2026-10-02-study2-calibration/`; pools are not yet split or controlled for coverage and edge length | F-14 |
| Studies 3–5 (faithfulness, connectivity, human) | Missing | — | Not run | — |
| Device run on a Rs 10–15k phone | Partly: installed and run on one Android phone (model not recorded), reported to behave like the web app; no measurements, offline untested | — | MOBILE_TESTING.md table is empty | F-06 |
| Live passability data feed | Missing | — | Decides the startup track | — |

**Whole system: TRL 3.** Each critical function has been shown separately. The integrated system has never been demonstrated, even in the lab.

## Research deliverables

| Item | Location | State |
|---|---|---|
| IEEE paper v2 (8 pp, 90 refs) | `02_paper/` | Honest evaluation with negative results. Author placeholders still to fill. |
| Literature review v2 (14 pp, 323 refs) | `03_literature_review/` | All references verified against Crossref, arXiv or a publisher page |
| Critique, deep review, council and plan | `04_critique_and_review/`, `05_council/` | Complete |
| Re-analysis scripts and results | `07_reanalysis/` | Reproducible from `01_code` data |

## Decisions in force

- **Council, 1 October 2026:**
  - *Startup:* FIX FIRST, for the second time. It becomes KILL without a live, timestamped passability feed by 15 October 2026.
  - *Research paper:* BUILD.
- **ADR-035** (13 Oct 2026): route questions answered on the phone, model-free first; small model only if it beats D0 on a sealed test set.
- **ADR-034** (11 Oct 2026): OpenStreetMap street-scale features tested for the Chennai core; no evidence they help; across floods the low core scores chance with every feature set.
- **ADR-033** (11 Oct 2026): scorecard and stress test of the trained flood models; one modest, the rest no evidence; what a better training set would be.
- **ADR-026** (4 Oct 2026): terrain and past floods as training data; results and limits.
- **ADR-024, ADR-025** (4 Oct 2026): what to train on; the nationwide district model and its negative result.
- **ADR-023** (4 Oct 2026): merged India flood event dataset.
- **ADR-021, ADR-022** (3 Oct 2026): offline route advisor; one app for Chennai and Tamil Nadu, advice inside Chennai only.
- **ADR-020** (3 Oct 2026): India in phases, Tamil Nadu main roads first.
- **ADR-001 to ADR-012** in `01_code/citypulse-IDP/docs/DECISIONS.md` remain in force, except where `KNOWN_FLAWS.md` shows a claim is wrong.

## Blocked on people, not code

1. Access to a live data feed (CFM-DSS WFS, GCC ICCC or GCTP).
2. A physical low-cost Android phone for device tests.
3. An ethics (IEC) application before any human study.
4. Free-tier accounts (Supabase, Upstash, Groq, TomTom, OpenAQ). The code runs without them.
5. Author details for the paper: departments, surnames, e-mails.

**Web demo (4 October 2026).** The web app, router API and report server run as one container on a free Render instance at <https://citypulse-idp.onrender.com>. `scripts/smoke_deploy.py` passes 11 read-only checks against it. Reports are in memory and the host sleeps when idle.

**Android app (5 October 2026).** A GitHub workflow built a 60.9 MB release APK; the team installed it on one Android phone and reports that it behaves exactly like the web app. No timing, memory, battery or airplane-mode result is recorded, so the readiness levels above do not change (the offline claim in particular is still untested). The next step is the measurement table in `01_code/citypulse-IDP/docs/ops/MOBILE_TESTING.md`.

**Event state (5 October 2026, ADR-027).** The router now sets the flood-event state from NASA satellite rain by default, and an operator can override it. It reacts about six hours late and uses placeholder thresholds, so it is context for whether the 2015 hazard map is applied, not a flood measure (F-36). Readiness levels do not change.

## 17 to 18 October 2026: research candidates C3, C5 to C8 (local commits, not pushed)

| Item | What exists | Evidence | State |
|---|---|---|---|
| C6 MCP server | `services/router_api/bin/mcp_stdio.dart`, `lib/src/mcp.dart`, `docs/MCP.md`: tools `search_places`, `plan_route`, `ask_about_route`, `flood_event_state`; every returned sentence passed the verifier; safety questions refused | 11 tests on the real pack; manual stdio run | Works; the official MCP Python SDK client passes all six checks against the compiled server (18 Oct, `data/results/2026-10-18-c6-mcp-client/`); not yet tried inside Claude Desktop |
| C7 label grammar | `labelGrammar()` in `pulse_explain`; option in the app labeller | 300 held-out rows: accuracy 0.99 with and without; median 1504 ms with, 692 ms without (`data/results/2026-10-17-c7-grammar/`) | Works; **off by default** (no gain, twice the latency) |
| C8a signals on the route | 485 OpenStreetMap signals snapped (465 nodes); `route_signals` fact; time answer says signal waits are not in the free-flow time; router service and app | Tests; T. Nagar to Velachery passes 9 | Works; a count, not a wait |
| C8b signal-timing learner | `ml/signal_timing/` (cycle, red, delay per time-of-week bin) | Simulated passes only; cycle exact on 4 simulated signals | Field pipeline built 18 Oct (GPX/CSV traces → approaches → learner → stopwatch evaluation with the 15 s kill rule; 20 candidate junctions); untested on real traces |
| C5 conformal flags | `ml/conformal/`, `scripts/c5_conformal_eval.py`, pre-registration committed first | Coverage 0.894 on a spatial split (kill line 0.85), but 54 % of non-report edges flagged; crowd evidence barely beats the prior (`data/results/2026-10-17-c5-conformal/`) | Not killed; low information with today's scores. C5b route certificates (18 Oct): coverage met only by flagging every edge (threshold at the prior floor). Not adopted: ADR-036 |
| C3 microwave-link rain | `ml/cml_rain/` retrieval chain, no invented coefficients | Synthetic links only | Ready for data; no operator data |

## 30 October 2026: prototype evidence dataset and paper v3 (local commits, not pushed)

| Item | State | Evidence |
|---|---|---|
| Chennai Street Flood Evidence (CSFE) v0.2 | Built locally; tables not redistributable (CFM-DSS has no licence); datasheet written | 7,010 observations, 163 negatives, 247 timed to the day or better, 78 hand-extracted news facts over 7 events, a 19-subway status timeline, gauge rain and water levels (`data/csfe/`, `scripts/build_csfe_proto.py`) |
| Benchmark B1 (subway closure from rain) | Pre-registered; first run invalid (rain window); two exploratory runs: no evidence either way | Only 3 events have both labels and gauge rain (`data/results/2026-10-30-csfe-b1*/`) |
| IEEE paper v3 | Source complete; **PDF not built** (no TeX on this laptop); author departments, e-mails and the AI-disclosure wording need the authors | `02_paper/README.md`, `02_paper/REVIEW_2026-10-29.md` |
