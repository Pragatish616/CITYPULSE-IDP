"""Fetch Copernicus DEM 90 m tiles that cover a bounding box (ADR-026).

Source: the public AWS Open Data bucket copernicus-dem-90m, one Cloud-Optimised GeoTIFF per 1 degree cell, named by its
south-west corner (for example N13_00_E080_00 covers 13 to 14 N and 80 to 81 E). Free to use, including commercially, with the
Copernicus acknowledgement. No account is needed. Tiles that do not exist (open sea) are recorded as missing.

Usage: python scripts/dem_fetch.py MIN_LAT MAX_LAT MIN_LON MAX_LON
Saves to data/dem90/raw/ (git-ignored) and appends to data/dem90/fetch_log.json (tile, bytes, sha256).
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://copernicus-dem-90m.s3.amazonaws.com"


def tile_name(lat0: int, lon0: int) -> str:
    ns = "N" if lat0 >= 0 else "S"
    ew = "E" if lon0 >= 0 else "W"
    return f"Copernicus_DSM_COG_30_{ns}{abs(lat0):02d}_00_{ew}{abs(lon0):03d}_00_DEM"


def tiles_for(min_lat: float, max_lat: float, min_lon: float, max_lon: float) -> list[str]:
    """Names of the 1 degree tiles that cover the box."""
    return [tile_name(la, lo) for la in range(math.floor(min_lat), math.ceil(max_lat)) for lo in range(math.floor(min_lon), math.ceil(max_lon))]


def fetch(min_lat: float, max_lat: float, min_lon: float, max_lon: float) -> None:
    out = ROOT / "data" / "dem90"
    (out / "raw").mkdir(parents=True, exist_ok=True)
    log_path = out / "fetch_log.json"
    log = json.loads(log_path.read_text(encoding="utf-8")) if log_path.exists() else {"tiles": {}}
    for lat0 in range(math.floor(min_lat), math.ceil(max_lat)):
        for lon0 in range(math.floor(min_lon), math.ceil(max_lon)):
            name = tile_name(lat0, lon0)
            dest = out / "raw" / f"{name}.tif"
            if name in log["tiles"] and (dest.exists() or log["tiles"][name].get("missing")):
                continue
            for attempt in range(1, 7):
                try:
                    r = requests.get(f"{BASE}/{name}/{name}.tif", timeout=120)
                    break
                except requests.RequestException as e:
                    print(f"  {name}: {type(e).__name__}; retry {attempt}", file=sys.stderr)
                    time.sleep(min(30, 5 * attempt))
            else:
                raise RuntimeError(f"could not fetch {name}")
            if r.status_code == 404:
                log["tiles"][name] = {"missing": True}
                print(f"{name}: no tile (sea)")
            else:
                r.raise_for_status()
                dest.write_bytes(r.content)
                log["tiles"][name] = {"bytes": len(r.content), "sha256": hashlib.sha256(r.content).hexdigest()}
                print(f"{name}: {len(r.content) / 1e6:.1f} MB")
            log_path.write_text(json.dumps(log, indent=1, sort_keys=True), encoding="utf-8")


def main() -> int:
    fetch(*map(float, sys.argv[1:5]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
