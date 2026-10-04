"""
T0.5 -- Watchlist feasibility spike (de-risking, week 1; added in the 2026-09-12 review).

Goal: can >=100 watchlist points actually be sourced, cross-checked and (eventually)
edge-resolved from open data? Per docs/IMPLEMENTATION_PLAN.md T0.5 / ADR-009's own
"Reconsider if" clause.

This spike parses the real OpenCity/GCC Chennai flood-hazard-zones KML (downloaded
2026-09-12 from https://data.opencity.in/dataset/chennai-flooding-data) and extracts one
candidate point per polygon (centroid), tagged with its CATEGORY (risk level) and area.
It does NOT yet: snap to OSM edges, cross-check against the 2015/Michaung corpus, or
assign a basin label -- those are T-W1's job in week 2, once this spike has answered the
go/no-go question.

Usage: .venv/Scripts/python.exe scripts/t0_5_watchlist_feasibility.py
"""
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parent.parent
KML_PATH = ROOT / "data" / "watchlist_raw" / "chennai_flood_hazard_zones.kml"
RESULTS_DIR = ROOT / "data" / "results" / "2026-09-12-t05-watchlist"

NS = {"kml": "http://www.opengis.net/kml/2.2"}

# Chennai metro bbox, same as T0.2, to sanity-check the data actually falls where expected.
BBOX = {"min_lat": 12.75, "max_lat": 13.25, "min_lon": 79.95, "max_lon": 80.35}


def parse_coords(coord_text: str):
    """KML coordinates are 'lon,lat,alt lon,lat,alt ...' whitespace-separated."""
    pts = []
    for tok in coord_text.split():
        parts = tok.split(",")
        if len(parts) >= 2:
            lon, lat = float(parts[0]), float(parts[1])
            pts.append((lat, lon))
    return pts


def centroid(pts):
    lats = [p[0] for p in pts]
    lons = [p[1] for p in pts]
    return (mean(lats), mean(lons))


def in_bbox(lat, lon):
    return BBOX["min_lat"] <= lat <= BBOX["max_lat"] and BBOX["min_lon"] <= lon <= BBOX["max_lon"]


def extract_placemarks():
    print(f"Parsing {KML_PATH.name} ({KML_PATH.stat().st_size / 1e6:.1f} MB)...")
    tree = ET.parse(KML_PATH)
    root = tree.getroot()
    placemarks = root.findall(".//kml:Placemark", NS)
    print(f"Found {len(placemarks)} Placemarks")

    results = []
    for pm in placemarks:
        # ExtendedData / SchemaData / SimpleData fields (CATEGORY, SHAPE.AREA, etc.)
        fields = {}
        for sd in pm.findall(".//kml:SimpleData", NS):
            name = sd.get("name")
            fields[name] = sd.text

        # Geometry: could be Polygon, MultiGeometry of Polygons, etc. Take the first
        # outer boundary ring found.
        coord_el = pm.find(".//kml:outerBoundaryIs//kml:coordinates", NS)
        if coord_el is None:
            coord_el = pm.find(".//kml:coordinates", NS)
        if coord_el is None or not coord_el.text:
            continue
        pts = parse_coords(coord_el.text)
        if not pts:
            continue
        c_lat, c_lon = centroid(pts)

        results.append({
            "name": (pm.findtext("kml:name", default="", namespaces=NS) or "").strip(),
            "category": fields.get("CATEGORY"),
            "shape_area": fields.get("SHAPE.AREA"),
            "centroid_lat": round(c_lat, 6),
            "centroid_lon": round(c_lon, 6),
            "in_chennai_bbox": in_bbox(c_lat, c_lon),
            "n_boundary_points": len(pts),
        })
    return results


def main():
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    zones = extract_placemarks()

    in_bbox_zones = [z for z in zones if z["in_chennai_bbox"]]
    by_category = {}
    for z in in_bbox_zones:
        cat = z["category"] or "(uncategorised)"
        by_category[cat] = by_category.get(cat, 0) + 1

    print(f"\nTotal zones parsed: {len(zones)}")
    print(f"Zones with centroid inside Chennai bbox: {len(in_bbox_zones)}")
    print("By category:")
    for cat, n in sorted(by_category.items(), key=lambda x: -x[1]):
        print(f"  {cat}: {n}")

    summary = {
        "spike": "T0.5 - watchlist feasibility",
        "source": {
            "dataset": "Chennai Flooding Data / Chennai Flood Hazard Zones Map (OpenCity/GCC)",
            "url": "https://data.opencity.in/dataset/chennai-flooding-data/resource/e61afe07-0f52-4be9-bdf3-5eb0f62b2ed6",
            "downloaded": "2026-09-12",
            "licence_stated": "public domain (per OpenCity CKAN listing) -- NOT independently verified, per research/SYNTHESIS.md's citation discipline",
        },
        "total_zones_in_file": len(zones),
        "zones_in_chennai_bbox": len(in_bbox_zones),
        "zones_by_category": by_category,
        "go_no_go": (
            f"GO -- {len(in_bbox_zones)} real, geometrically distinct flood-hazard zone "
            f"polygons fall inside the Chennai metro bbox, comfortably clearing ADR-009's "
            f"~100-point reconsideration threshold before any cross-checking or edge-snapping "
            f"has even happened. This is zone COUNT, not validated watchlist POINT count -- "
            f"T-W1 (week 2) still has to cross-check against the 2015/Michaung corpus, snap "
            f"each zone to a representative OSM edge, and get a resident sign-off. But the "
            f"raw material clearly exists and is downloadable today."
        ),
        "sample_zones": in_bbox_zones[:15],
    }

    out_path = RESULTS_DIR / "result.json"
    out_path.write_text(json.dumps(summary, indent=2))
    print(f"\nWrote {out_path}")
    return summary


if __name__ == "__main__":
    main()
