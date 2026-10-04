"""Tests for scripts/build_india_flood_dataset.py (ADR-023).

The unit tests need nothing but the script. The last group checks the committed outputs and is skipped
on a machine that has not built them.
"""

from __future__ import annotations

import csv
import datetime as dt
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_india_flood_dataset as b  # noqa: E402

OUT = Path(__file__).resolve().parents[2] / "data" / "india_flood" / "2026-10-04"


def test_dates_are_day_first_and_bad_values_are_none():
    assert b.parse_date("02-07-1967 00:00") == dt.date(1967, 7, 2)
    assert b.parse_date("12-04-2015") == dt.date(2015, 4, 12)
    assert b.parse_date("") is None
    assert b.parse_date("not a date") is None


def test_district_names_are_matched_across_spellings():
    assert b.key("Thiruvallur") == b.key("Tiruvallur") == "thiruvallur"
    assert b.key("Kanniyakumariumari") == b.key("Nagarkoil") == b.key("Kanniyakumari")
    assert b.key("The Nilgiris") == b.key("Nilgiris")
    assert b.key("Chennai ") == "chennai"


def test_numbers_and_lists_are_parsed_without_inventing_values():
    assert b.to_int("12") == 12 and b.to_int("12.0") == 12
    assert b.to_int("") is None and b.to_int("many") is None
    assert b.split_list(" A, B ,,C ") == ["A", "B", "C"]


SQUARE_WITH_HOLE = {
    "type": "Polygon",
    "coordinates": [
        [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
        [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
    ],
}


def test_a_point_in_the_polygon_is_inside_and_one_in_the_hole_or_outside_is_not():
    assert b.polygon_contains(SQUARE_WITH_HOLE, 2, 2)
    assert not b.polygon_contains(SQUARE_WITH_HOLE, 5, 5), "inside the hole"
    assert not b.polygon_contains(SQUARE_WITH_HOLE, 11, 5)


def test_multipolygon_contains_a_point_in_any_part():
    multi = {
        "type": "MultiPolygon",
        "coordinates": [
            [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]],
            [[[5, 5], [6, 5], [6, 6], [5, 6], [5, 5]]],
        ],
    }
    assert b.polygon_contains(multi, 5.5, 5.5)
    assert not b.polygon_contains(multi, 3, 3)


def test_the_link_window_is_plus_or_minus_three_days_on_each_side():
    d = dt.date
    # 4 days apart: each widened by 3 days, so they meet.
    assert b.overlaps(d(2015, 12, 1), d(2015, 12, 1), d(2015, 12, 5), d(2015, 12, 5), b.LINK_DAYS)
    # 7 days apart: the windows are 3 + 3 = 6 days wide in total, so they do not meet.
    assert not b.overlaps(d(2015, 12, 1), d(2015, 12, 1), d(2015, 12, 8), d(2015, 12, 8), b.LINK_DAYS)
    assert b.overlaps(d(2015, 12, 1), d(2015, 12, 3), d(2015, 12, 2), d(2015, 12, 2), 0)


def test_the_link_rule_constant_is_the_registered_one():
    assert b.LINK_DAYS == 3


built = pytest.mark.skipif(not (OUT / "result.json").exists(), reason="dataset not built")


@built
def test_every_row_is_tagged_non_commercial_and_deaths_are_not_summed():
    rows = [json.loads(x) for x in (OUT / "events.ndjson").read_text(encoding="utf-8").splitlines()]
    assert rows and all(r["commercial_use"] is False and r["licence"] for r in rows)
    cal = list(csv.DictReader((OUT / "tn_event_calendar.csv").open(encoding="utf-8")))
    assert "imd_deaths_max" in cal[0] and "dfo_deaths_max" in cal[0]
    assert not any("deaths_total" in k for k in cal[0])


@built
def test_counts_in_the_result_file_match_the_files():
    res = json.loads((OUT / "result.json").read_text(encoding="utf-8"))
    rows = [json.loads(x) for x in (OUT / "events.ndjson").read_text(encoding="utf-8").splitlines()]
    assert len(rows) == res["counts"]["ifi_events"] + res["counts"]["dfo_events"]
    links = list(csv.DictReader((OUT / "links_tn.csv").open(encoding="utf-8")))
    assert len(links) == res["counts"]["links"]
    cal = list(csv.DictReader((OUT / "tn_event_calendar.csv").open(encoding="utf-8")))
    assert len(cal) == res["counts"]["tn_calendar_rows"]
    assert sum(1 for c in cal if c["corroborated_by_both_sources"] == "True") == res["counts"][
        "tn_calendar_corroborated_by_both"
    ]


@built
def test_inputs_are_pinned_by_hash():
    res = json.loads((OUT / "result.json").read_text(encoding="utf-8"))
    for name, digest in res["inputs_sha256"].items():
        assert b.sha256(OUT / "raw" / name) == digest, f"{name} changed since the build"


@built
def test_the_existing_replay_proxy_date_is_inside_an_imd_chennai_event():
    res = json.loads((OUT / "result.json").read_text(encoding="utf-8"))
    assert res["chennai_2015"]["proxy_date_inside_an_imd_chennai_event"] is True
