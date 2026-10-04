"""Part B2 step 1 (ADR-026): the nationwide feature builder, memory-safe for ALL 91 flood maps (addendum B2 of PREREGISTRATION_B.md).

Same labels, features and sampling idea as sus_national_build.py (which handled only the 11 maps small enough to hold in memory), with these
differences, all stated in addendum B2 before this script ran:
  * a map is processed in horizontal windows of WINDOW_ROWS rows with a MARGIN of rows on each side, and samples are drawn only from the core rows;
  * windows get sampling quotas proportional to their share of the event's observed positives and negatives (at least one per class when present),
    and each sampled cell carries weight = (its window's observed cells of its class) / (samples drawn in that window of that class), so an
    event's weights still sum to its true observed class sizes;
  * distance to the sea and to permanent water, and the height above the nearest permanent water, are computed on a 4x coarser grid
    (blocks of 4 x 4 cells, about 1 km) to keep the distance transform affordable; they are then looked up at full resolution;
  * every DEM tile needed by any map is fetched first, 8 at a time.
Writes data/susceptibility/2026-10-04/national_samples_all.npz and national_report_all.json (git-ignored samples).
"""

from __future__ import annotations

import json
import math
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import rasterio
import requests
from rasterio.enums import Resampling
from rasterio.transform import Affine
from rasterio.warp import reproject
from rasterio.windows import Window
from scipy import ndimage as ndi

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dem_fetch  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
GFD = ROOT / "data" / "gfd_india" / "2026-10-04" / "raw"
DEM = ROOT / "data" / "dem90" / "raw"
SEED = 20261004
N_PER_CLASS = 15000
MIN_CLEAR_VIEWS = 5
WINDOW_ROWS = 1200
MARGIN = 60
BLOCK = 4
FEATURES = ["elev", "elev_min", "elev_range", "slope", "relief5km", "tpi5km", "dist_sea_km", "dist_water_km", "hand_water"]


def prefetch(tile_names: list[str]) -> dict:
    """Download every missing tile, 8 at a time; record sizes and hashes once at the end."""
    import hashlib

    log_path = ROOT / "data" / "dem90" / "fetch_log.json"
    log = json.loads(log_path.read_text(encoding="utf-8")) if log_path.exists() else {"tiles": {}}
    DEM.mkdir(parents=True, exist_ok=True)
    todo = [t for t in tile_names if t not in log["tiles"] or (not (DEM / f"{t}.tif").exists() and not log["tiles"][t].get("missing"))]

    def one(name: str):
        for attempt in range(1, 7):
            try:
                r = requests.get(f"{dem_fetch.BASE}/{name}/{name}.tif", timeout=180)
                if r.status_code == 404:
                    return name, {"missing": True}
                r.raise_for_status()
                (DEM / f"{name}.tif").write_bytes(r.content)
                return name, {"bytes": len(r.content), "sha256": hashlib.sha256(r.content).hexdigest()}
            except requests.RequestException:
                time.sleep(min(30, 5 * attempt))
        raise RuntimeError(f"could not fetch {name}")

    with ThreadPoolExecutor(8) as ex:
        for name, info in ex.map(one, todo):
            log["tiles"][name] = info
    log_path.write_text(json.dumps(log, indent=1, sort_keys=True), encoding="utf-8")
    return {"fetched": len(todo)}


def dem_window(win_tr, shape, tiles):
    """Mean, min and max DEM on the window grid, reprojecting each tile only into the part of the window it covers."""
    out = {k: np.full(shape, np.nan, dtype=np.float32) for k in ("mean", "min", "max")}
    inv = ~win_tr
    H, W = shape
    for t in tiles:
        p = DEM / f"{t}.tif"
        if not p.exists():
            continue
        with rasterio.open(p) as ds:
            west, south, east, north = ds.bounds
            c0, r0 = inv * (west, north)
            c1, r1 = inv * (east, south)
            ca, cb = max(int(math.floor(min(c0, c1))), 0), min(int(math.ceil(max(c0, c1))), W)
            ra, rb = max(int(math.floor(min(r0, r1))), 0), min(int(math.ceil(max(r0, r1))), H)
            if ca >= cb or ra >= rb:
                continue
            sub_tr = win_tr * Affine.translation(ca, ra)
            sub_shape = (rb - ra, cb - ca)
            for name, rs in (("mean", Resampling.average), ("min", Resampling.min), ("max", Resampling.max)):
                tmp = np.full(sub_shape, np.nan, dtype=np.float32)
                reproject(rasterio.band(ds, 1), tmp, dst_transform=sub_tr, dst_crs=ds.crs, resampling=rs, dst_nodata=np.nan)
                dst = out[name][ra:rb, ca:cb]
                m = np.isnan(dst) & ~np.isnan(tmp)
                dst[m] = tmp[m]
    return out


def coarse_nearest(mask, values, cell_km):
    """Distance (km) to the nearest True cell and the value there, computed on BLOCK x BLOCK blocks and looked up at full resolution."""
    H, W = mask.shape
    h, w = H // BLOCK, W // BLOCK
    if h < 2 or w < 2 or not mask.any():
        return np.full((H, W), np.nan, np.float32), np.full((H, W), np.nan, np.float32)
    m = mask[: h * BLOCK, : w * BLOCK].reshape(h, BLOCK, w, BLOCK).any(axis=(1, 3))
    mm = mask[: h * BLOCK, : w * BLOCK].reshape(h, BLOCK, w, BLOCK)
    vv_ = values[: h * BLOCK, : w * BLOCK].reshape(h, BLOCK, w, BLOCK)
    v = (vv_ * mm).sum(axis=(1, 3)) / np.maximum(mm.sum(axis=(1, 3)), 1)  # mean height of the mask cells in each block
    dist, idx = ndi.distance_transform_edt(~m, return_indices=True)
    d = np.full((H, W), np.nan, np.float32)
    nv = np.full((H, W), np.nan, np.float32)
    dd = np.kron((dist * BLOCK * cell_km).astype(np.float32), np.ones((BLOCK, BLOCK), np.float32))
    vv = np.kron(v[idx[0], idx[1]].astype(np.float32), np.ones((BLOCK, BLOCK), np.float32))
    d[: h * BLOCK, : w * BLOCK] = dd
    nv[: h * BLOCK, : w * BLOCK] = vv
    return d, nv


def window_features(ds, row0, row1, tiles_cache):
    """Features for rows [row0, row1) with margins; returns dict of arrays for the CORE rows plus the label masks."""
    H, W = ds.height, ds.width
    a, b = max(row0 - MARGIN, 0), min(row1 + MARGIN, H)
    win = Window(0, a, W, b - a)
    flooded, clear, perm = (ds.read(i, window=win) for i in (1, 3, 5))
    win_tr = ds.window_transform(win)
    west, south, east, north = rasterio.windows.bounds(win, ds.transform)
    tiles = dem_fetch.tiles_for(max(south, -90), min(north, 90), max(west, -180), min(east, 180))
    d = dem_window(win_tr, (b - a, W), tiles)
    elev, emin, emax = d["mean"], d["min"], d["max"]
    lat_mid = 0.5 * (south + north)
    dy = abs(ds.transform.e) * 111320.0
    dx = ds.transform.a * 111320.0 * np.cos(np.radians(lat_mid))
    cell_km = float((dx + dy) / 2000.0)
    e0 = np.where(np.isnan(elev), 0.0, elev).astype(np.float32)
    sea = np.nan_to_num(elev, nan=1.0) <= 0.0
    gy, gx = np.gradient(e0, dy, dx)
    slope = np.degrees(np.arctan(np.hypot(gx, gy))).astype(np.float32)
    relief = (e0 - ndi.minimum_filter(e0, 21, mode="nearest")).astype(np.float32)
    tpi = (e0 - ndi.uniform_filter(e0, 21, mode="nearest")).astype(np.float32)
    dist_sea, _ = coarse_nearest(sea, e0, cell_km)
    water = perm == 1
    dist_w, e_nearest = coarse_nearest(water, e0, cell_km)
    hand_w = (e0 - e_nearest).astype(np.float32)
    core = slice(row0 - a, row1 - a)
    feats = {"elev": elev, "elev_min": emin, "elev_range": emax - emin, "slope": slope, "relief5km": relief, "tpi5km": tpi,
             "dist_sea_km": dist_sea, "dist_water_km": dist_w, "hand_water": hand_w}
    observed = ~np.isnan(flooded) & (clear >= MIN_CLEAR_VIEWS) & ~(perm == 1) & ~np.isnan(elev)
    pos = (observed & (flooded == 1))[core]
    neg = (observed & (flooded == 0))[core]
    return {k: v[core] for k, v in feats.items()}, pos, neg


def main() -> int:
    t0 = time.time()
    events = json.loads((BASE / "national_events.json").read_text(encoding="utf-8"))["events"]
    # 1. every DEM tile that any map needs
    need: set[str] = set()
    for ev in events:
        with rasterio.open(GFD / ev["name"]) as ds:
            west, south, east, north = ds.bounds
        need.update(dem_fetch.tiles_for(south, north, west, east))
    print(f"{len(need)} DEM tiles needed in total", flush=True)
    print(prefetch(sorted(need)), f"{time.time() - t0:.0f}s", flush=True)

    rng = np.random.default_rng(SEED)
    cols = {k: [] for k in FEATURES + ["lon", "lat", "y", "w", "event", "year"]}
    report = {"events": [], "window_rows": WINDOW_ROWS, "margin": MARGIN, "block": BLOCK}
    for ev in events:
        name = ev["name"]
        rep = {"name": name}
        with rasterio.open(GFD / name) as ds:
            H, W = ds.height, ds.width
            tr = ds.transform
            starts = list(range(0, H, WINDOW_ROWS))
            rep.update({"shape": [H, W], "windows": len(starts)})
            # pass 1: observed class counts per window
            counts = []
            for r0 in starts:
                r1 = min(r0 + WINDOW_ROWS, H)
                win = Window(0, r0, W, r1 - r0)
                fl, cv, pm = (ds.read(i, window=win) for i in (1, 3, 5))
                ob = ~np.isnan(fl) & (cv >= MIN_CLEAR_VIEWS) & ~(pm == 1)
                counts.append((int((ob & (fl == 1)).sum()), int((ob & (fl == 0)).sum())))
            tp, tn = sum(c[0] for c in counts), sum(c[1] for c in counts)
            rep.update({"observed_positives": tp, "observed_negatives": tn})
            if tp < 50 or tn < 50:
                rep["skipped"] = "fewer than 50 positive or negative observed cells"
                report["events"].append(rep)
                print(name, rep["skipped"], flush=True)
                continue
            got_p = got_n = 0
            for (r0, (cp, cn)) in zip(starts, counts):
                if cp == 0 and cn == 0:
                    continue
                r1 = min(r0 + WINDOW_ROWS, H)
                feats, pos, neg = window_features(ds, r0, r1, None)
                npos, nneg = int(pos.sum()), int(neg.sum())
                kp = min(npos, max(1 if npos else 0, math.ceil(N_PER_CLASS * cp / tp)))
                kn = min(nneg, max(1 if nneg else 0, math.ceil(N_PER_CLASS * cn / tn)))
                pr, pc = np.nonzero(pos)
                nr, nc = np.nonzero(neg)
                ip = rng.choice(npos, kp, replace=False) if kp else np.array([], int)
                inn = rng.choice(nneg, kn, replace=False) if kn else np.array([], int)
                rr = np.concatenate([pr[ip], nr[inn]])
                cc = np.concatenate([pc[ip], nc[inn]])
                if len(rr) == 0:
                    continue
                for k in FEATURES:
                    cols[k].append(feats[k][rr, cc])
                cols["lon"].append(tr.c + (cc + 0.5) * tr.a)
                cols["lat"].append(tr.f + (rr + r0 + 0.5) * tr.e)
                cols["y"].append(np.concatenate([np.ones(kp), np.zeros(kn)]))
                cols["w"].append(np.concatenate([np.full(kp, npos / max(kp, 1)), np.full(kn, nneg / max(kn, 1))]))
                cols["event"].append(np.full(len(rr), ev["dfo_id"]))
                cols["year"].append(np.full(len(rr), ev["year"]))
                got_p += kp
                got_n += kn
            rep.update({"sampled_positives": got_p, "sampled_negatives": got_n})
            report["events"].append(rep)
            print(f"{name[:30]} windows {len(starts)} observed pos {tp:,} neg {tn:,} sampled {got_p + got_n:,}  ({time.time() - t0:.0f}s)", flush=True)
    arrays = {k: np.concatenate(v) for k, v in cols.items() if v}
    np.savez_compressed(BASE / "national_samples_all.npz", **arrays)
    report["rows"] = int(len(arrays["y"]))
    report["events_used"] = int(len({int(x) for x in arrays["event"]}))
    report["seconds"] = round(time.time() - t0)
    (BASE / "national_report_all.json").write_text(json.dumps(report, indent=1, sort_keys=True), encoding="utf-8")
    print(f"rows {report['rows']:,}; events used {report['events_used']} of {len(events)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
