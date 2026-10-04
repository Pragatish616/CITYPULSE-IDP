> **Note (2 October 2026):** several claims in this README are outdated: the badges, "verified rationale", "entirely on-device", "ALT" and "250+ tests" (about 290). See `../../CLAUDE.md` and `../../00_START_HERE/KNOWN_FLAWS.md`.

# CityPulse AI

**Hazard-aware navigation for Chennai that keeps routing — and keeps explaining itself — after the network dies.**

[![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart)](packages/)
[![Flutter](https://img.shields.io/badge/Flutter-Android-02569B?logo=flutter)](app/)
[![Python](https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python)](server/)
[![FastAPI](https://img.shields.io/badge/FastAPI-async-009688?logo=fastapi)](server/)
[![Tests](https://img.shields.io/badge/tests-250%2B%20passing-brightgreen)](#status)
[![Budget](https://img.shields.io/badge/infra%20cost-%E2%82%B90%2Fmonth-informational)](docs/APIS_AND_COSTS.md)

Every monsoon, Chennai floods in roughly the same places — Velachery, Pallikaranai, the Mudichur
corridor — and every year the apps people actually use route them straight into it, or go dark
the moment a tower drops. CityPulse fuses live signals (rainfall, reservoir levels, citizen
reports) with a static hazard prior built from real GCC flood data onto the OSM road graph,
computes routes that trade travel time against *probability-weighted* hazard exposure, and
explains every routing decision in plain language — **entirely on-device, with zero network
connectivity.** Confidence in every hazard signal decays with age, and the app tells you when it
doesn't know something instead of quietly guessing.

> **Route, confidence state, and a verified natural-language rationale — produced on-device
> when the network is gone.**

---

## Why this is hard (and why most routing apps don't bother)

- No source gives you live street-level flood depth for Chennai — not Google, not the
  Corporation, nobody. So the system doesn't pretend to. It maintains a bounded, validated
  watchlist of ~150–200 chronic waterlogging points instead of a fake city-wide sensor claim.
- An unverified crowd report of a flood should make a route *more* cautious, not less — most
  naive hazard-routing designs get this backwards (low confidence → treated as "probably fine").
  CityPulse's cost model is pessimistic under uncertainty by construction, tunable per user
  class (commuter vs. ambulance vs. pedestrian).
- An LLM that writes route explanations is one hallucinated street name away from being
  actively dangerous. Every explanation here is generated from a structured decision trace and
  passes a symbolic verifier before it's ever shown — if it fails, the app silently serves a
  template instead of ever displaying an unverified claim.
- It has to work with the phone in aeroplane mode. Not "degrade gracefully" — actually compute
  the same route, the same way, offline.

## What's built and running

| Layer | What it does | Status |
|---|---|---|
| **`pulse_router`** (Dart) | CSR road graph, bidirectional Dijkstra + ALT landmarks, hazard-aware edge costing, structured decision traces | ✅ 80 tests |
| **`pulse_belief`** (Dart) | Log-odds hazard fusion, per-class temporal decay, pessimistic-under-uncertainty plug-in | ✅ 26 tests |
| **`pulse_explain`** (Dart) | Template explanation renderer + a 6-rule symbolic verifier (no hallucinated facts, no absolute-safety claims, ever) | ✅ 75 tests |
| **`app/`** (Flutter, Android) | Offline routing shell — loads the real Chennai graph, computes routes in-process (no server round-trip), confidence-banded UI, local SQLite hazard cache with spatial indexing | ✅ 23 tests |
| **`server/`** (FastAPI) | Hazard ingest API, live rainfall + flood-alert workers, spatial storage layer | ✅ 33 tests |
| **`scripts/`** | Real Chennai road graph (193k nodes / 471k edges), a 6,000+ event historical flood corpus, and a deterministic replay/evaluation harness | ✅ 15 tests |

One router implementation, two consumers: the Flutter app and the Python evaluation harness both
run the exact same Dart routing code — never a re-implementation that can silently drift.

## How it works

```
                     ┌─────────────────────────────────────┐
                     │   OSM (Chennai) + GCC flood data     │
                     └──────────────────┬────────────────────┘
                                        │  offline, one-time build
                                        ▼
                     ┌─────────────────────────────────────┐
                     │  Road graph + static hazard prior    │
                     └───────┬───────────────────┬───────────┘
                             │                   │
                 ships to device        Python evaluation harness
                             │                   │
                             ▼                   ▼
        ┌─────────────────────────────┐   ┌─────────────────────┐
        │   Flutter client (Android)  │   │  Replay / studies    │
        │  • pulse_router (in-process)│   │  (same router code,  │
        │  • local hazard cache       │   │   AOT-compiled CLI)  │
        │  • confidence-banded UI     │   └─────────────────────┘
        │  • works with zero network  │
        └───────────────┬─────────────┘
                        │ syncs when online
                        ▼
        ┌─────────────────────────────┐
        │   FastAPI server            │
        │  • live rainfall / alerts   │
        │  • hazard ingest + storage  │
        └─────────────────────────────┘
```

## Getting started

```bash
git clone <this-repo>
cd citypulse-IDP

# Dart packages (routing core, belief model, explanation engine)
cd packages/pulse_router  && dart pub get && dart test && cd ../..
cd packages/pulse_belief  && dart pub get && dart test && cd ../..
cd packages/pulse_explain && dart pub get && dart test && cd ../..

# Flutter app (Android)
cd app && flutter pub get && flutter test && cd ..

# FastAPI server
cd server && pip install -r requirements.txt && pytest -q && cd ..
```

The server runs fully in-memory out of the box — no database or API keys required to develop
against it. See [`server/README.md`](server/README.md) for wiring up real Supabase/Upstash/
TomTom/OpenAQ credentials when you're ready to go live, and [`.env.example`](.env.example) for
what each one unlocks.

## Project layout

```
packages/pulse_router    routing core — the single implementation the app and the evaluation harness both run
packages/pulse_belief    hazard belief fusion — log-odds decay, pessimistic plug-in
packages/pulse_explain   explanation templates + the symbolic verifier
app/                     Flutter client (Android)
server/                  FastAPI ingest + live-data server
scripts/                 graph build, hazard corpus, evaluation/replay harness
data/                    the Chennai graph, hazard corpus, and every experiment's results (dated, reproducible)
config/hazard_classes.yaml   per-hazard-class decay/severity/threshold config — the knobs every study varies
docs/                    architecture, ADRs, data contracts, the full build plan
research/                the source material this system is built from — real Chennai flood data and prior art
paper/                   evaluation write-up outline (this project is also producing a defensible evaluation, not just a demo)
```

`docs/IMPLEMENTATION_PLAN.md` is the single source of truth for what's built, what's next, and
why it's sequenced the way it is. `docs/DECISIONS.md` records every non-obvious design call and
the reasoning behind it — read it before assuming something should be built differently.

## Non-negotiables

These aren't style preferences — they're the constraints that keep this shippable and legal:

- **₹0 infrastructure budget.** Every service is free-tier, no credit card. See
  [`docs/APIS_AND_COSTS.md`](docs/APIS_AND_COSTS.md).
- **Never Google Maps Platform data.** Its terms forbid the offline caching this product is
  built around, and mixing it with OSM poisons the whole map dataset's license.
  Self-hosted PMTiles only, never `tile.openstreetmap.org` directly.
- **No passive location tracking.** Explicit consent only, per India's DPDP Act 2023.
- **The LLM never invents a fact or draws a route.** Every number and street name in an
  explanation comes from the router's own decision trace and is verified before display, every
  time, with no exceptions.

## Team

Pragatish N · Ravi · Jyotish — VIT Chennai.

## License

Not yet finalized — do not treat this repository as licensed for reuse until a `LICENSE` file
is added.
