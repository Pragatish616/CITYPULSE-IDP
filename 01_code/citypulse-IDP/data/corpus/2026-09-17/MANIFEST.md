# T3.1 -- Replay Corpus Manifest

Generated: 2026-09-17
Source dataset: OpenCity "Chennai Floods 2015 Data" (C13), https://data.opencity.in/dataset/chennai-floods-2015-data, downloaded 2026-09-17 (see docs/data-access-log.md)

## Counts by hazard_class

| hazard_class | count |
|---|---|
| flood | 5379 |
| waterlogging | 753 |

## Counts by source_class

| source_class | count |
|---|---|
| crowd | 5052 |
| official_feed | 1080 |

## Time histogram (daily bins)

**Single spike, not a distribution -- this is a real data limitation, not a bug.** None of the three source KMLs carry a per-point date; every observation is stamped with the same documented corpus-wide proxy `2015-12-02T00:00:00Z` (see the build script's top comment for sourcing). A finer-grained histogram would misrepresent precision the source data does not have.

| date (UTC) | count |
|---|---|
| 2015-12-02 | 6132 |

## KML parsing survival

| source | placemarks in KML | survived to observation |
|---|---|---|
| gcc_stagnation_2015.kml | 753 | 753 |
| gcc_flood_hotspots_2015.kml | 327 | 327 |
| crowd_sourced_flooding_2015.kml | 7894 | 5052 |

Drop reasons:
- stagnation: 0 dropped (missing/unparseable coords or outside Chennai bbox)
- hotspots: 0 dropped (missing/unparseable coords or outside Chennai bbox)
- crowd: 10 excluded (is_flooded=0, not a presence report), 26 dropped (missing coords or outside bbox), 2806 deduplicated (same osm_id already kept -- see build script's CROWD_DEDUP_KEY comment)

## Edge-snapping (against the real T1.3 CSR graph, data/graph/2026-09-14/chennai_prior_ell0.json)

- Candidates offered to the snapper: 6132
- Snapped to a CSR edge: 6132
- Failed to snap within the search radius: 0
- Low-confidence far snaps (>300 m): 29
- Snap distance stats (m): min=0.0, median=2.9, p90=23.6, max=764.9
- No point required manual disambiguation between multiple equally-close edges -- the search always returns a single nearest edge deterministically.

## Assumptions and limitations (flagged per CLAUDE.md section 8.4)

1. **observed_at/received_at are a corpus-wide proxy, not per-point dates** (2015-12-02T00:00:00Z, chosen as the widely-reported acute peak of the 2015 Chennai floods -- Wikipedia "2015 South India floods"; ReliefWeb Situation Report No. 1, "Chennai Flood, 2-4 December 2015"). [UNVERIFIED at per-observation granularity.] If T3.2's replay engine or T3.4's decay calibration need genuine temporal spread within the 2015 event, this corpus cannot currently provide it -- flagging now rather than after it silently breaks a decay-calibration result.
2. **intensity (depth_mm) is deliberately omitted for all observations.** None of these three KMLs carry a measured per-point depth. gcc_flood_hotspots_2015.kml carries categorical inundation-vulnerability bands (e.g. "Low Vulnerability less than 2 feet") preserved verbatim in `raw`, but converting a vulnerability category into a fabricated depth_mm number would misrepresent it as a measurement. C12's separate "Inundation Points with Depth" resource (not used here) is the right source for real depth_mm, per the task card.
3. **accuracy_m values (30 m official_feed / 50 m crowd) are engineering estimates, not sourced from KML metadata** -- none of the three KMLs publish a positional-accuracy field.
4. **way_id is not recorded in the edge_snap_index** -- data/graph/2026-09-14/chennai_prior_ell0.json (T1.3's output) does not carry OSM way_id per edge (verified: its per-edge fields are edge_id/from/to/prior_logodds/prior_p/n_contributing_zones/highway/street_name/geometry only). The crowd-sourced KML's own `osm_id` field is preserved in each observation's `raw` block instead, so the OSM-way identity is not lost, just not cross-linked to edge_id in this file.
5. **NRSC 2015 inundation-zone polygons and the three non-Chennai district hotspot KMLs were downloaded but not normalised into observations** -- see this script's top comment for why.
6. **UUIDv7 is a manual RFC 9562 construction**, not a vetted third-party library -- no uuid6/uuid7 package is declared anywhere in this repo. Structurally correct (48-bit ms timestamp, version 0111, variant 10) but not independently tested against a reference implementation.
