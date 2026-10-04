# Data Access Log

Every request for a data source: what, when, to whom, status. Tier 2 sources have low success
rates, so the log is how we know when to stop waiting and fall back to the replay corpus.

| Date | Source | Contact / route | Status | Notes |
|---|---|---|---|---|
| | IMD API whitelisting | | not started | needs VIT letter + fixed egress IP; ~40% in 7 weeks |
| | NDMA SACHET CAP feeds | | not started | may be genuinely open — verify URLs first; ~60% |
| | Google Flood Forecasting API | waitlist | not started | ~10%; Google says "several months" |
| | IIT Madras Chennai Water Logging | academic email | not started | ~35%, highest value if granted |
| 2026-09-17 | OpenCity — "Chennai Floods 2015 Data" (C13), dataset page `https://data.opencity.in/dataset/chennai-floods-2015-data` | Direct CKAN KML download, no auth, no card | **Obtained.** T3.1 replay corpus. | Downloaded 4 of 7 KML resources to `data/corpus_raw/`: `gcc_stagnation_2015.kml` (753 placemarks, HTTP 200), `crowd_sourced_flooding_2015.kml` (7,894 placemarks, HTTP 200), `gcc_flood_hotspots_2015.kml` (327 placemarks, HTTP 200), `nrsc_inundation_zone_2015.kml` (4,001 polygons, HTTP 200 — downloaded but **not** normalised into observations, see `data/corpus/2026-09-17/MANIFEST.md`). All four verified well-formed XML after download (one initial curl of the NRSC file completed mid-check — re-verified against `Content-Length` before use). Tiruvallur/Vellore/Kancheepuram district hotspot KMLs on the same page were **not** downloaded — out of Chennai/GCC scope. Public Domain per OpenCity; source org GCC & crowd-sourced, per `research/raw/C-data-sources.md` line 56 (C13). **Known gap, not fixed:** none of the 3 used KMLs carry a per-point date field — corpus uses one documented corpus-wide proxy timestamp instead of per-event dates (flagged loudly in `data/corpus/2026-09-17/MANIFEST.md` and `data/results/2026-09-17-t31-corpus/result.json`). |
