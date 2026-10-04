"""Step 3 (ADR-025): daily rainfall 1990-2023 at each district point, from the Open-Meteo historical API (ERA5).

One request per district, saved to data/nationwide_flood/<date>/rain/<slug>.json with the coordinates the service
actually used, the elevation it returned, and the daily precipitation sum in millimetres. Resumable: a district that
already has a file is skipped. A rate-limit answer (HTTP 429) waits and retries; any other failure stops the run so
nothing is silently skipped. Free for non-commercial use with attribution (ERA5, Copernicus/ECMWF via Open-Meteo).
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
URL = "https://archive-api.open-meteo.com/v1/archive"


def slug(did: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", did)


def fetch(lat: float, lon: float) -> dict:
    wait = 30
    while True:
        r = requests.get(
            URL,
            params={"latitude": lat, "longitude": lon, "start_date": "1990-01-01", "end_date": "2023-12-31",
                    "daily": "precipitation_sum", "timezone": "Asia/Kolkata"},
            timeout=120,
        )
        if r.status_code == 200:
            return r.json()
        if r.status_code == 429:
            print(f"  rate limited ({r.text[:100]}); waiting {wait}s", file=sys.stderr)
            time.sleep(wait)
            wait = min(wait * 2, 900)
            continue
        raise RuntimeError(f"unexpected answer {r.status_code}: {r.text[:200]}")


def main() -> int:
    base = ROOT / "data" / "nationwide_flood" / DATE
    out = base / "rain"
    out.mkdir(exist_ok=True)
    chosen = json.loads((base / "geocode.json").read_text(encoding="utf-8"))["chosen"]
    todo = [(k, v) for k, v in sorted(chosen.items()) if not (out / f"{slug(k)}.json").exists()]
    print(f"{len(chosen)} districts, {len(todo)} to fetch", file=sys.stderr)
    for i, (did, c) in enumerate(todo):
        j = fetch(c["latitude"], c["longitude"])
        d = j["daily"]
        assert d["time"][0] == "1990-01-01" and d["time"][-1] == "2023-12-31" and len(d["time"]) == 12418
        (out / f"{slug(did)}.json").write_text(
            json.dumps({"district_id": did, "latitude": j["latitude"], "longitude": j["longitude"],
                        "elevation": j.get("elevation"), "precip_mm": d["precipitation_sum"]}),
            encoding="utf-8")
        if (i + 1) % 50 == 0:
            print(f"{i + 1}/{len(todo)}", file=sys.stderr)
        time.sleep(0.3)
    return 0


if __name__ == "__main__":
    sys.exit(main())
