"""Build a city's search gazetteer (neighbourhoods and suburbs) from the OSM extract.

Why this exists. The Chennai map pack carries street names only, so a search for "Adyar" or "T. Nagar" found
streets that merely contain those words. The Tamil Nadu pack already has a `places.json`, but it was built
without OSM's `neighbourhood` places (254 inside the Chennai box). This writes a separate, dated file instead of
changing the pinned pack folder (CLAUDE.md §2 rule 3):

    data/places/<city>-<date>/places.json     {"version": 1, "places": [[name, lat, lon, kind, alt...], ...]}
    data/places/<city>-<date>/manifest.json   counts, source, checksums, every alias and extra place applied

`config/cities.yaml` points the city at it with a `places:` key.

Two small, reviewed input files sit next to this script's output (both committed):
  * aliases: other spellings people type for a place OSM already has (for example "T. Nagar" for
    "Thiyagaraya Nagar"). The target must exist in the OSM list or the build stops; nothing is invented.
  * extras: a place OSM has no `place=*` node for, given a point copied from a named OSM node of another kind
    (Velachery has only a railway-station node). The OSM node id/tags are recorded in the file and the manifest.

Usage:
    python scripts/build_places.py --city chennai --date 2026-10-04
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import region_pack as rp  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
# Kinds searched. `hamlet`, `locality` (unnamed-area labels) and the odd `plot`/`square` are left out on purpose:
# they are the noisy part of the OSM place list.
KINDS = ("city", "town", "suburb", "neighbourhood", "quarter", "village")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--city", required=True)
    ap.add_argument("--date", default=datetime.now(timezone.utc).date().isoformat())
    ap.add_argument("--pbf", type=Path, default=rp.DEFAULT_PBF)
    ap.add_argument("--aliases", type=Path, help="JSON {OSM name: [other spellings]}; default data/places/<city>_aliases.json")
    ap.add_argument("--extras", type=Path, help="JSON list of extra places; default data/places/<city>_extras.json")
    args = ap.parse_args(argv)

    city = rp.load_city(args.city)
    box = (city["bbox"]["min_lat"], city["bbox"]["max_lat"], city["bbox"]["min_lon"], city["bbox"]["max_lon"])
    aliases_path = args.aliases or ROOT / "data" / "places" / f"{args.city}_aliases.json"
    extras_path = args.extras or ROOT / "data" / "places" / f"{args.city}_extras.json"
    aliases = json.loads(aliases_path.read_text(encoding="utf-8")) if aliases_path.exists() else {}
    extras = json.loads(extras_path.read_text(encoding="utf-8")) if extras_path.exists() else []

    places = rp.read_places_pbf(args.pbf, box, kinds=KINDS)
    by_name = {}
    for row in places:
        by_name.setdefault(row[0], []).append(row)

    applied_aliases = {}
    for osm_name, spellings in aliases.items():
        rows = by_name.get(osm_name)
        if not rows:
            raise SystemExit(f"alias target '{osm_name}' is not an OSM place in the {args.city} box; fix {aliases_path.name}")
        for row in rows:
            for s in spellings:
                if s and s != row[0] and s not in row[4:]:
                    row.append(s)
        applied_aliases[osm_name] = spellings

    existing = {r[0].casefold() for r in places}
    applied_extras = []
    for e in extras:
        name, lat, lon, kind = e["name"], float(e["lat"]), float(e["lon"]), e["kind"]
        if kind not in KINDS:
            raise SystemExit(f"extra '{name}': kind '{kind}' not in {KINDS}")
        if not (box[0] <= lat <= box[1] and box[2] <= lon <= box[3]):
            raise SystemExit(f"extra '{name}' is outside the {args.city} box")
        if name.casefold() in existing:
            raise SystemExit(f"extra '{name}' already exists as an OSM place; remove it from {extras_path.name}")
        if not e.get("source"):
            raise SystemExit(f"extra '{name}' must record its OSM source")
        places.append([name, round(lat, 5), round(lon, 5), kind, *[a for a in e.get("alt", []) if a]])
        applied_extras.append(e)

    places.sort(key=lambda r: (r[3] != "city", r[3] != "town", r[0], r[1], r[2]))
    out = ROOT / "data" / "places" / f"{args.city}-{args.date}"
    info = rp.write_places(places, out)
    manifest = {
        "city": args.city, "built": args.date, "built_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "script": "scripts/build_places.py", "bbox": list(box), "kinds": list(KINDS),
        "source_extract": args.pbf.name, "source_extract_bytes": args.pbf.stat().st_size,
        "licence": "OpenStreetMap contributors, ODbL 1.0",
        "places_json": info, "aliases_applied": applied_aliases, "extras_applied": applied_extras,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"places: {info['count']:,} {info['by_kind']} -> {out / 'places.json'}; aliases {len(applied_aliases)}, extras {len(applied_extras)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
