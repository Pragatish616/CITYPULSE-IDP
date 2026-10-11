"""Part A3 (ADR-034): the OSM feature helpers do what they say on cases with known answers, and the stored verdict follows the pre-registered rule."""

import json
import sys
from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import extract_osm_chennai as ex

RESULT = json.loads((ROOT / "data" / "results" / "2026-10-11-susceptibility-chennai-a3" / "result.json").read_text(encoding="utf-8"))


def test_building_area_of_a_100_m_square_is_about_10000_square_metres() -> None:
    d = 100.0 / 111_195.0
    lat0, lon0 = 13.0, 80.2
    dx = d / np.cos(np.radians(lat0))
    lats = [lat0, lat0, lat0 + d, lat0 + d, lat0]
    lons = [lon0, lon0 + dx, lon0 + dx, lon0, lon0]
    assert abs(ex.area_m2(lats, lons) - 10_000.0) < 100.0


def test_polygon_and_line_rasters_mark_the_expected_cells() -> None:
    pytest.importorskip("PIL")
    pytest.importorskip("scipy")
    import sus_build_a3 as b3

    ident = lambda la, lo: (lo, la)  # noqa: E731  (the coordinates are already pixels in this test)
    square = np.array([[2.0, 2.0], [2.0, 6.0], [6.0, 6.0], [6.0, 2.0]])
    m = b3.raster_polys(square, np.array([0, 4]), (10, 10), ident)
    assert m[4, 4] and not m[0, 0] and 16 <= m.sum() <= 36
    line = np.array([[1.0, 0.0], [1.0, 9.0]])  # lat (row) 1, lon (column) 0..9 -> one row of cells
    ln = b3.raster_lines(line, np.array([0, 2]), (10, 10), ident)
    assert ln[:, :].sum() >= 10 and ln[1, 5]


def test_the_stored_verdict_follows_the_rule_written_before_the_run() -> None:
    r = RESULT["results"]
    a = all(r[k]["B_minus_A2"]["auc"]["ci95"][0] > 0 for k in ("core_2005_to_2015", "core_2015_to_2005"))
    b = r["spatial_blocks_2015"]["B_minus_A2"]["ap"]["ci95"][0] > 0
    assert RESULT["decision_rule"]["a_core_both_directions_auc_B_beats_A2"] == a
    assert RESULT["decision_rule"]["b_spatial_blocks_ap_B_beats_A2"] == b
    assert RESULT["decision_rule"]["osm_features_add_value"] == (a and b)


def test_the_run_used_the_committed_preregistration() -> None:
    assert len(RESULT["preregistration_commit"]) == 40
    assert RESULT["features"][-6:] == ["bld_share_90m", "bld_share_1km", "built_landuse_1km", "green_landuse_1km", "dist_waterway_km", "dist_waterbody_km"]
