"""
T1.3 -- Build the Chennai routing graph and the static hazard prior ell_0(e)
(docs/IMPLEMENTATION_PLAN.md Phase 1b; CLAUDE.md section 6).

**What this script does, and does not, complete.** T1.3's task card asks for ell_0(e) "from
OpenCity GCC flood hazard zones + inundation depth points + elevation/HAND," "shipped as a
packed array aligned to the CSR edge index," with acceptance being "a choropleth ... that a
local human recognises as plausible."

What this script DOES, from data already on disk (no new paid services, CLAUDE.md Rule 1):

  1. Builds a real, non-toy Chennai routing graph -- nodes and directed edges with per-class
     free-flow speed -- from data/osm/chennai_overpass_drivable.json (the same drivable-ways
     cache T-W1 uses; see scripts/fetch_chennai_drivable_ways.py for its provenance). This is
     the graph builder pulse_router's own docs say T1.3 owns
     (packages/pulse_router/lib/src/csr_graph.dart: "A two-way street is two
     GraphEdgeInput`s ... this package never infers directionality, the graph builder
     (T1.3/T3.1) does.") -- OSM ways are split into edges at junction nodes (a node used by
     >=2 ways, or a way's own endpoint), oneway tags are respected, and each direction of a
     two-way street becomes its own edge.
  2. Computes ell_0(e) per edge from the OpenCity/GCC flood-hazard-zone KML's CATEGORY field
     (the same source T-W1 uses) via inverse-distance-weighted nearby-zone scoring, in log-odds
     -- the *first* of T1.3's three named sources.
  3. Writes edge-aligned output two ways: the CLI JSON graph format
     packages/pulse_router/bin/pulse_router.dart already reads (see cli_io.dart's own
     docstring), so the real Dart router can be run against this real graph today; and a
     prior-plus-geometry sidecar for the choropleth this script also produces.

**What this script does NOT do -- verified absent, not silently skipped:**
  - **Inundation depth points** (T1.3's second named source): the OpenCity/GCC KML on this
    machine (data/watchlist_raw/chennai_flood_hazard_zones.kml) carries a CATEGORY field, not
    per-point depth values -- the "2015 inundation-depth KML" `research/raw/C` cites as a
    separate document (C13) was not located as a distinct file here. T-W1's manifest already
    flagged the same gap for its own purposes; this script inherits it.
  - **Elevation/HAND** (T1.3's third named source): checked `docs/APIS_AND_COSTS.md` and
    `research/raw/C-data-sources.md` before writing this script -- neither names a concretely
    sourced elevation/HAND dataset or API for Chennai. `docs/ARCHITECTURE.md`'s diagram names
    "Elevation / HAND / drainage / 2015 inundation" as a single input box, but no research
    strand actually sourced it. Per CLAUDE.md's "never invent a data source" rule, this script
    does not fabricate an elevation signal or silently substitute something else for it. This
    is a real, disclosed gap -- ell_0 here is built from flood-hazard-zone risk category alone.
  - **The packed-binary array format the Flutter client will eventually consume.** No such
    format is specified anywhere in this repo yet (cli_io.dart's own docstring: "the real graph
    build (T1.3) ships a packed binary array to the Flutter client, not this JSON" -- stated as
    a future fact, not a current spec). Designing that wire format is a real decision with no
    consumer yet (the client is Phase 5, week 5) -- inventing one now would be building ahead
    of what's needed. This script ships the CLI JSON format that already exists and already has
    a real consumer (the Dart AOT CLI, T2.4), and flags the binary format as separate future
    work rather than silently declaring this task fully done.

**Free-flow speed table is a planning default, not calibrated data** -- same status as
`config/hazard_classes.yaml`'s own `T_c_seconds` values, which that file's own header already
labels "STARTING GUESSES." No source in this repo specifies real speed-by-highway-class data
for Chennai; treat HIGHWAY_SPEEDS_KMH below the same way.

**Category-to-log-odds mapping is also a planning default, not calibrated data.** The five KML
CATEGORY values (Very Low..Very High) are ordinal risk labels from GCC's own zonation
methodology (whatever that is -- not documented anywhere this project has access to); mapping
them to specific probabilities is this script's own choice, flagged as such in the output.
Calibrating this against real Chennai closure data is T3.4's job, per
docs/IMPLEMENTATION_PLAN.md.

Usage: .venv/Scripts/python.exe scripts/t1_3_build_graph_and_prior.py
"""

from __future__ import annotations

import json
import math
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

import ijson

ROOT = Path(__file__).resolve().parent.parent
WAYS_PATH = ROOT / "data" / "osm" / "chennai_overpass_drivable.json"
KML_PATH = ROOT / "data" / "watchlist_raw" / "chennai_flood_hazard_zones.kml"
TODAY = datetime.now(tz=timezone.utc).date().isoformat()
GRAPH_DIR = ROOT / "data" / "graph" / TODAY
RESULTS_DIR = ROOT / "data" / "results" / f"{TODAY}-t1-3-graph-prior"

NS = {"kml": "http://www.opengis.net/kml/2.2"}

# Planning default -- see this file's top comment. km/h per OSM highway=* value.
HIGHWAY_SPEEDS_KMH = {
    "motorway": 70.0,
    "motorway_link": 40.0,
    "trunk": 60.0,
    "trunk_link": 35.0,
    "primary": 50.0,
    "primary_link": 30.0,
    "secondary": 40.0,
    "secondary_link": 25.0,
    "tertiary": 30.0,
    "tertiary_link": 20.0,
    "unclassified": 25.0,
    "residential": 20.0,
}

# Planning default -- see this file's top comment. Ordinal category -> P(hazard), converted to
# log-odds below. Monotonic in the KML's own ordinal risk ordering; magnitudes are this
# script's own illustrative choice pending T3.4 calibration.
CATEGORY_TO_PROBABILITY = {
    "Very Low": 0.02,
    "Low": 0.05,
    "Moderate": 0.12,
    "High": 0.25,
    "Very High": 0.45,
}

# Inverse-distance weighting cutoff for scoring an edge against nearby flood-hazard zones.
# Zones farther than this contribute nothing. 600m is roughly 4x T-W1's cluster radius --
# wide enough that most edges in a hazard-mapped area see at least one zone, narrow enough
# that a zone on the far side of the city doesn't leak into an unrelated edge's prior.
ZONE_INFLUENCE_RADIUS_M = 600.0
GRID_CELL_DEG = 0.01


def haversine_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dphi = math.radians(b[0] - a[0])
    dlambda = math.radians(b[1] - a[1])
    h = (
        math.sin(dphi / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(h))


def logit(p: float) -> float:
    return math.log(p / (1 - p))


def sigmoid(x: float) -> float:
    return 1.0 / (1.0 + math.exp(-x))


# ---------------------------------------------------------------------------------------
# Step 1: load drivable ways
# ---------------------------------------------------------------------------------------


def load_ways(path: Path | None = None) -> tuple[list[dict], int]:
    """Drivable ways from an Overpass `out geom` file; `path` defaults to Chennai's (ADR-018)."""
    ways = []
    skipped_unknown_class = 0
    with open(path or WAYS_PATH, "rb") as f:
        for el in ijson.items(f, "elements.item"):
            if el.get("type") != "way":
                continue
            geometry = el.get("geometry")
            nodes = el.get("nodes")
            if (
                not geometry
                or not nodes
                or len(geometry) != len(nodes)
                or len(nodes) < 2
            ):
                continue
            tags = el.get("tags", {})
            highway = tags.get("highway")
            if highway not in HIGHWAY_SPEEDS_KMH:
                skipped_unknown_class += 1
                continue
            oneway_tag = tags.get("oneway")
            ways.append(
                {
                    "id": int(el["id"]),
                    "nodes": [int(n) for n in nodes],
                    "pts": [(float(g["lat"]), float(g["lon"])) for g in geometry],
                    "highway": highway,
                    "oneway": oneway_tag in ("yes", "true", "1"),
                    "reversed_oneway": oneway_tag == "-1",
                    "name": tags.get("name"),
                }
            )
    return ways, skipped_unknown_class


# ---------------------------------------------------------------------------------------
# Step 2: split ways into edges at junction nodes
# ---------------------------------------------------------------------------------------


def find_junction_nodes(ways: list[dict]) -> set[int]:
    node_way_count: dict[int, int] = {}
    for w in ways:
        for n in w["nodes"]:
            node_way_count[n] = node_way_count.get(n, 0) + 1
    junctions = {n for n, count in node_way_count.items() if count >= 2}
    for w in ways:
        junctions.add(w["nodes"][0])
        junctions.add(w["nodes"][-1])
    return junctions


def split_way_into_segments(
    way: dict, junctions: set[int]
) -> list[tuple[int, int, list[tuple[float, float]]]]:
    nodes, pts = way["nodes"], way["pts"]
    segments = []
    seg_start = 0
    for i in range(1, len(nodes)):
        if nodes[i] in junctions:
            segments.append((nodes[seg_start], nodes[i], pts[seg_start : i + 1]))
            seg_start = i
    return segments


def build_graph(
    ways: list[dict], junctions: set[int]
) -> tuple[list[tuple[float, float]], list[dict]]:
    node_index: dict[int, int] = {}
    node_latlon: list[tuple[float, float]] = []

    def node_idx(osm_id: int, pt: tuple[float, float]) -> int:
        idx = node_index.get(osm_id)
        if idx is None:
            idx = len(node_latlon)
            node_index[osm_id] = idx
            node_latlon.append(pt)
        return idx

    edges: list[dict] = []
    next_edge_id = 0

    def add_edge(
        from_idx: int,
        to_idx: int,
        geom: list[tuple[float, float]],
        length_m: float,
        way: dict,
    ) -> None:
        nonlocal next_edge_id
        speed_kmh = HIGHWAY_SPEEDS_KMH[way["highway"]]
        edges.append(
            {
                "edge_id": next_edge_id,
                "from": from_idx,
                "to": to_idx,
                "free_flow_seconds": length_m / (speed_kmh * 1000.0 / 3600.0),
                "free_flow_kmh": speed_kmh,
                "length_m": length_m,
                "geometry": geom,
                "way_id": way["id"],
                "street_name": way["name"],
                "highway": way["highway"],
            }
        )
        next_edge_id += 1

    for w in ways:
        for start_osm, end_osm, seg_pts in split_way_into_segments(w, junctions):
            length_m = sum(
                haversine_m(seg_pts[i], seg_pts[i + 1]) for i in range(len(seg_pts) - 1)
            )
            if length_m <= 0:
                continue
            from_idx = node_idx(start_osm, seg_pts[0])
            to_idx = node_idx(end_osm, seg_pts[-1])
            if from_idx == to_idx:
                continue
            if w["reversed_oneway"]:
                add_edge(to_idx, from_idx, list(reversed(seg_pts)), length_m, w)
            elif w["oneway"]:
                add_edge(from_idx, to_idx, seg_pts, length_m, w)
            else:
                add_edge(from_idx, to_idx, seg_pts, length_m, w)
                add_edge(to_idx, from_idx, list(reversed(seg_pts)), length_m, w)

    return node_latlon, edges


# ---------------------------------------------------------------------------------------
# Step 3: flood hazard zones -> ell_0(e)
# ---------------------------------------------------------------------------------------


def parse_kml_coords(text: str) -> list[tuple[float, float]]:
    pts = []
    for tok in text.split():
        parts = tok.split(",")
        if len(parts) >= 2:
            lon, lat = float(parts[0]), float(parts[1])
            pts.append((lat, lon))
    return pts


def load_flood_zones() -> list[dict]:
    tree = ET.parse(KML_PATH)
    root = tree.getroot()
    zones = []
    for pm in root.findall(".//kml:Placemark", NS):
        fields = {sd.get("name"): sd.text for sd in pm.findall(".//kml:SimpleData", NS)}
        coord_el = pm.find(".//kml:outerBoundaryIs//kml:coordinates", NS)
        if coord_el is None:
            coord_el = pm.find(".//kml:coordinates", NS)
        if coord_el is None or not coord_el.text:
            continue
        pts = parse_kml_coords(coord_el.text)
        if not pts:
            continue
        lat = sum(p[0] for p in pts) / len(pts)
        lon = sum(p[1] for p in pts) / len(pts)
        category = fields.get("CATEGORY")
        if category not in CATEGORY_TO_PROBABILITY:
            continue
        zones.append({"lat": lat, "lon": lon, "category": category})
    return zones


def build_zone_index(
    zones: list[dict], cell_deg: float
) -> dict[tuple[int, int], list[int]]:
    index: dict[tuple[int, int], list[int]] = {}
    for i, z in enumerate(zones):
        cell = (int(z["lat"] / cell_deg), int(z["lon"] / cell_deg))
        index.setdefault(cell, []).append(i)
    return index


def edge_prior_logodds(
    midpoint: tuple[float, float],
    zones: list[dict],
    index: dict[tuple[int, int], list[int]],
    cell_deg: float,
) -> tuple[float, int]:
    """Inverse-distance-weighted average of nearby zones' logit(P), in probability space,
    then converted back to log-odds -- averaging in probability space (not log-odds space)
    keeps one very-high-risk zone from being diluted by nearby zones the way log-odds
    summation would, which is the right direction for a hazard *prior* (ADR-002's "less
    evidence means more caution" spirit, applied here to spatial evidence rather than
    temporal). Falls back to CATEGORY_TO_PROBABILITY["Very Low"] with zero contributing
    zones when nothing is within range -- absence of a mapped zone is not evidence of zero
    risk, just the most conservative prior this data supports.
    """
    lat, lon = midpoint
    cx, cy = int(lat / cell_deg), int(lon / cell_deg)
    reach = max(1, int(ZONE_INFLUENCE_RADIUS_M / (cell_deg * 111_320.0)) + 1)
    total_weight = 0.0
    weighted_p = 0.0
    n_contributing = 0
    for dx in range(-reach, reach + 1):
        for dy in range(-reach, reach + 1):
            for zi in index.get((cx + dx, cy + dy), []):
                z = zones[zi]
                d = haversine_m(midpoint, (z["lat"], z["lon"]))
                if d > ZONE_INFLUENCE_RADIUS_M:
                    continue
                weight = 1.0 - (d / ZONE_INFLUENCE_RADIUS_M)
                total_weight += weight
                weighted_p += weight * CATEGORY_TO_PROBABILITY[z["category"]]
                n_contributing += 1
    if total_weight <= 0:
        return logit(CATEGORY_TO_PROBABILITY["Very Low"]), 0
    p = weighted_p / total_weight
    p = min(max(p, 1e-6), 1 - 1e-6)
    return logit(p), n_contributing


# ---------------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------------


def main() -> None:
    GRAPH_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Streaming {WAYS_PATH.name}...")
    ways, skipped_unknown_class = load_ways()
    print(
        f"  {len(ways)} drivable ways ({skipped_unknown_class} skipped: unmapped class)"
    )

    print("Finding junction nodes...")
    junctions = find_junction_nodes(ways)
    print(f"  {len(junctions)} junction nodes")

    print("Splitting ways into directed edges...")
    node_latlon, edges = build_graph(ways, junctions)
    print(f"  {len(node_latlon)} nodes, {len(edges)} directed edges")

    print(f"Parsing {KML_PATH.name}...")
    zones = load_flood_zones()
    print(f"  {len(zones)} flood-hazard zones")
    zone_index = build_zone_index(zones, GRID_CELL_DEG)

    print("Computing ell_0(e) per edge...")
    n_with_evidence = 0
    for e in edges:
        geom = e["geometry"]
        mid = geom[len(geom) // 2]
        ell0, n_contrib = edge_prior_logodds(mid, zones, zone_index, GRID_CELL_DEG)
        e["prior_logodds"] = round(ell0, 4)
        e["prior_p"] = round(sigmoid(ell0), 4)
        e["n_contributing_zones"] = n_contrib
        if n_contrib > 0:
            n_with_evidence += 1

    print(
        f"  {n_with_evidence}/{len(edges)} edges have >=1 nearby zone within "
        f"{ZONE_INFLUENCE_RADIUS_M:.0f}m"
    )

    # CLI graph JSON (packages/pulse_router/lib/src/cli_io.dart's graphFromJson format) --
    # runnable against the real Dart router today.
    cli_graph = {
        "node_count": len(node_latlon),
        "edges": [
            {
                "edge_id": e["edge_id"],
                "from": e["from"],
                "to": e["to"],
                "free_flow_seconds": round(e["free_flow_seconds"], 3),
                "free_flow_kmh": e["free_flow_kmh"],
            }
            for e in edges
        ],
    }
    with open(GRAPH_DIR / "chennai_graph_cli.json", "w", encoding="utf-8") as f:
        json.dump(cli_graph, f)

    # Prior + geometry sidecar -- what the CLI graph format has no slot for. This, not the
    # CLI graph file, is what a future packed-binary client format and the choropleth both
    # need to be built from.
    prior_sidecar = {
        "generated": TODAY,
        "source_ways": str(WAYS_PATH.relative_to(ROOT)),
        "source_kml": str(KML_PATH.relative_to(ROOT)),
        "category_to_probability": CATEGORY_TO_PROBABILITY,
        "zone_influence_radius_m": ZONE_INFLUENCE_RADIUS_M,
        "nodes": [{"lat": lat, "lon": lon} for lat, lon in node_latlon],
        "edges": [
            {
                "edge_id": e["edge_id"],
                "from": e["from"],
                "to": e["to"],
                "prior_logodds": e["prior_logodds"],
                "prior_p": e["prior_p"],
                "n_contributing_zones": e["n_contributing_zones"],
                "highway": e["highway"],
                "street_name": e["street_name"],
                "geometry": [{"lat": p[0], "lon": p[1]} for p in e["geometry"]],
            }
            for e in edges
        ],
    }
    with open(GRAPH_DIR / "chennai_prior_ell0.json", "w", encoding="utf-8") as f:
        json.dump(prior_sidecar, f)

    manifest = {
        "task": "T1.3 -- Chennai graph build + static hazard prior ell_0(e) (partial, see this script's top comment)",
        "generated": TODAY,
        "node_count": len(node_latlon),
        "edge_count": len(edges),
        "junction_node_count": len(junctions),
        "flood_hazard_zones_used": len(zones),
        "edges_with_nearby_zone_evidence": n_with_evidence,
        "edges_with_no_nearby_zone_evidence": len(edges) - n_with_evidence,
        "prior_p_by_category_used": CATEGORY_TO_PROBABILITY,
        "free_flow_speed_kmh_by_highway_class": HIGHWAY_SPEEDS_KMH,
        "not_done_still_pending": [
            (
                "inundation depth points (T1.3's second named source) -- not located on "
                "this machine as a separate structured dataset from the CATEGORY-only "
                "hazard-zone KML; see this script's top comment"
            ),
            (
                "elevation/HAND (T1.3's third named source) -- no concretely sourced "
                "dataset or API found in docs/APIS_AND_COSTS.md or research/raw/ before "
                "writing this script; not fabricated as a placeholder"
            ),
            (
                "the packed binary array format for the Flutter client -- no such format "
                "is specified anywhere in this repo yet; this script ships the existing "
                "CLI JSON format instead of inventing an unreviewed new wire format ahead "
                "of the client that would consume it (Phase 5)"
            ),
            (
                "category_to_probability and free_flow_speed_kmh_by_highway_class are "
                "planning defaults, not calibrated data -- same status as "
                "config/hazard_classes.yaml's own T_c 'PLACEHOLDER' values. T3.4 is where "
                "calibration against real Chennai data happens."
            ),
            (
                "the choropleth acceptance test itself: 'a choropleth of sigma(ell_0) "
                "over Chennai that a local human recognises as plausible' -- a "
                "renderable choropleth is produced alongside this manifest, but a human "
                "who knows Chennai has not yet looked at it"
            ),
        ],
    }
    with open(RESULTS_DIR / "result.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    print("\n=== Summary ===")
    for k, v in manifest.items():
        if k != "not_done_still_pending":
            print(f"  {k}: {v}")
    print("  not_done_still_pending:")
    for item in manifest["not_done_still_pending"]:
        print(f"    - {item}")
    print(f"\nWrote {(GRAPH_DIR / 'chennai_graph_cli.json').relative_to(ROOT)}")
    print(f"Wrote {(GRAPH_DIR / 'chennai_prior_ell0.json').relative_to(ROOT)}")
    print(f"Wrote {(RESULTS_DIR / 'result.json').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
