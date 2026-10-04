"""Step 3 (ADR-025, addendum B): daily rainfall 1990-2023 at each district point, from NASA POWER.

Replaces the Open-Meteo/ERA5 download, whose free tier allowed only about 60 districts an hour. NASA POWER's daily point API
(parameter PRECTOTCORR, MERRA-2 reanalysis corrected with gauge-based monthly rainfall, native 0.5 degree grid, no key) returns 34 years in one
small answer. One request per district; saved to data/nationwide_flood/<date>/power/<slug>.json. Resumable; transient errors
retry with growing waits; a persistent failure stops the run so nothing is silently skipped. The 72 files already fetched from Open-Meteo
stay in rain/ and are NOT used by the model, so the rainfall source is the same for every district.

Elevation is taken from the geocoding answer (a DEM value at the town), not from POWER.
"""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
DATE = "2026-10-04"
URL = "https://power.larc.nasa.gov/api/temporal/daily/point"


def slug(did: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", did)


def fetch(lat: float, lon: float) -> dict:
    for attempt in range(1, 13):
        try:
            r = requests.get(URL, params={"parameters": "PRECTOTCORR", "community": "AG", "longitude": round(lon, 4),
                                          "latitude": round(lat, 4), "start": "19900101", "end": "20231231", "format": "JSON"},
                             timeout=180)
            if r.status_code == 200:
                return r.json()
            note = f"{r.status_code} {r.text[:100]}"
        except (requests.RequestException, ValueError) as e:
            note = type(e).__name__
        wait = min(120, 5 * attempt)
        print(f"  {note}; retry {attempt} in {wait}s", file=sys.stderr, flush=True)
        time.sleep(wait)
    raise RuntimeError("NASA POWER did not answer after 12 tries")


def main() -> int:
    base = ROOT / "data" / "nationwide_flood" / DATE
    out = base / "power"
    out.mkdir(exist_ok=True)
    chosen = json.loads((base / "geocode.json").read_text(encoding="utf-8"))["chosen"]
    todo = [(k, v) for k, v in sorted(chosen.items()) if not (out / f"{slug(k)}.json").exists()]
    print(f"{len(chosen)} districts, {len(todo)} to fetch", file=sys.stderr, flush=True)
    for i, (did, c) in enumerate(todo):
        j = fetch(c["latitude"], c["longitude"])
        series = j["properties"]["parameter"]["PRECTOTCORR"]
        days = sorted(series)
        assert days[0] == "19900101" and days[-1] == "20231231" and len(days) == 12418, "unexpected date range"
        vals = [series[d] for d in days]
        fills = sum(1 for v in vals if v == -999.0)
        (out / f"{slug(did)}.json").write_text(
            json.dumps({"district_id": did, "latitude": j["geometry"]["coordinates"][1], "longitude": j["geometry"]["coordinates"][0],
                        "fill_values": fills, "precip_mm": [None if v == -999.0 else v for v in vals]}), encoding="utf-8")
        if (i + 1) % 25 == 0:
            print(f"{i + 1}/{len(todo)}", file=sys.stderr, flush=True)
        time.sleep(0.4)
    return 0


if __name__ == "__main__":
    sys.exit(main())
