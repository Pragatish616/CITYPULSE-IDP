# Deploying CityPulse AI (preparation only, 3 October 2026)

Nothing here has been published. This is the set-up for a single-origin deployment: one web server
serves the Flutter web build and forwards `/api/*` to the router service and `/ingest/*` to the ingest
server, so the browser makes no cross-origin calls and CORS stays off. Read `docs/LICENCE_AUDIT.md`
first; its "re-check before launch" list applies.

## What was tested and what was not

| Part | State |
|---|---|
| Web build with `ROUTER_API_URL=/api`, `INGEST_URL=/ingest`, served behind a path-stripping proxy | **Tested** on 3 Oct with a small local stand-in for Caddy: map, `/api/health`, `/api/risk`, `/api/event-state` all worked, and the only outside host contacted was `tiles.openfreemap.org`. Route search and report posting through `/api` and `/ingest` were not clicked through. |
| `deploy/Caddyfile`, `deploy/docker-compose.yml`, both Dockerfiles | **Untested.** The authoring machine has no Docker or Caddy. Expect to fix small things on the first build. |
| `POST /api/rewrite` | Tested with a mocked Groq (19 router_api tests) and against the keyless server (503). Never run against live Groq. |
| Ingest storage | In memory. Reports vanish on restart. Needs the database settings in `server/README.md` before anything beyond a demo. |
| Compression, caching headers | In the Caddyfile, untested. |
| One-container image (`deploy/single/`) | **Deployed on Render (free instance), 4 October 2026: <https://citypulse-idp.onrender.com>.** It took six real builds to get there (see KNOWN_FLAWS F-35). `scripts/smoke_deploy.py` passed 11 read-only checks against the live URL on 4 Oct 2026 (a 12th, the rain-context check, was added later and has not been run on the live site; posting a test report was not run there either). Still not built on a local Docker, and not checked after the host's idle sleep and wake-up. |
| Memory | Measured on Windows (working set, not Linux RSS): router 83 MB at start, 170 MB after 30 walking routes; report server 50 MB. Caddy not measured. Expect roughly 250 to 300 MB in total. |

## Steps

1. **Build the map pack** if it is missing: `python scripts/build_packs.py`.
2. **Build the web app** from `app/`:

   ```bash
   bash scripts/sync_data_assets.sh && flutter pub get
   flutter build web --release --no-web-resources-cdn \
     --dart-define=ROUTER_API_URL=/api --dart-define=INGEST_URL=/ingest \
     --output <absolute path to deploy/web>
   ```

   Two pitfalls found while testing: on Windows **Git Bash rewrites an argument that starts with `/`**
   into `C:/Program Files/Git/...`, which silently bakes a wrong address into the build. Prefix the
   command with `MSYS_NO_PATHCONV=1` or build from PowerShell. And `--output` must be an absolute path;
   a relative `../` path fails in the shader step.
3. **Configure**: `cp deploy/.env.example deploy/.env`, set `ADMIN_TOKEN` to a long random string. Leave
   `GROQ_API_KEY` empty to run without the cloud rewriter (the app uses the template).
4. **Run**: `docker compose -f deploy/docker-compose.yml --env-file deploy/.env up --build`, then open
   `http://localhost:8088`.
5. **A real domain**: set `SITE_ADDRESS=your.domain` in `.env`; Caddy then obtains a TLS certificate by
   itself. Point DNS at the host first.

## The event state: automatic by default, with a human override (ADR-027)

The router sets the event state from NASA satellite rain, polled every 15 minutes: `watch` after about 8 mm in three hours (or a heavy cell), `active` after about 15 mm (or a violent cell), held for hours after, `dry` otherwise. The numbers are placeholders (ADR-027). The data runs about six hours behind, so it cannot warn ahead.

See what it decided and why (no token needed): `GET /api/event-state` returns the state, `mode` (`auto`, `manual` or `fixed`), `source` (`rain`, `forecast`, `manual`, `fallback` or `configured`), a sentence of reasons with the numbers, and the rain reading.

Override it (admin token in the `x-admin-token` header; set `ADMIN_TOKEN` in the host's environment settings or this is disabled):

```bash
# force a state until cleared
curl -X PUT https://YOUR-SITE/api/event-state -H "x-admin-token: $ADMIN_TOKEN" -H "content-type: application/json" -d '{"event_state":"active"}'
# force a state for 6 hours, then return to automatic by itself
curl -X PUT https://YOUR-SITE/api/event-state -H "x-admin-token: $ADMIN_TOKEN" -H "content-type: application/json" -d '{"event_state":"watch","hours":6}'
# give the decision back to the rain rule
curl -X PUT https://YOUR-SITE/api/event-state -H "x-admin-token: $ADMIN_TOKEN" -H "content-type: application/json" -d '{"mode":"auto"}'
```

**Optional: a rain forecast (ADR-029, off by default).** With `EVENT_FORECAST=1` the router also reads `GET /context/forecast` from the report server (Open-Meteo, ECMWF IFS 0.25 degree, nine points over Chennai, every 30 minutes). If 8 mm or more (area mean, three hours) is forecast within the next 12 hours, a `dry` state is raised to `watch` and the answer says `source: forecast` with the numbers. It never gives `active` and never lowers anything; a forecast older than 6 hours is ignored; an override still wins. **Not recommended:** in the pre-registered replay (ADR-029) it caught 7 of 46 wet satellite times a day ahead and warned ahead for 5 of 24 rain episodes, so it is off by default. Open-Meteo's free API is for non-commercial use (`docs/LICENCE_AUDIT.md`, row 2).

If the rain data is missing, older than 12 hours, or flagged stale, the configured `EVENT_STATE` (default `active`) applies and the answer says `source: fallback`. Holds are kept in memory, so a restart (a free host sleeping) forgets them. On a dry day the demo now shows `dry`: the 2015 hazard map is off and the advice card says no flood event is under way.

## Settings that matter

| Variable | Where | Purpose |
|---|---|---|
| `ADMIN_TOKEN` | router | Required to change the event state (`PUT /event-state`). Unset means the endpoint is disabled. |
| `GROQ_API_KEY`, `GROQ_MODEL` | router | Enables `POST /rewrite`. Unset means 503 and the app falls back to the template. The key stays in the server's environment. |
| `TRUST_FORWARDED_FOR=1` | router | Set only behind the proxy, so rate limits see real caller addresses. Never set it when the router is reachable directly. |
| `OBSERVATIONS_URL` | router | Where the router pulls reports from (the ingest server). |
| `CITY` | router, and `--dart-define=CITY=` for the app | Which city from `config/cities.yaml` to serve (default: its `default_city`). One deployment serves one city (`docs/ADDING_A_CITY.md`). |
| `EVENT_STATE` | router | `dry`, `watch` or `active`; decides whether the static hazard prior counts (ADR-015). With a rain source (below) it is the **fallback** used when the rain data is missing or older than 12 hours; default `active`. Without one, it is the state. |
| `OBSERVATIONS_URL` | router | The report server root. It also supplies the satellite rain (`/context/rain`), so with it set the event state is **automatic** (ADR-027). In the one-container image it is `http://127.0.0.1:8000`. |
| `EVENT_AUTO` | router | Set to `0` to turn the automatic state off and use `EVENT_STATE` as a fixed value, as before ADR-027. |
| `EVENT_FORECAST` | router | Set to `1` to let a rain forecast raise `dry` to `watch` ahead of rain (ADR-029). Default off. Needs the automatic state (`OBSERVATIONS_URL` set, `EVENT_AUTO` not `0`). |
| `CORS_ALLOWED_ORIGINS` | ingest | Leave empty for single-origin. |
| `FIELDLOG_TOKENS` | ingest | `code:token,code:token`, one pair per volunteer (make them with `scripts/fieldlog_ops.py token`). **Unset means field logging is off**, not open. A token under 16 characters is refused. ADR-028. |
| `FIELDLOG_ADMIN_TOKEN` | ingest | Lets an operator read and export the field log. Unset means reading is off. Use a different value from every volunteer token. |
| `FIELDLOG_DIR` | ingest | Where the field-log files go. Default: a folder in the container's temporary directory, which a free host wipes. |
| `FIELDLOG_DURABLE` | ingest | Set to `1` only when `FIELDLOG_DIR` is on a persistent disk. It changes only what `/fieldlog/health` says. |

## The volunteer field log (ADR-028, off until you set tokens)

The image already contains the field-log page and API. At `<site>/ingest/fieldlog/` there is a page for volunteers to record what they see at a road point (passable, not passable, can't tell). It is research data and is kept apart from the router: it does not change any route. The protocol, safety rules, notice and the pre-registered analysis are in `docs/FIELD_PROTOCOL.md`.

To switch it on: make tokens (`python scripts/fieldlog_ops.py token v01 v02`), set `FIELDLOG_TOKENS` and `FIELDLOG_ADMIN_TOKEN` in the host's environment, and redeploy. Check with `python scripts/fieldlog_ops.py status https://<site>/ingest`.

**Storage is the weak point.** The log is files on the container's disk. On Render's free tier that disk is wiped by a restart or a redeploy and probably when the service sleeps, so every entry made since the last export can vanish. Until a persistent disk or a database is attached, export after every logging day: `FIELDLOG_ADMIN_TOKEN=... python scripts/fieldlog_ops.py export https://<site>/ingest`. The export refuses to write a file whose row count does not match the server's and prints a SHA-256. `/ingest/fieldlog/health` reports `durable: false` until `FIELDLOG_DURABLE=1`.

Not checked on a live host yet: the page behind the `/ingest` prefix was tested through a stand-in proxy that copies the Caddy rules, not through Caddy itself; and the offline service worker has not been seen to register in any browser used so far. `scripts/smoke_deploy.py` does not test the field log (a new check would fail against a site that has not been redeployed); use the `status` command instead.

## One container, for hosts that run a single service

`deploy/single/` builds one image holding the web app, the router API, the report server and Caddy (the front door on `$PORT`).
Build and run it anywhere Docker runs:

```bash
docker build -f deploy/single/Dockerfile -t citypulse .      # from 01_code/citypulse-IDP
docker run --rm -p 8080:8080 -e ADMIN_TOKEN=change-me citypulse
python scripts/smoke_deploy.py http://127.0.0.1:8080 --write   # 12 checks; --write posts one test report
```

Files: `deploy/single/Dockerfile` (web stage, router stage, runtime), `Caddyfile` (plain HTTP on `$PORT`; the host ends TLS),
`start.sh` (starts the three processes and stops the container if one dies, so the host restarts it). `.dockerignore` is an
allow-list because `data/` holds gigabytes of research inputs.

A host that expects `Dockerfile` at the top of the Git repository (Render's default) uses the generated copy at the repository root. Never edit it by hand:
change `deploy/single/Dockerfile` and run `python scripts/make_root_dockerfile.py`. `scripts/tests/test_root_dockerfile.py` fails if the copy is stale or if a file
the image copies is not tracked in Git (a fresh clone could not build it).

Things to know before the first build:
- The web stage installs Flutter 3.47.2 from its Git tag (`--build-arg FLUTTER_VERSION=...` to change it). The app needs Dart 3.13.2 or newer.
  The `cirruslabs/flutter:stable` image was tried first and shipped Dart 3.12.0, so `flutter pub get` failed. The tag was checked against the
  upstream repository and matches the Flutter used for all local tests.
- Reports are held in memory. A restart, a redeploy, or a free host going to sleep loses them. Persistence needs the database settings
  in `server/README.md`, which means a Supabase account that you create.
- Set `ADMIN_TOKEN` in the host's environment settings, not in the image. Without it the event state cannot be changed.
- A fix made while preparing this: the older `deploy/router_api.Dockerfile` did not copy `config/cities.yaml` or the places file, so the
  router would not have started in it (F-35).

## Where to host it (nothing signed up, nothing published)

Searched on 4 October 2026. Free-tier terms change often; read the host's own page before choosing. The router and report server
need about 300 MB, so a 512 MB free service is enough on paper, though a free host's CPU share is small (below) and the route times
measured here (10 to 14 ms for a car, up to about 0.4 s on foot) will be slower.

| Host | What the search found | Fit |
|---|---|---|
| [Render](https://docs.render.com/free) | Free web service: 512 MB RAM, 0.1 CPU, sleeps after 15 minutes idle (30 to 60 s to wake), 750 free hours a month, 100 GB bandwidth ([summary](https://livemy.app/blog/render-pricing)). Runs a Dockerfile from a GitHub repo. Whether an account needs a card was not confirmed. | Best first try. A generated `Dockerfile` at the repository root makes Render's default settings work, so no Root Directory or Dockerfile path needs setting; only set `ADMIN_TOKEN`. (The first attempt, with those settings typed by hand, was not picked up and failed with "open Dockerfile: no such file".) |
| [Koyeb](https://www.koyeb.com/docs/faqs/pricing) | One free service, 512 MB, 0.1 vCPU, sleeps after an hour; a credit card was added as a requirement in February 2026 ([source](https://freetier.co/directory/products/koyeb)). | Needs a card, which breaks the "no card" rule. |
| [Hugging Face Spaces](https://huggingface.co/docs/hub/en/spaces-overview) | Free CPU is 2 vCPU and 16 GB, but a [forum thread](https://discuss.huggingface.co/t/docker-sdk-now-marked-as-paid-when-creating-a-new-space/177580/5) reports Docker Spaces now marked as paid. Not confirmed on the host's own docs. | Check before relying on it. |
| Your own machine plus a tunnel | Run the image locally and publish it through a tunnel. Not researched. | Fallback for a demo; the site is down when the machine is off. |

Sleeping hosts: the first request after idle takes up to a minute, so the smoke test waits 60 s for it. For a live demo, open the site a
few minutes beforehand.

A split alternative (static web app on a static host, router and reports on a container host) needs CORS switched on and
`ALLOWED_ORIGIN` set. It is not prepared because it undoes the no-CORS design above.

## Before this is public

- Choose and add a project licence; decide the Open-Meteo question; read the unchecked terms
  (`docs/LICENCE_AUDIT.md`).
- Connect the ingest server to a database so reports persist.
- Decide how the DPDP duties are met (notice, erasure on request).
- Serve over HTTPS; keep `ADMIN_TOKEN` and any API key out of the repository.

## Serving a state (Tamil Nadu, ADR-020)

Set `CITY=tamil_nadu` for the router (`PORT`, `ADMIN_TOKEN` as above) and build the web app with `--dart-define=CITY=tamil_nadu`. The router
loads `places.json` from the pack folder for town and village search. Memory is small (the pack is 9 MB), but a larger or finer region pack
needs measuring first (F-26).

**Chennai inside Tamil Nadu (ADR-022).** With `CITY=tamil_nadu` the router also loads the Chennai pack, named by `detail_regions` in `config/cities.yaml`
(about twice the memory of one pack; not measured). Routes with both ends in Chennai use it and get the flood layer and advice; every other route uses
the main-road pack. `GET /health` lists `detail_regions`. `PUT /event-state` changes both engines.
