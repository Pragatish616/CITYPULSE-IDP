"""PLAN.md M2.1 -- compact binary "map pack" for the app and router_api.

Why this exists (KNOWN_FLAWS F-06). The app bundled a 47 MB JSON graph, never had the 152 MB prior
on the device, and so could route one fixed pair and could not let a new report change any route
(only 14,534 of 471,240 edges had a hazard entry). This converts the pinned 2026-09-14 snapshot
into four small, typed-array files that need no JSON parsing and carry a prior for **every** edge:

  graph.bin   CSR source data: from/to (Int32), free-flow seconds (Float64), free-flow km/h (Float32)
  nodes.bin   node coordinates (Float64 lat, lon)
  meta.bin    per-edge prior log-odds (Int16, thousandths -- exact, the source has 3 decimals),
              street-name index (Uint16, 0 = unnamed), highway class (Uint8), and the name table
  manifest.json  counts, sizes, SHA-256 of every file and of the source snapshot

Everything is little-endian. `edge_id == array index` (asserted); the router relies on it.
Re-running with the same inputs produces byte-identical files. Output goes to a NEW dated folder;
`data/graph/2026-09-14/` is never modified.

Usage: .venv/Scripts/python.exe scripts/build_packs.py
"""

from __future__ import annotations

import hashlib
import json
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

import ijson

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT_DIR = ROOT / "data" / "graph" / "2026-09-14"
GRAPH_JSON = SNAPSHOT_DIR / "chennai_graph_cli.json"
PRIOR_JSON = SNAPSHOT_DIR / "chennai_prior_ell0.json"
TODAY = "2026-10-02"  # pinned: a pack is identified by the date it was built
OUT_DIR = ROOT / "data" / "packs" / TODAY

PRIOR_SCALE = 1000  # Int16 thousandths
HIGHWAY_CODES = [
    "unknown",
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "primary",
    "primary_link",
    "secondary",
    "secondary_link",
    "tertiary",
    "tertiary_link",
    "unclassified",
    "residential",
]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_graph(edges: list[dict], node_count: int, path: Path) -> None:
    e = len(edges)
    for i, edge in enumerate(edges):
        if edge["edge_id"] != i:
            raise ValueError(f"edge_id {edge['edge_id']} != index {i}; the router assumes equality")
    with open(path, "wb") as f:
        f.write(b"CPG1")
        f.write(struct.pack("<III", 1, node_count, e))
        f.write(struct.pack(f"<{e}i", *(x["from"] for x in edges)))
        f.write(struct.pack(f"<{e}i", *(x["to"] for x in edges)))
        f.write(struct.pack(f"<{e}d", *(float(x["free_flow_seconds"]) for x in edges)))
        f.write(struct.pack(f"<{e}f", *(float(x["free_flow_kmh"]) for x in edges)))


def write_nodes(nodes: list[tuple[float, float]], path: Path) -> None:
    n = len(nodes)
    with open(path, "wb") as f:
        f.write(b"CPN1")
        f.write(struct.pack("<III", 1, n, 0))
        f.write(struct.pack(f"<{n}d", *(lat for lat, _ in nodes)))
        f.write(struct.pack(f"<{n}d", *(lon for _, lon in nodes)))


def write_meta(priors: list[int], name_idx: list[int], hwy: list[int], names: list[str], path: Path) -> None:
    e = len(priors)
    encoded = [n.encode("utf-8") for n in names]
    offsets = [0]
    for b in encoded:
        offsets.append(offsets[-1] + len(b))
    with open(path, "wb") as f:
        f.write(b"CPM1")
        f.write(struct.pack("<IIII", 1, e, len(names), PRIOR_SCALE))
        f.write(struct.pack(f"<{e}h", *priors))
        f.write(struct.pack(f"<{e}H", *name_idx))
        f.write(struct.pack(f"<{e}B", *hwy))
        # pad to a 4-byte boundary so the offset table can be read as Uint32
        f.write(b"\0" * (-f.tell() % 4))
        f.write(struct.pack(f"<{len(offsets)}I", *offsets))
        for b in encoded:
            f.write(b)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    with open(GRAPH_JSON, encoding="utf-8") as f:
        graph = json.load(f)
    edges = graph["edges"]
    node_count = graph["node_count"]
    print(f"graph: {node_count} nodes, {len(edges)} edges")

    nodes: list[tuple[float, float]] = []
    priors: list[int] = []
    name_idx: list[int] = []
    hwy: list[int] = []
    names: list[str] = [""]  # index 0 reserved for "unnamed"
    name_lookup: dict[str, int] = {}

    with open(PRIOR_JSON, "rb") as f:
        for node in ijson.items(f, "nodes.item"):
            nodes.append((float(node["lat"]), float(node["lon"])))
    if len(nodes) != node_count:
        raise ValueError(f"prior has {len(nodes)} nodes, graph has {node_count}")

    hw_index = {h: i for i, h in enumerate(HIGHWAY_CODES)}
    unknown_hw: dict[str, int] = {}
    with open(PRIOR_JSON, "rb") as f:
        for i, e in enumerate(ijson.items(f, "edges.item")):
            if e["edge_id"] != i or e["from"] != edges[i]["from"] or e["to"] != edges[i]["to"]:
                raise ValueError(f"edge {i}: prior and graph disagree")
            milli = round(float(e["prior_logodds"]) * PRIOR_SCALE)
            if not -32768 <= milli <= 32767:
                raise ValueError(f"edge {i}: prior {e['prior_logodds']} does not fit Int16 thousandths")
            priors.append(milli)
            name = (e.get("street_name") or "").strip()
            if name:
                if name not in name_lookup:
                    name_lookup[name] = len(names)
                    names.append(name)
                name_idx.append(name_lookup[name])
            else:
                name_idx.append(0)
            h = e.get("highway")
            code = hw_index.get(h, 0)
            if code == 0 and h:
                unknown_hw[h] = unknown_hw.get(h, 0) + 1
            hwy.append(code)
    if len(names) > 65535:
        raise ValueError("more than 65,535 distinct street names; widen the name index")

    write_graph(edges, node_count, OUT_DIR / "graph.bin")
    write_nodes(nodes, OUT_DIR / "nodes.bin")
    write_meta(priors, name_idx, hwy, names, OUT_DIR / "meta.bin")

    manifest = {
        "pack": "citypulse-map-pack",
        "format_version": 1,
        "built": TODAY,
        "built_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "script": "scripts/build_packs.py",
        "source_snapshot": "data/graph/2026-09-14",
        "source_sha256": {
            "chennai_graph_cli.json": sha256(GRAPH_JSON),
            "chennai_prior_ell0.json": sha256(PRIOR_JSON),
        },
        "counts": {
            "nodes": node_count,
            "edges": len(edges),
            "named_edges": sum(1 for x in name_idx if x),
            "distinct_names": len(names) - 1,
            "unknown_highway_values": unknown_hw,
        },
        "prior_scale": PRIOR_SCALE,
        "highway_codes": HIGHWAY_CODES,
        "licence_note": "OSM-derived (ODbL) graph and names; GCC hazard-zone prior (OpenCity, stated public domain, "
        "not independently verified). See data/MANIFEST.md.",
        "files": {
            name: {"bytes": (OUT_DIR / name).stat().st_size, "sha256": sha256(OUT_DIR / name)}
            for name in ("graph.bin", "nodes.bin", "meta.bin")
        },
    }
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    for name, info in manifest["files"].items():
        print(f"{name:10s} {info['bytes'] / 1e6:6.2f} MB  {info['sha256'][:16]}")
    print("wrote", OUT_DIR)


if __name__ == "__main__":
    sys.exit(main())
