# app — CityPulse AI Flutter client (Android and web)

One Flutter codebase for the Android app and the web app (PLAN.md M4, M5). Flutter, Riverpod,
go_router, MapLibre (`maplibre_gl`, Android and web) on the OpenFreeMap `liberty` style.

**Status, stated plainly.** The web build has been run end to end in a browser, locally and on the
hosted demo. The Android app compiles in GitHub Actions (`.github/workflows/android-apk.yml`, 4 Oct 2026)
and has been installed and run on one phone (5 Oct 2026), where it is reported to behave like the web
app. Not yet recorded: timings, memory, battery, airplane-mode routing (KNOWN_FLAWS F-06). Tier 1
(`flutter_gemma`) and Tier 2 (Groq) rewriters have never been executed.

## What it does

- **Map** of Chennai with the risk overlay (hazard-map edges coloured by the router's belief,
  dashed where only the 2015 hazard zones speak and solid where a report exists) and the
  watchlist candidates layer. The legend explains both; the overlay never means "safe" (ADR-011).
- **Four travel modes**: car, bicycle, on foot, emergency vehicle. Each has its own speeds, its own
  roads and its own route and time (walkers may go against a one-way street; bicycles and cars may
  not). The speeds are placeholder assumptions in `config/hazard_classes.yaml` (ADR-019).
- **Route planner** for any origin and destination. Search a place or tap the map. The router
  (`packages/pulse_router`) runs in-process on Android; the web build calls `services/router_api`.
  The route is the one the router chose on a pessimistic belief; user class sets the caution.
- **Explanation card** from the decision trace: a template, gated by the verifier. Data gaps are
  listed (a hazard-map edge on the route with no recent report).
- **Report flow**: tap the map, choose a type. Location is rounded to 4 decimal places (about
  10 m), no photo and no free text, anonymous resettable code (ADR-007). A report changes routes.
- **Event banner** shows the event state (dry / watch / active). The static prior only counts in
  watch and active; reports always count (ADR-015, F-09).
- A disclaimer gate (ADR-011) wraps the app. The UI never says a road is safe, dry, clear or
  passable; `test/` enforces the vocabulary.

## Run it

Needs Flutter (stable) and Dart 3. From `01_code/citypulse-IDP`:

```bash
# 1. Build the map pack once (reads data/graph/2026-09-14; writes data/packs/<date>)
python scripts/build_packs.py

# 2. Copy the pack, configs and watchlist into app/assets (not checked in). The argument is a city
#    id from config/cities.yaml (default: its default_city); build with the same --dart-define=CITY=<id>
cd app && bash scripts/sync_data_assets.sh [city-id] && flutter pub get
```

Back ends for the web build (two terminals):

```bash
# Router service on :8080
cd services/router_api && ADMIN_TOKEN=dev-admin OBSERVATIONS_URL=http://localhost:8000 dart run bin/server.dart
```

```bash
# Ingest server on :8000, allowing the web app's origin
cd server && CORS_ALLOWED_ORIGINS=http://localhost:5000 ../.venv/Scripts/python.exe -m uvicorn app.main:app
```

```bash
# Web app (release build, then serve it). --no-web-resources-cdn bundles CanvasKit so the page
# asks Google's CDN for nothing; MapLibre GL JS and the fonts are already self-hosted.
cd app && flutter build web --release --no-web-resources-cdn \
  --dart-define=ROUTER_API_URL=http://localhost:8080 \
  --dart-define=INGEST_URL=http://localhost:8000
python -m http.server 5000 --directory build/web
```

If the browser shows an old build, unregister the service worker and hard-reload.

Build-time settings are `--dart-define` values (`lib/src/core/app_config.dart`): `CITY`, `ROUTER_API_URL`,
`INGEST_URL`, `MAP_STYLE_URL`. The app serves one city per build; its name, map centre, data texts and
local contact come from `config/cities.yaml` (`docs/ADDING_A_CITY.md`). Never point the map style at `tile.openstreetmap.org` or any Google
source (CLAUDE.md §2). The app holds no API keys. `lib/src/explain/cloud_rewriter.dart` no longer
reads a key from a compile-time define or the environment (F-16). The Groq tier goes through
`router_api` `POST /rewrite`, which holds `GROQ_API_KEY`; with no key there it answers 503 and the app
uses the template. The rewriters are not wired into the explanation card yet. Do not add a key with
`--dart-define`.

Android: `flutter run -d <device>` after the steps above. **A debug build was attempted on
2 October 2026 and failed before compiling any Dart:** Gradle tried to install NDK 28.2.13676358
through `sdkmanager`, which crashed (exit -1073740791), and `flutter doctor` reports the Android
licences as unknown. A person has to run `flutter doctor --android-licenses` (accepting the SDK
terms) and install the NDK in Android Studio's SDK Manager, then retry. The pack (about 15 MB) is bundled in the
APK until PLAN.md M2.6 moves it to a downloadable pack.

## Speed and third-party requests

- **On a phone** the router runs in a background isolate (`lib/src/platform/engine_host.dart`), so the
  15 MB pack parse and the route searches never block the UI thread. On this desktop (JIT, not a phone)
  the same work stalled the main isolate for about 425 ms in-process and under 50 ms in the
  background (`test/platform/in_process_backend_test.dart` guards it). No phone numbers exist yet.
- **On the web** a page load fetches only this site's files plus `tiles.openfreemap.org` (the base map).
  CanvasKit, MapLibre GL JS (`web/vendor/maplibre-gl`, BSD-3) and subset Roboto / Noto Sans Tamil
  (`assets/fonts`, SIL OFL) are served by the app itself, so visitors' addresses go to no CDN. The
  vendored library version must match `maplibre_gl_web` (see its README).
- Serve `build/web` with gzip or brotli on a real host (`python -m http.server` does not compress);
  `canvaskit.wasm` is 5.3 MB and `main.dart.js` 3.4 MB uncompressed.
- Licences and terms: `docs/LICENCE_AUDIT.md`. The app's Settings has "Data sources and licences" and
  "Software licences".

## Tests

```bash
cd app && flutter test
```

Widget tests inject small fixtures; checks that read the real pack are plain unit tests. The
harness (`test/helpers`) replaces the map with a fake because MapLibre needs a platform view.

## Not built yet

Offline PMTiles basemap, the Drift outbox wired to sync, a downloadable pack instead of the bundled
one, saved places and alerts, data export and deletion, geolocation ("my location"), the watchlist
status page (needs PLAN.md M3.1), and a native-speaker review of the Tamil strings.
