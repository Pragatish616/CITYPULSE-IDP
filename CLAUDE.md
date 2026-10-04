# CLAUDE.md — CityPulse AI (final IDP folder)

**Read this whole file before you read, run or change anything here.** It applies to Claude, Codex, Cursor, Gemini or any other coding or research agent. It is the most recent and most accurate description of the project. Where any other file in this folder disagrees with it, this file wins. That includes the older `01_code/citypulse-IDP/CLAUDE.md`, the README badges and the pitch documents.

Last updated: 2 October 2026 (PLAN.md added).

Team: Pragatish N, Ravi, Jyotish (B.Tech, VIT Chennai). This is a credited university project (IDP) with a startup ambition. Budget: Rs 0, free tiers only.

---

## 0. Ten-line summary

1. **What it is.** CityPulse AI is an offline-first navigation prototype for Chennai.
   - It keeps a flood probability for every road segment, fusing GCC flood-hazard zones with age-decayed, source-weighted reports.
   - It routes on a pessimistic version of that probability.
   - It produces a structured decision record, which a template and an optional language model turn into an explanation.
2. **What exists.** The router and belief engine work on the full Chennai graph (193,191 nodes, 471,240 directed edges) in a deterministic replay. Readiness is TRL 4 for those components and TRL 3 for the system as a whole. **The Android app has been installed and run on one phone (5 Oct 2026, reported to behave like the web app); no timings or offline tests are recorded.**
3. **Main result.** On the 2015 flood replay, the crowd reports added **nothing** over the static GCC hazard map. The default commuter setting changed 7 of 100 routes.
4. **The pessimistic index is broken.** It *lowers* caution after one weak crowd report (Section 5.2).
5. **Evidence is one-directional.** Reports are attached to one direction of each two-way street only.
6. **The explanation checker passes unsafe text,** for example "the bridge is dry now, go ahead".
7. **Novelty is narrow.** Every component has prior art. The defensible contribution is a systems-integration and Chennai case study with an honest evaluation.
8. **Council verdict (1 Oct 2026):**
   - *Startup:* FIX FIRST. It becomes KILL if there is no live, timestamped passability feed by **15 Oct 2026**.
   - *Research paper:* BUILD, as an honest evaluation that reports the negative results.
9. **The scarce resource is data, not modelling.** What is missing is independent, time-stamped, street-level passability evidence.
10. **Where to start.** Read `00_START_HERE/` next, then follow the task protocol in Section 9. **To build anything, take tasks from `PLAN.md`** (architecture, tech stack, features, milestones M0–M8).

---

## 1. Folder map

```
final_citypulse_ai_idp/
├── CLAUDE.md                 ← this file (read first)
├── PLAN.md                   ← build plan: architecture, stack, features, tasks M0–M8 (read second)
├── AGENTS.md                 ← pointer for non-Claude agents
├── README.md                 ← short human overview
├── 00_START_HERE/
│   ├── PROJECT_STATUS.md     ← what works, what doesn't, readiness per component
│   ├── KNOWN_FLAWS.md        ← every confirmed flaw: ID, file:line, evidence, fix
│   ├── NEXT_STEPS.md         ← gated plan: this week, 15 Oct gate, research and startup tracks
│   └── KEY_NUMBERS.md        ← every load-bearing number and where it comes from
├── 01_code/
│   ├── citypulse-IDP/        ← THE real codebase (Dart packages, Flutter app, FastAPI server, Python harness, data)
│   └── citypulse-ai-kotlin-prototype/   ← AI-generated Android UI mock-up (TRL 2). Not evidence for anything.
├── 02_paper/                 ← IEEE conference paper v2 (PDF + LaTeX source)
├── 03_literature_review/     ← review v2 (PDF + LaTeX) + 323 verified references (TSV) + verification log
├── 04_critique_and_review/   ← classification, deep review (8 specialists → 5 defences → adjudication), report PDF
├── 05_council/               ← Believer, Skeptic, Investor, Judge + COUNCIL_LOG.md (all verdicts)
├── 06_research_notes/        ← verified literature tables and the market/competitor brief
├── 07_reanalysis/            ← independent re-scoring of Study 1 under a common reference belief
├── 08_archive_v1/            ← superseded v1 paper, review and plan (kept for history; do not cite)
└── 09_skills/                ← writing and review skills used here (human-scope, roast-council)
```

The original folders `Downloads/citypulse-IDP` (an outer, older copy containing a nested, newer `citypulse-IDP/` repo with its git history) and `Downloads/citypulse-ai` remain untouched as archives. `01_code/citypulse-IDP` is a clean copy of the **nested, newer** repo. It leaves out `.git`, `.venv`, `.dart_tool`, `build/`, caches and the 557 MB raw OSM file `data/osm/southern-zone-260911.osm.pbf`. That file is used only by the throwaway T0.2 timing spike; it is still in the original folder.

---

## 2. Safety rules for any agent working here

1. **Never modify the archived originals** (`Downloads/citypulse-IDP`, `Downloads/citypulse-ai`). All work happens inside `final_citypulse_ai_idp/`.
2. **Do not delete files** without the owner's explicit approval. Move them to a `_to_delete/` folder instead.
3. **Do not overwrite pinned data.** Files under `01_code/citypulse-IDP/data/` are dated snapshots. A new build goes in a new dated folder, and `data/MANIFEST.md` is updated.
4. **Never fabricate results, numbers, citations, quotations or sources.** Every number in a paper or document must trace to a script output in `data/results/` or `07_reanalysis/`, or to a verified reference. Mark anything unverified `[UNVERIFIED]`.
5. **Do not overclaim.** Read Section 6 before writing anything public. In particular, never write that the system:
   - runs on the phone;
   - verifies explanations;
   - gets more cautious as evidence thins;
   - is novel for flood-aware routing, report decay or ALT correctness.
6. **Legal and licence constraints** (unchanged from the original brief; they are binding):
   - **No Google Maps Platform data.** Its terms forbid caching and offline use, and mixing it with OSM breaks ODbL.
   - **No bulk use of `tile.openstreetmap.org`.** Use self-hosted PMTiles.
   - **DPDP Act 2023:** no passive location inference. Saved places must be explicit (ADR-006).
   - **Never assert that a road is safe or passable** (ADR-011). Show relative risk and its age.
   - **The LLM never produces route geometry.** Graph search does.
7. **Secrets.** Copy `.env.example` to `.env` and never commit `.env`. Note that `app/lib/src/explain/cloud_rewriter.dart` calls Groq directly from the client: an API key placed there would ship in the APK. Move that call server-side before any real key is used.
8. **Budget is Rs 0.** If a step needs paid infrastructure, stop and ask.
9. **Before changing any of these, ask the owner:** a shared schema (`docs/CONTRACTS.md`), the cost model, the evaluation protocol, or a claim in the paper. For schemas, also write an ADR in `docs/DECISIONS.md`.

---

## 3. Purpose and the problem

Every northeast monsoon (October to December), Chennai floods in roughly the same places: Velachery, Pallikaranai, the railway subways, the Mudichur corridor. In 2015 and in December 2023 (Cyclone Michaung) the floods were severe. Two things go wrong for people on the road:

- **Navigation apps optimise travel time.** They have limited street-level flood information.
- **Connectivity fails during floods.** Cloud-only apps stop working.

Some of this is already covered by others:
- Google Maps India and Mappls accept crowd flood and waterlogging reports.
- TN-ALERT pushes flood alerts for saved places.
- The RiskMap crowd flood map ran in Chennai from 2017 to 2019.

What none of them documents publicly is:
- how much a single report should change a route;
- how fast it should fade;
- what to do when evidence is thin;
- how to explain the choice without inventing facts.

**The original idea** was a router that:
- keeps a per-segment flood belief (prior plus decaying reports);
- grows more cautious when evidence is thin, with caution set by user class (commuter, pedestrian, emergency);
- separates slowdown from harm in the cost;
- explains each route from a structured record, with a symbolic gate on any language-model rewrite;
- does all of this on a phone without network.

**The honest current position** (after the review in October 2026):
- The integration is sound engineering.
- The evaluation shows the crowd-fusion layer adds no measurable value on the only data available.
- The project's value now depends on obtaining **independent, time-stamped passability data**, such as:
  - GCC subway boom-barrier states;
  - flood sensors;
  - official closure posts;
  - probe-vehicle traces;
  - field logs.

---

## 4. The codebase: `01_code/citypulse-IDP`

### 4.1 Layout

| Path | Language | What it is | State |
|---|---|---|---|
| `packages/pulse_router/` | Dart | CSR graph, bidirectional Dijkstra, edge cost, depth–disruption, decision trace, CLI (`bin/pulse_router.dart`); `alt_landmarks.dart` exists but is **not used** by `planRoute` | Works; about 80 tests |
| `packages/pulse_belief/` | Dart | Log-odds fusion (`fusion.dart`), kernel, pessimistic index (`pessimistic.dart`) | Works as coded; **the index has a design flaw** (F-01) |
| `packages/pulse_explain/` | Dart | Tier 0 template (`template_renderer.dart`) and the 6-rule verifier (`verifier.dart`) | Works; **false accepts and false text** (F-04, F-05) |
| `app/` | Flutter (Android) | Offline shell: loads the real graph, runs **one fixed query** (T. Nagar → Velachery) in-process, confidence badge, SQLite + R*-tree cache, outbox, HLC, Tier 1 (`flutter_gemma`) and Tier 2 (Groq) rewriters | Desktop-host tests; built as an APK in CI and run on one phone (unmeasured, offline untested); rewriters never executed |
| `server/` | Python, FastAPI | Observation ingest, SSE events, memory or PostGIS storage, ingest adapters (Open-Meteo, GDACS, TomTom, OpenAQ, CMWSSB) | In-memory tests pass; never deployed; workers unscheduled |
| `scripts/` | Python | Graph and prior build (`t1_3_build_graph_and_prior.py`), corpus build (`t31_build_replay_corpus.py`), replay engine (`t3_2_replay_engine.py`), Study 1 (`study1_route_quality.py`), Study 2 (`study2_calibration.py`), shared helpers (`study_common.py`) | Deterministic; byte-identical reruns |
| `config/hazard_classes.yaml` | YAML | Source reliabilities, user classes (z, λ), per-class T_c, severity, h_max, ε | **T_c values are placeholders**, never fitted |
| `data/` | — | Pinned snapshots: graph and prior (`graph/2026-09-14/`), corpus (`corpus/2026-09-17/`), raw KMLs, watchlist, results, compiled CLI (`bin/pulse_router.exe`) | See `data/results/*/result.json` |
| `docs/` | Markdown | ADR-001…012 (`DECISIONS.md`), `CONTRACTS.md`, `ARCHITECTURE.md`, `EVALUATION.md`, `IMPLEMENTATION_PLAN.md` (historical; replaced by the root `PLAN.md`), `CHENNAI_PROTOTYPE_SPEC.md`, older `COUNCIL_VERDICT.md` | ADR-012 records the weak and negative results honestly |
| `research/` | Markdown | Seven agent-written research reports plus `SYNTHESIS.md` | Unverified citations; use `03_literature_review/` instead |
| `.claude/agents/` | Markdown | Role briefs (implementer, reviewer, experimentalist, paper-writer, data-wrangler, council roles) | Useful; some claims are outdated (see Section 6) |

Test counts: the README says 250+. The review counted about 290 across all packages.

### 4.2 Commands (from `01_code/citypulse-IDP`)

```bash
# Dart packages (Dart 3.x stable)
cd packages/pulse_belief  && dart pub get && dart test && cd ../..
cd packages/pulse_router  && dart pub get && dart test && cd ../..
cd packages/pulse_explain && dart pub get && dart test && cd ../..

# Compile the router CLI that the Python harness calls (harness expects data/bin/pulse_router.exe on Windows)
cd packages/pulse_router && dart compile exe bin/pulse_router.dart -o ../../data/bin/pulse_router.exe && cd ../..

# Python (3.11+), from a fresh venv
python -m venv .venv && .venv/Scripts/activate   # Windows; use .venv/bin/activate elsewhere
pip install -r scripts/requirements.txt -r server/requirements.txt
pytest scripts/tests server

# Experiments (pinned seed 20260918; results go to data/results/<date>-<name>/)
python scripts/t3_2_replay_engine.py
python scripts/study1_route_quality.py
python scripts/study2_calibration.py

# Flutter app (Android; data assets must be synced first)
cd app && bash scripts/sync_data_assets.sh && flutter pub get && flutter test
```

**Makefile drift.** The `Makefile` names `study1_replay.py`, `study3_faithfulness.py` and a `bin/` output path that do not exist. Use the commands above until the Makefile is fixed.

Each CLI call takes about 3 s, almost all of it reloading the 47 MB graph. That is why Study 1 used 100 origin–destination pairs. A long-lived router process or a batch mode would fix this.

### 4.3 The model as implemented

The model is implemented in these files:
- `packages/pulse_belief/lib/src/fusion.dart`
- `packages/pulse_belief/lib/src/pessimistic.dart`
- `packages/pulse_router/lib/src/edge_cost.dart`
- `packages/pulse_router/lib/src/depth_disruption.dart`

```
ℓ(e,t)   = ℓ0(e) + Σi yi · κ(d(e,xi)) · exp(−(t−ti)/Tc) · logit(αi)       (log-odds fusion)
p̄(e,t)   = σ(ℓ(e,t));   n_eff(e,t) = Σi κ(d)·exp(−Δt/Tc)                (unsigned; ignores α)
p̃(e,t)   = min{1, p̄ + z·sqrt(p̄(1−p̄)/(n_eff+1))}                          (pessimistic INDEX, not a bound)
w(e,t)   = τ0·[1 + p̃(δ−1)] + λ·p̃·s·τ0                                    (slowdown + harm)
δ        = max{1, v0/v_safe(h)},  v_safe from Pregnolato et al. 2017:
           v = 0.0009h² − 0.5529h + 86.9448  (h in mm)                      (δ = 1 when depth unknown, i.e. always today)
remove e if reported depth > h_max AND p̃ ≥ ε                               (never fires: corpus has no depth)
```

Parameters (`config/hazard_classes.yaml`):

| Group | Values |
|---|---|
| Reliability α | sensor 0.97, official 0.92, responder 0.90, app_traversal 0.70, **crowd 0.60** |
| User classes | commuter z = 0, λ = 0.3 · pedestrian z = 1.28, λ = 1.2 · emergency z = 2, λ = 1.0 |
| Flood class | T_c = 7200 s (placeholder), severity 1.0, h_max 300 mm, ε = 0.1 |

**Prior ℓ0.**
- Source: 7,453 GCC flood-hazard polygons (OpenCity), mapped to edges within 600 m.
- Category defaults run from 0.02 to 0.45 and are **not calibrated**.
- There is no DEM or HAND layer.
- Only 14,534 of 471,240 edges carry a hazard entry: 5,775 with observations, plus 8,759 prior-only edges with p0 ≥ 0.25. About 97% of edges are never penalised.

**Proposition (useful and correct).** With δ = 1, an edge's cost is at most (1 + λs) × free-flow time. So the commuter default (λ = 0.3) is nearly hazard-blind: a 60 s flooded segment justifies at most an 18 s detour.

### 4.4 Data reality (read before any experiment)

- **Replay corpus:** `data/corpus/2026-09-17/observations.ndjson`, 6,132 observations from OpenCity 2015 KMLs.
  - 5,379 flood and 753 waterlogging.
  - 1,080 official and 5,052 crowd.
- **The corpus is not a proper ground truth:**
  - **every** observation has the same proxy timestamp, 2015-12-02T00:00Z;
  - none has depth;
  - all are positive.
- Some "official" points are GCC vulnerability designations, not dated observations.
- Consequences:
  - decay cannot be tested;
  - the chance constraint never fires;
  - false-avoidance cost cannot be measured;
  - every decay variant (C2, C3, C4, oracle) produces identical routes.

---

## 5. What the evaluation actually shows

Sources: `07_reanalysis/`, `04_critique_and_review/deep_review/`, `01_code/citypulse-IDP/data/results/`.

### 5.1 Route quality (Study 1, re-scored correctly)

The team's harness scored each configuration under its own belief and counted penalty seconds as travel time, which made configurations incomparable. The re-analysis scores every route under one reference belief (C3 p̄ at the replay clock) and uses free-flow time for detours.

| Configuration | Σp̄ per route | Observed / prior-only | Routes touching p̄ ≥ 0.5 | Mean detour |
|---|---|---|---|---|
| C0 free-flow | 1.61 | 1.03 / 0.57 | 30% | 0 |
| C1 block p̄ ≥ 0.5 | 1.22 | 0.71 / 0.51 | 0% | 1.53% |
| Hybrid: block > 0.5, plus λ = 5 | 0.79 | 0.52 / 0.27 | 0% | 2.14% |
| C3 default (z = 0, λ = 0.3) | 1.52 | — | 29% | +0.026 s (7/100 routes changed) |
| C3 z = 0, λ = 5 | 0.98 | 0.75 / 0.23 | 21% | 0.85% |
| C3 z = 0, λ = 20 | 0.44 | 0.36 / 0.08 | 6% | 4.53% |

- **The advantage over C1 comes from the prior.** C3 (λ = 5) beats C1 by −0.28 on prior-only edges and is +0.04 *worse* on edges with observations.
- **Against held-out official reports,** prior-only routing performs the same as prior + crowd routing, or better:
  - λ = 5: 1.07 vs 1.09 official edges per route;
  - λ = 20: 0.86 vs 0.91.
- **Higher z cannot be credited.** Scoring a belief against itself can never show pessimism helping.

### 5.2 The pessimistic index is non-monotone (critical flaw F-01)

At p0 = 0.05, with crowd reliability α = 0.6:

| Fresh crowd reports on the edge | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| p̃ at z = 1.28 | 0.329 | 0.309 | 0.333 | 0.380 |
| p̃ at z = 2 | 0.486 | 0.441 | 0.461 | 0.509 |

- **The crossover** is α* ≈ 0.63 (z = 1.28) or ≈ 0.645 (z = 2). Any source below it lowers caution on its first report.
- **Ageing reports** lower p̃ at every z.
- **Saturation:** at z = 2, p̃ = 1 on all 8,759 prior-only edges.
- **The fix** is to replace the Wald band with a Beta posterior upper quantile. Use an α-weighted, conflict-aware evidence count. A Beta posterior always raises its upper quantile after a positive observation.

### 5.3 Calibration (Study 2)

- **Label.** An edge counts as positive if it has an official report; the models see the crowd reports and the prior.
- **Rows.** 4,876 crowd edges × 6 simulated ages, plus **5,000 report-free easy negatives that the team's write-up did not mention**. That gives 34,256 rows, 708 of them positive.

| Model | Brier | Brier skill vs climatology (0.0202) | AUROC |
|---|---|---|---|
| C3 | 0.0343 | −0.70 | 0.609 (pooled) / 0.566 (crowd pool) |
| C4 (6 h TTL) | 0.0367 | −0.81 | 0.609 |
| Beta reputation | 0.292 | −13.4 | 0.568 |

- **Crowd evidence makes the belief worse.** On the crowd pool at age 0, the prior alone scores Brier 0.0361 and C3 scores 0.0478.
- **Inside GCC coverage there is no discrimination at all:** prior AUROC 0.456, C3 0.455. Edge length alone scores 0.651.
- **The label is weak.** It measures co-location of official and crowd points on the same directed edge, not flooding.

### 5.4 Engineering checks that pass

- Two replay runs produce byte-identical traces.
- An independent SciPy re-implementation reproduced the Dart router's C3 paths on 100 of 100 pairs.
- Malformed inputs (NaN, future-dated observations, out-of-range α) are rejected with runtime errors.

---

## 6. Claims: what you may and may not write

| Do not write | Write instead |
|---|---|
| "Runs entirely on the phone" | "Designed to run on-device; not yet tested on a device" |
| "Caution grows as evidence thins" | "A pessimistic index intended to add caution; in its current Wald form it decreases after a single low-reliability report" |
| "p̃ is an upper confidence bound" | "a pessimistic index" (it has no coverage guarantee) |
| "Verified explanations" | "Template explanations with a symbolic gate whose error rates are not yet measured" |
| "Bidirectional Dijkstra with ALT" | "Bidirectional Dijkstra (an ALT module exists but is not used)" |
| "Novel flood-aware routing / decay / ALT admissibility" | Cite the prior art: IBM US20130116920A1, Uber US10563994B2, Jøsang and Ismail 2002, Delling and Wagner 2007 |
| "Crowd reports improve routing" | "On the 2015 replay, crowd reports added no measurable value over the static prior" |
| "Risk-seeking under ambiguity" | "Ambiguity-seeking" |
| "Calibrated" | Report the Brier skill score, which is negative |

Confirmed prior art and context (see `03_literature_review/` for verified records):
- Flood routing on modelled floods: Li et al. 2023; de Faria et al. 2026; Panakkal et al. 2023.
- Multi-source link-level flood fusion: Panakkal and Padgett 2024.
- Spatially decaying social-media impedance: Fu et al. 2026.
- Offline evacuation app that infers blocked segments: Itoi et al. 2017.
- Route explanation: Alsheeb and Brandão 2023; Schild et al. 2025.
- Traversal and probe-based flood detection: Hiramoto et al. 2025; Pietrobon et al. 2019; Kong et al. 2022.

---

## 7. Classification (use when describing the project)

- **Readiness:**
  - router + belief: TRL 4;
  - explanation template + gate: TRL 3–4;
  - LLM rewriters: TRL 2–3;
  - client, server and sync: TRL 3;
  - **whole system: TRL 3**;
  - Kotlin app: TRL 2.
- **Software maturity:** research artifact. It is above a prototype (ADRs, contracts, tests, determinism, recorded negative results) and below an MVP (no user can choose a route, submit a report or receive live data).
- **Contribution type:** systems integration plus an application case study, with a small modelling part:
  - the (1 + λs) cap;
  - the non-monotonicity result;
  - the slowdown/harm split.
- **Product category:** a civic-tech flood resilience tool delivered as a navigation feature. A B2B "passability API" has no code behind it.
- **Suitable venues:** ACM COMPASS, IEEE GHTC or ITSC, ISCRAM, or a SIGSPATIAL short or demo paper. Check deadlines before choosing.

---

## 8. Where to improve (priority order)

**P0. Correctness fixes in the code** (details and file:line in `00_START_HERE/KNOWN_FLAWS.md`):
1. Snap each observation to **both directions** of two-way streets (F-02).
2. Replace the Wald index with a **Beta posterior upper quantile**, using a reliability-weighted, conflict-aware evidence count (F-01, F-12).
3. Fix the template:
   - say "avoids" only when the route avoids the place;
   - compare free-flow time with free-flow time;
   - never invent "reported moments ago";
   - catch Tier 0 failures and still show the route (F-04, F-07, F-08).
4. Strengthen the gate: check comparative direction, bind each number to its subject, and add a paraphrase and negation test set for safety claims (F-05).
5. Add an event gate on the prior, and define what the emergency class does on dry days (F-09).
6. Page sync by server arrival or HLC, not by `observed_at` (F-10).
7. Either put ALT on the query path or correct every description of it (F-11).
8. Fix the Makefile (F-19) and move the Groq call server-side (F-16).

**P1. Evaluation.**
- Re-run Study 1 with the hybrid baseline and the observed/prior-only split, and report disconnections.
- Rebuild Study 2:
  - split the pools;
  - control for coverage and edge length;
  - report Brier skill against both climatology and the prior.

**P2. Data. This decides the project.**
- Try the CFM-DSS public WFS for subway-barrier and sensor layers with live timestamps.
- Ask GCC ICCC and GCTP for barrier and sensor states.
- Run a field-logging protocol at the 22 GCC subways and 290 named waterlogging points (timestamped photo plus a passable / not passable / unknown flag).

**P3. Device.**
- Run the app on a Rs 10–15k Android phone and measure latency, memory and the on-device prior footprint. The current prior file is 152 MB.
- Measure the Tier 1 gate's pass, false-reject and detection rates.

**P4. Product (only if the 15 Oct gate passes).**
- Rescope to 22 subways and 290 points.
- Sell timestamped evidence with age and confidence, never "safe routes".
- Target the first commercial bar: a written Rs 1 lakh commitment from a non-grant buyer by 15 Dec 2026.

---

## 9. How to take on a task here (protocol)

1. **Restate the task.** Find which section above it touches, and read the relevant file in `00_START_HERE/`. If it is build work, find its task ID in `PLAN.md` and follow that task's steps and "Done when" list; if it has no task ID, add one to `PLAN.md` first.
2. **Check existing decisions.** If the task touches the model, cost or schemas, read `01_code/citypulse-IDP/docs/DECISIONS.md` and `docs/CONTRACTS.md` first.
3. **Run the existing tests before changing code,** and record the baseline.
4. **Make the smallest change that produces evidence.**
   - Add a test that fails before the fix and passes after it.
   - Keep the Dart router the single implementation; never fork the algorithm into Python for production use.
   - Python re-implementations are allowed only for analysis, and must be validated against the Dart traces, as `07_reanalysis/` does.
5. **Experiment hygiene.** Experiments are scripts with pinned seeds. They write to a new `data/results/<YYYY-MM-DD>-<name>/` folder with a `result.json`. Never edit an old result.
6. **Record findings.**
   - If a result contradicts a claim, write it into `docs/DECISIONS.md` (new ADR) and into `00_START_HERE/KNOWN_FLAWS.md` or `PROJECT_STATUS.md`. Do not quietly fix the wording.
   - When a flaw is fixed, mark it `FIXED (date, commit/file)` in `KNOWN_FLAWS.md` and re-run any study it affects.
7. **Writing tasks:**
   - follow `09_skills/human-scope/SKILL.md` for voice;
   - follow the IEEE rules in the paper folder for citations;
   - only cite references listed in `03_literature_review/references_verified.tsv`, or new ones you have opened and verified.
8. **Report back** with: what changed, which files, test results before and after, and anything that remains open.

---

## 10. Glossary

| Term | Meaning |
|---|---|
| p̄ | fused flood probability for an edge |
| p̃ | pessimistic index used by the router |
| n_eff | sum of kernel-and-decay weights (not a sample size) |
| z | per-class caution parameter |
| λ | risk weight converting probability into seconds of penalty |
| s | class severity |
| δ | depth-based slowdown (1 when depth is unknown) |
| C0 | free-flow routing |
| C1 | hard block of edges with p̄ ≥ θ |
| C2 | single decay constant |
| C3 | the method (class-specific decay) |
| C4 | fixed 6 h time-to-live |
| C∞ | hindsight oracle |
| Prior-only edge | an edge with a hazard entry from the GCC prior but no observation |
| GCC | Greater Chennai Corporation |
| GCTP | Greater Chennai Traffic Police |
| ICCC | Integrated Command and Control Centre |
| CFM-DSS | Chennai flood management decision-support system (public WFS) |
| TRL | technology readiness level (EU H2020 Annex G) |
