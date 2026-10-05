# server — CityPulse AI ingest server (T5.3)

FastAPI app that accepts, stores, and streams `HazardObservation` records (docs/CONTRACTS.md
§1). Implements the ingest slice of `docs/IMPLEMENTATION_PLAN.md` T5.3 — schema validation,
G-Set dedup (ADR-008), bbox/time query, SSE push, and two zero-key ingest workers
(Open-Meteo, GDACS). See "What's stubbed" below for what T5.3 deliberately does not build.

## Current status: no cloud accounts exist yet

Per `docs/data-access-log.md`, **no Supabase, Upstash, TomTom, OpenAQ, or Groq accounts have
been created** (T0.4 is incomplete) — those require a human to sign up on a free tier with no
credit card (CLAUDE.md §3; this server never signs up for services on its own). Until that
happens, the server runs entirely in **memory-store, two-feed-only mode**:

- Storage is in-process (`app/storage/memory.py`) — nothing persists across a restart.
- Only the Open-Meteo and GDACS ingest workers are real. TomTom/OpenAQ/CMWSSB are
  interface-shaped stubs that raise `NotImplementedError` (see below).
- No LLM call exists anywhere in this server (ADR-007 scope; that's T4.4).

The server is fully runnable and testable today in this mode. The moment `.env` is
populated with real Supabase/Upstash credentials, it switches backends automatically — no
code change required (see "Storage backend selection" below).

## Running locally

```bash
cd server
# from the repo's .venv (already has fastapi, uvicorn, etc. — see requirements.txt)
../.venv/Scripts/python.exe -m pip install -r requirements.txt   # first time only
../.venv/Scripts/python.exe -m uvicorn app.main:app --reload
```

Then:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/observations
```

## Running tests

```bash
cd server
../.venv/Scripts/python.exe -m pytest -q
```

33 tests, all passing against the in-memory backend — no network access, no database, no
API keys required. `respx` mocks the two ingest workers' HTTP calls; nothing in the suite
hits a real network endpoint.

Formatters/linters (must be clean before committing, CLAUDE.md §7):

```bash
../.venv/Scripts/black.exe app tests conftest.py
../.venv/Scripts/ruff.exe check app tests conftest.py
```

## Env vars — which feature each one gates

| Var | Gates | Status |
|---|---|---|
| `SUPABASE_URL` | Switches storage from in-memory to PostGIS (`app/storage/factory.py`). Unset -> memory. | **Not set — no project exists yet.** |
| `SUPABASE_SERVICE_KEY` | Used to build the derived Postgres DSN when `SUPABASE_DB_URL`/`DATABASE_URL` isn't set directly (see below). | **Not set.** |
| `SUPABASE_DB_URL` / `DATABASE_URL` | Preferred: the actual Postgres connection string from Supabase's dashboard (Project Settings -> Database). Not in `.env.example` yet — add it once a project exists. | **Not set; doesn't exist in `.env.example` yet.** |
| `UPSTASH_REDIS_URL` | Not consumed anywhere in this task. ADR-005's decay sweeper (parallel ZSET, since Redis can't expire individual geo-set members) is a separate, not-yet-built piece of work. | **Not set — not wired up yet either way.** |
| `TOMTOM_API_KEY` | Would enable `app/ingest/tomtom.py`. Currently an interface-shaped stub — see below. | **Not set — no account.** |
| `OPENAQ_API_KEY` | Would enable `app/ingest/openaq.py`. Currently an interface-shaped stub. | **Not set — no account.** |
| `GROQ_API_KEY` | Not used anywhere in this server. Cloud LLM calls are T4.4's scope, out of T5.3. | **Not set — not applicable here.** |
| *(none)* | `app/ingest/open_meteo.py`, `app/ingest/gdacs.py` — both real, no key required. | **Working today.** |

## Storage backend selection

`app/storage/factory.get_repository()` is the one place this happens: `SUPABASE_URL` set
and non-empty -> `PostGISObservationRepository`; otherwise -> `InMemoryObservationRepository`.
Called once, at app startup, in `app/main.create_app()`.

**Judgement call on the PostGIS DSN** (documented, not silently resolved): Supabase's
dashboard gives you `SUPABASE_URL` (a REST endpoint, `https://<ref>.supabase.co`) and
`SUPABASE_SERVICE_KEY` — neither is a Postgres connection string, and `.env.example` (as of
this task) doesn't list one. `factory.py` prefers an explicit `SUPABASE_DB_URL` /
`DATABASE_URL` env var (copy the real one from Supabase's Database settings page) and falls
back to a best-effort derived DSN (`postgresql://postgres:<service_key>@db.<ref>.supabase.co:5432/postgres`)
only if neither is set. **That derived hostname pattern must be confirmed against a real
project before it's trusted** — Supabase's pooler hostname varies by project/region and this
has not been tested against a live database.

`app/storage/postgis.py` is real, parameterised SQL — bbox queries via
`ST_Intersects`/`ST_MakeEnvelope` over a GiST index, plus an `ST_DWithin`-based radius query
method (`get_observations_within_radius`, not yet wired to an HTTP endpoint) — but it has
**not been run against a live database**, because none exists. Treat it as reviewed-correct,
not verified-correct, until it has been.

## What's real vs. stubbed

**Real (implemented, tested):**
- `HazardObservation` / `EdgeBelief` Pydantic models (`app/models.py`), mirroring
  `docs/CONTRACTS.md` §1/§2 exactly, with `hazard_class`/`source_class` derived at import
  time from `config/hazard_classes.yaml` (`app/config.py`) — one source of truth, no second
  hardcoded enum.
- `POST /observations`, `GET /observations`, `GET /health`, `GET /events` (SSE).
- `GET /context/rain` (`app/ingest/imerg.py`): NASA IMERG satellite rain intensity for the Chennai box, decoded from NASA GIBS map
  images with GIBS's own colour legend. No key, no login. Context, not a hazard report: it is never stored as an observation and says
  nothing about a road being flooded or passable. Returns the age of the data (it ran about 6 hours behind in the first live check),
  caches 15 minutes, serves the last good answer marked `stale` if NASA is down, and returns 503 if there is none. The intensity bands
  are generic descriptive rain bands, placeholders until a pre-registered study fits them. 28 tests (mocked HTTP).
- G-Set dedup (`ON CONFLICT DO NOTHING` semantics, ADR-008) in both storage backends.
- `app/ingest/open_meteo.py` — real HTTP calls to the Open-Meteo forecast API, normalised
  into `heat` `HazardObservation` records. The Open-Meteo *flood* API (GloFAS river
  discharge) is also called for real but is **not** written as a `HazardObservation` — see
  the module docstring: discharge is a magnitude with no polarity or depth, doesn't fit the
  contract, and is instead normalised into a `context_facts`-shaped dict
  (docs/CONTRACTS.md §3) for a future router-side consumer, which is out of T5.3's scope.
- `app/ingest/gdacs.py` — real HTTP fetch + XML parse of `xml/rss_fl_7d.xml`, filtered to
  India-relevant items, stamped with a deliberately large `accuracy_m` (GDACS is
  country/event-level per `research/raw/C-data-sources.md` C34, not a street-level fix).
  **Caveat, flagged rather than silently assumed:** the exact GeoRSS element names
  (`georss:point` vs `geo:Point`/`geo:lat`+`geo:long`) were not confirmed against a live
  fetch — this sandboxed environment has no outbound network access to gdacs.org. Run this
  once against the real URL before a demo depends on it.

**Interface-shaped stubs (NotImplementedError, per the task's explicit scope boundary):**
- `app/ingest/tomtom.py` — needs `TOMTOM_API_KEY` (docs/APIS_AND_COSTS.md §1, Tier 1). Also
  needs TomTom's caching/storage terms read before any incident enters the permanent log —
  the pricing page doesn't state them (research/raw/C-data-sources.md C29).
- `app/ingest/openaq.py` — needs `OPENAQ_API_KEY`.
- `app/ingest/cmwssb.py` — needs confirmed reachability of `cmwssb.tn.gov.in`, which failed
  from two independent research environments outside India (`docs/IMPLEMENTATION_PLAN.md`
  T0.5). Do not build a scraper against a page nobody on this team has loaded.

**Not built in T5.3 at all (explicitly out of scope, noted so nobody assumes it exists):**
- A real scheduler. Each real worker exposes `run_ingest_cycle(...)`; wiring a cron/APScheduler/
  background task to call it periodically is follow-up work.
- Redis / ADR-005's decay sweeper (parallel ZSET for expiring individual geo-set members).
- ADR-010's 30-day coarsening sweep — `HazardObservation` has `precision_state`/
  `coarsened_at` and the model enforces their consistency, but nothing here runs the sweep.
- Any LLM call (ADR-007's scope is respected by omission — this server has no code path that
  forwards any payload to a cloud LLM at all).
- Full watchlist wiring — ingest workers currently poll a small hardcoded set of
  representative Chennai points, not the ~150-200 point watchlist in
  `data/watchlist/2026-09-14/watchlist_candidates.json`.

## Documented contract ambiguity

ADR-009 (`docs/DECISIONS.md`) says `HazardObservation` "gains `watchlist_point_id`", added
2026-09-14 — after `docs/CONTRACTS.md` §1's own last edit (2026-09-12), which does not show
that field in its worked example. Rather than silently dropping the ADR's consequence or
silently inventing an undocumented required field, `watchlist_point_id` is modelled here as
`Optional[str] = None` (additive — every existing CONTRACTS.md §1 example still validates
unchanged). **CONTRACTS.md should be updated to show this field explicitly**; this is flagged
here rather than fixed there, since CONTRACTS.md changes only by ADR (its own preamble).
