"""
T3.1 -- Replay corpus (docs/IMPLEMENTATION_PLAN.md Phase 3; docs/CONTRACTS.md section 1).

**What this script does.** Normalises three of OpenCity's "Chennai Floods 2015 Data" (C13)
KML resources into `HazardObservation` records (docs/CONTRACTS.md section 1), snapped to the
real Chennai CSR routing graph built by T1.3 (data/graph/2026-09-14/chennai_prior_ell0.json,
which carries edge_id + full geometry -- unlike the CLI graph JSON, which is stripped of
coordinates). Target (task card): >=200 geolocated events.

**Sources used, and why** (data/corpus_raw/, downloaded 2026-09-17 from
https://data.opencity.in/dataset/chennai-floods-2015-data -- see docs/data-access-log.md):
  1. gcc_stagnation_2015.kml       -- "GCC Stagnation Locations in 2015"           -> hazard_class=waterlogging, source_class=official_feed
  2. gcc_flood_hotspots_2015.kml   -- "Chennai 2015 GCC Area Flood Hotspots"       -> hazard_class=flood,        source_class=official_feed
  3. crowd_sourced_flooding_2015.kml -- "Chennai 2015 Crowd-sourced Flooding Locations" -> hazard_class=flood,  source_class=crowd

Three resources on the same dataset page were deliberately NOT converted into observations:
  - "Chennai 2015 Floods Inundation Zone (as per NRSC)" -- satellite-derived flood-extent
    POLYGONS (4001 of them, fields limited to area/perimeter/pixelvalue -- no location name,
    no date, no source-report semantics). This is a validation/cross-reference layer in the
    same spirit as C12's hazard-zone KML used by T1.3's static prior, not a "someone reported
    a hazard here" event. Downloaded to data/corpus_raw/nrsc_inundation_zone_2015.kml for
    future cross-checking but not normalised here. See not_done_still_pending.
  - Tiruvallur / Vellore / Kancheepuram district flood hotspots -- these are neighbouring
    districts, not Chennai city/GCC limits, and out of this project's bounded Chennai scope
    (docs/CHENNAI_PROTOTYPE_SPEC.md). Not downloaded.

**observed_at / received_at -- the hard part, stated loudly, not silently fixed.** None of
the three source KMLs carry a per-point date field (verified structurally: their KML <Schema>
field lists are {timestamp,begin,end,...,OBJECTID,ZONE,DIVISION,LAT,LONG_},
{id,location,inundation_level,...,latitude,longitude} and
{class,oneway,osm_id,type,is_flooded,layer,area,length,l} respectively -- no date/time field
in any of them). Per this task's instruction, no precise per-point timestamp is fabricated.
Instead every observation in this corpus is stamped with a single, documented, corpus-wide
proxy timestamp: **2015-12-02T00:00:00Z** (2015-12-02 05:30 IST), chosen to sit inside the
widely-reported acute peak of the 2015 Chennai floods -- Chembarambakkam reservoir's highest
inflow in 100 years and record discharge into the Adyar river on 1 December 2015, with the
worst inundation across Chennai by the night of 1-2 December 2015 (Wikipedia, "2015 South
India floods"; ReliefWeb Situation Report No. 1, "Chennai Flood, 2-4 December 2015",
https://reliefweb.int/report/india/chennai-floods-situation-report-no-1-chennai-flood-2-4-december-2015).
**This is a source-dataset-level date, not a point-level one** -- it is [UNVERIFIED] at the
per-observation granularity and is flagged as such in MANIFEST.md and here. `received_at` is
set equal to `observed_at` throughout (documented historical-backfill convention -- there is
no real ingestion latency to record for a 2015 archival dataset). A consequence stated
plainly: the corpus's own time histogram is a single spike, not a distribution, because the
source data supports no finer granularity. See docs/DECISIONS.md if this should become a
standing ADR-level caveat.

**Snapping.** Each surviving point is snapped to the nearest directed edge of the real T1.3
CSR graph (data/graph/2026-09-14/chennai_prior_ell0.json), reusing the grid-ring nearest-way
search scripts/tw1_build_watchlist.py already built and had independently reviewed (its
2026-09-14 ring-termination bug-fix is inherited unchanged here). Snapping against the real
edge-indexed graph, rather than the raw Overpass ways T-W1 snapped against, means edge_id
here is exactly `EdgeBelief.edge_id` / `DecisionTrace` `edge_id` (docs/CONTRACTS.md sections
2-3) with no further remapping needed for T3.2.

**UUIDv7.** No uuid6/uuid7 library is declared anywhere in this repo's requirements files
(checked scripts/requirements.txt) and no generator exists in packages/pulse_belief or
packages/pulse_router. This script implements UUIDv7 directly per RFC 9562 (48-bit
millisecond Unix timestamp, 4-bit version 0111, 12 pseudo-random bits, 2-bit variant 10, 62
pseudo-random bits) rather than silently falling back to uuid4 -- this is the "manual
construction" path CLAUDE.md/the task card asks for when no v7 backport is available.

Usage: .venv/Scripts/python.exe scripts/t31_build_replay_corpus.py
"""

from __future__ import annotations

import itertools
import json
import math
import os
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

import ijson
import yaml

ROOT = Path(__file__).resolve().parent.parent
CORPUS_RAW = ROOT / "data" / "corpus_raw"
GRAPH_PATH = ROOT / "data" / "graph" / "2026-09-14" / "chennai_prior_ell0.json"
HAZARD_CLASSES_PATH = ROOT / "config" / "hazard_classes.yaml"
TODAY = datetime.now(tz=timezone.utc).date().isoformat()
OUT_DIR = ROOT / "data" / "corpus" / TODAY
RESULTS_DIR = ROOT / "data" / "results" / f"{TODAY}-t31-corpus"

NS = {"kml": "http://www.opengis.net/kml/2.2"}

# Same Chennai metro bbox T0.5 and T-W1 already use, for consistency.
BBOX = {"min_lat": 12.75, "max_lat": 13.25, "min_lon": 79.95, "max_lon": 80.35}

# Documented corpus-wide proxy timestamp -- see this file's top comment for sourcing.
PROXY_OBSERVED_AT = "2015-12-02T00:00:00Z"

# Grid-ring snap parameters -- same defaults tw1_build_watchlist.py validated.
GRID_CELL_DEG = 0.01
FAR_SNAP_THRESHOLD_M = 300.0

# Crowd-sourced flooding dedup: many LineString sub-segments in the source KML share the same
# `osm_id` (the same real road, split into several short sub-segments by the extraction that
# produced this KML). Counting each sub-segment as an independent "someone reported this road
# flooded" event would overcount a single real report many times over. Deduplicating to one
# observation per unique osm_id (keeping the first sub-segment's midpoint encountered) is a
# principled dedup key here -- unlike tw1's arbitrary-radius spatial clustering, osm_id is a
# real identifier already present in the source data, not a heuristic this script invented.
# Verified before choosing this: in-bbox unique osm_id count (5,052) and in-bbox 150m-grid
# spatial-dedup count (5,300) are within 5% of each other, so osm_id-dedup is not silently
# discarding real spatial diversity relative to the geometric alternative.
CROWD_DEDUP_KEY = "osm_id"


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(a))


def in_bbox(lat: float, lon: float) -> bool:
    return (
        BBOX["min_lat"] <= lat <= BBOX["max_lat"]
        and BBOX["min_lon"] <= lon <= BBOX["max_lon"]
    )


# ---------------------------------------------------------------------------------------
# UUIDv7 -- manual construction, RFC 9562. No uuid6/uuid7 library declared in this repo.
# ---------------------------------------------------------------------------------------

_last_uuid7_ms = 0
_uuid7_seq = 0


def uuid7() -> str:
    """RFC 9562 UUIDv7: unix_ts_ms (48 bits) | ver (4 bits) | rand_a (12 bits) |
    var (2 bits) | rand_b (62 bits). A per-millisecond monotonic counter is folded into
    rand_a so bulk generation within the same millisecond still sorts and stays unique,
    without needing a real monotonic-clock library.
    """
    global _last_uuid7_ms, _uuid7_seq
    ms = int(time.time() * 1000)
    if ms == _last_uuid7_ms:
        _uuid7_seq += 1
    else:
        _uuid7_seq = 0
        _last_uuid7_ms = ms
    rand_a = _uuid7_seq & 0xFFF
    rand_b = int.from_bytes(os.urandom(8), "big") & ((1 << 62) - 1)

    b = bytearray(16)
    b[0:6] = ms.to_bytes(6, "big")
    b[6] = 0x70 | ((rand_a >> 8) & 0x0F)
    b[7] = rand_a & 0xFF
    b[8] = 0x80 | ((rand_b >> 56) & 0x3F)
    b[9:16] = (rand_b & ((1 << 56) - 1)).to_bytes(7, "big")
    h = b.hex()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


# ---------------------------------------------------------------------------------------
# Source parsing
# ---------------------------------------------------------------------------------------


def load_stagnation() -> list[dict]:
    """GCC Stagnation Locations in 2015 -- Point placemarks, fields LAT/LONG_/ZONE/DIVISION."""
    path = CORPUS_RAW / "gcc_stagnation_2015.kml"
    tree = ET.parse(path)
    out = []
    n_total = 0
    n_dropped_bbox = 0
    for pm in tree.getroot().findall(".//kml:Placemark", NS):
        n_total += 1
        fields = {sd.get("name"): sd.text for sd in pm.findall(".//kml:SimpleData", NS)}
        try:
            lat, lon = float(fields["LAT"]), float(fields["LONG_"])
        except (KeyError, TypeError, ValueError):
            n_dropped_bbox += 1
            continue
        if not in_bbox(lat, lon):
            n_dropped_bbox += 1
            continue
        out.append(
            {
                "hazard_class": "waterlogging",
                "source_class": "official_feed",
                "source_id": "opencity.gcc_stagnation_2015",
                "lat": lat,
                "lon": lon,
                "accuracy_m": 30.0,
                "raw": {
                    "kml_source": "gcc_stagnation_2015.kml",
                    "objectid": fields.get("OBJECTID"),
                    "oid": fields.get("OID_"),
                    "zone": fields.get("ZONE"),
                    "division": fields.get("DIVISION"),
                },
            }
        )
    return out, {
        "n_placemarks": n_total,
        "n_dropped_bad_or_out_of_bbox": n_dropped_bbox,
    }


def load_hotspots() -> list[dict]:
    """Chennai 2015 GCC Area Flood Hotspots (Chennai SDSS) -- Point placemarks with
    categorical inundation-vulnerability bands (not a measured depth -- see this file's top
    comment on why `intensity` is deliberately left unset for these).
    """
    path = CORPUS_RAW / "gcc_flood_hotspots_2015.kml"
    tree = ET.parse(path)
    out = []
    n_total = 0
    n_dropped_bbox = 0
    for pm in tree.getroot().findall(".//kml:Placemark", NS):
        n_total += 1
        fields = {sd.get("name"): sd.text for sd in pm.findall(".//kml:SimpleData", NS)}
        try:
            lat, lon = float(fields["latitude"]), float(fields["longitude"])
        except (KeyError, TypeError, ValueError):
            n_dropped_bbox += 1
            continue
        if not in_bbox(lat, lon):
            n_dropped_bbox += 1
            continue
        out.append(
            {
                "hazard_class": "flood",
                "source_class": "official_feed",
                "source_id": "opencity.gcc_flood_hotspots_2015",
                "lat": lat,
                "lon": lon,
                "accuracy_m": 30.0,
                "raw": {
                    "kml_source": "gcc_flood_hotspots_2015.kml",
                    "id": fields.get("id"),
                    "location": fields.get("location"),
                    "inundation_level": fields.get("inundation_level"),
                    "vulnerability": fields.get("vulnerability"),
                    "inundation_ft_band": fields.get("inundation_ft"),
                    "zone": fields.get("zone"),
                    "ward": fields.get("ward"),
                },
            }
        )
    return out, {
        "n_placemarks": n_total,
        "n_dropped_bad_or_out_of_bbox": n_dropped_bbox,
    }


def load_crowd() -> tuple[list[dict], dict]:
    """Chennai 2015 Crowd-sourced Flooding Locations -- LineString placemarks, each already
    carrying the source `osm_id` of the flooded road. `is_flooded` is 0 for a small control
    set (10 of 7,894) -- only `is_flooded == 1` are presence (`polarity: 1`) reports; the
    handful of `is_flooded == 0` rows are evidence-of-absence candidates but are OUT OF SCOPE
    here (T3.1's task card asks for hazard events; polarity -1 / absence handling is
    improvement I-02's job, not this script's).
    """
    path = CORPUS_RAW / "crowd_sourced_flooding_2015.kml"
    tree = ET.parse(path)
    n_total = 0
    n_not_flooded = 0
    n_dropped_bbox = 0
    n_dedup_dropped = 0
    seen_osm_ids: set[str] = set()
    out = []
    for pm in tree.getroot().findall(".//kml:Placemark", NS):
        n_total += 1
        fields = {sd.get("name"): sd.text for sd in pm.findall(".//kml:SimpleData", NS)}
        if fields.get("is_flooded") != "1":
            n_not_flooded += 1
            continue
        ls = pm.find(".//kml:LineString/kml:coordinates", NS)
        if ls is None or not ls.text:
            n_dropped_bbox += 1
            continue
        coords = []
        for tok in ls.text.split():
            parts = tok.split(",")
            if len(parts) >= 2:
                coords.append((float(parts[0]), float(parts[1])))
        if not coords:
            n_dropped_bbox += 1
            continue
        lon = sum(c[0] for c in coords) / len(coords)
        lat = sum(c[1] for c in coords) / len(coords)
        if not in_bbox(lat, lon):
            n_dropped_bbox += 1
            continue
        osm_id = fields.get("osm_id")
        dedup_key = osm_id if osm_id else f"noid-{lat:.6f}-{lon:.6f}"
        if dedup_key in seen_osm_ids:
            n_dedup_dropped += 1
            continue
        seen_osm_ids.add(dedup_key)
        out.append(
            {
                "hazard_class": "flood",
                "source_class": "crowd",
                "source_id": "opencity.crowd_2015",
                "lat": lat,
                "lon": lon,
                "accuracy_m": 50.0,
                "raw": {
                    "kml_source": "crowd_sourced_flooding_2015.kml",
                    "osm_id": osm_id,
                    "osm_class": fields.get("class"),
                    "osm_type": fields.get("type"),
                    "oneway": fields.get("oneway"),
                    "segment_length_km": fields.get("length"),
                },
            }
        )
    stats = {
        "n_placemarks": n_total,
        "n_is_flooded_0_excluded": n_not_flooded,
        "n_dropped_bad_or_out_of_bbox": n_dropped_bbox,
        "n_deduped_by_osm_id": n_dedup_dropped,
    }
    return out, stats


# ---------------------------------------------------------------------------------------
# Snap to nearest T1.3 CSR graph edge (reuses tw1_build_watchlist.py's reviewed algorithm,
# adapted to stream chennai_prior_ell0.json's edge records instead of raw Overpass ways).
# ---------------------------------------------------------------------------------------


def point_segment_distance_m(
    p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]
) -> float:
    lat0 = p[0]
    m_per_deg_lat = 111320.0
    m_per_deg_lon = 111320.0 * math.cos(math.radians(lat0))

    def to_xy(pt: tuple[float, float]) -> tuple[float, float]:
        return (pt[1] * m_per_deg_lon, pt[0] * m_per_deg_lat)

    px, py = to_xy(p)
    ax, ay = to_xy(a)
    bx, by = to_xy(b)
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


def load_graph_edges() -> list[dict]:
    """Streams data/graph/2026-09-14/chennai_prior_ell0.json (146 MB) with ijson, same
    reason tw1_build_watchlist.py streams the Overpass ways file: keep this script's memory
    footprint independent of the graph file's size on this machine's limited free RAM.
    """
    edges = []
    with open(GRAPH_PATH, "rb") as f:
        for e in ijson.items(f, "edges.item"):
            geom = e.get("geometry")
            if not geom or len(geom) < 2:
                continue
            pts = [(float(p["lat"]), float(p["lon"])) for p in geom]
            edges.append(
                {
                    "edge_id": int(e["edge_id"]),
                    "street_name": e.get("street_name"),
                    "highway": e.get("highway"),
                    "pts": pts,
                }
            )
    return edges


def build_grid_index(
    edges: list[dict], cell_deg: float
) -> dict[tuple[int, int], list[int]]:
    index: dict[tuple[int, int], list[int]] = {}
    for i, e in enumerate(edges):
        cells = set()
        for lat, lon in e["pts"]:
            cells.add((int(lat / cell_deg), int(lon / cell_deg)))
        for cell in cells:
            index.setdefault(cell, []).append(i)
    return index


def snap_to_nearest_edge(
    point: tuple[float, float],
    edges: list[dict],
    index: dict[tuple[int, int], list[int]],
    cell_deg: float,
) -> dict | None:
    """Grid-ring nearest-edge search -- same termination logic tw1_build_watchlist.py's
    snap_to_nearest_way carries (independently reviewed 2026-09-14 for a ring-termination
    bug): a ring is only safe to stop at once no farther ring could possibly contain
    anything closer than the best match already found.
    """
    lat, lon = point
    cx, cy = int(lat / cell_deg), int(lon / cell_deg)
    m_per_deg = 111_320.0 * math.cos(math.radians(lat))

    best_edge, best_dist = None, None
    max_radius = 60
    for radius in range(max_radius + 1):
        ring_min_dist_m = max(0, radius - 1) * cell_deg * m_per_deg
        if best_dist is not None and ring_min_dist_m > best_dist:
            break

        cell_ids: set[int] = set()
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                if max(abs(dx), abs(dy)) != radius:
                    continue
                cell_ids.update(index.get((cx + dx, cy + dy), []))

        for i in cell_ids:
            edge = edges[i]
            pts = edge["pts"]
            for a, b in itertools.pairwise(pts):
                d = point_segment_distance_m(point, a, b)
                if best_dist is None or d < best_dist:
                    best_dist, best_edge = d, edge

    if best_edge is None:
        return None
    return {
        "edge_id": best_edge["edge_id"],
        "street_name": best_edge.get("street_name"),
        "highway": best_edge.get("highway"),
        "distance_m": round(best_dist, 1),
        "low_confidence_far_snap": best_dist > FAR_SNAP_THRESHOLD_M,
    }


# ---------------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------------


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    with open(HAZARD_CLASSES_PATH, "r", encoding="utf-8") as f:
        hazard_classes_cfg = yaml.safe_load(f)
    valid_classes = set(hazard_classes_cfg["classes"].keys())

    print("Parsing source KMLs (data/corpus_raw/)...")
    stagnation_points, stagnation_stats = load_stagnation()
    print(f"  stagnation: {len(stagnation_points)} survive ({stagnation_stats})")
    hotspot_points, hotspot_stats = load_hotspots()
    print(f"  hotspots:   {len(hotspot_points)} survive ({hotspot_stats})")
    crowd_points, crowd_stats = load_crowd()
    print(f"  crowd:      {len(crowd_points)} survive ({crowd_stats})")

    all_points = stagnation_points + hotspot_points + crowd_points
    for p in all_points:
        assert p["hazard_class"] in valid_classes, p["hazard_class"]
    print(f"Total candidate points after bbox/dedup filtering: {len(all_points)}")

    print(f"Streaming {GRAPH_PATH.name} (this is the slow step, ~146 MB)...")
    t0 = time.time()
    edges = load_graph_edges()
    print(f"  {len(edges)} directed CSR edges loaded in {time.time() - t0:.1f}s")
    index = build_grid_index(edges, GRID_CELL_DEG)

    print("Snapping candidates to nearest CSR edge...")
    t0 = time.time()
    n_snapped = 0
    n_unsnapped = 0
    n_far_snap = 0
    observations = []
    snap_index_records = []
    for p in all_points:
        snap = snap_to_nearest_edge((p["lat"], p["lon"]), edges, index, GRID_CELL_DEG)
        if snap is None:
            n_unsnapped += 1
            continue
        n_snapped += 1
        if snap["low_confidence_far_snap"]:
            n_far_snap += 1

        obs_id = uuid7()
        observation = {
            "id": obs_id,
            "hazard_class": p["hazard_class"],
            "polarity": 1,
            "geometry": {"type": "Point", "coordinates": [p["lon"], p["lat"]]},
            "accuracy_m": p["accuracy_m"],
            "observed_at": PROXY_OBSERVED_AT,
            "received_at": PROXY_OBSERVED_AT,
            "source_class": p["source_class"],
            "source_id": p["source_id"],
            "intensity": None,
            "raw": p["raw"],
            "precision_state": "exact",
            "coarsened_at": None,
        }
        observations.append(observation)
        snap_index_records.append(
            {
                "observation_id": obs_id,
                "edge_id": snap["edge_id"],
                "way_id": None,  # not carried by chennai_prior_ell0.json -- see MANIFEST.md
                "street_name": snap["street_name"],
                "highway": snap["highway"],
                "snap_distance_m": snap["distance_m"],
                "low_confidence_far_snap": snap["low_confidence_far_snap"],
            }
        )
    print(f"  snapped {n_snapped}/{len(all_points)} in {time.time() - t0:.1f}s")

    # ---- write observations (NDJSON: one HazardObservation per line, documented choice --
    # matches the append-only-log framing in docs/CONTRACTS.md section 1 and is what T3.2's
    # replay engine can stream without loading the whole corpus into memory at once) ----
    obs_path = OUT_DIR / "observations.ndjson"
    with open(obs_path, "w", encoding="utf-8") as f:
        f.writelines(json.dumps(obs) + "\n" for obs in observations)

    # ---- write the edge-snap index as a sibling file (outside HazardObservation's strict
    # schema per docs/CONTRACTS.md section 1 -- T3.2 needs edge_id per observation but the
    # schema itself carries no such field) ----
    snap_path = OUT_DIR / "edge_snap_index.json"
    with open(snap_path, "w", encoding="utf-8") as f:
        json.dump(snap_index_records, f, indent=2)

    # ---- counts by class / time histogram (single-bin, honestly, see top comment) ----
    counts_by_class: dict[str, int] = {}
    counts_by_source_class: dict[str, int] = {}
    for obs in observations:
        counts_by_class[obs["hazard_class"]] = (
            counts_by_class.get(obs["hazard_class"], 0) + 1
        )
        counts_by_source_class[obs["source_class"]] = (
            counts_by_source_class.get(obs["source_class"], 0) + 1
        )
    time_histogram = {PROXY_OBSERVED_AT[:10]: len(observations)}

    snap_distances = [r["snap_distance_m"] for r in snap_index_records]
    snap_distances_sorted = sorted(snap_distances)

    def pct(p: float) -> float:
        if not snap_distances_sorted:
            return 0.0
        idx = min(len(snap_distances_sorted) - 1, int(len(snap_distances_sorted) * p))
        return round(snap_distances_sorted[idx], 1)

    manifest_lines = [
        "# T3.1 -- Replay Corpus Manifest",
        "",
        f"Generated: {TODAY}",
        (
            'Source dataset: OpenCity "Chennai Floods 2015 Data" (C13), '
            "https://data.opencity.in/dataset/chennai-floods-2015-data, "
            "downloaded 2026-09-17 (see docs/data-access-log.md)"
        ),
        "",
        "## Counts by hazard_class",
        "",
        "| hazard_class | count |",
        "|---|---|",
    ]
    for k, v in sorted(counts_by_class.items()):
        manifest_lines.append(f"| {k} | {v} |")
    manifest_lines += [
        "",
        "## Counts by source_class",
        "",
        "| source_class | count |",
        "|---|---|",
    ]
    for k, v in sorted(counts_by_source_class.items()):
        manifest_lines.append(f"| {k} | {v} |")
    manifest_lines += [
        "",
        "## Time histogram (daily bins)",
        "",
        (
            "**Single spike, not a distribution -- this is a real data limitation, not a "
            "bug.** None of the three source KMLs carry a per-point date; every observation "
            f"is stamped with the same documented corpus-wide proxy `{PROXY_OBSERVED_AT}` "
            "(see the build script's top comment for sourcing). A finer-grained histogram "
            "would misrepresent precision the source data does not have."
        ),
        "",
        "| date (UTC) | count |",
        "|---|---|",
    ]
    for k, v in sorted(time_histogram.items()):
        manifest_lines.append(f"| {k} | {v} |")
    manifest_lines += [
        "",
        "## KML parsing survival",
        "",
        "| source | placemarks in KML | survived to observation |",
        "|---|---|---|",
        f"| gcc_stagnation_2015.kml | {stagnation_stats['n_placemarks']} | {len(stagnation_points)} |",
        f"| gcc_flood_hotspots_2015.kml | {hotspot_stats['n_placemarks']} | {len(hotspot_points)} |",
        f"| crowd_sourced_flooding_2015.kml | {crowd_stats['n_placemarks']} | {len(crowd_points)} |",
        "",
        "Drop reasons:",
        (
            f"- stagnation: {stagnation_stats['n_dropped_bad_or_out_of_bbox']} dropped "
            "(missing/unparseable coords or outside Chennai bbox)"
        ),
        (
            f"- hotspots: {hotspot_stats['n_dropped_bad_or_out_of_bbox']} dropped "
            "(missing/unparseable coords or outside Chennai bbox)"
        ),
        (
            f"- crowd: {crowd_stats['n_is_flooded_0_excluded']} excluded (is_flooded=0, not "
            f"a presence report), {crowd_stats['n_dropped_bad_or_out_of_bbox']} dropped "
            f"(missing coords or outside bbox), {crowd_stats['n_deduped_by_osm_id']} "
            "deduplicated (same osm_id already kept -- see build script's CROWD_DEDUP_KEY "
            "comment)"
        ),
        "",
        "## Edge-snapping (against the real T1.3 CSR graph, data/graph/2026-09-14/chennai_prior_ell0.json)",
        "",
        f"- Candidates offered to the snapper: {len(all_points)}",
        f"- Snapped to a CSR edge: {n_snapped}",
        f"- Failed to snap within the search radius: {n_unsnapped}",
        f"- Low-confidence far snaps (>{FAR_SNAP_THRESHOLD_M:.0f} m): {n_far_snap}",
        (
            f"- Snap distance stats (m): min={pct(0.0)}, median={pct(0.5)}, "
            f"p90={pct(0.9)}, max={pct(1.0)}"
        ),
        (
            "- No point required manual disambiguation between multiple equally-close "
            "edges -- the search always returns a single nearest edge deterministically."
        ),
        "",
        "## Assumptions and limitations (flagged per CLAUDE.md section 8.4)",
        "",
        (
            "1. **observed_at/received_at are a corpus-wide proxy, not per-point dates** "
            f"({PROXY_OBSERVED_AT}, chosen as the widely-reported acute peak of the 2015 "
            'Chennai floods -- Wikipedia "2015 South India floods"; ReliefWeb Situation '
            'Report No. 1, "Chennai Flood, 2-4 December 2015"). [UNVERIFIED at '
            "per-observation granularity.] If T3.2's replay engine or T3.4's decay "
            "calibration need genuine temporal spread within the 2015 event, this corpus "
            "cannot currently provide it -- flagging now rather than after it silently "
            "breaks a decay-calibration result."
        ),
        (
            "2. **intensity (depth_mm) is deliberately omitted for all observations.** "
            "None of these three KMLs carry a measured per-point depth. "
            "gcc_flood_hotspots_2015.kml carries categorical inundation-vulnerability "
            'bands (e.g. "Low Vulnerability less than 2 feet") preserved verbatim in '
            "`raw`, but converting a vulnerability category into a fabricated depth_mm "
            "number would misrepresent it as a measurement. C12's separate \"Inundation "
            'Points with Depth" resource (not used here) is the right source for real '
            "depth_mm, per the task card."
        ),
        (
            "3. **accuracy_m values (30 m official_feed / 50 m crowd) are engineering "
            "estimates, not sourced from KML metadata** -- none of the three KMLs "
            "publish a positional-accuracy field."
        ),
        (
            "4. **way_id is not recorded in the edge_snap_index** -- "
            "data/graph/2026-09-14/chennai_prior_ell0.json (T1.3's output) does not "
            "carry OSM way_id per edge (verified: its per-edge fields are "
            "edge_id/from/to/prior_logodds/prior_p/n_contributing_zones/highway/"
            "street_name/geometry only). The crowd-sourced KML's own `osm_id` field is "
            "preserved in each observation's `raw` block instead, so the OSM-way "
            "identity is not lost, just not cross-linked to edge_id in this file."
        ),
        (
            "5. **NRSC 2015 inundation-zone polygons and the three non-Chennai district "
            "hotspot KMLs were downloaded but not normalised into observations** -- see "
            "this script's top comment for why."
        ),
        (
            "6. **UUIDv7 is a manual RFC 9562 construction**, not a vetted third-party "
            "library -- no uuid6/uuid7 package is declared anywhere in this repo. "
            "Structurally correct (48-bit ms timestamp, version 0111, variant 10) but "
            "not independently tested against a reference implementation."
        ),
    ]
    manifest_path = OUT_DIR / "MANIFEST.md"
    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write("\n".join(manifest_lines) + "\n")

    not_done_still_pending = [
        (
            "per-point observed_at precision -- source KMLs carry no date field at all;"
            " the whole corpus is stamped with one documented proxy date"
            f" ({PROXY_OBSERVED_AT}), not a real per-event timestamp distribution"
        ),
        (
            "NRSC 2015 inundation-zone polygons (data/corpus_raw/nrsc_inundation_zone_2015.kml)"
            " -- downloaded, not normalised into observations (polygon validation layer,"
            " not point-event data; see build script's top comment)"
        ),
        (
            "way_id is not cross-linked into edge_snap_index.json -- T1.3's graph output"
            " does not carry it; only the crowd KML's own osm_id (in `raw`) survives"
        ),
        (
            "C12's separate 'Inundation Points with Depth' resource was not fetched in this"
            " task -- it is the correct source for real depth_mm intensity values, which"
            " this corpus does not have for any observation"
        ),
        (
            "resident/domain-expert review of the corpus (analogous to T-W1's resident map"
            " review) has not happened -- this is raw normalised OpenCity data, not"
            " validated ground truth"
        ),
    ]

    result = {
        "task": "T3.1 -- Replay corpus from OpenCity C13 2015 Chennai flood data",
        "generated": TODAY,
        "source_dataset_page": "https://data.opencity.in/dataset/chennai-floods-2015-data",
        "sources_used": [
            "gcc_stagnation_2015.kml",
            "gcc_flood_hotspots_2015.kml",
            "crowd_sourced_flooding_2015.kml",
        ],
        "sources_downloaded_not_used": [
            "nrsc_inundation_zone_2015.kml (polygon validation layer, see MANIFEST.md)",
        ],
        "observation_count": len(observations),
        "target": ">=200 per docs/IMPLEMENTATION_PLAN.md T3.1",
        "target_met": len(observations) >= 200,
        "counts_by_hazard_class": counts_by_class,
        "counts_by_source_class": counts_by_source_class,
        "observed_at_convention": {
            "value": PROXY_OBSERVED_AT,
            "type": "corpus-wide proxy, NOT per-point",
            "confidence": "UNVERIFIED at per-observation granularity; well-sourced at the"
            " event level (see MANIFEST.md sources)",
        },
        "snap": {
            "candidates": len(all_points),
            "snapped": n_snapped,
            "unsnapped": n_unsnapped,
            "low_confidence_far_snap_gt_300m": n_far_snap,
            "snap_distance_m_stats": {
                "min": pct(0.0),
                "median": pct(0.5),
                "p90": pct(0.9),
                "max": pct(1.0),
            },
        },
        "kml_survival": {
            "stagnation": stagnation_stats | {"survived": len(stagnation_points)},
            "hotspots": hotspot_stats | {"survived": len(hotspot_points)},
            "crowd": crowd_stats | {"survived": len(crowd_points)},
        },
        "output_files": {
            "observations": str(obs_path.relative_to(ROOT)),
            "edge_snap_index": str(snap_path.relative_to(ROOT)),
            "manifest": str(manifest_path.relative_to(ROOT)),
        },
        "not_done_still_pending": not_done_still_pending,
    }
    with open(RESULTS_DIR / "result.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print("\n=== Summary ===")
    for k, v in result.items():
        if k != "not_done_still_pending":
            print(f"  {k}: {v}")
    print("  not_done_still_pending:")
    for item in not_done_still_pending:
        print(f"    - {item}")
    print(f"\nWrote {obs_path.relative_to(ROOT)}")
    print(f"Wrote {snap_path.relative_to(ROOT)}")
    print(f"Wrote {manifest_path.relative_to(ROOT)}")
    print(f"Wrote {(RESULTS_DIR / 'result.json').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
