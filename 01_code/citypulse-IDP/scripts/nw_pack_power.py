"""Pack the per-district NASA POWER rainfall files into one compressed file (ADR-025) so the training input is small enough for git.

Reads data/nationwide_flood/<date>/power/*.json, writes power_daily_precip.npz with district ids, points, elevation from the
geocoding answer, the first date, and a (districts x 12418 days) float32 array of daily rainfall in mm (missing = NaN).
The per-district JSON files and the 72 Open-Meteo files stay local (see .gitignore); this file plus fetch/pack scripts reproduce them.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "nationwide_flood" / "2026-10-04"


def slug(did: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", did)


def main() -> int:
    geo = json.loads((BASE / "geocode.json").read_text(encoding="utf-8"))["chosen"]
    ids = sorted(geo)
    P = np.full((len(ids), 12418), np.nan, dtype=np.float32)
    lat = np.zeros(len(ids)); lon = np.zeros(len(ids)); elev = np.zeros(len(ids), dtype=np.float32)
    for i, d in enumerate(ids):
        j = json.loads((BASE / "power" / f"{slug(d)}.json").read_text(encoding="utf-8"))
        P[i] = np.array([np.nan if v is None else v for v in j["precip_mm"]], dtype=np.float32)
        lat[i], lon[i] = j["latitude"], j["longitude"]
        elev[i] = geo[d].get("elevation") or 0.0
    np.savez_compressed(BASE / "power_daily_precip.npz", district_id=np.array(ids), latitude=lat, longitude=lon,
                        elevation=elev, first_date="1990-01-01", precip_mm=P)
    print(f"{len(ids)} districts packed; missing values {int(np.isnan(P).sum())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
