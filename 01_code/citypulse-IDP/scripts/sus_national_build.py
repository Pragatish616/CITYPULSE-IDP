"""Part B step 1 (ADR-026): terrain features and flood labels sampled from Global Flood Database maps of India.

Follows data/susceptibility/2026-10-04/PREREGISTRATION_B.md (committed before this script ran). For every event in the frozen list:
  * read the 250 m flood map (bands flooded, duration, clear_views, clear_perc, jrc_perm_water);
  * observed cells = flooded is not NaN, clear_views >= 5, not permanent water; positive = flooded == 1, negative = flooded == 0;
  * fetch the 90 m Copernicus DEM tiles covering the map (skipped, and recorded, if more than MAX_TILES are needed);
  * resample the DEM onto the 250 m grid (mean, minimum, maximum), compute slope, 5 km relief and 5 km TPI, distance to the sea,
    and distance to and height above the nearest permanent water of the map itself;
  * sample up to N_PER_CLASS positives and the same number of negatives, with row weights that restore the event's true class sizes.
Writes data/susceptibility/2026-10-04/national_samples.npz and national_report.json (git-ignored: derived from licensed maps).
No flood label is used to make a feature.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.warp import reproject
from scipy import ndimage as ndi

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dem_fetch  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
GFD = ROOT / "data" / "gfd_india" / "2026-10-04" / "raw"
DEM = ROOT / "data" / "dem90" / "raw"
SEED = 20261004
TRIAL = bool(os.environ.get("SUS_TRIAL"))  # wiring check on one event; writes to trial files, never the real ones
N_PER_CLASS = 15000
MAX_TILES = 80
MAX_CELLS = 40_000_000
MIN_CLEAR_VIEWS = 5
FEATURES = ["elev", "elev_min", "elev_range", "slope", "relief5km", "tpi5km", "dist_sea_km", "dist_water_km", "hand_water"]


def dem_on_grid(transform, shape, crs, tiles):
    """DEM mean, min and max resampled onto the event grid."""
    out = {}
    for name, rs in (("mean", Resampling.average), ("min", Resampling.min), ("max", Resampling.max)):
        dst = np.full(shape, np.nan, dtype=np.float32)
        for t in tiles:
            with rasterio.open(DEM / f"{t}.tif") as ds:
                tmp = np.full(shape, np.nan, dtype=np.float32)
                reproject(rasterio.band(ds, 1), tmp, dst_transform=transform, dst_crs=crs, resampling=rs, dst_nodata=np.nan)
                m = np.isnan(dst) & ~np.isnan(tmp)
                dst[m] = tmp[m]
        out[name] = dst
    return out


def main() -> int:
    events = json.loads((BASE / ("national_events_trial.json" if TRIAL else "national_events.json")).read_text(encoding="utf-8"))["events"]
    rng = np.random.default_rng(SEED)
    cols = {k: [] for k in FEATURES + ["lon", "lat", "y", "w", "event", "year"]}
    report = {"events": []}
    for ev in events:
        name = ev["name"]
        rep = {"name": name}
        with rasterio.open(GFD / name) as ds:
            tr, crs, H, W = ds.transform, ds.crs, ds.height, ds.width
            if H * W > MAX_CELLS:
                rep.update({"shape": [H, W], "skipped": f"map has {H * W:,} cells (> {MAX_CELLS:,})"})
                report["events"].append(rep)
                print(name, rep["skipped"], flush=True)
                continue
            west, south, east, north = ds.bounds
            tiles = dem_fetch.tiles_for(south, north, west, east)
            rep.update({"shape": [H, W], "tiles_needed": len(tiles)})
            if len(tiles) > MAX_TILES:
                rep["skipped"] = f"needs {len(tiles)} DEM tiles (> {MAX_TILES})"
                report["events"].append(rep)
                print(name, rep["skipped"], flush=True)
                continue
            dem_fetch.fetch(south, north, west, east)
            tiles = [t for t in tiles if (DEM / f"{t}.tif").exists()]
            flooded = ds.read(1)
            clear = ds.read(3)
            perm = ds.read(5)
        observed = ~np.isnan(flooded) & (clear >= MIN_CLEAR_VIEWS) & ~(perm == 1)
        pos = observed & (flooded == 1)
        neg = observed & (flooded == 0)
        rep.update({"observed": int(observed.sum()), "positives": int(pos.sum()), "negatives": int(neg.sum()), "permanent_water_cells": int((perm == 1).sum())})
        if pos.sum() < 50 or neg.sum() < 50:
            rep["skipped"] = "fewer than 50 positive or negative observed cells"
            report["events"].append(rep)
            print(name, rep["skipped"], flush=True)
            continue
        d = dem_on_grid(tr, (H, W), crs, tiles)
        elev, emin, emax = d["mean"], d["min"], d["max"]
        lat_mid = 0.5 * (south + north)
        dy = abs(tr.e) * 111320.0
        dx = tr.a * 111320.0 * np.cos(np.radians(lat_mid))
        cell_km = float((dx + dy) / 2000.0)
        e0 = np.where(np.isnan(elev), 0.0, elev).astype(np.float32)
        sea = (np.nan_to_num(elev, nan=1.0) <= 0.0)
        gy, gx = np.gradient(e0, dy, dx)
        slope = np.degrees(np.arctan(np.hypot(gx, gy))).astype(np.float32)
        relief = (e0 - ndi.minimum_filter(e0, 21, mode="nearest")).astype(np.float32)
        tpi = (e0 - ndi.uniform_filter(e0, 21, mode="nearest")).astype(np.float32)
        dist_sea = (ndi.distance_transform_edt(~sea) * cell_km).astype(np.float32) if sea.any() else np.full((H, W), np.nan, np.float32)
        water = perm == 1
        if water.any():
            dist, idx = ndi.distance_transform_edt(~water, return_indices=True)
            dist_w = (dist * cell_km).astype(np.float32)
            hand_w = (e0 - e0[idx[0], idx[1]]).astype(np.float32)
        else:
            dist_w = np.full((H, W), np.nan, np.float32)
            hand_w = np.full((H, W), np.nan, np.float32)
        feats = {"elev": elev, "elev_min": emin, "elev_range": emax - emin, "slope": slope, "relief5km": relief, "tpi5km": tpi,
                 "dist_sea_km": dist_sea, "dist_water_km": dist_w, "hand_water": hand_w}
        usable = ~np.isnan(elev)
        pos &= usable
        neg &= usable
        npos, nneg = int(pos.sum()), int(neg.sum())
        if npos < 50 or nneg < 50:
            rep["skipped"] = "fewer than 50 cells with elevation"
            report["events"].append(rep)
            continue
        pr, pc = np.nonzero(pos)
        nr, nc = np.nonzero(neg)
        kp, kn = min(N_PER_CLASS, npos), min(N_PER_CLASS, nneg)
        ip = rng.choice(npos, kp, replace=False)
        inn = rng.choice(nneg, kn, replace=False)
        rr = np.concatenate([pr[ip], nr[inn]])
        cc = np.concatenate([pc[ip], nc[inn]])
        yy = np.concatenate([np.ones(kp), np.zeros(kn)])
        ww = np.concatenate([np.full(kp, npos / kp), np.full(kn, nneg / kn)])
        for k in FEATURES:
            cols[k].append(feats[k][rr, cc])
        cols["lon"].append(tr.c + (cc + 0.5) * tr.a)
        cols["lat"].append(tr.f + (rr + 0.5) * tr.e)
        cols["y"].append(yy)
        cols["w"].append(ww)
        cols["event"].append(np.full(len(yy), ev["dfo_id"]))
        cols["year"].append(np.full(len(yy), ev["year"]))
        rep.update({"sampled_positives": kp, "sampled_negatives": kn, "tiles_used": len(tiles)})
        report["events"].append(rep)
        print(name, f"pos {npos:,} neg {nneg:,} sampled {kp + kn:,}", flush=True)
    arrays = {k: np.concatenate(v) for k, v in cols.items() if v}
    sfx = "_trial" if TRIAL else ""
    np.savez_compressed(BASE / f"national_samples{sfx}.npz", **arrays)
    report["rows"] = int(len(arrays["y"]))
    report["events_used"] = int(len({int(x) for x in arrays["event"]}))
    (BASE / f"national_report{sfx}.json").write_text(json.dumps(report, indent=1, sort_keys=True), encoding="utf-8")
    print(f"rows {report['rows']:,}; events used {report['events_used']} of {len(events)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
