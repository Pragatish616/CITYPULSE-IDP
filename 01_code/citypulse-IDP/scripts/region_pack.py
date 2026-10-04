"""ADR-020 -- build a map pack for a large region (a state) straight from a Geofabrik PBF extract.

`city_pipeline.py` builds a pack from an Overpass JSON file with the Chennai code, which keeps a Python
dict and a geometry list per edge. That is fine for one city and impossible for a state on a laptop
with 8 GB of RAM. This builder reads the PBF once, keeps only compact arrays, and writes the same
binary pack format (`graph.bin`, `nodes.bin`, `meta.bin`, `manifest.json`) that `MapPack` reads. The
format is byte-identical to `build_packs.py`'s for the same graph: tests/test_region_pack.py checks that.

What it builds: the drivable roads of one or more classes inside the city's bounding box in
config/cities.yaml. `--levels backbone` (motorway to secondary) is the Phase-1 Tamil Nadu pack: it
routes between towns and cities. Detailed local roads need regional packs (ADR-020), not one big graph.

Needs pyosmium and numpy (not in the project venv; use the separate osm environment).

Usage:
  <osm venv>/python scripts/region_pack.py --city tamil_nadu --levels backbone [--pbf <file>] [--date YYYY-MM-DD]

Honest limits: the bounding box is a rectangle, so it also holds roads in neighbouring states. The
prior is the flat default (no flood data outside Chennai). Two directed edges are made for every
two-way segment, as in the Chennai pack; edges are NOT merged across degree-2 junction nodes.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import struct
import sys
import time
from array import array
from datetime import datetime, timezone
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PBF = Path(r"C:\Users\nprag\Downloads\citypulse-IDP\data\osm\southern-zone-260911.osm.pbf")

# Must match build_packs.HIGHWAY_CODES and travel_profile.dart kHighwayCodes (format v1).
HIGHWAY_CODES = [
    "unknown", "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
    "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified", "residential",
]
SPEEDS_KMH = {  # same table as t1_3_build_graph_and_prior.HIGHWAY_SPEEDS_KMH
    "motorway": 70.0, "motorway_link": 40.0, "trunk": 60.0, "trunk_link": 35.0, "primary": 50.0,
    "primary_link": 30.0, "secondary": 40.0, "secondary_link": 25.0, "tertiary": 30.0,
    "tertiary_link": 20.0, "unclassified": 25.0, "residential": 20.0,
}
LEVELS = {
    "backbone": HIGHWAY_CODES[1:9],       # motorway .. secondary_link
    "tertiary": HIGHWAY_CODES[1:11],      # + tertiary
    "all": HIGHWAY_CODES[1:],             # + unclassified, residential
}
PRIOR_SCALE = 1000
FLAT_PRIOR_MILLI = round(math.log(0.02 / 0.98) * PRIOR_SCALE)  # the "no mapped zone" value, -3892


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0  # the radius the Chennai builder uses, so the packs agree
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


CITIES_PATH = ROOT / "config" / "cities.yaml"


def load_city(city_id: str, path: Path = CITIES_PATH) -> dict:
    """The city's entry from config/cities.yaml, with its box checked (a small copy of
    city_pipeline.load_city so this script needs only pyosmium, numpy-free standard library and PyYAML)."""
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


# ------------------------------------------------------------------ reading ways (PBF or fixture)


def display_name(name: str | None, ref: str | None) -> str:
    """What a road is called in search. OSM keeps highway numbers in `ref` ("NH 44"), and many main
    roads have a long descriptive name as well, so the two are joined: "Salem - Kochi Highway (NH 544)".
    A road with only a number is called by it."""
    name = (name or "").strip()
    ref = (ref or "").strip()
    if name and ref and ref.lower() not in name.lower():
        return f"{name} ({ref})"
    return name or ref


def read_ways_pbf(pbf: Path, box, classes, index_path: str):
    """Yield (way_id, highway, oneway, name, node_ids, lats, lons) for drivable ways whose first node
    lies inside `box` = (min_lat, max_lat, min_lon, max_lon)."""
    import osmium

    fp = (
        osmium.FileProcessor(str(pbf), osmium.osm.NODE | osmium.osm.WAY)
        .with_locations(f"sparse_file_array,{index_path}")
        .with_filter(osmium.filter.KeyFilter("highway"))
    )
    wanted = set(classes)
    try:
        for way in fp:
            if not way.is_way():
                continue
            hw = way.tags.get("highway")
            if hw not in wanted:
                continue
            ids, lats, lons = [], [], []
            ok = True
            for n in way.nodes:
                if not n.location.valid():
                    ok = False
                    break
                ids.append(n.ref)
                lats.append(n.location.lat)
                lons.append(n.location.lon)
            if not ok or len(ids) < 2:
                continue
            if not (box[0] <= lats[0] <= box[1] and box[2] <= lons[0] <= box[3]):
                continue
            ow = way.tags.get("oneway")
            oneway = 1 if ow in ("yes", "true", "1") else (-1 if ow == "-1" else 0)
            yield way.id, hw, oneway, display_name(way.tags.get("name"), way.tags.get("ref")), ids, lats, lons
    finally:
        del fp


def read_ways_overpass_json(path: Path, classes):
    """Same tuples from an Overpass `out geom` JSON file (used by the tests with the Testville fixture)."""
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    wanted = set(classes)
    for el in doc["elements"]:
        tags = el.get("tags", {})
        hw = tags.get("highway")
        if el.get("type") != "way" or hw not in wanted or len(el.get("nodes", [])) < 2:
            continue
        ow = tags.get("oneway")
        oneway = 1 if ow in ("yes", "true", "1") else (-1 if ow == "-1" else 0)
        yield (
            el["id"], hw, oneway, (tags.get("name") or "").strip(), list(el["nodes"]),
            [g["lat"] for g in el["geometry"]], [g["lon"] for g in el["geometry"]],
        )


PLACE_KINDS = ("city", "town", "village", "suburb")


def read_places_pbf(pbf: Path, box, kinds=PLACE_KINDS):
    """Named places inside `box`: [name, lat, lon, kind, alt names...]. Alternative names are the
    Tamil and English names when the node carries them, so a search in either script finds the place.
    `kinds` limits the OSM `place` values read; the default is the list the state packs were built with."""
    import osmium

    fp = osmium.FileProcessor(str(pbf), osmium.osm.NODE).with_filter(osmium.filter.KeyFilter("place"))
    out = []
    try:
        for n in fp:
            kind = n.tags.get("place")
            name = (n.tags.get("name") or "").strip()
            if kind not in kinds or not name or not n.location.valid():
                continue
            lat, lon = n.location.lat, n.location.lon
            if not (box[0] <= lat <= box[1] and box[2] <= lon <= box[3]):
                continue
            alts = []
            for key in ("name:ta", "name:en", "alt_name"):
                v = (n.tags.get(key) or "").strip()
                if v and v != name and v not in alts:
                    alts.append(v)
            out.append([name, round(lat, 5), round(lon, 5), kind, *alts])
    finally:
        del fp
    out.sort(key=lambda r: (r[3] != "city", r[3] != "town", r[0], r[1], r[2]))  # stable, readable
    return out


def write_places(places: list, out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    path = out / "places.json"
    path.write_text(json.dumps({"version": 1, "places": places}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    kinds = collections.Counter(r[3] for r in places)
    return {"count": len(places), "by_kind": dict(kinds), "bytes": path.stat().st_size, "sha256": sha256(path)}


# ------------------------------------------------------------------ building the arrays


class Built:
    """Compact graph arrays. Everything is a typed `array`, not a list of objects."""

    def __init__(self):
        self.node_lat = array("d")
        self.node_lon = array("d")
        self.src = array("i")
        self.dst = array("i")
        self.seconds = array("d")
        self.kmh = array("f")
        self.name_idx = array("H")
        self.hwy = array("B")
        self.names = [""]
        self.skipped_nameless_overflow = 0


# In a graph of main roads only, the places where small roads join are no longer junctions, so a long
# highway stretch would be one edge and a village beside it could only snap to a node miles away. An
# edge is therefore also ended once it is this long, which leaves a node to snap to every few hundred
# metres of road. 800 m is a choice, not a measurement.
MAX_EDGE_M = 800.0


def build_arrays(ways: list, max_edge_m: float = MAX_EDGE_M) -> Built:
    """Split ways at junctions (a node used by two or more ways, or a way end), like the Chennai
    builder, and also after `max_edge_m` of road; emit directed edges."""
    refs = collections.Counter()
    for _, _, _, _, ids, _, _ in ways:
        refs.update(ids)
    b = Built()
    node_index: dict[int, int] = {}
    name_lookup: dict[str, int] = {}
    hw_code = {h: i for i, h in enumerate(HIGHWAY_CODES)}

    def node(osm_id: int, lat: float, lon: float) -> int:
        i = node_index.get(osm_id)
        if i is None:
            i = len(b.node_lat)
            node_index[osm_id] = i
            b.node_lat.append(lat)
            b.node_lon.append(lon)
        return i

    for _way_id, hw, oneway, name, ids, lats, lons in ways:
        speed = SPEEDS_KMH[hw]
        code = hw_code[hw]
        nidx = -1  # resolved at the first edge this way emits, so the name table matches build_packs.py
        last = len(ids) - 1
        start = 0
        length = 0.0
        for i in range(1, len(ids)):
            length += haversine_m(lats[i - 1], lons[i - 1], lats[i], lons[i])
            if i == last or refs[ids[i]] >= 2 or length >= max_edge_m:
                if length > 0:
                    a = node(ids[start], lats[start], lons[start])
                    z = node(ids[i], lats[i], lons[i])
                    if a != z:
                        if nidx < 0:
                            if name:
                                nidx = name_lookup.get(name, -1)
                                if nidx < 0:
                                    nidx = len(b.names)
                                    name_lookup[name] = nidx
                                    b.names.append(name)
                            else:
                                nidx = 0
                        secs = length / (speed / 3.6)
                        directions = []
                        if oneway == -1:
                            directions.append((z, a))
                        elif oneway == 1:
                            directions.append((a, z))
                        else:
                            directions.append((a, z))
                            directions.append((z, a))
                        for f, t in directions:
                            b.src.append(f)
                            b.dst.append(t)
                            b.seconds.append(secs)
                            b.kmh.append(speed)
                            b.name_idx.append(nidx)
                            b.hwy.append(code)
                start = i
                length = 0.0
    return b


# ------------------------------------------------------------------ writing the pack


def _le(a: array, typecode: str) -> bytes:
    assert sys.byteorder == "little"
    return a.tobytes() if a.typecode == typecode else array(typecode, a).tobytes()


def write_pack(b: Built, out: Path) -> None:
    n_nodes, n_edges = len(b.node_lat), len(b.src)
    if len(b.names) > 65535:
        raise SystemExit(
            f"{len(b.names)} distinct street names do not fit the pack format's 16-bit name index "
            "(65,535); the format needs a v2 with a 32-bit index before this level can be built"
        )
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "graph.bin", "wb") as f:
        f.write(b"CPG1")
        f.write(struct.pack("<III", 1, n_nodes, n_edges))
        f.write(_le(b.src, "i"))
        f.write(_le(b.dst, "i"))
        f.write(_le(b.seconds, "d"))
        f.write(_le(b.kmh, "f"))
    with open(out / "nodes.bin", "wb") as f:
        f.write(b"CPN1")
        f.write(struct.pack("<III", 1, n_nodes, 0))
        f.write(_le(b.node_lat, "d"))
        f.write(_le(b.node_lon, "d"))
    encoded = [n.encode("utf-8") for n in b.names]
    offsets = [0]
    for e in encoded:
        offsets.append(offsets[-1] + len(e))
    with open(out / "meta.bin", "wb") as f:
        f.write(b"CPM1")
        f.write(struct.pack("<IIII", 1, n_edges, len(b.names), PRIOR_SCALE))
        f.write(struct.pack(f"<{n_edges}h", *([FLAT_PRIOR_MILLI] * n_edges)))
        f.write(_le(b.name_idx, "H"))
        f.write(_le(b.hwy, "B"))
        f.write(b"\0" * (-f.tell() % 4))
        f.write(struct.pack(f"<{len(offsets)}I", *offsets))
        for e in encoded:
            f.write(e)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--city", required=True)
    ap.add_argument("--levels", choices=sorted(LEVELS), default="backbone")
    ap.add_argument("--pbf", type=Path, default=DEFAULT_PBF)
    ap.add_argument("--date", default=datetime.now(timezone.utc).date().isoformat())
    ap.add_argument("--index", default=str(ROOT / "data" / "osm" / "_node_index.tmp"))
    ap.add_argument("--no-places", action="store_true", help="skip the named-places list")
    ap.add_argument("--places-only", action="store_true", help="add places.json to an existing pack; build nothing else")
    args = ap.parse_args(argv)

    city = load_city(args.city)
    if city.get("hazard_layer"):
        raise SystemExit(f"{args.city} is marked hazard_layer: true; this builder writes the flat prior only")
    box = (city["bbox"]["min_lat"], city["bbox"]["max_lat"], city["bbox"]["min_lon"], city["bbox"]["max_lon"])
    classes = LEVELS[args.levels]

    if args.places_only:
        out = ROOT / "data" / "packs" / f"{args.city}-{args.levels}-{args.date}"
        manifest_path = out / "manifest.json"
        if not manifest_path.exists():
            raise SystemExit(f"no pack at {out}; build it first")
        t0 = time.time()
        info = write_places(read_places_pbf(args.pbf, box), out)
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["places"] = {**info, "seconds": round(time.time() - t0, 1)}
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print(f"places: {info['count']:,} {info['by_kind']} -> {out / 'places.json'}")
        return 0

    t0 = time.time()
    ways = list(read_ways_pbf(args.pbf, box, classes, args.index))
    t_read = time.time() - t0
    print(f"{len(ways):,} ways read in {t_read:.0f}s", flush=True)
    t1 = time.time()
    built = build_arrays(ways)
    del ways
    t_build = time.time() - t1
    print(f"{len(built.node_lat):,} nodes, {len(built.src):,} edges, {len(built.names) - 1:,} names in {t_build:.0f}s", flush=True)

    out = ROOT / "data" / "packs" / f"{args.city}-{args.levels}-{args.date}"
    write_pack(built, out)

    manifest = {
        "pack": "citypulse-map-pack",
        "format_version": 1,
        "built": args.date,
        "script": "scripts/region_pack.py",
        "city": {
            "id": args.city,
            "bbox": city["bbox"],
            "centre": city["centre"],
            "hazard_layer": False,
            "levels": args.levels,
            "road_classes": classes,
        },
        "source_pbf": args.pbf.name,
        "source_pbf_bytes": args.pbf.stat().st_size,
        "cities_config_sha256": sha256(CITIES_PATH),
        "counts": {
            "nodes": len(built.node_lat),
            "edges": len(built.src),
            "named_edges": sum(1 for x in built.name_idx if x),
            "distinct_names": len(built.names) - 1,
        },
        "prior_scale": PRIOR_SCALE,
        "prior_note": "Flat default prior on every edge (p=0.02). No flood-hazard source is loaded.",
        "highway_codes": HIGHWAY_CODES,
        "licence_note": "OSM-derived (ODbL) graph and names. See data/MANIFEST.md.",
        "seconds": {"read_pbf": round(t_read, 1), "build_arrays": round(t_build, 1)},
        "files": {
            name: {"bytes": (out / name).stat().st_size, "sha256": sha256(out / name)}
            for name in ("graph.bin", "nodes.bin", "meta.bin")
        },
    }
    if not args.no_places:
        t2 = time.time()
        info = write_places(read_places_pbf(args.pbf, box), out)
        manifest["places"] = {**info, "seconds": round(time.time() - t2, 1)}
        print(f"places: {info['count']:,} {info['by_kind']}", flush=True)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    total = sum(v["bytes"] for v in manifest["files"].values())
    print(f"wrote {out}  ({total / 1e6:.1f} MB)")
    try:
        Path(args.index).unlink(missing_ok=True)
    except OSError as e:
        print(f"note: could not delete {args.index} ({e}); delete it by hand", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
