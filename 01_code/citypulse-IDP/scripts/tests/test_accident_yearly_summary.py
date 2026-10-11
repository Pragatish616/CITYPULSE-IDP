"""The Greater Chennai Police yearly crash totals: the files are the ones logged, and their one inconsistency is reported, not hidden."""

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import accident_yearly_summary as ays

LOG = json.loads((ays.DIR / "fetch_log.json").read_text(encoding="utf-8"))
SUMMARY = json.loads((ays.DIR / "summary.json").read_text(encoding="utf-8"))


def test_the_files_are_exactly_the_ones_in_the_fetch_log() -> None:
    for f in LOG["files"]:
        data = ays.lf(ays.DIR / "raw" / f["name"])  # line endings differ between the download (CRLF) and a Linux checkout (LF)
        assert len(data) == f["bytes_lf"] and hashlib.sha256(data).hexdigest() == f["sha256_lf"], f["name"]
    assert LOG["licence"].startswith("Other (Public Domain)")


def test_the_summary_is_what_the_script_makes_from_the_files() -> None:
    rows = ays.read_chennai()
    assert ays.checks(rows) == SUMMARY["checks"]
    assert SUMMARY["files"]["chennai-road-crashes-1998-2025.csv"]["sha256_lf"] == LOG["files"][0]["sha256_lf"]


def test_27_of_28_years_add_up_and_2013_is_reported_as_off_by_five() -> None:
    c = ays.checks(ays.read_chennai())
    assert c["rows"] == 28 and c["years"] == [1998, 2025] and c["years_consecutive"] is True
    assert c["years_where_the_four_severity_counts_add_up_to_the_total"] == 27
    assert c["years_where_they_do_not"] == [2013]
    r = next(r for r in ays.read_chennai() if r["year"] == 2013)
    assert r["fatal"] + r["grievous"] + r["minor"] + r["non_injury"] == 9705 and r["total"] == 9710
    assert c["killed_at_least_fatal_accidents_every_year"] and c["no_negative_values"]


def test_recent_years_are_as_in_the_file_and_2021_matches_the_figure_a_news_report_quoted() -> None:
    by = {r["year"]: r for r in ays.read_chennai()}
    assert [by[y]["total"] for y in (2022, 2023, 2024, 2025)] == [3453, 3654, 3763, 4104]
    assert by[2021]["total"] == 5035 and by[2021]["killed"] == 999, "DT Next (8 Sep 2022) quoted NCRB 2021 as 5,034 and 998"
    assert SUMMARY["change_in_total_accidents_2022_to_2025_percent"] == 18.9


def test_the_summary_says_what_the_files_cannot() -> None:
    assert "no location" in SUMMARY["scope"] and "which road" in SUMMARY["scope"]
    assert "classification" in SUMMARY["caution"]
