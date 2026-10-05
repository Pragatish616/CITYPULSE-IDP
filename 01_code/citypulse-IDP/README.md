# CityPulse AI: the codebase

The code behind CityPulse AI. For the project overview, results and status start at the
[repository README](../../README.md); this page is the map of the code.

> Research prototype. It never says a road is safe or passable. The Android app has been installed and run on one phone (not measured; offline use untested).
> The rules for working in this code are in [`../../CLAUDE.md`](../../CLAUDE.md) (the wording table in section 6
> overrides any older claim, including in `CLAUDE.md` in this folder).

## Components

| Path | Language | What it is |
|---|---|---|
| [`packages/pulse_router/`](packages/pulse_router) | Dart | Map pack reader, bidirectional Dijkstra, hazard-aware edge cost, travel profiles, decision trace, place search, region configuration, route advisor |
| [`packages/pulse_belief/`](packages/pulse_belief) | Dart | Flood belief: log-odds fusion, source weights, decay, Beta-posterior cautious index |
| [`packages/pulse_explain/`](packages/pulse_explain) | Dart | Template explanation and the symbolic verifier |
| [`services/router_api/`](services/router_api) | Dart | HTTP service for routes, search, hazard overlay and event state; serves Chennai and Tamil Nadu together |
| [`app/`](app) | Flutter | Android and web client |
| [`server/`](server) | Python (FastAPI) | Citizen-report ingest, the source adapters, and the volunteer field log (ADR-028; off until tokens are set) |
| [`scripts/`](scripts) | Python | Pack builders, replay engine, Study 1 and Study 2, tests |
| [`config/`](config) | YAML | `cities.yaml` (regions) and `hazard_classes.yaml` (reliabilities, traveller classes, travel profiles) |
| [`data/`](data) | | Pinned snapshots, map packs, results; provenance in [`data/MANIFEST.md`](data/MANIFEST.md) |
| [`docs/`](docs) | Markdown | Decision records, contracts, architecture, deployment |
| [`deploy/`](deploy) | | Caddy and Docker files (untested: no Docker on the authoring machine) |

## Run the tests

```bash
(cd packages/pulse_belief  && dart pub get && dart test)
(cd packages/pulse_router  && dart pub get && dart test)
(cd packages/pulse_explain && dart pub get && dart test)
(cd services/router_api    && dart pub get && dart test)
(cd app && bash scripts/sync_data_assets.sh && flutter pub get && flutter test)

python -m venv .venv && . .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r scripts/requirements.txt -r server/requirements.txt
pytest scripts/tests server
```

Tests that need large files outside git (the Chennai graph, the compiled router) skip themselves.

## Run it

```bash
# API: Chennai detail inside the Tamil Nadu main-road map
cd services/router_api && dart pub get
CITY=tamil_nadu PORT=8080 dart run bin/server.dart       # CITY=chennai for Chennai alone

# Web app against that API
cd ../../app && bash scripts/sync_data_assets.sh && flutter pub get
flutter run -d chrome --dart-define=CITY=tamil_nadu --dart-define=ROUTER_API_URL=http://localhost:8080
```

Environment variables, deployment and the reverse-proxy set-up are in [`docs/DEPLOY.md`](docs/DEPLOY.md).

## Build data

| To | Run |
|---|---|
| Rebuild the Chennai pack | `python scripts/build_packs.py` (needs the graph build, see `data/MANIFEST.md`) |
| Add a routing-only city | `python scripts/city_pipeline.py fetch --city <id>` then `pack --city <id> --date <yyyy-mm-dd>` |
| Build a state-sized region | `python scripts/region_pack.py --city <id> --levels backbone --date <yyyy-mm-dd>` (needs `pyosmium` and a Geofabrik extract) |
| Run the studies | `python scripts/t3_2_replay_engine.py`, `study1_route_quality.py`, `study2_calibration.py` (pinned seed 20260918, results to `data/results/<date>-<name>/`) |

Details: [`docs/ADDING_A_CITY.md`](docs/ADDING_A_CITY.md).

## Where to read next

- Why things are the way they are: [`docs/DECISIONS.md`](docs/DECISIONS.md)
- Schemas that components share: [`docs/CONTRACTS.md`](docs/CONTRACTS.md)
- Known flaws: [`../../00_START_HERE/KNOWN_FLAWS.md`](../../00_START_HERE/KNOWN_FLAWS.md)
- The build plan: [`../../PLAN.md`](../../PLAN.md)
