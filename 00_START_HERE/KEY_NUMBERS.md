# Key numbers and their sources

Use these exact values. Each one is reproducible from the file named in the right-hand column.

| Quantity | Value | Source |
|---|---|---|
| Graph nodes / directed edges | 193,191 / 471,240 | `01_code/citypulse-IDP/data/graph/2026-09-14/chennai_graph_cli.json` |
| GCC hazard-zone polygons | 7,453 | `data/watchlist_raw/chennai_flood_hazard_zones.kml`, `scripts/t1_3_build_graph_and_prior.py` |
| Prior defaults | 0.02–0.45, 600 m radius | same script |
| Replay observations | 6,132 (5,379 flood, 753 waterlogging; 1,080 official, 5,052 crowd) | `data/corpus/2026-09-17/` |
| Observation timestamp | all 2015-12-02T00:00Z; no depth; all positive | same |
| Snap distance | median 2.9 m, P90 23.6 m | `data/results/2026-09-17-t31-corpus/result.json` |
| Hazard-config edges | 14,534 (5,775 observed + 8,759 prior-only with p0 ≥ 0.25); 124 two-class conflicts resolved | `scripts/t3_2_replay_engine.py`, `07_reanalysis/` |
| Observed edges with an unpenalised reverse twin | 5,177 of 5,775 (2 twins carry evidence) | deep review D4-F3 |
| Router CLI time | about 3.07 s per call (graph reload) | `data/results/2026-09-18-study1-route-quality/result.json` (`measured_seconds_per_cli_call`) |
| Study 1 pairs and seed | 100 OD pairs, seed 20260918 | `scripts/study1_route_quality.py` |
| C3 default effect | 7/100 routes changed; +0.026 s free-flow [0.003, 0.061]; Σp̄ change −0.085 [−0.250, 0.002], **inconclusive** | `07_reanalysis/reanalysis_result.json` |
| C1 block at 0.5 | 30/100 changed; +27.3 s [16.9, 38.9]; 1.53% mean detour, 6.2% P90 | same |
| Σp̄ per route | C0 1.61 · C1 1.22 · hybrid 0.79 · C3 λ=5 0.98 · C3 λ=20 0.44 · C3 z=2 λ=20 0.18 | same, plus deep review D3 defence |
| Observed / prior-only split of Σp̄ | C0 1.03 / 0.57 · C1 0.71 / 0.51 · C3 λ=5 0.75 / 0.23 | D3 defence |
| Held-out official edges per route | C0 1.27 · prior λ=5 1.07 · prior+crowd λ=5 1.09 · prior λ=20 0.86 · prior+crowd λ=20 0.91 | D3 defence |
| Pessimistic index dip (p0 = 0.05) | z=1.28: 0.329 → 0.309 → 0.333 → 0.380; z=2: 0.486 → 0.441 → 0.461 → 0.509 | D4 findings and defence |
| Crossover reliability α* | about 0.63 (z=1.28), about 0.645 (z=2) | same |
| Study 2 rows | 34,256 = 4,876 crowd edges × 6 ages + 5,000 report-free negatives; 708 positives | D3-F17 |
| Study 2 Brier | C3 0.0343, C2 0.0344, C4 0.0367, Beta 0.2921; climatology 0.0202 | `data/results/2026-09-18-study2-calibration/result.json` |
| Brier skill score | C3 −0.70, C4 −0.81, Beta −13.4 | D3 defence |
| AUROC | C3 0.609 pooled, 0.566 crowd pool; inside GCC coverage 0.455 (prior 0.456); edge length alone 0.651 | D3 findings |
| Prior vs C3 Brier, crowd pool, age 0 | 0.0361 vs 0.0478 | D3 defence |
| Automated tests | about 290 (README says 250+) | review count S8 |
| Prior file size | 152 MB | `data/graph/2026-09-14/chennai_prior_ell0.json` |


## 2 October 2026 re-run (fixed router; new section, the rows above are unchanged)

Source for each row: `01_code/citypulse-IDP/data/results/2026-10-02-study1-rescored/result.json` unless stated. The reference belief is the Beta posterior mean, so these are not comparable with the sum-of-p rows above.

| Quantity | Value | Source |
|---|---|---|
| Study 1 pairs | 1000 (first 100 identical to the 2026-09-18 sample), seed 20260918; 0 disconnected under all 9 configurations | `2026-10-02-study1-route-quality/result.json` |
| Sum of reference p-mean per route, 1000 pairs | C0 2.013 · C1 1.983 · hybrid 1.435 · C3 default 1.973 · C3 λ=5 1.479 · C3 λ=20 0.795 | rescored |
| Share of routes touching p-mean ≥ 0.5 | C0 14.8% · C1 0% · hybrid 0% · C3 default 11.5% · C3 λ=5 7.5% · C3 λ=20 2.5% | rescored |
| Mean free-flow detour | C1 0.49% · hybrid 1.35% · C3 default 0.01% · C3 λ=5 0.85% · C3 λ=20 6.27% | rescored |
| Routes changed vs C0 (of 1000) | C1 148 · hybrid 445 · C3 default 118 · C3 λ=5 418 · C3 λ=20 697 | rescored |
| C3 λ=5 minus hybrid, sum of p | +0.045 [+0.019, +0.072] (C3 slightly worse) | rescored |
| Held-out official edges per route, crowd minus prior-only | λ=5 +0.081 [0.039, 0.126] · λ=20 +0.107 [0.058, 0.159] | rescored |
| Study 2 rows | 9,336 crowd edges × 6 ages = 56,016; with 5,000 report-free edges 61,016 rows, 1,356 positives | `2026-10-02-study2-calibration/result.json` |
| Study 2 crowd-pool Brier (skill vs prior) | prior 0.0361 · C3 0.0415 (−0.15) · fixed TTL 0.0464 (−0.285) · Beta reputation 0.2995 | same |
| Study 2 crowd-pool AUROC | prior 0.569 · C3 0.546 | same |
| Study 2 age-0 Brier | prior 0.0361 · C3 0.0567 | same |
| Verifier on the authored set | false accepts 150/209 (71.8%) to 0/209; false rejects 0/27; the set is not independent | `data/results/2026-10-02-verifier/result.json` |
| Test counts, 3 Oct 2026 | belief 44 · router 146 · explain 82 · router_api 23 · server 38 · app 130 · Python scripts 60 | test runs in this session |

## 3 October 2026: travel modes (placeholder profiles; model output, not measured travel)

Source: `01_code/citypulse-IDP/data/results/2026-10-03-travel-modes-arterial-emergency/result.json` (seed 20261003, 296 random node pairs with a car route, static GCC prior, no reports).

| Quantity | Value |
|---|---|
| Median speed by mode | car 46.8 km/h · bicycle 14.0 · on foot 4.9 · emergency 62.8 |
| Median trip time | car 31.9 min · bicycle 109.4 · on foot 287.3 · emergency 24.7 (median trip 25 km: random node pairs across the city) |
| Route differs from the car route | on foot 296/296 · bicycle 296/296 · emergency 112/296 (38%) dry, 122/296 (41%) in an active flood event |
| Same, flat 1.3 emergency factor (superseded) | emergency 1/296 dry, 24/296 flood event (`2026-10-03-travel-modes/`) |
| One trip, T. Nagar to Velachery (before: all modes 14.9 min) | car 14.9 min / 10.6 km · bicycle 51.2 / 10.4 · on foot 98.3 / 7.9 · emergency 11.3 / 11.2 |

## Tamil Nadu main-road region (ADR-020, 2026-10-03)

| Quantity | Value |
|---|---|
| Survey: motorway to secondary inside the box | 76,802 ways, 73,375 km (`data/results/2026-10-03-india-survey-tamil_nadu/result.json`) |
| Estimated pack from Chennai's ratio vs built | 1,298,218 edges / 42.7 MB estimated; **257,249 edges / 9.0 MB built** (estimate about five times too high for a rural network) |
| Pack | 143,227 nodes · 257,249 directed edges · 8,438 distinct street names · 25,144 places (39 cities, 571 towns, 23,013 villages, 1,521 suburbs) |
| One statewide route (Chennai to the far south) | 693.1 km, 11 h 46 min · 1,278 points, 65.3 KB · 291-305 ms on the server |
| Test counts after ADR-020 | pulse_router 165 · router_api 25 · app 144 · Python 104 |

## Route advisor (ADR-021, 3 October 2026)

| Quantity | Value |
|---|---|
| Cost of one piece of advice | 1.5-1.7 microseconds per call, 100,000 calls, authoring laptop (`route_advisor_test.dart`); phone not measured |
| Advisor tests | 20 (`pulse_router`) + 5 (`advice_card_test.dart`) |
| Status of the weights | hand-set placeholders; outputs are scores, not measured frequencies |

## Combined Chennai + Tamil Nadu (ADR-022, 3 October 2026)

| Quantity | Value |
|---|---|
| Route inside Chennai (T. Nagar to Velachery) | 9.3 km, advice shown, 139 ms (first call) on the server |
| Chennai to Madurai | 447.1 km, 7 h 35 min, no advice, 263-298 ms |
| Test counts | pulse_router 188 · router_api 32 · app 153 |

## Merged India flood events (ADR-023, 4 October 2026)

| Quantity | Value |
|---|---|
| Events | 7,172 = 6,876 IMD (1967-2023, no coordinates) + 296 DFO polygons (1985-2021) |
| Tamil Nadu | 188 IMD events; 172 calendar rows after linking; 15 seen by both sources; 47 name Chennai |
| Links | 31 (date +-3 days and the DFO polygon contains a named district's headquarters point) |
| Chennai District Flood Severity Index | 16.62: 2nd of 37 in Tamil Nadu, 117th of 743 in India |
| Replay proxy date 2015-12-02 | inside the IMD Chennai event of 1-3 December 2015 |
| Source | `data/india_flood/2026-10-04/result.json` |

## Training-source profile (ADR-024, 4 October 2026)

| Quantity | Value |
|---|---|
| Daily rain gauges, every year 1988 to 2019 | 53 stations, about 19,300 rows a year; none for 2020 to 2022; 41 to 51 stations for 2023 to 2026 |
| Chennai-named IMD events in 1988 to 2019 | 33 events, 354 event-days of 11,688 (3%) |
| Citizen flood reports | 173; 161 are level 1; 12 are level 2 or more (9 inside Chennai); 3 contain "test" |
| Spatial flood labels | 2015: 327 GCC hotspots, 4,001 extent polygons; 2005: 200 depth points, 235 extent polygons; 2020: 53 hotspots |
| NYC FloodNet | 3,422 events, 318 sensors, 2020-11 to 2026-09; median peak depth 3.48 in; 8% reach 12 in |
| Source | `data/chennai_cfm/2026-10-04/profile.json`, `data/nyc_floodnet/2026-10-04/profile.json` |

## Nationwide district flood-event model (ADR-025, 4 October 2026)

| Quantity | Value |
|---|---|
| Districts and states with a point | 592 of 948 names; 29 states; 77.2% of 17,787 district-event pairs |
| Rows | train 4,324,560 (1.35% positive), validation 1,297,072, test 1,729,824 (4.45% positive, 77,002) |
| Test average precision | model 0.090 (0.057, 0.126); month-rate baseline 0.097; 3-day-rain rule 0.066 |
| Test event recall at a 2% alert budget | model 0.326; month-rate 0.206; 3-day-rain rule 0.356 |
| State-holdout mean AP | model on unseen states 0.0506; best baseline 0.0497 |
| Verdict against the pre-registered rule | **no evidence of added value** |
| Source | `data/results/2026-10-04-nationwide-flood-gating/result.json` |
