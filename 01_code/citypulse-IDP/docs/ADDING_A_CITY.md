# Adding a city

How to make CityPulse route in a city other than Chennai (ADR-018). Read the first section before
you spend time on it: the pipeline makes the *roads* easy, and the *flood data* is the hard part.

## What you get, and what you do not

| | Roads and routing | Flood-hazard layer |
|---|---|---|
| What the pipeline builds | Yes: a pack from OpenStreetMap, searchable street names, any-to-any routing, the same explanation and report flow | **No.** Every edge gets the flat default prior (p = 0.02). Nothing is shown as flood-prone. |
| What the app says | Normal map and routes | "No flood-hazard layer is loaded for this city" in the layers sheet, About, and licences screen. Routes use road speeds and citizen reports only. |
| What it is good for | Checking that the pipeline works, demos of the interface, collecting reports | Not for telling anyone a route avoids flooding. Without a hazard source it cannot. |

So a new city is a **routing-only** city until you add a verified hazard source. Do not set
`hazard_layer: true` for a city because you want the app to look finished.

Project guidance (`CLAUDE.md`, `NEXT_STEPS.md`): do not add hazards or cities before one monsoon of
Chennai labels exists. The pipeline is there so the second city is cheap when the time comes, not as a
reason to start one now.

## Steps

1. **Add the entry** to `config/cities.yaml`: id, names (English; Tamil is a draft until reviewed), centre,
   bounding box, `hazard_layer: false`. Leave `local_contact` out unless you have *checked* a number;
   the national emergency number (112) always shows. Use a box that covers the built-up area with a
   little margin; a larger box is slower to fetch and makes a bigger pack.
2. **Fetch the roads** (network; the public Overpass server is shared, so be patient and do not loop it):

   ```bash
   python scripts/city_pipeline.py fetch --city <id>
   ```

   This writes `data/osm/<id>_overpass_drivable.json`, live and unpinned. Record the snapshot
   timestamp it prints.
3. **Build the pack:**

   ```bash
   python scripts/city_pipeline.py pack --city <id> --date <YYYY-MM-DD>
   ```

   It refuses a city marked `hazard_layer: true`, and refuses a box whose roads do not contain the
   configured centre. Output: `data/packs/<id>-<date>/` with `graph.bin`, `nodes.bin`, `meta.bin` and
   `manifest.json` (counts, hashes, the OSM timestamp, the city block). Re-running with the same inputs
   gives byte-identical files. Packs are pinned by date and never edited.
4. **Point the config at it:** set `pack: data/packs/<id>-<date>` in the city's entry.
5. **Licences:** add the new files to `data/MANIFEST.md`. The roads and names are ODbL; the pack is a
   derived database and must be offered under ODbL if published. Check that OpenFreeMap's tiles cover the
   city (they are worldwide).
6. **Run it:**
   - router service: `CITY=<id> dart run bin/server.dart` in `services/router_api`
   - app: `bash app/scripts/sync_data_assets.sh <id>`, then `flutter build ... --dart-define=CITY=<id>`
   - web, same origin: add `--dart-define=CITY=<id>` to the build in `docs/DEPLOY.md`
7. **Check it by eye:** search a street you know, route two places, and read the About screen. If a
   local person can look, ask them to check that the street names and one-way streets are right.

One build serves one city. Switching cities inside one app, or serving two cities from one router, is
not built.

## Adding a hazard layer later

A hazard layer is data plus a licence, and it must be real:

- a source you can name and verify (official flood-extent or hazard-zone maps, a past-event
  inundation survey), with its licence read and recorded in `data/MANIFEST.md`;
- a build step that turns it into a per-edge prior, like `scripts/t1_3_build_graph_and_prior.py` does for
  Chennai's GCC zones (this is code you write for that source, not a flag);
- the city's `hazard_note`, `about_data` and `data_credit` texts in `config/cities.yaml`;
- and the same caution the Chennai results force on us: the prior has not been calibrated, and on the 2015
  replay the citizen-report layer added nothing over the static prior (ADR-017). Do not claim more for a
  new city than that evidence supports.

## What is tested without a real second city

`Testville` is a synthetic 6 x 6 street grid (`scripts/tests/make_testville_fixture.py`), placed in open
country, with one broken link and one one-way road. The Python builder produces its pack, the Dart router
routes on it (`packages/pulse_router/test/city_pack_test.dart`), the HTTP service serves it
(`services/router_api/test/other_city_test.dart`), and the app's texts follow the city
(`app/test/core/city_strings_test.dart`). That shows the code carries no Chennai assumption. It does **not**
show that a real city's OpenStreetMap data builds cleanly or looks right; that needs a real fetch.

## Larger regions: a state, in phases (ADR-020)

A whole state does not fit the Overpass route above. Use `scripts/region_pack.py` with a Geofabrik extract
(needs `pyosmium`, so a separate virtual environment):

```bash
python scripts/region_pack.py --city tamil_nadu --levels backbone --date 2026-10-03
```

- `--levels backbone` is motorway to secondary. Estimate nothing from Chennai's ratios: build a trial pack and read the counts from `manifest.json`.
- Serve it with `CITY=tamil_nadu` on `services/router_api`; build the web app with `--dart-define=CITY=tamil_nadu`.
- In `config/cities.yaml` give a region a wide `max_snap_metres` (Tamil Nadu: 15000) and a low `initial_zoom` (7.2).
- The builder refuses more than 65,535 street names (F-26). Do not work around it; the pack format needs a version 2.
- Regions have no flood data unless you add a verified source (F-27).
