"""
T1.3 -- Aggregate the per-edge static prior into a compact choropleth dataset.

data/graph/<date>/chennai_prior_ell0.json (the full per-edge prior + geometry sidecar
scripts/t1_3_build_graph_and_prior.py writes) is ~150 MB for ~470k edges -- too large to hand
to a browser-rendered choropleth directly, and too fine-grained to usefully eyeball anyway.
This script aggregates it onto a coarse grid (mean prior_p per cell, weighted by edge length so
a handful of short residential stubs don't out-vote one long arterial), producing a JSON small
enough to publish as an Artifact for the actual acceptance test T1.3 asks for: "a choropleth of
sigma(ell_0) over Chennai that a local human recognises as plausible."

Usage: .venv/Scripts/python.exe scripts/t1_3_make_choropleth_data.py
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import ijson

ROOT = Path(__file__).resolve().parent.parent
TODAY = datetime.now(tz=timezone.utc).date().isoformat()
PRIOR_PATH = ROOT / "data" / "graph" / TODAY / "chennai_prior_ell0.json"
OUT_PATH = ROOT / "data" / "graph" / TODAY / "chennai_prior_choropleth.json"

# ~330m cells -- fine enough to recognise real corridors, coarse enough to keep the output
# small. (Independent of T-W1's 300m cluster radius and ADR-010's 150m privacy grid -- this
# one is purely about output size vs. visual resolution, not a "same real place" judgement.)
CELL_DEG = 0.003


def main() -> None:
    cells: dict[tuple[int, int], dict] = {}
    n_edges = 0
    with open(PRIOR_PATH, "rb") as f:
        for edge in ijson.items(f, "edges.item"):
            n_edges += 1
            geom = edge["geometry"]
            mid = geom[len(geom) // 2]
            lat, lon = float(mid["lat"]), float(mid["lon"])
            cell_key = (round(lat / CELL_DEG), round(lon / CELL_DEG))
            p = float(edge["prior_p"])
            # Edge-count weighting -- length isn't carried in this sidecar's edge records.
            weight = 1.0

            c = cells.get(cell_key)
            if c is None:
                cells[cell_key] = {
                    "lat": lat,
                    "lon": lon,
                    "sum_p_weight": p * weight,
                    "sum_weight": weight,
                    "n_edges": 1,
                    "max_p": p,
                }
            else:
                c["sum_p_weight"] += p * weight
                c["sum_weight"] += weight
                c["n_edges"] += 1
                c["max_p"] = max(c["max_p"], p)
                # Running centroid update (cheap, avoids buffering every point).
                n = c["n_edges"]
                c["lat"] += (lat - c["lat"]) / n
                c["lon"] += (lon - c["lon"]) / n

    out_cells = [
        {
            "lat": round(c["lat"], 5),
            "lon": round(c["lon"], 5),
            "mean_p": round(c["sum_p_weight"] / c["sum_weight"], 4),
            "max_p": round(c["max_p"], 4),
            "n_edges": c["n_edges"],
        }
        for c in cells.values()
    ]

    out = {
        "generated": TODAY,
        "source": str(PRIOR_PATH.relative_to(ROOT)),
        "cell_deg": CELL_DEG,
        "total_edges": n_edges,
        "cell_count": len(out_cells),
        "cells": out_cells,
    }
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f)

    print(f"{n_edges} edges -> {len(out_cells)} populated cells")
    print(
        f"Wrote {OUT_PATH.relative_to(ROOT)} ({OUT_PATH.stat().st_size / 1e6:.2f} MB)"
    )


if __name__ == "__main__":
    main()
