"""CSFE prototype: parsing rules, the hand-entered news facts, and invariants of the built table (when it has been built)."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import build_csfe_proto as b  # noqa: E402

NEWS = ROOT / "data" / "csfe" / "news_facts_2026-10-30.csv"
OBS = ROOT / "data" / "csfe" / "2026-10-30" / "observations.csv"
COUNTS = ROOT / "data" / "csfe" / "news_counts_2026-10-30.csv"


def test_depth_classes_become_cm_ranges() -> None:
    assert b.depth_range("<2ft") == (0, 61)
    assert b.depth_range("3 to 5 ft") == (91, 152)
    assert b.depth_range(">5ft") == (152, None)
    assert b.depth_range("2-3") == (61, 91)
    assert b.depth_range(None) == (None, None)
    assert b.depth_range("unknown") == (None, None)


def test_news_names_map_to_one_watchlist_subway_each() -> None:
    subs = json.loads((ROOT / "data" / "watchlist" / "2026-10-09" / "subways.json").read_text(encoding="utf-8"))["entries"]
    alias = b.subway_aliases(subs)
    assert alias[b.norm_name("Gangureddy subway")]["id"] == alias[b.norm_name("Gengureddy subway")]["id"]
    assert alias[b.norm_name("Saidapet-Aranganathan subway")]["id"] == alias[b.norm_name("Aranganathan subway")]["id"]
    # Ambiguous names stay unmatched on purpose.
    for name in ("Mount subway", "CB Road subway", "C.P. Road subway"):
        assert b.norm_name(name) not in alias


def test_news_facts_are_well_formed() -> None:
    rows = list(csv.DictReader(NEWS.open(encoding="utf-8")))
    assert len(rows) == 78
    assert len({r["fact_id"] for r in rows}) == len(rows)
    for r in rows:
        assert r["status"] in {"closed", "not_waterlogged", "partly_open", "waterlogged_open", "reopened"}
        assert r["url"].startswith("https://")
        assert len(r["phrase"].split()) <= 12  # a short quote, never article text


@pytest.mark.skipif(not OBS.exists(), reason="prototype not built on this machine")
def test_built_table_invariants() -> None:
    rows = list(csv.DictReader(OBS.open(encoding="utf-8")))
    assert len({r["obs_id"] for r in rows}) == len(rows)
    kinds = {"closed", "partly_open", "open", "waterlogged_open", "not_waterlogged", "waterlogged", "depth", "depth_range",
             "report_unclear"}
    assert {r["kind"] for r in rows} <= kinds
    for r in rows:
        if r["kind"] == "depth":
            assert r["value_unit"] == "cm" and float(r["value"]) >= 0
        if r["lat"]:
            assert b.in_box(float(r["lat"]), float(r["lon"]))
        if r["rain_day_mm_nearest"]:
            assert float(r["rain_gauge_km"]) <= 10 and r["t_precision"] in ("minute", "reported_by")
        assert r["source_ref"] and r["licence"]
    # Free text from the citizen app is never carried into the table.
    assert "details" not in rows[0]


def test_new_spellings_map_to_the_same_subway() -> None:
    subs = json.loads((ROOT / "data" / "watchlist" / "2026-10-09" / "subways.json").read_text(encoding="utf-8"))["entries"]
    alias = b.subway_aliases(subs)
    perambur = alias[b.norm_name("Perambur subway")]["id"]
    for name in ("Perambur Railway subway", "Perambur High Road subway", "Sembium (Perambur) subway"):
        assert alias[b.norm_name(name)]["id"] == perambur, name
    dorai = alias[b.norm_name("Duraisamy subway")]["id"]
    for name in ("Duraisami subway", "Duralsamy subway"):
        assert alias[b.norm_name(name)]["id"] == dorai, name
    assert alias[b.norm_name("Rangarajapuram 2-wheeler subway")]["id"] == alias[b.norm_name("Rangarajapuram subway")]["id"]
    assert alias[b.norm_name("Gunguruddy subway")]["id"] == alias[b.norm_name("Gengu Reddy subway")]["id"]


def test_city_level_counts_are_well_formed() -> None:
    rows = list(csv.DictReader(COUNTS.open(encoding="utf-8")))
    assert len(rows) == 8
    for r in rows:
        assert r["url"].startswith("https://") and r["status"]
        assert len(r["statement"].split()) <= 15
