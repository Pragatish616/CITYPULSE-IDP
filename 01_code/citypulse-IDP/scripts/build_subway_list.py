"""Build the Chennai subway watchlist (PLAN.md M3.1, ADR-031): the Greater Chennai Corporation's own table of subways, matched
to OpenStreetMap geometry where OSM has it, plus other subways that news or OSM name.

Inputs (all committed; nothing is fetched):
  data/watchlist/2026-10-09/gcc_subways_source.json   GCC Bridges Department table (16 road/rail + 5 pedestrian), transcribed row for row
  data/watchlist_raw/osm-subways-2026-10-09.json      OSM features from scripts/extract_osm_subways.py (ODbL)
  data/places/chennai-2026-10-04/places.json          OSM place names, for area hints

Outputs:
  data/watchlist/2026-10-09/subways.json              the watchlist, one entry per subway, with how its position was found
  data/watchlist/2026-10-09/CHECKSHEET.md             a sheet for two people to confirm each position on a map (M3.1 "Done when")
  server/app/fieldlog/subway_sites.json              the same entries in the shape the volunteer field log serves (ADR-028)

Every position is labelled: `osm_named` (an OSM way carries the subway's name), `osm_road_tunnel` (an OSM tunnel on the road the
GCC row names), `osm_hint` (an OSM feature near the described place whose identity is not certain) or `none` (no OSM geometry:
no coordinate is invented; the entry carries a clearly-labelled AREA hint instead). Nothing is verified on the ground.

    python scripts/build_subway_list.py
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATE = "2026-10-09"
SOURCE = ROOT / "data" / "watchlist" / DATE / "gcc_subways_source.json"
OSM = ROOT / "data" / "watchlist_raw" / f"osm-subways-{DATE}.json"
PLACES = ROOT / "data" / "places" / "chennai-2026-10-04" / "places.json"
OUT_LIST = ROOT / "data" / "watchlist" / DATE / "subways.json"
OUT_SITES = ROOT / "server" / "app" / "fieldlog" / "subway_sites.json"
OUT_SHEET = ROOT / "data" / "watchlist" / DATE / "CHECKSHEET.md"
AREA_KINDS = ("suburb", "neighbourhood", "quarter", "town", "city")
AREA_MAX_M = 2000.0
KNOWN_KINDS = ("suburb", "town", "city")
KNOWN_MAX_M = 1200.0
MAX_SPAN_M = 600.0  # the OSM pieces of one subway must lie this close to their common centre, or the rule is wrong

# One rule per GCC row. `name` is the display name; `names` are OSM names matched exactly (case-folded); `ids` are OSM way ids
# chosen by hand, with `why`. `quality` says how sure the position is. `area` names a place in places.json used only as a hint.
ROAD_RAIL = {
    1: {"name": "Ganesapuram subway", "names": ["Ganeshpuram Subway"], "quality": "osm_named", "area": "Vyasarpadi",
            "why": "OSM spells it 'Ganeshpuram Subway' and tags the way highway=construction; GCC places it east of Vyasarpadi Jeeva station"},
    2: {"name": "Monegar Choultry Road subway (near Stanley Hospital)", "ids": [666393460], "quality": "osm_road_tunnel", "area": "Old Washermanpet",
            "why": "the tunnel=yes way named Monegar Choultry Road, the road GCC row 2 names"},
    3: {"name": "Stanley Nagar subways 1 and 2 (Cochrane Basin Bridge Road)", "quality": "none", "area": "Stanley Nagar",
            "why": "no OSM feature carries this name; the area is only a hint (GCC: south of Stanley Nagar near the post office)"},
    4: {"name": "Reserve Bank (RBI) subway, Rajaji Salai", "names": ["RBI Subway"], "quality": "osm_named", "area": "George Town" , "why": ""},
    5: {"name": "Gengu Reddy Road subway, Egmore", "names": ["Gengu Reddy Subway"], "quality": "osm_named", "area": "Egmore", "why": ""},
    6: {"name": "Manickam Nagar subway", "quality": "none", "area": "Tiruvottiyur",
            "why": "no OSM feature carries this name; GCC lists it in zone I (Tiruvottiyur); the area is only a hint"},
    7: {"name": "Perambur subway, Perambur High Road", "ids": [457176568], "quality": "osm_hint", "area": "Perambur",
            "why": "the only OSM 'Perambur Subway' is a pedestrian tunnel near Perambur station; GCC row 7 is a road subway west of the station, so this is a hint, not the subway itself"},
    8: {"name": "Villivakkam subway (Redhills Road, LC-2)", "quality": "none", "area": "Villivakkam",
            "why": "no OSM feature carries this name; the area is only a hint"},
    9: {"name": "Nungambakkam subway", "names": ["Nungambakkam Subway"], "quality": "osm_named", "area": "Nungambakkam", "why": ""},
    10: {"name": "Harrington Road subway (Pachaiyappa's College)", "ids": [240340223, 240340224], "quality": "osm_road_tunnel",
             "area": "Chetpet", "why": "the tunnel=yes ways named Harrington Road, the road GCC row 10 names"},
    11: {"name": "Dheeran Sivalingam (Doraisamy) subway", "names": ["Doraiswamy Subway"], "quality": "osm_named", "area": "West Mambalam",
             "why": "GCC: Dheeran Sivalingam Subway connecting Doraisamy road and Brindavan Road; OSM and news call it Doraiswamy/Duraisamy"},
    12: {"name": "Madley subway", "names": ["Madley subway"], "quality": "osm_named", "area": "West Mambalam", "why": ""},
    13: {"name": "Thyagi Aranganathan subway", "names": ["Aranganathan Subway"], "quality": "osm_named", "area": "West Mambalam", "why": ""},
    14: {"name": "Saidapet Bazaar Road subway", "names": ["Bazaar Road Subway"], "quality": "osm_named", "area": "Saidapet", "why": ""},
    15: {"name": "C.P. Pavalavannan Bridge subway, Jones Road", "names": ["Jones Subway"], "quality": "osm_named", "area": "Saidapet",
             "why": "GCC calls it C.P. Pavalavannan Bridge in Jones Road; OSM calls it Jones Subway"},
    16: {"name": "Rangarajapuram level crossing subway (pedestrian and two-wheeler)", "ids": [723477928], "quality": "osm_road_tunnel",
             "area": "Kodambakkam", "why": "the tunnel=yes way named Rangarajapuram Main Road; GCC row 16 is at the Rangarajapuram level crossing"},
}
PEDESTRIAN = {
    1: {"name": "Rajaji Salai pedestrian subway (Beach Railway Station)", "names": ["Beach Railway Station Pedestrians Subway"],
            "quality": "osm_hint", "area": "George Town",
            "why": "OSM's 'Beach Railway Station Pedestrians Subway' is at the station GCC names; the names differ"},
    2: {"name": "Jamaliah pedestrian subway (Perambur Bus Terminus)", "quality": "none", "area": "Perambur", "why": "no OSM feature found"},
    3: {"name": "Perambur raised tunnels (railway lines, pedestrian)", "quality": "none", "area": "Perambur", "why": "no OSM feature found"},
    4: {"name": "Ezhilagam pedestrian subway (near MGR Samadhi)", "quality": "none", "area": "Chepauk", "why": "no OSM feature found"},
    5: {"name": "Kamarajar Salai pedestrian subway (Bharathi Salai, Triplicane)", "quality": "none", "area": "Triplicane",
            "why": "no OSM feature found"},
}
# Named in news but not on GCC's table.
NEWS_ONLY = [
    {"key": "choolaimedu-loyola", "name": "Choolaimedu (Loyola) subway", "match": "Choolaimedu, Loyola Subway", "area": None},
    {"key": "kathirvedu", "name": "Kathirvedu subway", "match": "Kathirvedu Subway", "area": "Kathirvedu"},
    {"key": "vyasarpadi", "name": "Vyasarpadi subway", "match": "Vyasarpadi subway", "area": "Vyasarpadi"},
]
# Named by OpenStreetMap, not on GCC's table: exact OSM names (case-folded).
OSM_ONLY = [
    ("thillaiganga-nagar", "Thillaiganga Nagar subway", ["thillaiganga nagar subway"]),
    ("st-thomas-mount", "St Thomas Mount subway", ["st thomas mount subway"]),
    ("radha-nagar", "Radha Nagar subway", ["radha nagar subway"]),
    ("easwari-nagar", "Easwari Nagar subway", ["easwari nagar subway", "easwari nagar subway underpass"]),
    ("chennai-central-square", "Chennai Central Square pedestrian subway", ["chennai central square subway"]),
    ("guindy", "Guindy pedestrian subway", ["guindy subway"]),
    ("ambattur-underpass", "Ambattur railway underpass (under construction in OSM)", ["ambattur railway underpass"]),
]


def dist_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    dy = (a[0] - b[0]) * 111_195.0
    dx = (a[1] - b[1]) * 111_195.0 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot(dx, dy)


def centre(features: list[dict]) -> dict | None:
    """Centre of the pieces that are tunnels (tunnel=yes|culvert or a negative layer) if there are any, else of all pieces."""
    if not features:
        return None
    tun = [f for f in features if f["tags"].get("tunnel") in ("yes", "culvert") or str(f["tags"].get("layer", "0")).startswith("-")]
    use = tun or features
    lat = sum(f["lat"] for f in use) / len(use)
    lon = sum(f["lon"] for f in use) / len(use)
    span = max(dist_m((lat, lon), (f["lat"], f["lon"])) for f in features)
    if span > MAX_SPAN_M:
        raise ValueError(f"OSM pieces lie {span:.0f} m from their centre (more than {MAX_SPAN_M:.0f} m); the match rule is wrong")
    return {"lat": round(lat, 5), "lon": round(lon, 5), "span_m": round(span), "pieces_used": len(use), "pieces_total": len(features)}


def osm_ref(f: dict) -> dict:
    t = f["tags"]
    return {"type": f["type"], "id": f["id"], "name": t.get("name"), "highway": t.get("highway"), "tunnel": t.get("tunnel"),
            "layer": t.get("layer")}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def area_hint(places: dict, name: str | None) -> dict | None:
    if name is None:
        return None
    for p in places["rows"]:
        if p[0].lower() == name.lower():
            return {"place": p[0], "kind": p[3], "lat": p[1], "lon": p[2],
                    "note": "the AREA the subway lies in or beside; not the subway's position"}
    raise ValueError(f"area hint {name!r} is not in places.json")


def nearest_area(places: dict, lat: float, lon: float) -> tuple[str | None, int | None]:
    """The familiar area name a volunteer would search by: a suburb or town within 1.2 km if there is one (those are the names
    people use), otherwise the nearest neighbourhood or quarter within 2 km."""
    best = best_known = None
    for p in places["rows"]:
        if p[3] not in AREA_KINDS:
            continue
        d = dist_m((lat, lon), (p[1], p[2]))
        if d <= AREA_MAX_M and (best is None or d < best[0]):
            best = (d, p[0])
        if p[3] in KNOWN_KINDS and d <= KNOWN_MAX_M and (best_known is None or d < best_known[0]):
            best_known = (d, p[0])
    chosen = best_known or best
    return (chosen[1], round(chosen[0])) if chosen else (None, None)


def build() -> tuple[dict, dict]:
    src = json.loads(SOURCE.read_text(encoding="utf-8"))
    osm = json.loads(OSM.read_text(encoding="utf-8"))
    places = {"rows": json.loads(PLACES.read_text(encoding="utf-8"))["places"]}
    feats = osm["features"]
    by_id = {(f["type"], f["id"]): f for f in feats}
    by_name: dict[str, list[dict]] = {}
    for f in feats:
        n = (f["tags"].get("name") or "").strip().lower()
        if n:
            by_name.setdefault(n, []).append(f)
    news = {}
    for row in src["news_name_forms_for_gcc_rows"]:
        news.setdefault(row["gcc_row"], []).append({"name": row["name_in_news"], "source": row["source"],
                                                    "relation": row.get("relation")})

    def match(rule: dict) -> list[dict]:
        found = []
        for n in rule.get("names", []):
            hits = by_name.get(n.lower(), [])
            if not hits:
                raise ValueError(f"no OSM feature named {n!r}: the extract changed or the rule is wrong")
            found += hits
        for i in rule.get("ids", []):
            if ("way", i) not in by_id:
                raise ValueError(f"OSM way {i} is not in the extract")
            found.append(by_id[("way", i)])
        return found

    entries = []

    def add(eid, listname, rule, gcc_no=None, zone_ward=None, gcc_location=None, news_names=None, notes=None, matched=None):
        pieces = matched if matched is not None else match(rule)
        pos = centre(pieces)
        ta = next((f["tags"]["name:ta"] for f in pieces if f["tags"].get("name:ta")), None)
        quality = rule["quality"] if pos else "none"
        if (rule["quality"] != "none") != bool(pos):
            raise ValueError(f"{eid}: rule says {rule['quality']} but {len(pieces)} OSM features matched")
        entries.append({
            "id": eid, "name": rule["name"], "name_ta": ta, "list": listname, "gcc_no": gcc_no, "zone_ward": zone_ward,
            "gcc_location": gcc_location, "names_in_news": news_names or [],
            "lat": pos["lat"] if pos else None, "lon": pos["lon"] if pos else None,
            "position": {"quality": quality, "osm_features": [osm_ref(f) for f in pieces],
                         "span_m": pos["span_m"] if pos else None, "note": rule.get("why") or None},
            "area_hint": area_hint(places, rule.get("area")),
            "verified_on_ground": False,
            "notes": notes,
        })

    for row in src["road_rail_subways"]:
        n = row["gcc_no"]
        add(f"sub-gcc-rr-{n:02d}", "gcc_road_rail", ROAD_RAIL[n], n, row["zone_ward"], row["location"], news.get(f"road_rail:{n}"))
    for row in src["pedestrian_subways"]:
        n = row["gcc_no"]
        add(f"sub-gcc-ped-{n:02d}", "gcc_pedestrian", PEDESTRIAN[n], n, row["zone_ward"], row["location"])
    news_rows = {r["name"]: r for r in src["named_in_news_not_on_gcc_table"]}
    for item in NEWS_ONLY:
        r = news_rows[item["match"]]
        rule = {"name": item["name"], "quality": "none", "area": item["area"], "why": "named in the news; no OSM feature found"}
        add(f"sub-news-{item['key']}", "news_only", rule, news_names=[{"name": r["name"], "source": r["source"], "relation": r["stated"]}],
            notes="not on GCC's Bridges Department table; identity relative to that table unresolved" if item["key"] == "vyasarpadi" else None)
    for key, name, osm_names in OSM_ONLY:
        pieces = []
        for n in osm_names:
            pieces += by_name.get(n, [])
        if not pieces:
            raise ValueError(f"no OSM feature named any of {osm_names}")
        rule = {"name": name, "quality": "osm_named", "area": None, "why": "named by OpenStreetMap; not on GCC's Bridges Department table"}
        add(f"sub-osm-{key}", "osm_only", rule, matched=pieces)

    for e in entries:
        if e["lat"] is not None:
            e["nearest_area"], e["nearest_area_m"] = nearest_area(places, e["lat"], e["lon"])
        else:
            e["nearest_area"] = e["area_hint"]["place"] if e["area_hint"] else None
            e["nearest_area_m"] = None
    counts = {k: sum(1 for e in entries if e["list"] == k) for k in ("gcc_road_rail", "gcc_pedestrian", "news_only", "osm_only")}
    quality = {}
    for e in entries:
        quality[e["position"]["quality"]] = quality.get(e["position"]["quality"], 0) + 1
    meta = {
        "version": 1, "kind": "subway_watchlist_candidates", "date": DATE,
        "note": ("Candidates, not a verified list. The Greater Chennai Corporation's table is the backbone; positions come from "
                 "OpenStreetMap where it has the subway and are labelled by how sure the match is. NOTHING is verified on the ground. "
                 "News reports of '22 subways' do not give names, so this list makes no claim to equal them."),
        "sources": src["sources"] | {"openstreetmap": {"title": "OpenStreetMap extract southern-zone-260911, subway candidates",
                                                       "licence": "OpenStreetMap contributors, ODbL 1.0", "file": OSM.name,
                                                       "sha256": sha256(OSM)}},
        "source_sha256": {"gcc_subways_source.json": sha256(SOURCE), "places.json": sha256(PLACES)},
        "counts": counts, "position_quality": dict(sorted(quality.items())), "entries_total": len(entries),
    }
    listing = meta | {"entries": entries}

    sites = []
    kind_text = {"gcc_road_rail": "GCC road/rail subway", "gcc_pedestrian": "GCC pedestrian subway",
                 "news_only": "named in the news", "osm_only": "named in OpenStreetMap"}
    for e in entries:
        tail = f"{kind_text[e['list']]}" + (f" {e['gcc_no']}" if e["gcc_no"] else "") + (f", ward {e['zone_ward']}" if e["zone_ward"] else "")
        aliases = [n["name"] for n in e["names_in_news"]] + ([e["name_ta"]] if e["name_ta"] else [])
        if e["gcc_location"]:
            aliases.append(re.sub(r"\s+", " ", e["gcc_location"]).strip())
        sites.append({
            "id": e["id"], "label": f"{e['name']} ({tail}) [{e['id']}]", "site_kind": "subway", "list": e["list"],
            "near": e["nearest_area"], "near_m": e["nearest_area_m"], "lat": e["lat"], "lon": e["lon"],
            "position_quality": e["position"]["quality"], "aliases": aliases, "verified_on_ground": False,
        })
    site_doc = {
        "version": 1, "kind": "subway_candidates",
        "note": "Subways from GCC's Bridges Department table, with news and OpenStreetMap names. Unverified. Where lat/lon are null "
                "the position is unknown (only an area is given): find the subway on the ground and log it by name.",
        "source": {"file": "data/watchlist/2026-10-09/subways.json", "sha256": None}, "count": len(sites), "sites": sites,
    }
    return listing, site_doc


def build_checksheet(listing: dict) -> str:
    """A markdown table, one row per subway, with an OpenStreetMap link at the stated position and blank columns to fill in."""
    lines = [
        "# Subway check sheet (generated by scripts/build_subway_list.py; do not edit, copy it to fill in)",
        "",
        (f"Watchlist {listing['date']}: {listing['entries_total']} candidates. None is verified on the ground. "
        "For each row, open the map link and look at the place the GCC row describes. Mark the first column `yes` (a subway is "
        "within 50 m of the pin), `near` (it is within 200 m; write the distance and direction) or `no`. Where there is no pin, "
        "find the subway on the map or on the ground and write its latitude and longitude. Check at least 30 positions, two "
        "people each, and fix or remove any that is more than 100 m out (PLAN.md M3.1)."),
        "",
        "| Found? (yes / near / no) | Id | Subway | GCC row and ward | How the position was found | Map | Latitude, longitude if corrected | Checked by, date |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for e in listing["entries"]:
        where = (f"[open map](https://www.openstreetmap.org/?mlat={e['lat']}&mlon={e['lon']}#map=18/{e['lat']}/{e['lon']})"
                 if e["lat"] is not None else "no pin: search by name")
        row = f"GCC {e['list'].replace('gcc_', '').replace('_', '/')} {e['gcc_no']}, ward {e['zone_ward']}" if e["gcc_no"] else e["list"].replace("_", " ")
        lines.append(f"| | {e['id']} | {e['name']} | {row} | {e['position']['quality']} | {where} | | |")
    return "\n".join(lines) + "\n"


def main() -> int:
    listing, site_doc = build()
    OUT_LIST.parent.mkdir(parents=True, exist_ok=True)
    OUT_LIST.write_text(json.dumps(listing, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    OUT_SHEET.write_text(build_checksheet(listing), encoding="utf-8")
    site_doc["source"]["sha256"] = sha256(OUT_LIST)
    OUT_SITES.write_text(json.dumps(site_doc, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {OUT_LIST.relative_to(ROOT)} ({listing['entries_total']} entries: {listing['counts']}; positions {listing['position_quality']})")
    print(f"wrote {OUT_SITES.relative_to(ROOT)} ({site_doc['count']} sites)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
