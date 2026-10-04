# Data sources for training a flood model: assessment (4 October 2026)

**Question.** Which dataset could make a machine-learning model worth using to guide route selection?
**Short answer.** No existing dataset is both street-level and large enough for Chennai. The best achievable
training set is a layered one: Chennai's official flood-monitoring archive plus past flood extents and
points, terrain, and (the part that decides it) street-level labels we collect ourselves during the 2026
northeast monsoon. Dense public street-level data from other cities is useful to build and test the method,
not to train the Chennai model.

Everything below was read from the source's own page on 4 October 2026 unless marked `[NOT CHECKED]`. Nothing
has been downloaded except the two sources in ADR-023.

## What a route-guiding model needs

Labels that say, for a road segment at a time, whether it was flooded or impassable, plus the conditions at
that time (rain, water levels, terrain, drainage). It must be checkable on events and places it never saw.

## Ranked sources

| # | Source | What it gives | Why it matters | Limits | Licence / access |
|---|---|---|---|---|---|
| 1 | **Chennai Flood Monitor (CFM-DSS) archive**, mirrored on Hugging Face (`CashlessConsumer/chennai-flood-monitor-transactions`, `chennaidss-gis-layers`, `chennai-flood-history`) | **daily rainfall from 53 gauges for every year 1988 to 2019**, then 41 to 51 gauges for 2023 to 2026 (includes the 2015 event and Michaung 2023); water levels from 4 to 40 stations in 2023 to 2026; automatic-station data 2018 to 2021 only; 181 GIS layers (wards, drainage, waterways, tanks, bathymetry); flood extents 2005 and 2015; GCC hotspot maps; ward depth scenarios; 173 citizen reports with a 1 to 6 water level (see the findings below: almost all are level 1) | The only Chennai source with time-stamped rain and water levels and some timestamped street reports. Same government system the project already planned to try (CLAUDE.md P2). | Citizen reports are nearly useless as flood labels (below). Ward depth model "frozen at August 2021". Some stations stale. Five layers failed to extract. | Publisher states **no licence**; redistributed under fair dealing; station staff contacts removed; takedown risk acknowledged by the mirror's authors. Keep local, research use, do not commit to the public repo. 16.8 MB + 41.9 MB + 2.4 MB |
| 2 | **GCC flood points with depth, return-period zones (OpenCity)**, [Chennai Flooding Data](https://data.opencity.in/dataset/chennai-flooding-data) | Inundation points with depth in inches; 2015 flood points; hazard zones for 5, 10, 25, 50, 100 and 200 year return periods | Real depths and a hazard ranking for the whole city | No timestamps on the depth points | Public domain (stated on the page). KML |
| 3 | **Terrain: Copernicus GLO-30 DEM** | 30 m elevation for slope, height above nearest drainage, flow accumulation | Free for commercial use; the strongest static predictor of where water collects | 30 m is coarse for a street; buildings and trees add error | Free, full and open (FABDEM is non-commercial, so not chosen). AWS open data, no account |
| 4 | **Satellite flood extents for Chennai events** (Sentinel-1 for Dec 2015 and Dec 2023, labelled with a flood detector trained on the datasets in 6) | Road-level, dated flood labels for past events | Turns the two big Chennai floods into labelled road segments with dates | SAR in dense cities is hard (double-bounce); needs validation against the 2015 points and the 2025 reports; I found no ready-made Michaung extent product | Sentinel data are free but the portals need an account the user must create `[NOT CHECKED: exact access route]` |
| 5 | **Live collection this monsoon** | (a) poll the CFM-DSS public WFS (the archive above stops at the last published run) into an append-only archive; (b) field logs of passable / not passable / unknown with timestamp at the 22 GCC subways and 290 named points; (c) app reports with a passability state | **The only way to get street-level, time-stamped labels in Chennai.** The northeast monsoon is under way, so each week of delay is lost data | Needs volunteers and care with personal data (DPDP). The WFS terms are not stated | Our own data. Polling a government server needs the owner's go-ahead and a polite rate |
| 6 | **Method sandboxes** (other cities) | **NYC FloodNet**: per-minute street-flood depth from ultrasonic sensors, event table on NYC Open Data. **SpaceNet 8**: flooded and non-flooded road labels with imagery (New Orleans, Germany). **Urban Flood Observations**: 215 hand-labelled 3 m chips (Houston, Dhaka and others). **UrbanSARFloods**: 18 SAR urban flood events | Dense, checkable labels let us build and test the whole pipeline (features, model, route-level scoring, honest evaluation) before Chennai has enough | Different cities, drainage and climate. Useful for method and for a flood detector; **not** a source of Chennai labels. None includes India (checked for UFO and UrbanSARFloods) | NYC: open. SpaceNet 8: CC BY-SA 4.0 (AWS, no account). UFO: CC BY 4.0. UrbanSARFloods: CC BY-NC-SA 4.0 |
| 7 | Already merged | India Flood Inventory + DFO events (ADR-023) | Event calendar and district severity | District-level only | Non-commercial |

## Checked and set aside

- **IUTF** (traffic plus rain, 40 cities, 2015 to 2017): no Indian city, rain is 31 km ERA5, and flooding is not labelled.
- **INDOFLOODS**: river catchments, not urban streets `[NOT CHECKED in detail]`.
- **Mumbai, Bengaluru, Delhi points (OpenCity, BBMP, BMC)**: hotspot lists without times. Useful later for a second city, not for training now.
- **IITM Pune street-level inundation maps**: published inside PDF bulletins (92 MB for seven bulletins), not as GIS; licence not stated.

## What the best training set can and cannot do

- Chennai has at most five independent flood events with spatial labels: 2005 and 2015 (extents, points), the 2020 monsoon (hotspot map), the 2025 monsoon (a handful of citizen reports above level 1), and 2023 only if the SAR labelling in row 4 works. That sets the model size: **small** (a gradient-boosted or logistic susceptibility model on terrain and drainage, plus a rainfall-threshold model), validated by holding out **places and events**, not random rows.
- Realistic result: a better, evaluated **prior** (where water tends to collect) and better **event gating** (when to apply it). Not a live street-by-street predictor.
- Success must be fixed before training: the model must beat the existing GCC hazard prior and a rainfall-only baseline on held-out events, measured by flooded-segment exposure per route.
- The only thing that raises the ceiling is more labelled events, which means collecting them this monsoon.

## Order of work

1. Start the live archive and the field-log form now (monsoon in progress).
2. Download sources 1 to 3 (about 100 MB plus a few DEM tiles) and build the feature table.
3. Stand up the pipeline end to end on NYC FloodNet, with the full evaluation, as a dry run.
4. Add the SAR-derived labels for 2015 and 2023 once an account exists.
5. Train, evaluate under the pre-registered rule, and report whatever happens.

## Findings after downloading (4 October 2026)

Downloaded with `scripts/fetch_training_sources.py` and profiled by `scripts/profile_training_sources.py`; the numbers are
in `data/chennai_cfm/2026-10-04/profile.json` and `data/nyc_floodnet/2026-10-04/profile.json`. Pinned revisions and file hashes
are in each `fetch_log.json`. The Hugging Face cards were wrong in places; these are the checked values.

**Chennai Flood Monitor archive** (53 MB across 230 files; kept local because the publisher states no licence)
- **Daily rainfall is the strongest asset.** The state rain-gauge table has 53 gauges reporting every year from 1988 to 2019
  (about 19,300 rows a year), then 41 to 51 gauges for 2023 to 2026, and nothing for 2020 to 2022. It covers the 2005 and 2015
  floods (the 2015 event window shows a single-gauge reading of 494.2 mm) and Michaung 2023. Daily, not 15-minute.
- Water levels: 4 stations in the Michaung week, 25 in the 2025 monsoon. Automatic weather and rain stations: 2018 to 2021 only,
  none in any flood window.
- **Spatial flood labels exist for several events:** 327 GCC hotspots from 2015 with a vulnerability class and inundation in feet, 53
  from the 2020 monsoon, 200 with depths from 2005, 4,001 satellite flood-extent polygons for 2015 and 235 for 2005, plus hotspot
  lists for three neighbouring districts. These are places that flooded, with no hour attached.
- **Drainage and terrain-related layers:** 8 drainage layers (macro and micro drains, canals, rivers, channels), 34 water layers, 24
  boundary layers, 36 forecast layers.
- **The citizen reports are almost useless as labels.** Of 173 reports (14 November 2022 to 4 December 2025), 161 are level 1
  (mostly "no water"), 12 are level 2 or higher, 9 of those inside the Chennai box, and 3 contain the word "test".
- The "ward depth" table is one frozen model run dated 11 August 2021 (200 wards), not an observation.
- Of Chennai-named IMD events (ADR-023), 33 fall in 1988 to 2019, covering 354 of 11,688 days (3%).

**NYC FloodNet** (5.7 MB, public): 3,422 flood events from 318 sensors, 16 November 2020 to 28 September 2026, each with a
per-minute depth profile. Median sensor has 3 events (largest 469). Median peak depth 3.48 inches; 8% of events reach 12 inches or more.

## What this changes

1. **An event-gating model is now trainable and checkable.** 31 years of dense daily rainfall against 33 reported Chennai events
   (354 flood days of 11,688) supports a rain-threshold model for "watch / active", compared against a seasonal-rate baseline on later
   years. Few positives, so the model must stay tiny and report intervals.
2. **A spatial susceptibility model has several event layers** (2005, 2015, 2020, plus the existing 6,132-point corpus). Absent
   reports do not mean dry, so negatives are unlabelled and this is a positive-unlabelled problem. It still needs terrain (the
   Copernicus DEM, not yet approved for download).
3. **Street-level, time-stamped labels still do not exist for Chennai.** The citizen-report layer, the one source that had them,
   has about a dozen positives. This stays the binding constraint and the reason to collect during this monsoon.
4. **FloodNet is a usable sandbox**: dense labelled street flooding with depth profiles for building and testing the whole pipeline.
