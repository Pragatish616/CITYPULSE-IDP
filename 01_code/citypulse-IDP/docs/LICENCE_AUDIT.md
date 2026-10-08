# Licence and terms audit — 3 October 2026

Scope: everything CityPulse AI ships, calls at run time, or builds from. This is a working
engineering audit, **not legal advice**. Where a term was read from the publisher's page it is marked
*read*; the pages were summarised by a fetch tool, so confirm anything load-bearing against the
primary source before launch. Anything not read is `[UNVERIFIED]`.

Machine-readable scan of installed packages: `docs/licence_scan_2026-10-03.json` (script logic: read each
package's licence file from the pub cache / Python metadata and classify by its text).

## Verdict

Nothing found puts the current prototype outside licensed scope. Four things need action before any
public or commercial release (items 1–4 below); two were fixed in this session.

| # | Item | State |
|---|---|---|
| 1 | **Gemma 3 270M weights (Tier 1 rewriter).** Gemma Terms of Use are not an open-source licence: whoever redistributes the weights must pass on the use restrictions, give recipients the terms and include a notice (*read*). The app has never downloaded or run them. | **Open, needs a person.** Do not bundle or auto-download the model until the team has read and accepted the terms and chosen how users get the file. |
| 2 | **Open-Meteo free API** (used by the ingest worker `server/app/ingest/open_meteo.py`, and since 8 Oct 2026 by `GET /context/forecast` in `server/app/ingest/forecast.py`, which the router reads only when `EVENT_FORECAST=1`, ADR-029; the forecast model is ECMWF IFS, ECMWF open data, CC BY 4.0). The free API is for non-commercial use only; data is CC-BY 4.0 (*read*). | Fine for the university IDP and research. **Blocks a commercial or startup deployment** that polls it: use a paid plan, another source, or drop the worker. Give CC-BY attribution if its values are ever shown. |
| 3 | **Project's own licence.** There is no `LICENSE` file. The derived routing pack must be offered under ODbL (see OSM below). Source-code licence and the VIT IDP's IP policy are the team's decision. | **Open, needs the team.** |
| 4 | **OpenFreeMap public instance.** The terms page prohibits automated collection without permission and says nothing on commercial use or limits (*read*). | Fine for a prototype that loads tiles as a normal client. Do **not** bulk-download or cache tiles for offline use from it (the plan already self-hosts PMTiles). Email info@openfreemap.org before a launch with real traffic. |
| 5 | OSM attribution text lacked the OpenMapTiles credit and the licence name. | **Fixed:** `© OpenStreetMap contributors (ODbL) · OpenFreeMap © OpenMapTiles`, plus a Settings → Data sources and licences screen with the copyright URL. |
| 6 | The web app contacted Google's CDN (CanvasKit, Roboto font) and unpkg.com at page load, sending every visitor's address to them. | **Fixed:** CanvasKit, MapLibre GL JS and subset Roboto / Noto Sans Tamil fonts are served from the app itself. The only third-party host left on page load is the basemap (`tiles.openfreemap.org`). |
| 7 | **Local models for the event miner** (ADR-030, added 8 Oct 2026): `qwen3.5:0.8b` (Apache 2.0, read on the Qwen3.5 model card on Hugging Face) and `nomic-embed-text` (Apache 2.0, read from `ollama show --license`). Downloaded through Ollama on the authoring laptop and run there only; not in the app, the image or the repository. | Fine. If a model file is ever shipped (for example inside the app), ship the Apache 2.0 licence text and any NOTICE with it. Gemma 4 E4B, also installed on that laptop, is Apache 2.0 too but is not used. |

## Code dependencies

| Group | Result |
|---|---|
| Dart / Flutter packages (app + router service, 145 hosted packages) | 112 BSD-3, 23 MIT, 7 Apache-2.0, 1 BSD-2, 2 MPL-2.0. **No GPL or AGPL.** The two MPL-2.0 packages, `dbus` and `nm`, are Linux-desktop-only transitive dependencies of `connectivity_plus` (via `flutter_gemma`); they are not part of Android or web builds. MPL-2.0 is file-level copyleft and only matters if those files are modified. |
| Notice duty for BSD/MIT/Apache | The app's **Software licences** screen (`showLicensePage`) lists every Dart package's licence text, plus Roboto, Noto Sans Tamil and MapLibre GL JS through `LicenseRegistry`. |
| Native libraries inside Android plugins (MapLibre Native, SQLite via `sqlite3_flutter_libs`) | Not individually inspected. MapLibre Native is BSD-2 and SQLite is public domain from the projects' own descriptions, `[UNVERIFIED]` here. |
| Python server / scripts | Permissive (MIT/BSD/Apache/PSF) except: `psycopg` 3 is **LGPL-3.0** (used unmodified as a library by the server only; if the server is shipped in a container image, include its licence text and keep it replaceable); `certifi` and `pathspec` are MPL-2.0 (file-level); matplotlib, kiwisolver, cycler, scipy and python-dateutil carry BSD-style licences. Nothing GPL/AGPL. |
| Vendored front-end files | `app/web/vendor/maplibre-gl` — maplibre-gl 6.4.1, BSD-3-Clause, unmodified. Fonts in `app/assets/fonts` — SIL OFL 1.1, subset and weight-pinned (the licence texts ship with them). |

## Data

| Source | Terms | What we must do |
|---|---|---|
| OpenStreetMap (road graph, names, base map) | ODbL 1.0 (*read*): credit "OpenStreetMap contributors" and make the licence clear; a derived database redistributed must be offered under ODbL. | Attribution in the app is done. `data/packs/` and `data/graph/` are derived databases: publish them (if at all) under ODbL, never merge with data that forbids it. |
| OpenCity "Chennai Floods 2015 Data" (C13), GCC publisher | "Other (Public Domain)", no conditions stated on the dataset page (*read*). | Credit GCC / OpenCity as good practice (done in the Data sources screen). The dataset's NRSC inundation layer and the separate "flood hazard zones" dataset were **not** read: `[UNVERIFIED]`. |
| GDACS feed (ingest worker) | Terms page not retrieved. | `[UNVERIFIED]`: read https://www.gdacs.org/About/termofuse.aspx before relying on it commercially. |
| Groq API (cloud rewriter, currently unavailable) | Terms page returned 403. | `[UNVERIFIED]`; the client no longer holds a key (F-16). |
| Citizen reports | Anonymous, rounded to about 10 m, no text or photo, resettable code (ADR-007). | DPDP Act 2023 duties (notice, purpose, erasure on request) remain a launch task; data export and deletion are not built. |
| Google Maps Platform | Not used anywhere in code, data or style. | Keep it that way (CLAUDE.md §2). |

## Run-time network calls from a user's browser (after this session)

`tiles.openfreemap.org` (style, tiles, sprites, glyphs) and the project's own router and ingest
services. Nothing else. The Android build adds whatever `flutter_gemma` does when asked to fetch a
model, which is not exercised.

## Re-check before a public launch

1. Read the primary sources for OpenFreeMap, GDACS, Groq, OpenCity's other datasets and the Gemma terms.
2. Decide the project licence and confirm the VIT IDP IP position with the supervisor.
3. Decide Open-Meteo: paid plan or remove.
4. Re-run the dependency scan after any `pubspec.lock` or `requirements.txt` change.
