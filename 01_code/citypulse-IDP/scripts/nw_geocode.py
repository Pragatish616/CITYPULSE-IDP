"""Step 2 (ADR-025): a point for every district, from the Open-Meteo geocoding service.

For each district in districts.csv, ask for places with that name in India, keep those whose first-level
region (state) matches the district's state, and choose by this fixed rule:
  1. feature codes starting PPLA (administrative seats) before PPL (other populated places);
  2. a result whose second-level region (district) equals the name before one that does not;
  3. the largest population.
If nothing matches the state, one more query "<name> district" is tried.
AMENDMENT 2026-10-04, made after the first pass resolved only 551 of 948 districts and BEFORE any rainfall was joined to
labels or any model was run (see the addendum in PREREGISTRATION.md). Two further levels, tried in order only for districts
the first two levels left unresolved:
  3. the district's state or a state it was split from (Andhra Pradesh/Telangana, Madhya Pradesh/Chhattisgarh,
     Bihar/Jharkhand, Uttar Pradesh/Uttarakhand, Jammu and Kashmir/Ladakh), with an exact name or second-level region match;
  4. the name with its last 1 to 4 letters removed (the IFI has spellings like "Kanniyakumariumari"), accepted only if the
     result's name is at least 80% similar to the district name and lies in the state or a split-from state. Districts still unmatched are
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
from difflib import SequenceMatcher
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


SPLIT_FROM = {
    "andhrapradesh": {"telangana"}, "telangana": {"andhrapradesh"},
    "madhyapradesh": {"chhattisgarh"}, "chhattisgarh": {"madhyapradesh"},
    "bihar": {"jharkhand"}, "jharkhand": {"bihar"},
    "uttarpradesh": {"uttarakhand"}, "uttarakhand": {"uttarpradesh"},
    "jammuandkashmir": {"ladakh"}, "ladakh": {"jammuandkashmir"},
}


def allowed_states(state: str) -> set[str]:
    k = norm_state(state)
    return {k} | SPLIT_FROM.get(k, set())


def choose_relaxed(results: list[dict], name: str, state: str) -> dict | None:
    ok = [r for r in results if norm_state(r.get("admin1", "") or "") in allowed_states(state)
          and (norm(r.get("name", "") or "") == norm(name) or norm(r.get("admin2", "") or "") == norm(name))]
    if not ok:
        return None
    return sorted(ok, key=lambda r: (0 if (r.get("feature_code") or "").startswith("PPLA") else 1, -(r.get("population") or 0)))[0]


def choose_trimmed(results: list[dict], name: str, state: str) -> dict | None:
    ok = [r for r in results if norm_state(r.get("admin1", "") or "") in allowed_states(state)
          and SequenceMatcher(None, norm(name), norm(r.get("name", "") or "")).ratio() >= 0.80]
    if not ok:
        return None
    return sorted(ok, key=lambda r: (0 if (r.get("feature_code") or "").startswith("PPLA") else 1, -(r.get("population") or 0)))[0]


def query(name: str, tries: int = 6) -> list[dict]:
    last = "no answer"
    for attempt in range(tries):
        try:
            r = requests.get(URL, params={"name": name, "count": 20, "language": "en", "countryCode": "IN"}, timeout=60)
            if r.status_code == 200:
                return r.json().get("results", []) or []
            last = f"{r.status_code} {r.text[:120]}"
        except requests.RequestException as e:  # dropped connection: wait and try again
            last = type(e).__name__
        time.sleep(min(60, 2**attempt * 2))
    raise RuntimeError(f"geocoding failed for {name!r}: {last}")


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
        level = 1
        pick = choose(res["by_name"], name, state)
        if pick is None:
            level, pick = 2, choose(res.get("by_name_district", []), name, state)
        if pick is None:
            level, pick = 3, choose_relaxed(res["by_name"] + res.get("by_name_district", []), name, state)
        if pick is None and len(norm(name)) >= 8:
            if "by_trim" not in res:
                res["by_trim"] = {}
                for k in (1, 2, 3, 4):
                    if len(norm(name)) - k >= 6:
                        res["by_trim"][str(k)] = query(name[:-k])
                        time.sleep(0.15)
                cache.write_text(json.dumps(res, ensure_ascii=False), encoding="utf-8")
            for k in ("1", "2", "3", "4"):
                pick = choose_trimmed(res["by_trim"].get(k, []), name, state)
                if pick is not None:
                    level = 4
                    break
        if pick is None:
            unresolved.append(did)
            continue
        chosen[did] = {k: pick.get(k) for k in ("name", "latitude", "longitude", "elevation", "feature_code", "admin1", "admin2", "population")}
        chosen[did]["level"] = level
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
