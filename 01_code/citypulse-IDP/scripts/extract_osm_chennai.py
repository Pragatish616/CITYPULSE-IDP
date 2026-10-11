"""Extract buildings, land use, waterways and water bodies for the Chennai grid from the pinned OSM extract (ADR-034, Part A3).

Follows data/susceptibility/2026-10-04/PREREGISTRATION_A3.md. No flood label is read. Closed ways only: multipolygon relations are not read.
Needs pyosmium, which the project venv does not have; use the separate osm environment:

    C:\\Users\\nprag\\AppData\\Local\\citypulse_osmenv\\Scripts\\python.exe scripts/extract_osm_chennai.py

Reuses the node-location index file of earlier runs (data/osm/_node_index.tmp, git-ignored). Writes
data/susceptibility/2026-10-04/osm_chennai_raw.npz (OpenStreetMap contributors, ODbL 1.0; git-ignored) and osm_chennai_report.json.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PBF = Path(r"C:\Users\nprag\Downloads\citypulse-IDP\data\osm\southern-zone-260911.osm.pbf")
INDEX = ROOT / "data" / "osm" / "_node_index.tmp"
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
BOX = (12.48, 13.42, 79.28, 80.37)  # min_lat, max_lat, min_lon, max_lon: the grid plus 0.02 degrees
BUILT = {"residential", "commercial", "industrial", "retail", "construction"}
GREEN = {"grass", "forest", "meadow", "farmland", "orchard", "recreation_ground", "greenfield", "village_green", "cemetery"}
GREEN_LEISURE = {"park", "garden", "pitch", "playground", "golf_course", "nature_reserve"}
WATERWAYS = {"river", "stream", "canal", "drain", "ditch"}


def area_m2(lats, lons) -> float:
    la0 = sum(lats) / len(lats)
    kx = 111_195.0 * math.cos(math.radians(la0))
    ky = 111_195.0
    s = 0.0
    for i in range(len(lats) - 1):
        s += (lons[i] * kx) * (lats[i + 1] * ky) - (lons[i + 1] * kx) * (lats[i] * ky)
    return abs(s) / 2.0


class Bag:
    def __init__(self):
        self.coords, self.off = [], [0]

    def add(self, lats, lons):
        self.coords.extend(zip(lats, lons))
        self.off.append(len(self.coords))

    def arrays(self):
        return np.array(self.coords, dtype=np.float64).reshape(-1, 2), np.array(self.off, dtype=np.int64)


def main() -> int:
    import osmium

    fp = osmium.FileProcessor(str(PBF), osmium.osm.NODE | osmium.osm.WAY).with_locations(f"sparse_file_array,{INDEX}")
    bld_lat, bld_lon, bld_area = [], [], []
    built, green, water, ways = Bag(), Bag(), Bag(), Bag()
    seen = {"ways_read_with_tags_of_interest": 0, "buildings": 0, "buildings_dropped_open_or_degenerate": 0}
    for obj in fp:
        if not obj.is_way():
            continue
        t = obj.tags
        b = t.get("building")
        lu = t.get("landuse")
        nat = t.get("natural")
        ww = t.get("waterway")
        lei = t.get("leisure")
        if not (b or lu or nat == "water" or ww in WATERWAYS or lei in GREEN_LEISURE or t.get("water")):
            continue
        ids = [n.ref for n in obj.nodes]
        lats, lons, ok = [], [], True
        for n in obj.nodes:
            if not n.location.valid():
                ok = False
                break
            lats.append(n.location.lat)
            lons.append(n.location.lon)
        if not ok or len(lats) < 2:
            continue
        cl, co = sum(lats) / len(lats), sum(lons) / len(lons)
        if not (BOX[0] <= cl <= BOX[1] and BOX[2] <= co <= BOX[3]):
            continue
        seen["ways_read_with_tags_of_interest"] += 1
        closed = len(ids) >= 4 and ids[0] == ids[-1]
        if b and b != "no":
            if closed:
                a = area_m2(lats, lons)
                if 3.0 <= a <= 1_000_000.0:
                    bld_lat.append(cl)
                    bld_lon.append(co)
                    bld_area.append(a)
                    seen["buildings"] += 1
                    continue
            seen["buildings_dropped_open_or_degenerate"] += 1
            continue
        if ww in WATERWAYS:
            ways.add(lats, lons)
        elif closed and (nat == "water" or lu in ("reservoir", "basin") or t.get("water")):
            water.add(lats, lons)
        elif closed and lu in BUILT:
            built.add(lats, lons)
        elif closed and (lu in GREEN or lei in GREEN_LEISURE):
            green.add(lats, lons)
    del fp
    out = {"bld_lat": np.array(bld_lat), "bld_lon": np.array(bld_lon), "bld_area_m2": np.array(bld_area)}
    counts = {"buildings": len(bld_lat)}
    for name, bag in (("built", built), ("green", green), ("water", water), ("waterway", ways)):
        c, o = bag.arrays()
        out[f"{name}_coords"], out[f"{name}_off"] = c, o
        counts[name] = len(o) - 1
    BASE.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(BASE / "osm_chennai_raw.npz", **out)
    h = hashlib.sha256()
    with PBF.open("rb") as f:
        h.update(f.read(1 << 24))
    h.update(str(PBF.stat().st_size).encode())
    (BASE / "osm_chennai_report.json").write_text(json.dumps({
        "source": {"file": PBF.name, "bytes": PBF.stat().st_size, "fingerprint_first_16MB_plus_size": h.hexdigest()}, "licence": "OpenStreetMap contributors, ODbL 1.0",
        "box_min_lat_max_lat_min_lon_max_lon": list(BOX), "counts": counts, "reading": seen,
        "not_read": "multipolygon relations (large lakes, some parks), open ways used as areas"}, indent=1), encoding="utf-8")
    print(json.dumps({"counts": counts, **seen}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
