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
| Router service (`services/router_api`) | Works locally | 3 | 23 tests, including the Groq proxy and a second-city check; `/route`, `/risk`, `/places`, event state | Never deployed |
| Travel modes (car, bicycle, on foot, emergency) | Works; placeholder speeds | 3 | ADR-019; own graph, speeds, closed roads and route per mode; footpaths and cycle tracks not in the pack | F-25 |
| Tamil Nadu main-road region (server and web) | Works on a laptop; routing only | 3 | ADR-020; 257,249 edges / 9.0 MB, 25,144 searchable places, 693 km route in about 0.3 s; flat prior, no flood data; never run on a phone | F-26, F-27 |
| One app for Chennai and Tamil Nadu | Works in the web build; advice and flood layer inside Chennai only | 3 | ADR-022; routes with both ends in Chennai use the Chennai pack, all others the main-road pack with no advice; 7 API tests; never run on a phone | F-27 |
| Merged India flood events | Built; research-only licences; not used by the router | 3 | ADR-023; 7,172 events, district and region level, Tamil Nadu linked; no street-level data | F-28 |
| Nationwide district flood-event model | Trained; **no added value over two simple rules** (pre-registered rule) | 2 | ADR-025; 592 districts, 29 states, 77% of events; test AP 0.090 vs baselines 0.097 and 0.066 | F-29 |
| Terrain and past-flood susceptibility model | Nationwide terrain model beats the best single feature on 91 India flood maps (held-out regions); Chennai-local and routing tests not met; nothing in the app | 2 | ADR-026; AUC 0.930 vs 0.866 nationwide; no prior reduces route exposure to the 2015 flood | F-30 |
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

**Android app (5 October 2026).** A GitHub workflow built a 60.9 MB release APK; the team installed it on one Android phone and reports that it behaves exactly like the web app. No timing, memory, battery or airplane-mode result is recorded, so the readiness levels above do not change (the offline claim in particular is still untested). The next step is the measurement table in `01_code/citypulse-IDP/docs/MOBILE_TESTING.md`.
