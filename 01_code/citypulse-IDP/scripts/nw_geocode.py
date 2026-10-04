"""Step 2 (ADR-025): a point for every district, from the Open-Meteo geocoding service.

For each district in districts.csv, ask for places with that name in India, keep those whose first-level
region (state) matches the district's state, and choose by this fixed rule:
  1. feature codes starting PPLA (administrative seats) before PPL (other populated places);
  2. a result whose second-level region (district) equals the name before one that does not;
  3. the largest population.
If nothing matches the state, one more query "<name> district" is tried. Districts still unmatched are
recorded as unresolved, not guessed. Two names in one state that land on the same point (within 0.01 degrees)
are treated as spellings of one district.

The point is a district seat or large town, not a centroid; at the 0.25 degree rainfall grid this is adequate.
Writes data/nationwide_flood/<date>/geocode.json (choices and unresolved list) and geocode_raw/ (every answer).
"""

from __future__ import annotations

import csv
import json
import re
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
DATE = "2026-10-04"
URL = "https://geocoding-api.open-meteo.com/v1/search"
STATE_ALIAS = {
    "newdelhi": "delhi", "dadarnagarhaveli": "dadraandnagarhaveli", "jammukashmir": "jammuandkashmir",
    "andamannicobarislands": "andamanandnicobarislands", "nctofdelhi": "delhi",
}


def norm_state(s: str) -> str:
    k = re.sub(r"[^a-z]", "", s.lower().replace("&", "and"))
    return STATE_ALIAS.get(k, k)


def norm(s: str) -> str:
    return re.sub(r"[^a-z]", "", s.lower())


def query(name: str, tries: int = 6) -> list[dict]:
    for attempt in range(tries):
        r = requests.get(URL, params={"name": name, "count": 20, "language": "en", "countryCode": "IN"}, timeout=60)
        if r.status_code == 200:
            return r.json().get("results", []) or []
        time.sleep(min(60, 2**attempt * 2))
    raise RuntimeError(f"geocoding failed for {name!r}: {r.status_code} {r.text[:120]}")


def choose(results: list[dict], name: str, state: str) -> dict | None:
    ok = [r for r in results if norm_state(r.get("admin1", "") or "") == norm_state(state)]
    if not ok:
        return None
    def rank(r):
        fc = r.get("feature_code") or ""
        return (0 if fc.startswith("PPLA") else 1 if fc.startswith("PPL") else 2,
                0 if norm(r.get("admin2", "") or "") == norm(name) else 1,
                -(r.get("population") or 0))
    return sorted(ok, key=rank)[0]


def main() -> int:
    base = ROOT / "data" / "nationwide_flood" / DATE
    raw = base / "geocode_raw"
    raw.mkdir(exist_ok=True)
    dist = list(csv.DictReader((base / "districts.csv").open(encoding="utf-8")))
    chosen, unresolved = {}, []
    for i, d in enumerate(dist):
        did, name, state = d["district_id"], d["name"], d["state"]
        cache = raw / (re.sub(r"[^A-Za-z0-9]+", "_", did) + ".json")
        if cache.exists():
            res = json.loads(cache.read_text(encoding="utf-8"))
        else:
            res = {"by_name": query(name)}
            if choose(res["by_name"], name, state) is None:
                res["by_name_district"] = query(f"{name} district")
            cache.write_text(json.dumps(res, ensure_ascii=False), encoding="utf-8")
            time.sleep(0.15)
        pick = choose(res["by_name"], name, state) or choose(res.get("by_name_district", []), name, state)
        if pick is None:
            unresolved.append(did)
            continue
        chosen[did] = {k: pick.get(k) for k in ("name", "latitude", "longitude", "elevation", "feature_code", "admin1", "admin2", "population")}
        if (i + 1) % 100 == 0:
            print(f"{i + 1}/{len(dist)}", file=sys.stderr)
    # merge spellings: same state and the same point
    canonical, merged = {}, {}
    for did, c in sorted(chosen.items()):
        key = (did.split("|")[0], round(c["latitude"], 2), round(c["longitude"], 2))
        if key in canonical:
            merged[did] = canonical[key]
        else:
            canonical[key] = did
    out = {"chosen": {k: v for k, v in chosen.items() if k not in merged}, "merged_into": merged, "unresolved": unresolved}
    (base / "geocode.json").write_text(json.dumps(out, indent=1, ensure_ascii=False, sort_keys=True), encoding="utf-8")
    print(f"districts {len(dist)}; resolved {len(chosen)}; after merging spellings {len(out['chosen'])}; unresolved {len(unresolved)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
