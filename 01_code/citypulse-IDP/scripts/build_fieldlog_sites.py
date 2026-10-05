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
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "watchlist" / "2026-09-14" / "watchlist_candidates.json"
OUT = ROOT / "server" / "app" / "fieldlog" / "sites.json"


def label(row: dict) -> str:
    street = ((row.get("snapped_edge") or {}).get("street_name") or "").strip()
    basin = (row.get("basin_label_heuristic") or "").strip()
    cid = row["candidate_id"]
    if street:
        return f"{street} (candidate {cid})"
    if basin:
        return f"{basin} area, unnamed road (candidate {cid})"
    return f"Unnamed road (candidate {cid})"


def build() -> dict:
    raw = SOURCE.read_bytes()
    rows = json.loads(raw.decode("utf-8"))
    sites = []
    seen = set()
    for r in sorted(rows, key=lambda x: x["candidate_id"]):
        cid = r["candidate_id"]
        if cid in seen:
            raise SystemExit(f"duplicate candidate id {cid}")
        seen.add(cid)
        lat, lon = float(r["centroid_lat"]), float(r["centroid_lon"])
        if not (12.0 <= lat <= 14.0 and 79.0 <= lon <= 81.0):
            raise SystemExit(f"{cid}: point {lat},{lon} is outside the Chennai region")
        cats = r.get("source_categories") or []
        sites.append({
            "id": cid,
            "label": label(r),
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
