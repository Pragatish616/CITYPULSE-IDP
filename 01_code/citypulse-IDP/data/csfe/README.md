# Chennai Street Flood Evidence (CSFE): prototype v0.2 (30 Oct 2026)

One table of street- and subway-level flood evidence merged from sources that existed only in pieces, with daily gauge rain attached,
plus context tables. **Datasheet:** `DATASHEET.md`. **Benchmark:** `BENCHMARK_PREREGISTRATION.md` and
`data/results/2026-10-30-csfe-b1*/`. **Source survey:** `06_research_notes/DATASET_SOURCES_2026-10-29.md`.

Build: `python scripts/build_csfe_proto.py` (about 20 s) writes `2026-10-30/`. Tests: `python -m pytest scripts/tests/test_csfe_proto.py`.

| Build | What |
|---|---|
| `2026-10-29/` | v0: 45 news facts, rain window convention A (superseded) |
| `2026-10-30-windowA/` | v0.2 with convention A; the input of the first (invalid) B1 run, kept for the record |
| `2026-10-30/` | **v0.2, current**: 78 news facts, convention B |

**In git:** this README, `DATASHEET.md`, `BENCHMARK_PREREGISTRATION.md`, `news_facts_2026-10-30.csv`, `news_counts_2026-10-30.csv`
and each build's `summary.json`. **Not in git:** the generated tables (`*/*.csv`), because they include CFM-DSS data whose publisher
states no licence (`data/MANIFEST.md`).

## Tables in a build

| File | Rows (v0.2) | What |
|---|---|---|
| `observations.csv` | 7,010 | One row per statement about a place (schema below) |
| `subway_timeline.csv` | 68 | News reports per watchlist subway, in time order (19 subways, 7 events) |
| `news_counts.csv` | 8 | City-level statements ("22 subways free from stagnant water") that name no subway |
| `events.csv` | 247 | Rain events 1976–2026: days on which the median in-box gauge recorded at least 30 mm (at least 5 gauges) |
| `rain_daily.csv` | 451,408 | Daily total per gauge (87 gauges with a position, 29 inside the Chennai box) |
| `gauges.csv` | 87 | Gauge positions, matched from the CFM-DSS registries by id or name |
| `water_level_daily.csv` | 10,064 | Daily maximum level per CFM-DSS water level recorder (47 stations, 40 with a position), 2021–2026 |
| `ward_model_depth.csv` | 200 | Modelled minimum and maximum flood depth per ward (CFM-DSS); context, not observations |

## `observations.csv`

| Column | Meaning |
|---|---|
| `obs_id` | `csfe-000001`, ... (stable only within one build) |
| `event_id` | e.g. `2015-12`, `2020-nem`, `2021-11-11`, `2023-12-michaung`, `2024-11-fengal`, a rain event `rain-YYYY-MM-DD`, `day-YYYY-MM-DD`, or `unknown` |
| `t_observed`, `t_precision` | ISO time; precision `minute` (photo time), `reported_by` (publication time, an upper bound), `event`, `season`, `unknown` |
| `lat`, `lon` | WGS84; empty for news rows whose subway has no position yet |
| `place_id`, `place_name` | Subway watchlist id and the name as the source wrote it |
| `edge_ids`, `snap_m` | Nearest road edge within 50 m and its reverse twin (graph `2026-09-14`), and the distance |
| `kind` | `closed`, `partly_open`, `open`, `waterlogged_open`, `not_waterlogged`, `waterlogged`, `depth`, `depth_range`, `report_unclear` |
| `value`, `value_unit` | Depth in cm (`depth`), or a range `lo-hi` in cm (`depth_range`; open-ended above, e.g. `152-`) |
| `level_raw` | The source's own level field, unchanged (the citizen app's scale is undocumented) |
| `source_type`, `source`, `source_ref` | official / crowd / news; source name; id or URL |
| `licence`, `extraction` | Licence note; `automatic` or `manual` |
| `rain_reading_date` | The gauge reading whose 24 h window contains the observation |
| `rain_day_mm_nearest`, `rain_gauge`, `rain_gauge_km` | That reading at the nearest reporting gauge within 10 km |
| `rain_day_mm_city_median`, `rain_prev2d_mm_city_median` | Median over in-box gauges that day, and the sum of the two days before |

## Rules

- **Rain day:** median in-box daily total at least 30 mm with at least 5 gauges; consecutive rain days form one event.
- **Snapping:** nearest road edge within 50 m plus its reverse twin.
- **Rain window (convention B):** a reading dated D covers about 08:30 IST on D to 08:30 on D+1, so an observation before 08:30 is
  matched to the reading dated D−1. Inferred from the gauge series (storm totals sit on the readings dated the days of heavy rain);
  convention A, assumed in v0, was wrong. **[UNVERIFIED against gauge metadata]**.

## What it shows so far

- Descriptive (v0.2, timed rows): subway closures come with very heavy rain; crowd "no water" reports with moderate rain.
- **Benchmark B1** (subway closure from rain, leave one event out): **no evidence either way**. Only 3 events have both labels and
  gauge rain; two of them are all-closed lists, and the 2022 "no water" list falls in the gauge gap. Lesson: collect explicit open and
  not-waterlogged statements during events the gauges cover, with the time each status applied.

## Known gaps

No gauge rain for 2020–2022 or after Feb 2026; 247 of 7,010 rows timed to the day or better; 16 news rows link to subways without a
position; 9 place names unmatched on purpose; news favours closures and well-known subways; publication time only bounds when a
status applied. Sources found but not added (need downloads or requests): OpenCity depth points, IIT Madras depth logs, drain maps,
Groundsource, live CFM-DSS polling.
