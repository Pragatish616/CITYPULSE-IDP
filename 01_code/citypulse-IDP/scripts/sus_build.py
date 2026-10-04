"""Part A step 1 (ADR-026): terrain and drainage features, and past-flood labels, on the 90 m grid around Chennai.

Follows data/susceptibility/2026-10-04/PREREGISTRATION.md. Writes data/susceptibility/2026-10-04/grid.npz (git-ignored: derived
rasters of licensed inputs) and grid_report.json. Features use only the DEM and the drainage and water layers; labels use only the
flood-extent polygons and are stored separately. No coordinates are features.

Clarification (data validity, not tuning): the drainage and water layers cover a limited box; cells outside the box spanned by the
drainage lines have undefined distance features, so they are excluded. The report states how much of the pre-registered area that removes.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import rasterio
from rasterio.features import rasterize
from rasterio.merge import merge
from rasterio.transform import Affine
from scipy import ndimage as ndi
from shapely import wkb
from shapely.geometry import box, mapping
from shapely.ops import transform as shp_transform

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "susceptibility" / "2026-10-04"
GIS = ROOT / "data" / "chennai_cfm" / "2026-10-04" / "raw" / "chennaidss-gis-layers"
HIS = ROOT / "data" / "chennai_cfm" / "2026-10-04" / "raw" / "chennai-flood-history"
AREA = (79.3, 12.5, 80.35, 13.4)  # min lon, min lat, max lon, max lat
BOX2005 = (80.00, 12.85, 80.33, 13.29)
R_EARTH = 6378137.0


def mercator_to_lonlat(x, y, z=None):
    lon = np.degrees(np.asarray(x) / R_EARTH)
    lat = np.degrees(np.arctan(np.sinh(np.asarray(y) / R_EARTH)))
    return lon, lat


def load_geoms(path: Path, mercator: bool):
    df = pd.read_parquet(path)
    for c in df.columns:
        v = next((x for x in df[c] if x is not None), None)
        if isinstance(v, (bytes, bytearray)):
            try:
                g = [wkb.loads(bytes(x)) for x in df[c] if x is not None]
            except Exception:
                continue
            return [shp_transform(mercator_to_lonlat, x) for x in g] if mercator else g
    raise ValueError(f"no geometry in {path}")


def burn(geoms, shape, transform, all_touched):
    shapes = [(mapping(g), 1) for g in geoms if g is not None and not g.is_empty]
    if not shapes:
        return np.zeros(shape, dtype=bool)
    return rasterize(shapes, out_shape=shape, transform=transform, fill=0, dtype="uint8", all_touched=all_touched).astype(bool)


def nearest_value_and_distance(mask, values, cell_km):
    """Distance (km) to the nearest True cell and the value there."""
    dist, idx = ndi.distance_transform_edt(~mask, return_indices=True)
    return (dist * cell_km).astype(np.float32), values[idx[0], idx[1]]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = sorted((ROOT / "data" / "dem90" / "raw").glob("*.tif"))
    srcs = [rasterio.open(t) for t in tiles]
    dem, tr = merge(srcs, bounds=(AREA[0], AREA[1], AREA[2], AREA[3]))
    for s in srcs:
        s.close()
    elev_raw = dem[0].astype(np.float32)
    H, W = elev_raw.shape
    print("grid", H, W, "cell deg", tr.a, tr.e, flush=True)
    lat_c = 0.5 * (AREA[1] + AREA[3])
    dy_m, dx_m = abs(tr.e) * 111320.0, tr.a * 111320.0 * np.cos(np.radians(lat_c))
    cell_km = float((dy_m + dx_m) / 2 / 1000.0)

    sea = elev_raw <= 0.0
    elev = np.where(sea, 0.0, elev_raw).astype(np.float32)  # sea cells are held at 0 m for the neighbourhood filters
    gy, gx = np.gradient(elev, dy_m, dx_m)
    slope = np.degrees(np.arctan(np.hypot(gx, gy))).astype(np.float32)
    tpi1 = (elev - ndi.uniform_filter(elev, 11, mode="nearest")).astype(np.float32)
    tpi5 = (elev - ndi.uniform_filter(elev, 55, mode="nearest")).astype(np.float32)
    rel5 = (elev - ndi.minimum_filter(elev, 55, mode="nearest")).astype(np.float32)
    dist_sea = (ndi.distance_transform_edt(~sea) * cell_km).astype(np.float32)

    # drainage lines and water bodies (Web Mercator in the archive)
    drain_files = ["rivers_streams_876", "manmade_channels_line_3874", "macro_drains", "micro_drains", "buckingham_canal", "krishna_water_canal"]
    water_files = ["lakes_reservoirs_5841", "gcc_tanks", "pwd_tanks_785", "waterbodies_cma", "waterbodies_bulletin_5659", "creeks", "pallikaranai_marsh"]
    drain_geoms = [g for f in drain_files for g in load_geoms(GIS / "drainage" / f"{f}.parquet", True)]
    water_geoms = [g for f in water_files for g in load_geoms(GIS / "water" / f"{f}.parquet", True)]
    water_geoms += load_geoms(GIS / "drainage" / "manmade_channels.parquet", True)
    drain = burn(drain_geoms, (H, W), tr, True) & ~sea
    water = burn(water_geoms, (H, W), tr, False)
    dminx = min(g.bounds[0] for g in drain_geoms); dminy = min(g.bounds[1] for g in drain_geoms)
    dmaxx = max(g.bounds[2] for g in drain_geoms); dmaxy = max(g.bounds[3] for g in drain_geoms)
    cover = box(dminx, dminy, dmaxx, dmaxy)
    cols = np.arange(W); rows = np.arange(H)
    lon = tr.c + (cols + 0.5) * tr.a; lat = tr.f + (rows + 0.5) * tr.e
    LON, LAT = np.meshgrid(lon, lat)
    in_cover = (LON >= cover.bounds[0]) & (LON <= cover.bounds[2]) & (LAT >= cover.bounds[1]) & (LAT <= cover.bounds[3])

    d_drain, e_drain = nearest_value_and_distance(drain, elev, cell_km)
    d_water, e_water = nearest_value_and_distance(water, elev, cell_km)
    hand_drain = (elev - e_drain).astype(np.float32)
    hand_water = (elev - e_water).astype(np.float32)

    modelled = (~sea) & (~water) & in_cover
    feats = {"elev": elev, "slope": slope, "tpi1km": tpi1, "tpi5km": tpi5, "relief5km": rel5, "dist_sea_km": dist_sea,
             "dist_drain_km": d_drain, "hand_drain": hand_drain, "dist_water_km": d_water, "hand_water": hand_water}

    # labels
    nrsc = load_geoms(HIS / "flood_extents" / "nrsc_flood_extent_2015.parquet", False)
    irs = load_geoms(HIS / "flood_extents" / "irs_flood_extent_2005.parquet", False)
    y2015 = burn(nrsc, (H, W), tr, False)
    y2005 = burn(irs, (H, W), tr, False)
    in_box05 = (LON >= BOX2005[0]) & (LON <= BOX2005[2]) & (LAT >= BOX2005[1]) & (LAT <= BOX2005[3])

    pts = {}
    for name, path, lon_c, lat_c2 in [("gcc2015", HIS / "hotspots_2015" / "hotspots_gcc_2015.parquet", "longitude", "latitude"),
                                      ("gcc2020", HIS / "hotspots_2015" / "hotspots_gcc_nem2020.parquet", "longitude", "latitude"),
                                      ("irs2005", HIS / "hotspots_2015" / "hotspots_irs_2005.parquet", "longitude", "latitude")]:
        df = pd.read_parquet(path)
        pts[name] = np.column_stack([df[lon_c].astype(float).to_numpy(), df[lat_c2].astype(float).to_numpy()])

    np.savez_compressed(OUT / "grid.npz", **feats, modelled=modelled, y2015=y2015, y2005=y2005, in_box05=in_box05,
                        lon=lon.astype(np.float64), lat=lat.astype(np.float64), **{f"pts_{k}": v for k, v in pts.items()})
    area_cells = int((~sea).sum())
    rep = {
        "grid_shape": [H, W], "cell_km": round(cell_km, 4), "land_cells": area_cells,
        "land_cells_not_in_water": int(((~sea) & (~water)).sum()), "modelled_cells": int(modelled.sum()),
        "dropped_for_missing_drainage_coverage": int(((~sea) & (~water) & ~in_cover).sum()),
        "drainage_coverage_box_lonlat": [round(float(v), 3) for v in cover.bounds],
        "positives_2015_modelled": int((y2015 & modelled).sum()), "positives_2005_modelled_in_box": int((y2005 & modelled & in_box05).sum()),
        "positive_share_2015": round(float((y2015 & modelled).sum() / modelled.sum()), 4),
        "positive_share_2005_in_box": round(float((y2005 & modelled & in_box05).sum() / (modelled & in_box05).sum()), 4),
        "points": {k: int(len(v)) for k, v in pts.items()},
        "feature_ranges": {k: [round(float(np.nanpercentile(v[modelled], 1)), 3), round(float(np.nanpercentile(v[modelled], 99)), 3)] for k, v in feats.items()},
        "n_drain_cells": int(drain.sum()), "n_water_cells": int(water.sum()),
    }
    (OUT / "grid_report.json").write_text(json.dumps(rep, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(rep, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
