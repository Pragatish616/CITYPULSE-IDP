"""Extract the CityPulse places layer for a city box from the pinned OpenStreetMap extract.

Shops, schools, hospitals, police and fire stations, bus stands and stops, rail and metro stations, temples, mosques and churches,
landmarks, parks, banks, fuel, public services and utilities, and traffic signals, each as one point (a way is placed at its first
node, which is close enough to draw a pin on). Nothing is judged or invented: every point, name and kind is an OpenStreetMap tag.

Needs pyosmium, which the project venv does not have; use the separate osm environment:

    C:\\Users\\nprag\\AppData\\Local\\citypulse_osmenv\\Scripts\\python.exe scripts/extract_osm_places.py --date 2026-10-15

Writes data/places/chennai-poi-<date>/poi.json and manifest.json (OpenStreetMap contributors, ODbL 1.0). Three passes over the
extract, each read by pyosmium's C++ filters; no node-location index file is needed, so it uses little disk.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PBF = Path(r"C:\Users\nprag\Downloads\citypulse-IDP\data\osm\southern-zone-260911.osm.pbf")
BOX = (12.75, 13.25, 79.95, 80.35)  # Chennai box, as in extract_osm_subways.py: min lat, max lat, min lon, max lon

# (id, English label, Tamil label). The order is the order of the legend.
CATEGORIES = [
    ("education", "Schools and colleges", "பள்ளிகள், கல்லூரிகள்"),
    ("health", "Hospitals, clinics and pharmacies", "மருத்துவமனைகள், மருந்தகங்கள்"),
    ("police", "Police", "காவல் நிலையங்கள்"),
    ("fire", "Fire stations", "தீயணைப்பு நிலையங்கள்"),
    ("bus", "Bus stands and stops", "பேருந்து நிலையங்கள், நிறுத்தங்கள்"),
    ("rail", "Rail and metro stations", "ரயில், மெட்ரோ நிலையங்கள்"),
    ("worship", "Temples, mosques and churches", "கோயில்கள், மசூதிகள், தேவாலயங்கள்"),
    ("landmark", "Landmarks and attractions", "முக்கிய இடங்கள்"),
    ("park", "Parks and grounds", "பூங்காக்கள், மைதானங்கள்"),
    ("shop", "Shops and markets", "கடைகள், சந்தைகள்"),
    ("food", "Restaurants and cafes", "உணவகங்கள்"),
    ("money", "Banks and ATMs", "வங்கிகள், ஏடிஎம்"),
    ("fuel", "Fuel stations", "எரிபொருள் நிலையங்கள்"),
    ("utility", "Public services and utilities", "பொது சேவைகள்"),
    ("signal", "Traffic signals", "போக்குவரத்து சிக்னல்கள்"),
]
CAT_INDEX = {c[0]: i for i, c in enumerate(CATEGORIES)}

# Kinds that are useful on the map even without a name; they get a plain label instead.
UNNAMED_OK = {
    ("bus", "bus stop"), ("money", "atm"), ("fuel", "fuel"), ("utility", "toilets"), ("utility", "drinking water"),
    ("police", "police"), ("fire", "fire station"), ("health", "hospital"), ("signal", "traffic signals"),
}

AMENITY = {
    "school": ("education", "school"), "kindergarten": ("education", "kindergarten"), "college": ("education", "college"),
    "university": ("education", "university"),
    "hospital": ("health", "hospital"), "clinic": ("health", "clinic"), "doctors": ("health", "doctors"),
    "pharmacy": ("health", "pharmacy"), "dentist": ("health", "dentist"), "health_post": ("health", "health post"),
    "police": ("police", "police"), "fire_station": ("fire", "fire station"),
    "bus_station": ("bus", "bus stand"),
    "restaurant": ("food", "restaurant"), "cafe": ("food", "cafe"), "fast_food": ("food", "fast food"),
    "food_court": ("food", "food court"),
    "bank": ("money", "bank"), "atm": ("money", "atm"), "bureau_de_change": ("money", "money exchange"),
    "fuel": ("fuel", "fuel"), "charging_station": ("fuel", "charging station"),
    "marketplace": ("shop", "market"),
    "post_office": ("utility", "post office"), "townhall": ("utility", "town hall"),
    "community_centre": ("utility", "community centre"), "library": ("utility", "library"),
    "courthouse": ("utility", "court"), "toilets": ("utility", "toilets"), "drinking_water": ("utility", "drinking water"),
    "shelter": ("utility", "shelter"), "social_facility": ("utility", "social facility"),
    "public_building": ("utility", "public building"), "water_point": ("utility", "water point"),
}
RELIGION = {"hindu": "temple", "muslim": "mosque", "christian": "church", "jain": "jain temple", "sikh": "gurdwara",
            "buddhist": "buddhist temple"}
TOURISM = {"attraction": "attraction", "museum": "museum", "viewpoint": "viewpoint", "zoo": "zoo",
           "theme_park": "theme park", "gallery": "gallery", "aquarium": "aquarium"}
LEISURE = {"park": "park", "garden": "garden", "stadium": "stadium", "sports_centre": "sports centre",
           "nature_reserve": "nature reserve"}
WAY_KEYS = ("amenity", "shop", "tourism", "historic", "leisure", "railway", "public_transport", "office", "power",
            "man_made", "emergency")
NODE_KEYS = WAY_KEYS + ("highway",)


def classify(tags) -> tuple[str, str] | None:
    """The category and kind for an OSM object's tags, or None if it is not a place on this layer."""
    get = tags.get
    amenity = get("amenity")
    if amenity == "place_of_worship":
        return "worship", RELIGION.get(get("religion") or "", "place of worship")
    if amenity in AMENITY:
        return AMENITY[amenity]
    if get("highway") == "bus_stop":
        return "bus", "bus stop"
    if get("highway") == "traffic_signals":
        return "signal", "traffic signals"
    railway = get("railway")
    if railway in ("station", "halt") or (get("public_transport") == "station" and railway):
        return "rail", "metro station" if get("station") == "subway" or get("subway") == "yes" else "railway station"
    if get("shop"):
        return "shop", get("shop").replace("_", " ")
    if get("tourism") in TOURISM:
        return "landmark", TOURISM[get("tourism")]
    if get("historic"):
        return "landmark", get("historic").replace("_", " ")
    if get("leisure") in LEISURE:
        return "park", LEISURE[get("leisure")]
    if get("emergency") == "ambulance_station":
        return "health", "ambulance station"
    if get("office") == "government":
        return "utility", "government office"
    if get("power") in ("substation", "plant"):
        return "utility", "power " + get("power")
    if get("man_made") in ("water_tower", "water_works", "wastewater_plant"):
        return "utility", get("man_made").replace("_", " ")
    return None


def names(tags) -> tuple[str, str]:
    en = (tags.get("name:en") or tags.get("name") or "").strip()
    ta = (tags.get("name:ta") or "").strip()
    return en[:80], ta[:80]


def inside(lat: float, lon: float) -> bool:
    return BOX[0] <= lat <= BOX[1] and BOX[2] <= lon <= BOX[3]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pbf", type=Path, default=DEFAULT_PBF)
    ap.add_argument("--date", default=datetime.now(timezone.utc).date().isoformat())
    args = ap.parse_args(argv)

    import osmium
    from osmium.filter import IdFilter, KeyFilter

    places: list[list] = []
    seen: set[tuple] = set()

    def add(lat: float, lon: float, cat: str, kind: str, en: str, ta: str) -> None:
        if not en and (cat, kind) not in UNNAMED_OK:
            return
        key = (round(lat, 5), round(lon, 5), cat, en)
        if key in seen:
            return
        seen.add(key)
        places.append([round(lat, 5), round(lon, 5), CAT_INDEX[cat], en, kind, ta])

    # Pass 1: tagged ways (shops and schools are often drawn as buildings). Keep each candidate's first node.
    pending: dict[int, tuple] = {}
    fp = osmium.FileProcessor(str(args.pbf), osmium.osm.WAY).with_filter(KeyFilter(*WAY_KEYS))
    for w in fp:
        hit = classify(w.tags)
        if hit is None or len(w.nodes) == 0:
            continue
        en, ta = names(w.tags)
        if not en and hit not in UNNAMED_OK:
            continue
        pending.setdefault(w.nodes[0].ref, (hit[0], hit[1], en, ta))
    del fp

    # Pass 2: tagged nodes inside the box.
    fp = osmium.FileProcessor(str(args.pbf), osmium.osm.NODE).with_filter(KeyFilter(*NODE_KEYS))
    for n in fp:
        if not n.location.valid():
            continue
        lat, lon = n.location.lat, n.location.lon
        if not inside(lat, lon):
            continue
        hit = classify(n.tags)
        if hit is None:
            continue
        en, ta = names(n.tags)
        add(lat, lon, hit[0], hit[1], en, ta)
    del fp

    # Pass 3: the first node of each candidate way, by id.
    if pending:
        fp = osmium.FileProcessor(str(args.pbf), osmium.osm.NODE).with_filter(IdFilter(pending.keys()))
        for n in fp:
            if not n.location.valid():
                continue
            lat, lon = n.location.lat, n.location.lon
            if not inside(lat, lon):
                continue
            cat, kind, en, ta = pending[n.id]
            add(lat, lon, cat, kind, en, ta)
        del fp

    places.sort(key=lambda p: (p[2], p[3], p[0], p[1]))
    out_dir = ROOT / "data" / "places" / f"chennai-poi-{args.date}"
    out_dir.mkdir(parents=True, exist_ok=True)
    doc = {
        "version": 1,
        "source": "OpenStreetMap contributors, ODbL 1.0",
        "box": {"min_lat": BOX[0], "max_lat": BOX[1], "min_lon": BOX[2], "max_lon": BOX[3]},
        "categories": [{"id": c[0], "en": c[1], "ta": c[2]} for c in CATEGORIES],
        "fields": ["lat", "lon", "category", "name", "kind", "name_ta"],
        "places": places,
    }
    poi = out_dir / "poi.json"
    poi.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    counts = Counter(CATEGORIES[p[2]][0] for p in places)
    manifest = {
        "built": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "script": "scripts/extract_osm_places.py",
        "source_pbf": args.pbf.name,
        "source_sha256": sha256(args.pbf),
        "licence": "ODbL 1.0, (c) OpenStreetMap contributors",
        "places": len(places),
        "by_category": {c[0]: counts.get(c[0], 0) for c in CATEGORIES},
        "poi_json_sha256": sha256(poi),
        "poi_json_bytes": poi.stat().st_size,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    print(json.dumps(manifest, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
