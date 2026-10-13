# scripts

Every experiment and data-build step is a script here with a pinned seed (where randomness is involved), writing results to
`data/results/<date>-<task>/` (see `CLAUDE.md` §7). Install dependencies with `pip install -r scripts/requirements.txt` (kept separate
from `server/requirements.txt`, the FastAPI server's own production list). Tests are in `scripts/tests/`.

Scripts stay in this one folder on purpose: they import each other (`from sus_train import ...`), many compute the repository root from
their own location, and the decision records and pre-registrations cite them by path. Moving them would break those, so the index below
groups them instead.

## Map packs and routing graph
| Script | Does |
|---|---|
| `build_packs.py` | Compact binary map pack for the app and router service (PLAN M2.1) |
| `region_pack.py` | Map pack for a large region straight from a Geofabrik extract (ADR-020) |
| `city_pipeline.py` | Map pack for any city in `config/cities.yaml` (ADR-018) |
| `build_places.py` | A city's search gazetteer from the OSM extract |
| `fetch_chennai_drivable_ways.py` | Chennai's drivable OSM ways with geometry (live Overpass; unpinned) |
| `india_survey.py` | Phase-1 survey: size of Tamil Nadu's road network (ADR-020) |
| `t1_3_build_graph_and_prior.py` | Chennai routing graph and the static hazard prior (T1.3) |
| `t1_3_make_choropleth_data.py` | Compact choropleth data from the per-edge prior |
| `make_root_dockerfile.py` | Writes the root `Dockerfile` and `.dockerignore` from `deploy/single/` |
| `smoke_deploy.py` | Smoke test of a running deployment, local or live URL |

## Replay corpus and Studies 1 and 2 (route quality, calibration)
| Script | Does |
|---|---|
| `t31_build_replay_corpus.py` | Replay corpus from the 2015 flood data (T3.1) |
| `t31_plot_check.py` | Throwaway spatial sanity-check plot for the corpus |
| `t3_2_replay_engine.py` | Deterministic replay engine (T3.2) |
| `study_common.py` | Shared helpers for both studies |
| `study1_route_quality.py`, `study1_rescore.py` | Study 1 and its re-scoring under one reference belief |
| `study2_calibration.py` | Study 2 |
| `tw1_build_watchlist.py` | Watchlist from the KML hazard zones (T-W1) |
| `t0_2_graph_timing.py`, `t0_5_watchlist_feasibility.py` | Week-1 de-risking spikes (throwaway) |

## Flood data and the nationwide district model (ADR-023, ADR-025)
| Script | Does |
|---|---|
| `build_india_flood_dataset.py` | Merged Indian flood events (ADR-023) |
| `fetch_training_sources.py`, `profile_training_sources.py` | Fetch and describe the approved training sources |
| `nw_build_registry.py`, `nw_geocode.py` | Districts and district-event pairs; a point per district |
| `nw_fetch_rain.py`, `nw_fetch_power.py`, `nw_pack_power.py` | Daily rainfall per district (Open-Meteo, then NASA POWER) and packing |
| `nw_train.py` | Train and evaluate the district flood-event model |

## Terrain and flood susceptibility (ADR-026, ADR-033, ADR-034)
| Script | Does |
|---|---|
| `dem_fetch.py`, `gfd_fetch.py` | Copernicus 90 m elevation tiles; Global Flood Database maps |
| `hydrology.py` | Depression filling, flow direction and accumulation |
| `sus_build.py`, `sus_build_a2.py`, `sus_build_a3.py` | Chennai grid features: terrain, hydrology, OpenStreetMap |
| `extract_osm_chennai.py` | Buildings, land use, waterways and water from the OSM extract (needs the separate osm environment) |
| `sus_train.py`, `sus_train_a2.py`, `sus_train_a3.py` | Chennai models, parts A, A2, A3 |
| `sus_national_freeze.py`, `sus_national_build.py`, `sus_national_build_v2.py`, `sus_national_train.py` | Nationwide terrain model, part B |
| `sus_c3_grid.py`, `sus_c3_eval.py`, `sus_c3_router.py` | Nationwide model applied to Chennai, part C3 |
| `sus_router_eval.py`, `sus_router_round2.py` | Routing tests with learned priors |
| `sus_stress.py`, `model_scorecard.py` | Stress test and scorecard of the trained models |

## Event state, forecast and accidents (ADR-027, ADR-029, ADR-032)
| Script | Does |
|---|---|
| `imerg_rule_replay.py` | Replay the event-state rule over satellite rain |
| `forecast_rule_replay.py` | Replay the forecast rule |
| `accident_yearly_summary.py` | Check the Greater Chennai Police yearly crash totals |

## Field log and subways (ADR-028, ADR-031)
| Script | Does |
|---|---|
| `build_subway_list.py`, `extract_osm_subways.py`, `build_fieldlog_sites.py` | Subway watchlist and the site list the field log serves |
| `subway_board.py` | Internal board: what volunteers last saw at each subway |
| `fieldlog_ops.py`, `fieldlog_merge.py` | Operator tools; restore entries from phone exports |
| `cfm_live_probe.py` | One approved probe of the Chennai Flood Monitor service |

## One-offs
| Script | Does |
|---|---|
| `make_progress_doc.py` | Writes the week-1 progress document (`Week1_Progress.docx`, git-ignored) |
