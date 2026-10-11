"""Part A3 step 1 (ADR-034): rasterise the OpenStreetMap extract onto the Chennai 90 m grid.

Follows data/susceptibility/2026-10-04/PREREGISTRATION_A3.md. Reads grid.npz (geometry only) and osm_chennai_raw.npz; no flood label is read.
Writes grid_a3.npz with bld_share_90m, bld_share_1km, built_landuse_1km, green_landuse_1km, dist_waterway_km, dist_waterbody_km, and
grid_a3_report.json (coverage per feature and the correlation of building share with the A2 road density).
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
WINDOW = 11  # about 1 km, as for the A2 road density


def to_px(lat, lon, lat0, lon0, dlat, dlon):
    return (lon - lon0) / dlon, (lat - lat0) / dlat  # (column, row), pixel centres at integers


def raster_polys(coords, off, shape, mapper, outline=True):
    img = Image.new("L", (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(img)
    for i in range(len(off) - 1):
        c = coords[off[i]:off[i + 1]]
        if len(c) < 3:
            continue
        x, y = mapper(c[:, 0], c[:, 1])
        d.polygon(list(zip(x.tolist(), y.tolist())), fill=1, outline=1 if outline else None)
    return np.asarray(img, dtype=bool)


def raster_lines(coords, off, shape, mapper):
    img = Image.new("L", (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(img)
    for i in range(len(off) - 1):
        c = coords[off[i]:off[i + 1]]
        if len(c) < 2:
            continue
        x, y = mapper(c[:, 0], c[:, 1])
        d.line(list(zip(x.tolist(), y.tolist())), fill=1, width=1)
    return np.asarray(img, dtype=bool)


def main() -> int:
    t0 = time.time()
    g = np.load(BASE / "grid.npz")
    raw = np.load(BASE / "osm_chennai_raw.npz")
    lon, lat = g["lon"], g["lat"]
    H, W = len(lat), len(lon)
    dlon, dlat = lon[1] - lon[0], lat[1] - lat[0]
    mapper = lambda la, lo: to_px(la, lo, lat[0], lon[0], dlat, dlon)  # noqa: E731
    dy_m = abs(dlat) * 111_195.0
    dx_m = abs(dlon) * 111_195.0 * np.cos(np.radians(lat))  # per row
    cell_area = (dx_m * dy_m)[:, None] * np.ones((1, W))

    # buildings: area into the cell of the centroid
    x, y = mapper(raw["bld_lat"], raw["bld_lon"])
    ix, iy = np.rint(x).astype(int), np.rint(y).astype(int)
    ok = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
    area = np.zeros((H, W))
    np.add.at(area, (iy[ok], ix[ok]), raw["bld_area_m2"][ok])
    bld90 = np.minimum(area / cell_area, 1.0)
    bld1k = ndi.uniform_filter(bld90, size=WINDOW, mode="nearest")

    built = raster_polys(raw["built_coords"], raw["built_off"], (H, W), mapper)
    green = raster_polys(raw["green_coords"], raw["green_off"], (H, W), mapper)
    built1k = ndi.uniform_filter(built.astype(np.float64), size=WINDOW, mode="nearest")
    green1k = ndi.uniform_filter(green.astype(np.float64), size=WINDOW, mode="nearest")

    sampling = (dy_m / 1000.0, float(dx_m.mean()) / 1000.0)
    way = raster_lines(raw["waterway_coords"], raw["waterway_off"], (H, W), mapper)
    wat = raster_polys(raw["water_coords"], raw["water_off"], (H, W), mapper)
    d_way = ndi.distance_transform_edt(~way, sampling=sampling) if way.any() else np.full((H, W), np.nan)
    d_wat = ndi.distance_transform_edt(~wat, sampling=sampling) if wat.any() else np.full((H, W), np.nan)

    F = {"bld_share_90m": bld90, "bld_share_1km": bld1k, "built_landuse_1km": built1k, "green_landuse_1km": green1k,
         "dist_waterway_km": d_way, "dist_waterbody_km": d_wat}
    np.savez_compressed(BASE / "grid_a3.npz", **{k: v.astype(np.float32) for k, v in F.items()})
    mod = g["modelled"]
    a2 = np.load(BASE / "grid_a2.npz")
    rd = a2["road_density"][mod].astype(np.float64)
    rep = {
        "modelled_cells": int(mod.sum()),
        "objects_used": {"buildings_in_grid": int(ok.sum()), "built_landuse_polygons": int(len(raw["built_off"]) - 1), "green_polygons": int(len(raw["green_off"]) - 1),
                         "waterway_lines": int(len(raw["waterway_off"]) - 1), "water_polygons": int(len(raw["water_off"]) - 1)},
        "share_of_modelled_cells_nonzero": {k: float((v[mod] > 0).mean()) for k, v in F.items() if not k.startswith("dist_")},
        "distance_range_km_1_99_pct": {k: [float(np.nanpercentile(F[k][mod], 1)), float(np.nanpercentile(F[k][mod], 99))] for k in ("dist_waterway_km", "dist_waterbody_km")},
        "corr_bld_share_1km_with_road_density": float(np.corrcoef(bld1k[mod], rd)[0, 1]),
        "seconds": round(time.time() - t0),
    }
    (BASE / "grid_a3_report.json").write_text(json.dumps(rep, indent=1), encoding="utf-8")
    print(json.dumps(rep, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
