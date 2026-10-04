"""Builds the SYNTHETIC test city used to prove the pipeline is not Chennai-specific (ADR-018).

"Testville" is a 6 x 6 street grid placed in open country (lat 20.00 N, lon 78.00 E). It is made up:
no real road, name or place. Its shape is chosen to exercise the builder:

  * 6 two-way "Row Road N" streets and 6 "Column Street N" streets (residential);
  * Column Street 3 is broken between rows 3 and 4 (two separate ways, no shared node), so a
    straight run through it is impossible and the router must go around;
  * "Ring Road" (row 6) is a one-way primary road, so the builder must emit one direction only;
  * nodes are 0.004 deg apart (about 440 m).

Edges expected (worked out by hand, then checked against the builder): rows 1-5 two-way
5 x 5 x 2 = 50; the one-way Ring Road 5; the five unbroken columns 5 x 5 x 2 = 50; the broken
column's two halves 2 x 2 x 2 = 8; total 113 (EXPECTED_EDGES).

Usage (from the repo root): python scripts/tests/make_testville_fixture.py
Writes scripts/tests/fixtures/testville_ways.json and packages/pulse_router/test/fixtures/testville/
(pack + cities.yaml entry), both committed so tests need no network and no build step.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

LAT0, LON0, STEP, N = 20.00, 78.00, 0.004, 6
EXPECTED_NODES = 36
# rows 1-5 two-way (5 rows x 5 segs x 2) + ring road one-way (5) + columns 0,1,2,4,5 (5 x 5 x 2)
# + column 3 halves (2 x 2 segs x 2 dirs)
EXPECTED_EDGES = 5 * 5 * 2 + 5 + 5 * 5 * 2 + 2 * 2 * 2

FIXTURE_WAYS = HERE / "fixtures" / "testville_ways.json"
PACK_DIR = ROOT / "packages" / "pulse_router" / "test" / "fixtures" / "testville"


def node(r: int, c: int) -> tuple[int, dict]:
    return 1000 + r * 10 + c, {"lat": round(LAT0 + r * STEP, 6), "lon": round(LON0 + c * STEP, 6)}


def way(way_id: int, cells: list[tuple[int, int]], tags: dict) -> dict:
    nodes = [node(r, c) for r, c in cells]
    return {
        "type": "way",
        "id": way_id,
        "nodes": [n[0] for n in nodes],
        "geometry": [n[1] for n in nodes],
        "tags": tags,
    }


def build_ways() -> dict:
    elements = []
    for r in range(N):
        tags = {"highway": "residential", "name": f"Row Road {r + 1}"}
        if r == N - 1:
            tags = {"highway": "primary", "name": "Ring Road", "oneway": "yes"}
        elements.append(way(2000 + r, [(r, c) for c in range(N)], tags))
    for c in range(N):
        tags = {"highway": "residential", "name": f"Column Street {c + 1}"}
        if c == 3:
            elements.append(way(3000 + c, [(r, c) for r in range(0, 3)], tags))
            elements.append(way(3100 + c, [(r, c) for r in range(3, N)], tags))
        else:
            elements.append(way(3000 + c, [(r, c) for r in range(N)], tags))
    return {
        "version": 0.6,
        "generator": "scripts/tests/make_testville_fixture.py (synthetic; not OpenStreetMap)",
        "osm3s": {"timestamp_osm_base": "synthetic"},
        "bbox": {"min_lat": 19.99, "max_lat": 20.03, "min_lon": 77.99, "max_lon": 78.03},
        "elements": elements,
    }


CITIES_YAML = """\
# Fixture for packages/pulse_router/test/city_pack_test.dart. SYNTHETIC city, not a real place.
default_city: testville
cities:
  testville:
    name: { en: Testville, ta: டெஸ்ட்வில் }
    centre: { lat: 20.010, lon: 78.010 }
    bbox: { min_lat: 19.99, max_lat: 20.03, min_lon: 77.99, max_lon: 78.03 }
    pack: packages/pulse_router/test/fixtures/testville
    hazard_layer: false
"""


def main() -> None:
    import city_pipeline as cp

    FIXTURE_WAYS.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE_WAYS.write_text(json.dumps(build_ways(), indent=1), encoding="utf-8")
    PACK_DIR.mkdir(parents=True, exist_ok=True)
    cities = PACK_DIR / "cities.yaml"
    cities.write_text(CITIES_YAML, encoding="utf-8")
    city = cp.load_city("testville", cities)
    manifest = cp.build_pack(city, FIXTURE_WAYS, PACK_DIR, "2026-10-03", config_path=cities)
    c = manifest["counts"]
    assert (c["nodes"], c["edges"]) == (EXPECTED_NODES, EXPECTED_EDGES), c
    print(f"wrote {FIXTURE_WAYS} and {PACK_DIR}: {c['nodes']} nodes, {c['edges']} edges")


if __name__ == "__main__":
    main()
