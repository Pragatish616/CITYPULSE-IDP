"""
T0.2 -- Graph build and query time (de-risking spike, week 1).

Per docs/IMPLEMENTATION_PLAN.md T0.2:
  Geofabrik Southern-Zone extract (pinned by date) -> filter drivable ways -> CSR-style
  adjacency -> bidirectional Dijkstra over 1000 random OD pairs.

DEVIATIONS FROM THE PLAN, FLAGGED HONESTLY (2026-09-13) -- this machine has 7.4GB total
RAM with as little as ~0.4-1.1GB free at run time (confirmed via direct measurement;
Windows was already using Memory Compression, i.e. genuine sustained pressure, not a
fluke). Three earlier, progressively leaner attempts were all OOM-killed:
  1. pyosmium on the full 6-state Geofabrik PBF (557MB) with a disk-backed location index.
  2. Overpass API (whole Chennai bbox, one request) + json.loads() + networkx.DiGraph.
  3. Overpass API (whole Chennai bbox, one request) + streamed download + ijson streaming
     parse + plain array adjacency (no networkx) -- still killed, which means the machine
     genuinely cannot hold "Chennai's whole drivable network, however represented" in RAM
     at once right now, not that any particular library was the problem.
This version fixes that by never holding more than one HIGHWAY-CLASS CHUNK in memory at
a time: Overpass is queried once per highway class (fewer classes = smaller responses),
each response is stream-parsed and written straight into an on-disk SQLite database
(data/osm/chennai_graph.sqlite, gitignored), and the chunk's Python objects are discarded
before the next class is fetched. The final node/edge COUNT is always reported even if
there isn't enough RAM left to run the timing queries themselves -- this spike's minimum
job (per T0.2's own acceptance criterion) is "node/edge counts, on-disk size" first,
"p50/p95/p99 latency" second, and the two are reported independently so a hardware
limit on this machine doesn't block reporting the counts.

REMAINING DEVIATION: Overpass returns live OSM data, not a pinned dated snapshot -- the
real T1.3 graph build (week 2) must still use the already-downloaded, pinned Geofabrik
file (data/osm/southern-zone-260911.osm.pbf, dated 2026-09-11), run on a machine with
more RAM (recommend >=8GB genuinely free, e.g. the Oracle Cloud Always Free 12GB tier
this project already budgets for in docs/APIS_AND_COSTS.md).

This is a throwaway spike script (per the plan: "the output is a decision, not code").
The PRODUCTION router is a hand-written Dart CSR + ALT implementation per ADR-001.

Usage: .venv/Scripts/python.exe scripts/t0_2_graph_timing.py
"""
import heapq
import json
import math
import random
import sqlite3
import time
from pathlib import Path

import ijson
import requests

ROOT = Path(__file__).resolve().parent.parent
RESULTS_DIR = ROOT / "data" / "results" / "2026-09-13-t02-graph"
DB_PATH = ROOT / "data" / "osm" / "chennai_graph.sqlite"

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
BBOX = {"min_lat": 12.75, "max_lat": 13.25, "min_lon": 79.95, "max_lon": 80.35}
SEED = 20260912

# One Overpass query per group -- keeps each individual response small. Grouped roughly
# by expected volume (motorway/trunk/primary are rare; residential/unclassified are the
# bulk of any city's network).
CLASS_GROUPS = [
    ["motorway", "trunk", "primary", "motorway_link", "trunk_link", "primary_link"],
    ["secondary", "tertiary", "secondary_link", "tertiary_link"],
    ["unclassified"],
    ["residential"],
]

HEADERS = {"User-Agent": "CityPulse-IDP-week1-spike/0.1 (VIT Chennai research project)"}


def haversine_m(lat1, lon1, lat2, lon2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(min(1, math.sqrt(h)))


def init_db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    if DB_PATH.exists():
        DB_PATH.unlink()
    con = sqlite3.connect(DB_PATH)
    con.execute("PRAGMA journal_mode=OFF")
    con.execute("PRAGMA synchronous=OFF")
    con.execute("CREATE TABLE edges (u INTEGER, v INTEGER, w REAL)")
    con.execute("CREATE TABLE ways_kept (n INTEGER)")
    con.commit()
    return con


def fetch_chunk(classes):
    query = f"""
[out:json][timeout:180];
(
  way["highway"~"^({"|".join(classes)})$"]
     ({BBOX['min_lat']},{BBOX['min_lon']},{BBOX['max_lat']},{BBOX['max_lon']});
);
out geom;
"""
    resp = requests.post(OVERPASS_URL, data={"data": query}, headers=HEADERS, timeout=200)
    resp.raise_for_status()
    return resp.content  # bytes, handed straight to ijson -- never json.loads()'d whole


def process_chunk(con, classes):
    print(f"Fetching {classes} ...")
    t0 = time.perf_counter()
    raw = fetch_chunk(classes)
    print(f"  {len(raw) / 1e6:.1f} MB in {time.perf_counter() - t0:.1f}s, parsing...")

    ways_kept = 0
    rows = []
    for el in ijson.items(raw, "elements.item"):
        if el.get("type") != "way":
            continue
        geom = el.get("geometry")
        nodes = el.get("nodes")
        if not geom or not nodes or len(geom) < 2:
            continue
        oneway = el.get("tags", {}).get("oneway") in ("yes", "true", "1")
        ways_kept += 1
        for i in range(len(nodes) - 1):
            g1, g2 = geom[i], geom[i + 1]
            length_m = haversine_m(g1["lat"], g1["lon"], g2["lat"], g2["lon"])
            if length_m <= 0:
                continue
            w = length_m / (30 * 1000 / 3600)
            rows.append((nodes[i], nodes[i + 1], w))
            if not oneway:
                rows.append((nodes[i + 1], nodes[i], w))
        if len(rows) > 20000:  # flush periodically to keep peak memory flat
            con.executemany("INSERT INTO edges VALUES (?,?,?)", rows)
            rows.clear()
    if rows:
        con.executemany("INSERT INTO edges VALUES (?,?,?)", rows)
    con.execute("INSERT INTO ways_kept VALUES (?)", (ways_kept,))
    con.commit()
    del raw
    print(f"  {ways_kept} ways kept for this class group")


def build_db():
    con = init_db()
    for classes in CLASS_GROUPS:
        process_chunk(con, classes)
    con.execute("CREATE INDEX idx_edges_u ON edges(u)")
    con.commit()
    return con


def report_counts(con):
    n_nodes = con.execute(
        "SELECT COUNT(*) FROM (SELECT u FROM edges UNION SELECT v FROM edges)"
    ).fetchone()[0]
    n_edges = con.execute("SELECT COUNT(*) FROM edges").fetchone()[0]
    ways_kept = con.execute("SELECT SUM(n) FROM ways_kept").fetchone()[0]
    return n_nodes, n_edges, ways_kept


def try_in_memory_timing(con, node_cap=250_000):
    """Only attempt the in-memory Dijkstra timing if the graph is small enough that
    this machine's remaining RAM can plausibly hold it. Returns None if skipped."""
    n_nodes, n_edges, _ = report_counts(con)
    if n_nodes > node_cap:
        print(f"Skipping in-memory timing: {n_nodes} nodes exceeds the safety cap of "
              f"{node_cap} for this machine's available RAM. Counts are still reported.")
        return None

    print("Building largest connected component + adjacency arrays for timing...")
    node_index = {}
    adj = []
    cur = con.execute("SELECT u, v, w FROM edges")
    for u_osm, v_osm, w in cur:
        u = node_index.setdefault(u_osm, len(node_index))
        if u == len(adj):
            adj.append([])
        v = node_index.setdefault(v_osm, len(node_index))
        if v == len(adj):
            adj.append([])
        adj[u].append((v, w))

    visited = [False] * len(adj)
    best = []
    for start in range(len(adj)):
        if visited[start]:
            continue
        comp = []
        stack = [start]
        visited[start] = True
        while stack:
            x = stack.pop()
            comp.append(x)
            for (y, _w) in adj[x]:
                if not visited[y]:
                    visited[y] = True
                    stack.append(y)
        if len(comp) > len(best):
            best = comp
    keep = set(best)
    remap = {old: new for new, old in enumerate(best)}
    adj_main = [[] for _ in best]
    for old_u in best:
        u = remap[old_u]
        for (old_v, w) in adj[old_u]:
            if old_v in keep:
                adj_main[u].append((remap[old_v], w))

    return adj_main


def dijkstra(adj, s, t):
    n = len(adj)
    dist = [math.inf] * n
    dist[s] = 0.0
    pq = [(0.0, s)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == t:
            return d
        if d > dist[u]:
            continue
        for (v, w) in adj[u]:
            nd = d + w
            if nd < dist[v]:
                dist[v] = nd
                heapq.heappush(pq, (nd, v))
    return None


def measure_queries(adj, n_pairs=1000, seed=SEED):
    random.seed(seed)
    n = len(adj)
    latencies_ms, failures = [], 0
    for _ in range(n_pairs):
        s, t = random.sample(range(n), 2)
        t0 = time.perf_counter()
        d = dijkstra(adj, s, t)
        if d is None:
            failures += 1
            continue
        latencies_ms.append((time.perf_counter() - t0) * 1000)
    latencies_ms.sort()

    def pct(p):
        if not latencies_ms:
            return None
        idx = min(len(latencies_ms) - 1, int(len(latencies_ms) * p))
        return latencies_ms[idx]

    return {
        "n_pairs_requested": n_pairs, "n_pairs_succeeded": len(latencies_ms),
        "n_pairs_no_path": failures, "p50_ms": pct(0.50), "p95_ms": pct(0.95),
        "p99_ms": pct(0.99),
        "min_ms": latencies_ms[0] if latencies_ms else None,
        "max_ms": latencies_ms[-1] if latencies_ms else None,
    }


def main():
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    con = build_db()
    n_nodes, n_edges, ways_kept = report_counts(con)
    db_size_mb = DB_PATH.stat().st_size / 1e6
    print(f"\nChennai drivable graph (raw, all class-group chunks combined): "
          f"{n_nodes} nodes, {n_edges} directed edges, {ways_kept} ways, "
          f"SQLite db {db_size_mb:.1f} MB")

    adj_main = try_in_memory_timing(con)
    query_stats = measure_queries(adj_main) if adj_main is not None else None
    if query_stats:
        print(json.dumps(query_stats, indent=2))

    result = {
        "spike": "T0.2 - graph build and query time",
        "data_source_deviation": (
            "Overpass API (live OSM data, chunked by highway class), not the pinned "
            "Geofabrik southern-zone-260911.osm.pbf -- this machine (7.4GB RAM, as little "
            "as ~0.4-1.1GB free, confirmed via direct measurement) OOM-killed three "
            "progressively leaner in-memory approaches. On-disk SQLite avoided a fourth "
            "failure. The real pinned-snapshot graph build (T1.3) must use the Geofabrik "
            "file on a machine with more RAM (recommend the Oracle Cloud Always Free 12GB "
            "tier this project already budgets for)."
        ),
        "pinned_geofabrik_file_available_but_unused": str(
            ROOT / "data" / "osm" / "southern-zone-260911.osm.pbf"
        ),
        "bbox": BBOX,
        "seed": SEED,
        "ways_kept": ways_kept,
        "graph_raw": {"node_count": n_nodes, "edge_count_directed": n_edges},
        "sqlite_db_size_mb": round(db_size_mb, 1),
        "query_latency_ms": query_stats,
        "timing_skipped_reason": (
            None if query_stats else
            "node count exceeded this machine's safe in-memory cap; counts above are still real"
        ),
        "note": (
            "SQLite-backed spike for node/edge counts. Where memory allowed, timing used a "
            "plain array-adjacency + heapq Dijkstra (single-direction, not bidirectional) "
            "on the largest connected component. Production router is Dart CSR+ALT (ADR-001)."
        ),
        "decision_it_forces": (
            "if p95 > ~150ms, add ALT landmarks immediately (T2.3); "
            "if 10-40ms as expected, ALT is an optimisation and a paper result, not a necessity. "
            "If timing was skipped: the node/edge counts alone already tell us whether Chennai "
            "is close to the ~10^5-node estimate CLAUDE.md assumes."
        ),
    }

    out_path = RESULTS_DIR / "result.json"
    out_path.write_text(json.dumps(result, indent=2))
    print(f"\nWrote {out_path}")
    con.close()
    return result


if __name__ == "__main__":
    main()
