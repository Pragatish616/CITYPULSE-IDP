"""Phase-1 survey for mapping beyond Chennai (ADR-020): how big is Tamil Nadu's road network?

One streaming pass over a Geofabrik PBF extract (default: the pinned southern-zone snapshot of
2026-09-11 that the project already holds). For every drivable OSM way inside a bounding box it counts
ways, directed segments and kilometres per road class. It runs the same count for Chennai's box, where
the real pack is known (471,240 directed edges, 193,191 nodes, 15.5 MB), so that segments can be turned
into an estimate of pack size with a measured factor instead of a guess.

It does not build anything. It writes data/results/<date>-india-survey-<region>/result.json.

Needs pyosmium and numpy, which are NOT in the project venv: use a separate environment
(python -m venv <dir>; <dir>/Scripts/pip install osmium numpy pyyaml).

Usage: <osm venv>/python scripts/india_survey.py [--pbf <file>] [--region tamil_nadu]

Caveats stated up front: boxes are rectangles, so the Tamil Nadu box also holds roads in Kerala,
Karnataka, Andhra Pradesh and Puducherry (overcount); the factor from segments to edges is measured on
Chennai only and may differ in rural areas.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import osmium

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PBF = Path(r"C:\Users\nprag\Downloads\citypulse-IDP\data\osm\southern-zone-260911.osm.pbf")

# Same drivable classes the Chennai pack uses (scripts/t1_3_build_graph_and_prior.py).
CLASSES = [
    "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
    "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified", "residential",
]
# Cumulative detail levels, coarse to fine.
LEVELS = {
    "backbone (motorway to secondary)": CLASSES[:8],
    "plus tertiary": CLASSES[:10],
    "plus unclassified": CLASSES[:11],
    "everything (plus residential)": CLASSES,
}

BOXES = {
    # (min_lat, max_lat, min_lon, max_lon). Chennai's is the box the pack was built with.
    "chennai": (12.75, 13.25, 79.95, 80.35),
    # Tamil Nadu's extent, rounded outwards. A rectangle: it also covers parts of neighbouring states.
    "tamil_nadu": (8.0, 13.6, 76.2, 80.4),
}

# Chennai pack facts (data/packs/2026-10-02/manifest.json) for calibration.
CHENNAI_EDGES = 471_240
CHENNAI_NODES = 193_191
CHENNAI_PACK_BYTES = 15_500_000  # about; graph + nodes + meta


def haversine_km(a, b) -> float:
    r = 6371.0088
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dphi = p2 - p1
    dl = math.radians(b[1] - a[1])
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def inside(box, lat, lon) -> bool:
    return box[0] <= lat <= box[1] and box[2] <= lon <= box[3]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pbf", type=Path, default=DEFAULT_PBF)
    ap.add_argument("--region", default="tamil_nadu", choices=[k for k in BOXES if k != "chennai"])
    ap.add_argument("--index", default=str(ROOT / "data" / "osm" / "_node_index.tmp"),
                    help="disk-backed node location index (about 2-3 GB while running; deleted after)")
    args = ap.parse_args()
    if not args.pbf.exists():
        print(f"PBF not found: {args.pbf}", file=sys.stderr)
        return 2

    region_box, chennai_box = BOXES[args.region], BOXES["chennai"]
    zero = lambda: {"ways": 0, "segments": 0, "directed_segments": 0, "km": 0.0}
    stats = {name: {c: zero() for c in CLASSES} for name in ("region", "chennai")}
    oneway_seen = {"region": 0, "chennai": 0}

    started = time.time()
    seen = 0
    fp = (
        osmium.FileProcessor(str(args.pbf), osmium.osm.NODE | osmium.osm.WAY)
        .with_locations(f"sparse_file_array,{args.index}")
        .with_filter(osmium.filter.KeyFilter("highway"))
    )
    for way in fp:
        if not way.is_way():  # nodes with a highway tag (signals, crossings) pass the filter too
            continue
        seen += 1
        if seen % 500_000 == 0:
            print(f"  {seen:,} highway ways read, {time.time() - started:.0f}s", flush=True)
        hw = way.tags.get("highway")
        if hw not in stats["region"]:
            continue
        pts = []
        ok = True
        for n in way.nodes:
            if not n.location.valid():
                ok = False
                break
            pts.append((n.location.lat, n.location.lon))
        if not ok or len(pts) < 2:
            continue
        first = pts[0]
        targets = []
        if inside(region_box, *first):
            targets.append("region")
        if inside(chennai_box, *first):
            targets.append("chennai")
        if not targets:
            continue
        oneway = way.tags.get("oneway") in ("yes", "true", "1", "-1")
        km = sum(haversine_km(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
        segs = len(pts) - 1
        for t in targets:
            s = stats[t][hw]
            s["ways"] += 1
            s["segments"] += segs
            s["directed_segments"] += segs * (1 if oneway else 2)
            s["km"] += km
            oneway_seen[t] += 1 if oneway else 0

    elapsed = time.time() - started

    def total(name, classes):
        return {
            k: sum(stats[name][c][k] for c in classes)
            for k in ("ways", "segments", "directed_segments", "km")
        }

    chennai_all = total("chennai", CLASSES)
    # How many directed segments of the raw ways end up as edges after junction splitting and
    # collapsing in the pack builder. Measured on Chennai only.
    edge_per_segment = CHENNAI_EDGES / chennai_all["directed_segments"]
    bytes_per_edge = CHENNAI_PACK_BYTES / CHENNAI_EDGES

    levels = {}
    for label, classes in LEVELS.items():
        t = total("region", classes)
        est_edges = t["directed_segments"] * edge_per_segment
        levels[label] = {
            **{k: (round(v, 1) if isinstance(v, float) else v) for k, v in t.items()},
            "estimated_pack_edges": round(est_edges),
            "estimated_pack_mb": round(est_edges * bytes_per_edge / 1e6, 1),
            "relative_to_chennai_pack": round(est_edges / CHENNAI_EDGES, 2),
        }

    out_dir = ROOT / "data" / "results" / f"{datetime.now(timezone.utc).date().isoformat()}-india-survey-{args.region}"
    out_dir.mkdir(parents=True, exist_ok=True)
    result = {
        "task": f"ADR-020 phase-1 survey: {args.region}",
        "pbf": args.pbf.name,
        "pbf_bytes": args.pbf.stat().st_size,
        "region_box_min_lat_max_lat_min_lon_max_lon": region_box,
        "calibration_chennai": {
            "box": chennai_box,
            "raw_directed_segments": chennai_all["directed_segments"],
            "pack_edges": CHENNAI_EDGES,
            "edges_per_directed_segment": round(edge_per_segment, 4),
            "pack_bytes_per_edge": round(bytes_per_edge, 1),
        },
        "levels": levels,
        "by_class_region": {c: {k: (round(v, 1) if isinstance(v, float) else v) for k, v in s.items()}
                            for c, s in stats["region"].items()},
        "by_class_chennai": {c: {k: (round(v, 1) if isinstance(v, float) else v) for k, v in s.items()}
                             for c, s in stats["chennai"].items()},
        "seconds": round(elapsed, 1),
        "caveats": [
            "the box is a rectangle and also holds roads in neighbouring states",
            "edges-per-segment and bytes-per-edge are measured on Chennai only",
            "estimates, not a build; no graph was constructed",
        ],
    }
    (out_dir / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"done in {elapsed:.0f}s -> {out_dir / 'result.json'}")
    # The reader keeps the index file open until it is released; delete it last and never let a
    # failed delete lose the result.
    del fp
    import gc

    gc.collect()
    try:
        Path(args.index).unlink(missing_ok=True)
    except OSError as e:
        print(f"note: could not delete {args.index} ({e}); delete it by hand (about 2 GB)", file=sys.stderr)
    for label, v in levels.items():
        print(f"  {label}: {v['directed_segments']:,} directed segments -> ~{v['estimated_pack_edges']:,} edges, "
              f"~{v['estimated_pack_mb']} MB ({v['relative_to_chennai_pack']}x Chennai)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
