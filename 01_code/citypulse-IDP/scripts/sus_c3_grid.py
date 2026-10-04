"""Part C3 step 1 (ADR-026): Chennai on the 250 m grid of a Tamil Nadu flood map, with the nationwide builder's own feature code.

Follows data/susceptibility/2026-10-04/PREREGISTRATION_C3.md. Writes data/susceptibility/2026-10-04/chennai250.npz:
features (same names as the nationwide model), lon/lat of cell centres, `modelled`, `y2015` (NRSC December 2015 extent), `block` ids.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import rasterio
from rasterio.features import rasterize
from rasterio.windows import Window
from shapely import wkb
from shapely.geometry import mapping
from shapely.ops import transform as shp_transform

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sus_national_build_v2 as nb  # noqa: E402
from sus_build import load_geoms, mercator_to_lonlat  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
GIS = ROOT / "data" / "chennai_cfm" / "2026-10-04" / "raw" / "chennaidss-gis-layers"
HIS = ROOT / "data" / "chennai_cfm" / "2026-10-04" / "raw" / "chennai-flood-history"
MAP = "DFO_4001_From_20121104_to_20121108.tif"
AREA = (79.3, 12.5, 80.35, 13.4)  # min lon, min lat, max lon, max lat


def burn(geoms, shape, transform):
    shapes = [(mapping(g), 1) for g in geoms if g is not None and not g.is_empty]
    return rasterize(shapes, out_shape=shape, transform=transform, fill=0, dtype="uint8", all_touched=False).astype(bool) if shapes else np.zeros(shape, bool)


def main() -> int:
    with rasterio.open(nb.GFD / MAP) as ds:
        tr = ds.transform
        r0 = int(np.floor((tr.f - AREA[3]) / -tr.e))
        r1 = int(np.ceil((tr.f - AREA[1]) / -tr.e))
        c0 = int(np.floor((AREA[0] - tr.c) / tr.a))
        c1 = int(np.ceil((AREA[2] - tr.c) / tr.a))
        feats, _, _ = nb.window_features(ds, r0, r1, None)
        win = Window(c0, r0, c1 - c0, r1 - r0)
        perm = ds.read(5, window=win)
        win_tr = ds.window_transform(win)
    feats = {k: v[:, c0:c1] for k, v in feats.items()}
    H, W = perm.shape
    lon = win_tr.c + (np.arange(W) + 0.5) * win_tr.a
    lat = win_tr.f + (np.arange(H) + 0.5) * win_tr.e

    water_files = ["lakes_reservoirs_5841", "gcc_tanks", "pwd_tanks_785", "waterbodies_cma", "waterbodies_bulletin_5659", "creeks", "pallikaranai_marsh"]
    water_geoms = [g for f in water_files for g in load_geoms(GIS / "water" / f"{f}.parquet", True)]
    water_geoms += load_geoms(GIS / "drainage" / "manmade_channels.parquet", True)
    water = burn(water_geoms, (H, W), win_tr)
    nrsc = load_geoms(HIS / "flood_extents" / "nrsc_flood_extent_2015.parquet", False)
    y15 = burn(nrsc, (H, W), win_tr)
    inside = (lon[None, :] >= AREA[0]) & (lon[None, :] <= AREA[2]) & (lat[:, None] >= AREA[1]) & (lat[:, None] <= AREA[3])
    elev = feats["elev"]
    modelled = inside & ~np.isnan(elev) & (elev > 0) & (perm != 1) & ~water
    iy = np.floor((np.repeat(lat[:, None], W, 1) - AREA[1]) / 0.05).astype(int)
    ix = np.floor((np.repeat(lon[None, :], H, 0) - AREA[0]) / 0.05).astype(int)
    _, bid = np.unique((iy * 1000 + ix)[modelled], return_inverse=True)
    block = np.full((H, W), -1, dtype=np.int64)
    block[modelled] = bid
    np.savez_compressed(BASE / "chennai250.npz", **feats, lon=lon, lat=lat, modelled=modelled, y2015=y15, block=block)
    print(f"grid {H} x {W}; modelled cells {int(modelled.sum()):,}; positives {int((y15 & modelled).sum()):,} ({(y15 & modelled).sum() / modelled.sum():.3%}); blocks {int(block.max()) + 1}")
    for k, v in feats.items():
        print(k.ljust(14), "nan share in modelled", round(float(np.isnan(v[modelled]).mean()), 3), "p1/p50/p99", [round(float(x), 2) for x in np.nanpercentile(v[modelled], [1, 50, 99])])
    return 0


if __name__ == "__main__":
    sys.exit(main())
