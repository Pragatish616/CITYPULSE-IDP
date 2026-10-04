"""ADR-020: the lean regional builder writes exactly the pack that the Chennai builder writes."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import make_testville_fixture as fx  # noqa: E402
import region_pack as rp  # noqa: E402


def test_same_pack_as_the_chennai_builders_on_the_testville_grid(tmp_path):
    ways = list(rp.read_ways_overpass_json(fx.FIXTURE_WAYS, rp.LEVELS["all"]))
    built = rp.build_arrays(ways)
    assert (len(built.node_lat), len(built.src)) == (fx.EXPECTED_NODES, fx.EXPECTED_EDGES)
    rp.write_pack(built, tmp_path)
    # Nodes and metadata (names, road classes, priors) are byte-identical.
    for name in ("nodes.bin", "meta.bin"):
        assert (tmp_path / name).read_bytes() == (fx.PACK_DIR / name).read_bytes(), name
    # graph.bin: same endpoints, speeds and layout; the times agree to floating-point noise (Python's
    # `sum` compensates its rounding and a running total does not: about 1e-11 s on a 75 s edge).
    import struct

    mine = (tmp_path / "graph.bin").read_bytes()
    ref = (fx.PACK_DIR / "graph.bin").read_bytes()
    e = fx.EXPECTED_EDGES
    assert len(mine) == len(ref)
    structural = slice(0, 16 + 8 * e)  # header, from, to
    assert mine[structural] == ref[structural]
    assert mine[16 + 16 * e :] == ref[16 + 16 * e :]  # km/h
    a = struct.unpack(f"<{e}d", mine[16 + 8 * e : 16 + 16 * e])
    b = struct.unpack(f"<{e}d", ref[16 + 8 * e : 16 + 16 * e])
    assert max(abs(x - y) for x, y in zip(a, b)) < 1e-6


def test_a_level_keeps_only_its_road_classes():
    ways = list(rp.read_ways_overpass_json(fx.FIXTURE_WAYS, rp.LEVELS["backbone"]))
    # Testville has one primary road (the one-way Ring Road); its residential streets are dropped.
    assert {w[1] for w in ways} == {"primary"}
    # Only the Ring Road remains, so no small road joins it and its nodes are not junctions. A long
    # edge is cut every 800 m so there is something to snap to: 5 segments of about 420 m become 3.
    built = rp.build_arrays(ways)
    assert len(built.src) == 3
    uncut = rp.build_arrays(ways, max_edge_m=1e9)
    assert len(uncut.src) == 1
    # Cutting changes where the nodes are, not how long the road is or how long it takes.
    assert sum(built.seconds) == pytest.approx(sum(uncut.seconds), abs=0.01)
    longest_m = max(sec * spd / 3.6 for sec, spd in zip(built.seconds, built.kmh))
    assert longest_m < 800 + 450  # an edge ends at the first node past the limit


def test_the_name_table_overflow_is_refused_not_truncated(tmp_path):
    built = rp.Built()
    built.node_lat.extend([0.0, 1.0])
    built.node_lon.extend([0.0, 1.0])
    built.src.append(0)
    built.dst.append(1)
    built.seconds.append(10.0)
    built.kmh.append(20.0)
    built.name_idx.append(0)
    built.hwy.append(12)
    built.names.extend(f"street {i}" for i in range(70000))
    with pytest.raises(SystemExit, match="16-bit name index"):
        rp.write_pack(built, tmp_path)


def test_flat_prior_is_the_chennai_no_zone_value():
    assert rp.FLAT_PRIOR_MILLI == -3892


def test_places_file_is_compact_utf8_and_counted(tmp_path):
    places = [
        ["Madurai", 9.9252, 78.1198, "city", "மதுரை", "Madura"],
        ["Kovil Patti", 9.17, 77.87, "town"],
    ]
    info = rp.write_places(places, tmp_path)
    raw = (tmp_path / "places.json").read_text(encoding="utf-8")
    assert "மதுரை" in raw, "Tamil is written as text, not escapes"
    assert info["count"] == 2 and info["by_kind"] == {"city": 1, "town": 1}
    import json

    assert json.loads(raw)["places"][0][0] == "Madurai"
    assert info["bytes"] == len(raw.encode("utf-8"))


def test_a_roads_search_name_joins_its_name_and_highway_number():
    assert rp.display_name("Salem - Kochi Highway", "NH 544") == "Salem - Kochi Highway (NH 544)"
    assert rp.display_name(None, "NH 44") == "NH 44"
    assert rp.display_name("Anna Salai", None) == "Anna Salai"
    assert rp.display_name("NH 44 Bypass", "NH 44") == "NH 44 Bypass", "no repeat when the name has it"
    assert rp.display_name("", "") == ""
