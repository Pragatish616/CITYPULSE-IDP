"""Part A2 step 1 (ADR-026): hydrology and street-pattern features on the Chennai 90 m grid.

Follows data/susceptibility/2026-10-04/PREREGISTRATION_A2.md. Reads grid.npz (written by sus_build.py), writes grid_a2.npz with
fill_depth, log_upslope, twi, road_density, node_density. No flood label is read.
"""

from __future__ import annotations

import json
import struct
import sys
import time
from pathlib import Path

import numpy as np
from scipy import ndimage as ndi

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hydrology as hy  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "data" / "susceptibility" / "2026-10-04"
PACK = ROOT / "data" / "packs" / "2026-10-02"


def main() -> int:
    t0 = time.time()
    g = np.load(BASE / "grid.npz")
    elev = g["elev"].astype(np.float64)
    slope_deg = g["slope"].astype(np.float64)
    lon, lat = g["lon"], g["lat"]
    H, W = elev.shape
    sea = elev <= 0.0
    filled = hy.fill_depressions(elev, sea)
    depth = np.where(sea, 0.0, filled - elev)
    print(f"filled ({time.time() - t0:.0f}s); cells deeper than 0.5 m: {int((depth > 0.5).sum()):,}; max depth {depth.max():.1f} m", flush=True)
    down = hy.flow_direction(filled)
    acc = hy.flow_accumulation(filled, down)
    print(f"accumulated ({time.time() - t0:.0f}s); max upslope cells {int(acc.max()):,}", flush=True)
    dy = abs(lat[1] - lat[0]) * 111320.0
    dx = abs(lon[1] - lon[0]) * 111320.0 * np.cos(np.radians(lat.mean()))
    width_m = (dx + dy) / 2.0
    tan_b = np.maximum(np.tan(np.radians(slope_deg)), 0.001)
    twi = np.log(np.maximum(acc, 1.0) * width_m / tan_b)

    # road and junction density from the Chennai graph (built-up proxy)
    graph = (PACK / "graph.bin").read_bytes()
    _, n_nodes, n_edges = struct.unpack("<III", graph[4:16])
    src = np.frombuffer(graph, dtype="<i4", count=n_edges, offset=16)
    dst = np.frombuffer(graph, dtype="<i4", count=n_edges, offset=16 + 4 * n_edges)
    nd = (PACK / "nodes.bin").read_bytes()
    nlat = np.frombuffer(nd, dtype="<f8", count=n_nodes, offset=16)
    nlon = np.frombuffer(nd, dtype="<f8", count=n_nodes, offset=16 + 8 * n_nodes)
    elat = np.radians(nlat[src] + 0.0)
    length_km = np.hypot((nlat[dst] - nlat[src]) * 111.32, (nlon[dst] - nlon[src]) * 111.32 * np.cos(elat))
    mid_lat, mid_lon = (nlat[src] + nlat[dst]) / 2, (nlon[src] + nlon[dst]) / 2
    r = np.rint((mid_lat - lat[0]) / (lat[1] - lat[0])).astype(int)
    c = np.rint((mid_lon - lon[0]) / (lon[1] - lon[0])).astype(int)
    ok = (r >= 0) & (r < H) & (c >= 0) & (c < W)
    road = np.zeros((H, W))
    np.add.at(road, (r[ok], c[ok]), length_km[ok])
    rn = np.rint((nlat - lat[0]) / (lat[1] - lat[0])).astype(int)
    cn = np.rint((nlon - lon[0]) / (lon[1] - lon[0])).astype(int)
    okn = (rn >= 0) & (rn < H) & (cn >= 0) & (cn < W)
    node = np.zeros((H, W))
    np.add.at(node, (rn[okn], cn[okn]), 1.0)
    win_km2 = 11 * 11 * (width_m / 1000.0) ** 2
    road_density = ndi.uniform_filter(road, 11, mode="constant") * 121 / win_km2
    node_density = ndi.uniform_filter(node, 11, mode="constant") * 121 / win_km2

    np.savez_compressed(BASE / "grid_a2.npz", fill_depth=depth.astype(np.float32), log_upslope=np.log10(acc).astype(np.float32),
                        twi=twi.astype(np.float32), road_density=road_density.astype(np.float32), node_density=node_density.astype(np.float32))
    modelled = g["modelled"]
    rep = {"seconds": round(time.time() - t0),
           "ranges_1_99_percentile_in_modelled_cells": {k: [round(float(np.percentile(v[modelled], 1)), 3), round(float(np.percentile(v[modelled], 99)), 3)] for k, v in
                                                          {"fill_depth": depth, "log_upslope": np.log10(acc), "twi": twi, "road_density": road_density, "node_density": node_density}.items()},
           "edges_in_grid": int(ok.sum()), "nodes_in_grid": int(okn.sum())}
    (BASE / "grid_a2_report.json").write_text(json.dumps(rep, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(rep, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
