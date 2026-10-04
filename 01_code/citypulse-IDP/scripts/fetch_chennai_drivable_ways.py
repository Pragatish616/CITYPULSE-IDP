"""
Fetch Chennai's drivable OSM ways, WITH geometry, to data/osm/chennai_overpass_drivable.json.

**Why this script exists (added 2026-09-14, review pass).** An independent review of
scripts/tw1_build_watchlist.py found that data/osm/chennai_overpass_drivable.json -- the file
every one of T-W1's OSM-edge snaps depends on -- had no generating script anywhere in the repo,
and tw1_build_watchlist.py's own comment claiming it was "fetched by T0.2" was false: the real,
committed T0.2 spike (scripts/t0_2_graph_timing.py) fetches Overpass responses WITH geometry
(`out geom;`) per highway-class chunk, but only ever extracts (from_node, to_node, weight)
triples into data/osm/chennai_graph.sqlite -- it deliberately discards every coordinate to keep
memory bounded, and never writes the raw geometry to disk. The orphaned JSON file was almost
certainly a byproduct of one of T0.2's own documented earlier, abandoned attempts, saved by
hand or by an earlier agent and never given a real generating script. This is exactly the
"result committed without its generating script" failure docs/REVIEW_CHECKLIST.md section 4
exists to catch.

This script closes that gap by reusing T0.2's own proven, memory-safe pattern (same bbox, same
per-highway-class chunking, same `out geom;` query shape) but keeping the geometry this time
instead of discarding it.

**What this is not: a pinned snapshot.** Like T0.2's own script says of itself ("REMAINING
DEVIATION: Overpass returns live OSM data, not a pinned dated snapshot"), a re-run of this
script on a different day can return different data -- new edits, a renumbered way id, a
slightly different edge count. Every way_id downstream of this file (in particular
scripts/tw1_build_watchlist.py's watchlist candidates) is provisional for exactly this reason,
and should be treated as needing re-resolution once T1.3's real graph build exists, from the
pinned Geofabrik extract (data/osm/southern-zone-260911.osm.pbf, dated 2026-09-11) rather than
live Overpass. This script's own JSON output embeds Overpass's `osm3s.timestamp_osm_base` field
precisely so a reader can always see which live snapshot any given run actually captured.

Usage: .venv/Scripts/python.exe scripts/fetch_chennai_drivable_ways.py
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import ijson
import requests

ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = ROOT / "data" / "osm" / "chennai_overpass_drivable.json"

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
# Identical to scripts/t0_2_graph_timing.py's BBOX and CLASS_GROUPS -- same drivable-network
# definition, so this file and that spike's chennai_graph.sqlite describe the same roads.
BBOX = {"min_lat": 12.75, "max_lat": 13.25, "min_lon": 79.95, "max_lon": 80.35}
CLASS_GROUPS = [
    ["motorway", "trunk", "primary", "motorway_link", "trunk_link", "primary_link"],
    ["secondary", "tertiary", "secondary_link", "tertiary_link"],
    ["unclassified"],
    ["residential"],
]
HEADERS = {"User-Agent": "CityPulse-IDP-week2-tw1/0.1 (VIT Chennai research project)"}


def fetch_chunk(classes: list[str], bbox: dict | None = None) -> bytes:
    bbox = bbox or BBOX
    query = f"""
[out:json][timeout:180];
(
  way["highway"~"^({"|".join(classes)})$"]
     ({bbox['min_lat']},{bbox['min_lon']},{bbox['max_lat']},{bbox['max_lon']});
);
out geom;
"""
    # The public Overpass instance is rate-limiting and/or under load right now (429s and a
    # 504 both hit during this script's own development) -- retry both as transient, with the
    # server's own Retry-After header where given, else exponential backoff.
    for attempt in range(8):
        try:
            resp = requests.post(
                OVERPASS_URL, data={"data": query}, headers=HEADERS, timeout=200
            )
        except requests.exceptions.RequestException as exc:
            wait_s = 20 * (attempt + 1)
            print(
                f"  request error ({exc!r}), waiting {wait_s}s (attempt {attempt + 1}/8)..."
            )
            time.sleep(wait_s)
            continue
        if resp.status_code not in (429, 504):
            resp.raise_for_status()
            return resp.content
        wait_s = int(resp.headers.get("Retry-After", 0)) or (20 * (attempt + 1))
        print(f"  {resp.status_code}, waiting {wait_s}s (attempt {attempt + 1}/8)...")
        time.sleep(wait_s)
    resp.raise_for_status()
    return resp.content


def main() -> None:
    fetch_ways(BBOX, OUT_PATH, "scripts/fetch_chennai_drivable_ways.py")


def fetch_ways(bbox: dict, out_path: Path, generator: str) -> None:
    """Fetch every drivable way in `bbox` (same classes, same retry/courtesy behaviour as the
    original Chennai run) and write them to `out_path`. Used by scripts/city_pipeline.py (ADR-018)."""
    all_elements: list[dict] = []
    osm3s = None
    for i, classes in enumerate(CLASS_GROUPS):
        if i > 0:
            time.sleep(
                30
            )  # courtesy delay -- the endpoint rate-limited/504'd repeatedly
        print(f"Fetching {classes} ...")
        t0 = time.perf_counter()
        raw = fetch_chunk(classes, bbox)
        print(
            f"  {len(raw) / 1e6:.1f} MB in {time.perf_counter() - t0:.1f}s, parsing..."
        )

        # Stream-parse rather than json.loads() the whole response, per T0.2's own documented
        # memory lesson on this machine -- never hold more than one chunk's raw bytes at once.
        n_before = len(all_elements)
        for el in ijson.items(raw, "elements.item"):
            if el.get("type") != "way":
                continue
            geometry = el.get("geometry")
            if not geometry or len(geometry) < 2:
                continue
            all_elements.append(
                {
                    "type": "way",
                    "id": int(el["id"]),
                    "nodes": [int(n) for n in el.get("nodes", [])],
                    "geometry": [
                        {"lat": float(g["lat"]), "lon": float(g["lon"])}
                        for g in geometry
                    ],
                    "tags": el.get("tags", {}),
                }
            )
        print(f"  kept {len(all_elements) - n_before} ways with geometry")

        if osm3s is None:
            for meta in ijson.items(raw, "osm3s"):
                osm3s = meta
                break

    out = {
        "version": 0.6,
        "generator": f"{generator} (Overpass API, live/unpinned)",
        "osm3s": osm3s,
        "bbox": bbox,
        "class_groups": CLASS_GROUPS,
        "elements": all_elements,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f)

    print(f"\nWrote {len(all_elements)} ways to {out_path}")
    if osm3s:
        print(f"Overpass snapshot timestamp: {osm3s.get('timestamp_osm_base')}")


if __name__ == "__main__":
    main()
