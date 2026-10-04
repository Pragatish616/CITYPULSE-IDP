# India flood events, merged (2026-10-04)

A merged event dataset built from two free sources by `scripts/build_india_flood_dataset.py` (ADR-023).
**Research use only: every row is non-commercial.** Counts are in `result.json`; every input is pinned by SHA-256 there.

## Files

| File | What it is |
|---|---|
| `raw/India_Flood_Inventory_v3.csv` | IFI v4 event table: 6,876 IMD flood events, 1967 to 2023. District names and LGD codes; **no coordinates**. |
| `raw/DFSI.csv`, `raw/District_FloodedArea.csv`, `raw/District_FloodImpact.csv` | IFI v4 district tables (severity index, flooded area, impacts) |
| `raw/dfo_india_events.geojson` | 296 Dartmouth Flood Observatory event polygons touching India, 1985 to 2021 |
| `events.ndjson` | One row per source event from both sources (7,172 rows), common fields |
| `dfo_events.geojson` | The DFO polygons keyed by `event_id` |
| `district_summary.csv` | One row per district: DFSI, flooded area, fatalities, population, mean duration, IFI event counts |
| `tn_event_calendar.csv` | Tamil Nadu events from both sources, clustered by the link rule |
| `links_tn.csv` | Every IMD-DFO link behind the calendar |
| `result.json` | Counts, link rule, input hashes, the Chennai 2015 check, limits |

## Sources, attribution and licences

| Source | Where | Licence |
|---|---|---|
| India Flood Inventory v4 (IMD events, district tables) | Zenodo, [doi:10.5281/zenodo.16994648](https://zenodo.org/records/16994648), downloaded 2026-10-04. Cite: Saharia, M., et al. (2025), *District-level flood severity index for flood management*, Natural Hazards | CC BY-NC 4.0 |
| Dartmouth Flood Observatory, Global Active Archive of Large Flood Events | [floodobservatory.colorado.edu](https://floodobservatory.colorado.edu/Archives/index.html), queried 2026-10-04 from the observatory's public ArcGIS feature service (layer metadata states no licence) | CC BY 3.0 for older events; CC BY-NC-SA 4.0 for recent ones, per the observatory's site. **Treated as non-commercial and share-alike.** |

Because of the share-alike term, this merged dataset should be redistributed under CC BY-NC-SA 4.0 conditions, with attribution
to both sources. It is separate from the project's MIT-licensed code. **A product build must filter out every row with
`commercial_use: false`, which today means all of them.**

## What it is and is not

- District-level and region-level evidence of **when** and **where** (roughly) floods happened and **how bad** they were.
- Not street-level. Not live. Not a passability record.
- IFI has 3,770 of 6,876 events with a fatality count; all 296 DFO events have one. The counts come from different
  reporting chains and are **never added**.
- DFO polygons are hand-drawn and cover large regions. The Dec 2015 Tamil Nadu event polygon does not even contain
  the Chennai headquarters point (see `result.json`, `chennai_2015`).
- District points exist for Tamil Nadu only (OSM place names from the Tamil Nadu pack, not boundaries). Other states are
  in `events.ndjson` and `district_summary.csv` but cannot be linked spatially yet.
- Clusters can chain: the 2015 Tamil Nadu cluster joins seven IMD events through one DFO polygon.
