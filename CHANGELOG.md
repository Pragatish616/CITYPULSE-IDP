# Changelog

All notable changes. The project is a research prototype with no tagged releases yet; entries are by date and
by decision record. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Combined Chennai + Tamil Nadu serving: routes with both ends in Chennai use the detailed pack, flood layer
  and advisor; all other routes use the Tamil Nadu main-road pack (ADR-022).
- On-device route advisor: risk level, proceed / wait / avoid verdict, evidence level, route-choice check
  (ADR-021).
- Tamil Nadu main-road region pack (257,249 edges, 9 MB) and a 25,144-place gazetteer; highway-number search
  (ADR-020).
- Viewport-limited hazard overlay, thinned long routes, per-region snap radius and opening zoom.
- Travel modes: car, bicycle, on foot, emergency vehicle (ADR-019).
- City-agnostic pack pipeline (ADR-018) and an "Adding a city" guide.
- Project documentation for GitHub: README, contribution guide, security policy, CI, issue templates.

- Merged India flood event dataset: India Flood Inventory v4 plus Dartmouth Flood Observatory events, linked for Tamil Nadu, research-only licences (ADR-023).

- Training-data assessment and downloads: Chennai Flood Monitor archive (local only) and NYC FloodNet sandbox, with fetch and profile scripts (ADR-024).

- Nationwide district flood-event model, trained under a pre-registered rule; it did not beat two simple baselines (ADR-025).

- Terrain and past floods as training data: 91 India flood maps and elevation tiles, a nationwide terrain model, Chennai studies and three routing tests, all pre-registered; the nationwide model met its rule, the Chennai and routing rules were not met (ADR-026).
- Tested terrain-hydrology code (`scripts/hydrology.py`).

### Added (subway watchlist and pilot kit, 9 October 2026; nothing verified, nothing deployed)
- A subway watchlist from the Greater Chennai Corporation's own table (16 road/rail and 5 pedestrian subways, transcribed row for row) plus news and OpenStreetMap names: 31 candidates, 21 with an OSM position (labelled by how sure the match is) and 10 with none, which carry a labelled area hint instead of an invented point. No source gives "22" names or the 290 waterlogging points (ADR-031).
- The volunteer field log serves the subways first, lists those without a position by name, and searches GCC's location words, news names and Tamil names. A bug the tests caught: an id over the server's 32-character limit.
- `scripts/subway_board.py`: an internal one-page board from a field-log export (newest observation and age per subway, observer disagreement, "No observation" kept apart from "Could not tell"; no safety words, no volunteer codes). `data/watchlist/2026-10-09/CHECKSHEET.md` for confirming positions. `docs/PILOT_PLAN.md` and a draft offer (`docs/pilot/OFFER_DRAFT.md`, not sent).
- The event miner's place list now includes the subways.
- `scripts/fieldlog_merge.py`: restores entries the server lost from the phones' own CSVs, labelled by where each came from, with conflicts reported and no overwriting.
- Chennai flood-monitor live-data test: the first of two approved requests got HTTP 404 (wrong path), so it is inconclusive; its layer list has no subway or barrier layer.

### Added (event miner, 8 October 2026; not evaluated)
- `ml/event_miner/`: a local model (`qwen3.5:0.8b` through Ollama, Apache 2.0, small enough to consider for phones) reads pasted official posts and news in English or Tamil and lists street events (`closed`, `flooded`, `cleared`, `unknown`) with a word-for-word quote. Events whose quote is not in the text are dropped; places are matched only to the project's gazetteer (lexical plus `nomic-embed-text` embeddings), or left unmatched. Everything waits in an append-only review queue; accepted events export as CSV and never reach routes (ADR-030).
- The evaluation (at least 100 real items labelled before mining, precision and recall per language) is pre-registered and not yet run. `docs/EVENT_MINER.md` explains running, reviewing and labelling.

### Added (rain forecast input, 8 October 2026; off by default, not adopted)
- `GET /context/forecast` on the report server (Open-Meteo, ECMWF IFS 0.25 degree, nine points over Chennai) and an `EVENT_FORECAST=1` switch in the router that lets a forecast raise `dry` to `watch` ahead of rain, never higher. The app's rain sheet names the forecast when it is the source (ADR-029).
- Pre-registered replay over the 2024 and 2025 north-east monsoons and a dry season against NASA IMERG (`scripts/forecast_rule_replay.py`). **Negative:** at 24 h notice the forecast caught 7 of 46 wet times and warned ahead for 5 of 24 episodes; it never switched on in the dry season. The criteria were not met, so it stays off.

### Added (field log, 6 October 2026, local commits only, not deployed)
- A volunteer field log for the missing ground truth: a phone page (English, Tamil draft) where a volunteer records passable / not passable / can't tell at one of 402 candidate sites from the GCC hazard zones, or at another spot, with the time. Entries queue on the phone offline and sync later; the server stores them append-only and fsynced, idempotent by entry id, with per-volunteer tokens, rate limits and a checked, formula-safe CSV export. Kept apart from the router: it changes no route and is shown to no traveller (ADR-028).
- `docs/FIELD_PROTOCOL.md`: safety rules, what to tap, the sampling plan, volunteer notice, and the analysis pre-registered before any data. `scripts/fieldlog_ops.py`: token generation, status and a verified export.
- Not yet shown on a real phone or a live host; storage is not durable on a free host until a disk or database is attached.

### Added (deployment)
- Rain on the map screen: the flood-event banner now has a second line from NASA satellite rain (for example "Rain by satellite over Chennai: none in the last 3 h · image 5 h 44 min old", or "heavy now · 24 mm in the last 3 h"), and tapping the banner opens a sheet with the numbers, where the state comes from (automatic, operator, default) and the limits. It reads the existing `GET /event-state`, so there is no new server code. English and a Tamil draft. If the service cannot be reached the line is simply absent; an unknown is never shown as no rain.
- Automatic event state (ADR-027): the router sets dry / watch / active from NASA satellite rain every 15 minutes, with a human override (`PUT /event-state`, optional hours, or `{"mode":"auto"}` to return). `GET /event-state` now also reports the mode, source, reason and rain behind it. Falls back to `EVENT_STATE` when the rain data is missing or over 12 hours old; `EVENT_AUTO=0` turns it off. Placeholder thresholds (F-36).
- `GET /context/rain` on the report server: NASA IMERG satellite rain intensity and 3-hour accumulation for Chennai (keyless, cached, shows its age, serves stale when NASA is down). Context only; nothing is stored as a hazard report. Not yet used by the router or the app.
- Phone testing: a manual GitHub workflow that builds an installable Android APK (`.github/workflows/android-apk.yml`) and `docs/MOBILE_TESTING.md` (home-screen install of the web demo, APK install, what to record). First built on 4 Oct 2026 (60.9 MB APK, second run); installed on one Android phone on 5 Oct 2026 and reported to behave like the web app (no measurements recorded yet).
- Web demo live on a free Render instance: <https://citypulse-idp.onrender.com> (README "Live demo"; a temporary demo, see its limits).
- One-container image (`deploy/single/`: Dockerfile, Caddyfile, start.sh) that serves the web app, router API and report server from one address, and `scripts/smoke_deploy.py` (12 checks, local or live URL). Untested as an image; see docs/DEPLOY.md.
- A generated `Dockerfile` and `.dockerignore` at the repository root (`scripts/make_root_dockerfile.py`) so hosts that build from the top of the repo work without settings; a test checks it is current and that every copied file is in Git.
- Hosting options researched and recorded in docs/DEPLOY.md, with measured memory.

### Fixed
- The router Docker image copied neither `config/cities.yaml` nor the places file, so it could not start (F-35).
- Place search finds neighbourhoods and suburbs (a dated OSM gazetteer for Chennai), and a name typed exactly now ranks first (F-31).
- Web: the report sheet closes after sending; sheets no longer pass clicks through to the map (F-32).
- Report sheet names the spot as the centre of the map and says how to pick another (F-33).
- Route card says when no flood hazard was found, beside the thin-evidence reason (F-34).

### Changed
- Pessimistic index is now a Beta-posterior upper quantile; it no longer lowers caution after a weak report
  (ADR-015).
- Explanations are template-based with a stronger symbolic gate (ADR-016).
- Studies 1 and 2 re-run and re-scored under one reference belief (ADR-017).
- Routes in regions without a flood layer no longer show a flood banner, hazard badge or hazard explanation.
- Two Python tests that need the large Chennai graph now skip when it is absent, instead of failing.

### Known problems
See [`00_START_HERE/KNOWN_FLAWS.md`](00_START_HERE/KNOWN_FLAWS.md). Notably: nothing has run on a phone;
crowd reports add nothing measurable on the 2015 replay; the Tamil text is unreviewed; pack format v1 cannot
hold a whole state's streets (F-26).

## 2026-10-02 and 2026-10-03

Independent review and correction pass (see `04_critique_and_review/` and `07_reanalysis/`).

## 2026-09

Initial build: router, belief engine, explanation template and verifier, Flutter shell, ingest server,
replay harness and the first evaluation.
