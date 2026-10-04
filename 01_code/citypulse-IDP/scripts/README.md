# scripts

Every experiment and data-build step is a script here with a pinned seed (where randomness is
involved), writing results to `data/results/<date>-<task>/` — see `CLAUDE.md` §7. Install
dependencies with `pip install -r scripts/requirements.txt` (kept separate from
`server/requirements.txt`, which is the FastAPI server's own production dependency list).

- `t0_2_graph_timing.py` — T0.2 de-risking spike (graph build + query timing). Throwaway;
  writes `data/osm/chennai_graph.sqlite` (weighted edges only, no coordinates).
- `t0_5_watchlist_feasibility.py` — T0.5 de-risking spike (watchlist point-count feasibility).
- `fetch_chennai_drivable_ways.py` — fetches Chennai's drivable OSM ways **with geometry**
  from Overpass (live/unpinned snapshot; see its own docstring) to
  `data/osm/chennai_overpass_drivable.json`.
- `tw1_build_watchlist.py` — T-W1's automatable pipeline: KML parsing, clustering, Michaung
  press-lead cross-checking, OSM-edge snapping, and a coarse basin-label heuristic. See its
  own docstring for exactly what it does and does not complete of T-W1's full acceptance
  criteria (the resident map review is not automatable and is not attempted here).
- `make_progress_doc.py` — generates the week-1 progress document.
