"""Extract subway-like OpenStreetMap features inside a city's box (M3.1, ADR-031).

Reads the pinned OSM extract and writes every way or node that is plausibly a road/rail subway, underpass or tunnel on a road
or path: name tags that say subway/underpass/under-bridge/culvert (English or Tamil), or `tunnel=yes|culvert` on a highway
with a name. Nothing is judged here; `build_subway_list.py` matches these against the Greater Chennai Corporation's list.

Needs pyosmium, which the project venv does not have; use the separate osm environment:

    C:\\Users\\nprag\\AppData\\Local\\citypulse_osmenv\\Scripts\\python.exe scripts/extract_osm_subways.py --date 2026-10-09

Writes data/watchlist_raw/osm-subways-<date>.json (OpenStreetMap contributors, ODbL 1.0). About two to five minutes. It reuses
the node-location index file of earlier runs (data/osm/_node_index.tmp, git-ignored, about 1.2 GB) instead of making a new one.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PBF = Path(r"C:\Users\nprag\Downloads\citypulse-IDP\data\osm\southern-zone-260911.osm.pbf")
DEFAULT_INDEX = ROOT / "data" / "osm" / "_node_index.tmp"
# Chennai box of config/cities.yaml: min_lat, max_lat, min_lon, max_lon
BOX = (12.75, 13.25, 79.95, 80.35)
NAME_KEYS = ("name", "name:en", "name:ta", "alt_name", "old_name", "loc_name", "official_name", "short_name", "description", "note")
KEEP_TAGS = NAME_KEYS + ("highway", "tunnel", "layer", "bridge", "oneway", "ref", "railway", "access", "foot", "bicycle")
WORDS = ("subway", "underpass", "under bridge", "underbridge", "culvert", "tunnel", "சுரங்க")


def says_subway(tags) -> bool:
    for k in NAME_KEYS:
        v = (tags.get(k) or "").lower()
        if v and any(w in v for w in WORDS):
            return True
    return False


def length_m(lats, lons) -> float:
    total = 0.0
    for i in range(1, len(lats)):
        dy = (lats[i] - lats[i - 1]) * 111_195.0
        dx = (lons[i] - lons[i - 1]) * 111_195.0 * math.cos(math.radians(lats[i]))
        total += math.hypot(dx, dy)
    return round(total, 1)


def sha256(path: Path, limit: int = 1 << 24) -> str:
    """Hash of the first 16 MB plus the size: enough to name the extract without reading 557 MB twice."""
    h = hashlib.sha256()
    with path.open("rb") as f:
        h.update(f.read(limit))
    h.update(str(path.stat().st_size).encode())
    return h.hexdigest()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pbf", type=Path, default=DEFAULT_PBF)
    ap.add_argument("--index", type=Path, default=DEFAULT_INDEX)
    ap.add_argument("--date", default=datetime.now(timezone.utc).date().isoformat())
    args = ap.parse_args(argv)

    import osmium

    fp = osmium.FileProcessor(str(args.pbf), osmium.osm.NODE | osmium.osm.WAY).with_locations(
        f"sparse_file_array,{args.index}"
    )
    found = []
    try:
        for obj in fp:
            tags = obj.tags
            if obj.is_node():
                if not says_subway(tags) or not obj.location.valid():
                    continue
                lat, lon = obj.location.lat, obj.location.lon
                if not (BOX[0] <= lat <= BOX[1] and BOX[2] <= lon <= BOX[3]):
                    continue
                found.append({"type": "node", "id": obj.id, "lat": round(lat, 6), "lon": round(lon, 6), "length_m": 0.0,
                              "nodes": 1, "tags": {k: tags[k] for k in KEEP_TAGS if k in tags}})
                continue
            if not obj.is_way():
                continue
            highway = tags.get("highway")
            tunnel = tags.get("tunnel")
            named = bool((tags.get("name") or tags.get("name:ta") or "").strip())
            if not (says_subway(tags) or (highway and tunnel in ("yes", "culvert") and named)):
                continue
            lats, lons, ok = [], [], True
            for n in obj.nodes:
                if not n.location.valid():
                    ok = False
                    break
                lats.append(n.location.lat)
                lons.append(n.location.lon)
            if not ok or not lats:
                continue
            lat, lon = sum(lats) / len(lats), sum(lons) / len(lons)
            if not (BOX[0] <= lat <= BOX[1] and BOX[2] <= lon <= BOX[3]):
                continue
            found.append({"type": "way", "id": obj.id, "lat": round(lat, 6), "lon": round(lon, 6),
                          "length_m": length_m(lats, lons), "nodes": len(lats),
                          "tags": {k: tags[k] for k in KEEP_TAGS if k in tags}})
    finally:
        del fp
    found.sort(key=lambda e: (e["type"], e["id"]))
    out_dir = ROOT / "data" / "watchlist_raw"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"osm-subways-{args.date}.json"
    doc = {
        "kind": "osm_subway_candidates",
        "source": {"file": args.pbf.name, "bytes": args.pbf.stat().st_size, "fingerprint": sha256(args.pbf)},
        "licence": "OpenStreetMap contributors, ODbL 1.0",
        "box_min_lat_max_lat_min_lon_max_lon": list(BOX),
        "selection": "name tags with subway/underpass/under bridge/culvert/tunnel/Tamil சுரங்க, or highway with tunnel=yes|culvert and a name",
        "count": len(found),
        "features": found,
    }
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {out} ({len(found)} features)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
