"""ADR-018: the city pipeline builds a valid pack for a non-Chennai city, deterministically, and
refuses what it cannot do honestly."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import pytest
import yaml

SCRIPTS = Path(__file__).resolve().parent.parent
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import city_pipeline as cp  # noqa: E402
import make_testville_fixture as fx  # noqa: E402

CITIES_FIXTURE = fx.PACK_DIR / "cities.yaml"


@pytest.fixture()
def testville():
    return cp.load_city("testville", CITIES_FIXTURE)


def test_builds_the_expected_pack(testville, tmp_path):
    m = cp.build_pack(testville, fx.FIXTURE_WAYS, tmp_path, "2026-10-03", CITIES_FIXTURE)
    assert (m["counts"]["nodes"], m["counts"]["edges"]) == (fx.EXPECTED_NODES, fx.EXPECTED_EDGES)
    # 5 "Row Road N" + "Ring Road" + 6 "Column Street N"; the broken column keeps one name.
    assert m["counts"]["distinct_names"] == 12
    assert m["city"]["id"] == "testville"
    assert m["city"]["hazard_layer"] is False
    assert (tmp_path / "graph.bin").read_bytes()[:4] == b"CPG1"
    assert (tmp_path / "nodes.bin").read_bytes()[:4] == b"CPN1"
    assert (tmp_path / "meta.bin").read_bytes()[:4] == b"CPM1"


def test_one_way_ring_road_has_one_direction_only(testville, tmp_path):
    cp.build_pack(testville, fx.FIXTURE_WAYS, tmp_path, "2026-10-03", CITIES_FIXTURE)
    g = (tmp_path / "graph.bin").read_bytes()
    _, _, n, e = struct.unpack("<4sIII", g[:16])[0:1] + struct.unpack("<III", g[4:16])
    frm = struct.unpack(f"<{e}i", g[16 : 16 + 4 * e])
    to = struct.unpack(f"<{e}i", g[16 + 4 * e : 16 + 8 * e])
    pairs = set(zip(frm, to))
    # The ring road is the top row of the grid; its pairs must not appear reversed.
    one_way = [(a, b) for a, b in pairs if (b, a) not in pairs]
    assert len(one_way) == 5


def test_flat_default_prior_on_every_edge(testville, tmp_path):
    cp.build_pack(testville, fx.FIXTURE_WAYS, tmp_path, "2026-10-03", CITIES_FIXTURE)
    meta = (tmp_path / "meta.bin").read_bytes()
    e = fx.EXPECTED_EDGES
    priors = struct.unpack(f"<{e}h", meta[20 : 20 + 2 * e])
    assert set(priors) == {-3892}, "p = 0.02 -> logit -3.892 -> -3892 thousandths on every edge"


def test_rebuild_is_byte_identical(testville, tmp_path):
    a, b = tmp_path / "a", tmp_path / "b"
    cp.build_pack(testville, fx.FIXTURE_WAYS, a, "2026-10-03", CITIES_FIXTURE)
    cp.build_pack(testville, fx.FIXTURE_WAYS, b, "2026-10-03", CITIES_FIXTURE)
    for name in ("graph.bin", "nodes.bin", "meta.bin", "manifest.json"):
        assert (a / name).read_bytes() == (b / name).read_bytes(), name


def test_committed_fixture_pack_is_current(testville, tmp_path):
    """If the builder changes, the committed Dart fixture must be regenerated on purpose."""
    cp.build_pack(testville, fx.FIXTURE_WAYS, tmp_path, "2026-10-03", CITIES_FIXTURE)
    for name in ("graph.bin", "nodes.bin", "meta.bin"):
        assert (tmp_path / name).read_bytes() == (fx.PACK_DIR / name).read_bytes(), (
            f"{name} differs from the committed fixture; run scripts/tests/make_testville_fixture.py"
        )


def test_refuses_a_hazard_layer_city(testville, tmp_path):
    testville["hazard_layer"] = True
    with pytest.raises(SystemExit, match="hazard_layer"):
        cp.build_pack(testville, fx.FIXTURE_WAYS, tmp_path, "2026-10-03", CITIES_FIXTURE)


def test_refuses_a_centre_the_roads_do_not_cover(testville, tmp_path):
    testville["centre"] = {"lat": 13.04, "lon": 80.23}
    with pytest.raises(SystemExit, match="centre"):
        cp.build_pack(testville, fx.FIXTURE_WAYS, tmp_path, "2026-10-03", CITIES_FIXTURE)


def test_load_city_errors_are_specific(tmp_path):
    with pytest.raises(SystemExit, match="unknown city 'atlantis'.*testville"):
        cp.load_city("atlantis", CITIES_FIXTURE)
    doc = yaml.safe_load(CITIES_FIXTURE.read_text(encoding="utf-8"))
    doc["cities"]["testville"]["bbox"]["min_lat"] = 30.0
    bad = tmp_path / "bad.yaml"
    bad.write_text(yaml.safe_dump(doc), encoding="utf-8")
    with pytest.raises(SystemExit, match="inverted"):
        cp.load_city("testville", bad)


def test_the_real_chennai_entry_loads_and_is_not_buildable_here():
    chennai = cp.load_city("chennai")
    assert chennai["hazard_layer"] is True
    assert chennai["pack"] == "data/packs/2026-10-02"
    with pytest.raises(SystemExit, match="hazard_layer"):
        cp.build_pack(chennai, Path("unused.json"), Path("unused"), "2026-10-03")
