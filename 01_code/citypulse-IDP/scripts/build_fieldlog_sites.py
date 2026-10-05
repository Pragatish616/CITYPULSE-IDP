"""Build the field-log site list from the watchlist candidates (PLAN M0.8 field-label pilot; ADR-028).

    python scripts/build_fieldlog_sites.py

Reads  data/watchlist/2026-09-14/watchlist_candidates.json  (402 candidate points from the GCC flood-hazard zones; none is verified on the
ground, ADR-009) and writes  server/app/fieldlog/sites.json , which ships inside the report server so the field-log page needs no other file.

Honesty rules baked in:
- Every site is a **candidate**: the point is the centre of a hazard-zone polygon snapped to the nearest road, not a surveyed waterlogging
  spot. The label says "candidate" and carries the id, so a volunteer can tell two sites with the same street name apart.
- The basin name is the watchlist's own heuristic and is marked unverified; it is shown as a hint, never as a fact.
- Deterministic: sorted by id, fixed rounding, no timestamps inside the file except the source's name and SHA-256.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "watchlist" / "2026-09-14" / "watchlist_candidates.json"
PLACES = ROOT / "data" / "places" / "chennai-2026-10-04" / "places.json"
OUT = ROOT / "server" / "app" / "fieldlog" / "sites.json"
NEAR_KINDS = {"suburb", "neighbourhood", "quarter", "town", "city"}
NEAR_MAX_M = 2000.0


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371008.8
    p = math.pi / 180
    a = math.sin((lat2 - lat1) * p / 2) ** 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * math.sin((lon2 - lon1) * p / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def load_places() -> list[tuple[str, float, float]]:
    """Named OSM places (data/places/chennai-2026-10-04, ODbL) a volunteer would recognise: suburbs, neighbourhoods, towns."""
    rows = json.loads(PLACES.read_text(encoding="utf-8"))["places"]
    return [(r[0], r[1], r[2]) for r in rows if r[3] in NEAR_KINDS]


def nearest_place(lat: float, lon: float, places: list[tuple[str, float, float]]) -> tuple[str, float] | None:
    best = min(places, key=lambda p: haversine_m(lat, lon, p[1], p[2]))
    d = haversine_m(lat, lon, best[1], best[2])
    return (best[0], d) if d <= NEAR_MAX_M else None


def label(row: dict, near: str | None) -> str:
    street = ((row.get("snapped_edge") or {}).get("street_name") or "").strip() or "Unnamed road"
    where = f", near {near}" if near else ""
    return f"{street}{where} (candidate {row['candidate_id']})"


def build() -> dict:
    raw = SOURCE.read_bytes()
    rows = json.loads(raw.decode("utf-8"))
    sites = []
    seen = set()
    places = load_places()
    for r in sorted(rows, key=lambda x: x["candidate_id"]):
        cid = r["candidate_id"]
        if cid in seen:
            raise SystemExit(f"duplicate candidate id {cid}")
        seen.add(cid)
        lat, lon = float(r["centroid_lat"]), float(r["centroid_lon"])
        if not (12.0 <= lat <= 14.0 and 79.0 <= lon <= 81.0):
            raise SystemExit(f"{cid}: point {lat},{lon} is outside the Chennai region")
        cats = r.get("source_categories") or []
        near = nearest_place(lat, lon, places)
        sites.append({
            "id": cid,
            "label": label(r, near[0] if near else None),
            "near": near[0] if near else None,
            "near_m": round(near[1] / 50) * 50 if near else None,
            "lat": round(lat, 5),
            "lon": round(lon, 5),
            "hazard_category": cats[0] if cats else None,
            "basin_hint": (r.get("basin_label_heuristic") or None),
            "basin_hint_verified": False,
            "verified_on_ground": bool(r.get("resident_signoff")),
        })
    return {
        "version": 1,
        "kind": "candidate",
        "note": "Candidate points from GCC flood-hazard zones. None is verified on the ground. Positions are zone centres snapped to a road.",
        "source": {"file": "data/watchlist/2026-09-14/watchlist_candidates.json", "sha256": hashlib.sha256(raw).hexdigest(), "rows": len(rows)},
        "places_source": {"file": "data/places/chennai-2026-10-04/places.json", "licence": "OpenStreetMap contributors, ODbL 1.0", "max_distance_m": NEAR_MAX_M},
        "sites": sites,
    }


def main() -> int:
    doc = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(doc['sites'])} sites")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
