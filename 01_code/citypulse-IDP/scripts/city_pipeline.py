"""ADR-018 -- build a map pack for any city listed in config/cities.yaml.

Two stages, run separately because the first one needs the network:

  fetch   Overpass API -> data/osm/<city>_overpass_drivable.json   (live, unpinned; be polite)
  pack    that file -> data/packs/<city>-<date>/{graph,nodes,meta}.bin + manifest.json

The pack has the same binary format as the Chennai pack (scripts/build_packs.py) and is read by the
same Dart code (`MapPack`, `RoutingEngine`). Nothing in routing, belief or explanation is
city-specific; the city is data.

Scope, stated plainly:
  * This stage builds packs for cities with `hazard_layer: false`. Every edge gets the flat default
    prior (the same "no mapped zone" value Chennai uses away from its hazard zones), so no edge is
    treated as flood-prone and the apps say that no flood-hazard layer is loaded. It does not invent
    one. Chennai's pack, which has a real GCC prior, is built by the pinned
    t1_3_build_graph_and_prior.py + build_packs.py path and is not touched here.
  * Roads are OpenStreetMap data (ODbL): the pack is a derived database; see data/MANIFEST.md.
  * Adding a hazard layer for a city means adding a verified source and its licence first
    (docs/ADDING_A_CITY.md); this script refuses to pretend otherwise.

Usage:
  python scripts/city_pipeline.py fetch --city <id>
  python scripts/city_pipeline.py pack  --city <id> [--ways <file>] [--date YYYY-MM-DD] [--out <dir>]
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import build_packs as bp  # noqa: E402
import t1_3_build_graph_and_prior as t13  # noqa: E402

ROOT = SCRIPTS_DIR.parent
CITIES_PATH = ROOT / "config" / "cities.yaml"


def load_city(city_id: str, path: Path = CITIES_PATH) -> dict:
    """The entry for `city_id`, validated for what this script needs."""
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    cities = doc.get("cities") or {}
    if city_id not in cities:
        raise SystemExit(f"unknown city '{city_id}'; known: {', '.join(sorted(cities))}")
    city = dict(cities[city_id])
    city["id"] = city_id
    box = city.get("bbox") or {}
    for key in ("min_lat", "max_lat", "min_lon", "max_lon"):
        if not isinstance(box.get(key), (int, float)):
            raise SystemExit(f"{city_id}.bbox.{key} is missing or not a number")
    if not (box["min_lat"] < box["max_lat"] and box["min_lon"] < box["max_lon"]):
        raise SystemExit(f"{city_id}.bbox is empty or inverted")
    return city


def default_ways_path(city_id: str) -> Path:
    return ROOT / "data" / "osm" / f"{city_id}_overpass_drivable.json"


def fetch(city_id: str) -> None:
    import fetch_chennai_drivable_ways as fetcher

    city = load_city(city_id)
    out = default_ways_path(city_id)
    print(f"Fetching drivable ways for {city_id} {city['bbox']} -> {out}")
    fetcher.fetch_ways(city["bbox"], out, f"scripts/city_pipeline.py fetch --city {city_id}")


def build_pack(
    city: dict, ways_path: Path, out_dir: Path, built: str, config_path: Path = CITIES_PATH
) -> dict:
    """Build the pack files and manifest; returns the manifest."""
    if city.get("hazard_layer"):
        raise SystemExit(
            f"{city['id']} is marked hazard_layer: true. This script builds packs with the flat default "
            "prior only; a hazard layer needs a verified source and its own build (docs/ADDING_A_CITY.md)."
        )
    ways, skipped = t13.load_ways(ways_path)
    if not ways:
        raise SystemExit(f"no usable drivable ways in {ways_path}")
    junctions = t13.find_junction_nodes(ways)
    node_latlon, edges = t13.build_graph(ways, junctions)
    if not edges:
        raise SystemExit("the road network has no edges")

    # Sanity: the pack must actually cover the city centre it claims to serve.
    lats = [p[0] for p in node_latlon]
    lons = [p[1] for p in node_latlon]
    c = city["centre"]
    if not (min(lats) <= c["lat"] <= max(lats) and min(lons) <= c["lon"] <= max(lons)):
        raise SystemExit(
            f"the road network spans lat {min(lats):.4f}..{max(lats):.4f}, lon {min(lons):.4f}..{max(lons):.4f}, "
            f"which does not contain the configured centre {c}; check the bbox and the ways file"
        )

    default_prior = t13.logit(t13.CATEGORY_TO_PROBABILITY["Very Low"])
    milli = round(default_prior * bp.PRIOR_SCALE)

    names: list[str] = [""]
    name_lookup: dict[str, int] = {}
    name_idx: list[int] = []
    hwy: list[int] = []
    hw_index = {h: i for i, h in enumerate(bp.HIGHWAY_CODES)}
    unknown_hw: dict[str, int] = {}
    for e in edges:
        name = (e.get("street_name") or "").strip()
        if name:
            if name not in name_lookup:
                name_lookup[name] = len(names)
                names.append(name)
            name_idx.append(name_lookup[name])
        else:
            name_idx.append(0)
        h = e.get("highway")
        code = hw_index.get(h, 0)
        if code == 0 and h:
            unknown_hw[h] = unknown_hw.get(h, 0) + 1
        hwy.append(code)
    if len(names) > 65535:
        raise SystemExit("more than 65,535 distinct street names; the name index needs widening")

    out_dir.mkdir(parents=True, exist_ok=True)
    bp.write_graph(edges, len(node_latlon), out_dir / "graph.bin")
    bp.write_nodes(node_latlon, out_dir / "nodes.bin")
    bp.write_meta([milli] * len(edges), name_idx, hwy, names, out_dir / "meta.bin")

    ways_doc_meta = {}
    try:
        with open(ways_path, "rb") as f:
            import ijson

            for meta in ijson.items(f, "osm3s"):
                ways_doc_meta = meta
                break
    except Exception:  # noqa: BLE001 -- the timestamp is informative, never required
        ways_doc_meta = {}

    manifest = {
        "pack": "citypulse-map-pack",
        "format_version": 1,
        "built": built,
        "script": "scripts/city_pipeline.py",
        "city": {
            "id": city["id"],
            "bbox": city["bbox"],
            "centre": city["centre"],
            "hazard_layer": False,
            "node_bounds": {
                "min_lat": min(lats),
                "max_lat": max(lats),
                "min_lon": min(lons),
                "max_lon": max(lons),
            },
        },
        "source_ways": ways_path.name,
        "source_sha256": {ways_path.name: bp.sha256(ways_path)},
        "osm_snapshot_timestamp": ways_doc_meta.get("timestamp_osm_base"),
        "cities_config_sha256": bp.sha256(config_path),
        "counts": {
            "nodes": len(node_latlon),
            "edges": len(edges),
            "named_edges": sum(1 for x in name_idx if x),
            "distinct_names": len(names) - 1,
            "unknown_highway_values": unknown_hw,
            "ways_skipped_unmapped_class": skipped,
        },
        "prior_scale": bp.PRIOR_SCALE,
        "prior_note": (
            "Flat default prior on every edge (p=0.02, the same no-zone value the Chennai pack uses "
            "away from its hazard zones). No flood-hazard source is loaded for this city."
        ),
        "highway_codes": bp.HIGHWAY_CODES,
        "licence_note": "OSM-derived (ODbL) graph and names. See data/MANIFEST.md.",
        "files": {
            name: {"bytes": (out_dir / name).stat().st_size, "sha256": bp.sha256(out_dir / name)}
            for name in ("graph.bin", "nodes.bin", "meta.bin")
        },
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="stage", required=True)
    f = sub.add_parser("fetch", help="download drivable ways from Overpass (network)")
    f.add_argument("--city", required=True)
    p = sub.add_parser("pack", help="build the pack from a fetched ways file")
    p.add_argument("--city", required=True)
    p.add_argument("--ways", type=Path)
    p.add_argument("--date", default=datetime.now(timezone.utc).date().isoformat())
    p.add_argument("--out", type=Path)
    args = ap.parse_args(argv)

    if args.stage == "fetch":
        fetch(args.city)
        return 0
    city = load_city(args.city)
    ways = args.ways or default_ways_path(args.city)
    out = args.out or ROOT / "data" / "packs" / f"{args.city}-{args.date}"
    manifest = build_pack(city, ways, out, args.date)
    for name, info in manifest["files"].items():
        print(f"{name:10s} {info['bytes'] / 1e6:7.3f} MB  {info['sha256'][:16]}")
    c = manifest["counts"]
    print(f"{c['nodes']} nodes, {c['edges']} edges, {c['distinct_names']} street names")
    print(f"wrote {out}")
    print(f"next: set `pack: {out.relative_to(ROOT).as_posix()}` for '{args.city}' in config/cities.yaml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
