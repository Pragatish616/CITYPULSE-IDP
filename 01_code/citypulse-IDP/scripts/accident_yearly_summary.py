"""Check and summarise the Greater Chennai Police yearly crash totals (docs/field/ACCIDENT_DATA.md).

Reads the two files downloaded on 11 October 2026 from OpenCity (public domain) into data/accidents/chennai-2026-10-11/raw/ and
writes data/accidents/chennai-2026-10-11/summary.json: the checks that passed or failed and the recent years as they appear in
the file. Yearly totals only: no location, no date within a year. It says nothing about which road.

    python scripts/accident_yearly_summary.py
"""

from __future__ import annotations

import csv
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "data" / "accidents" / "chennai-2026-10-11"
CHENNAI = DIR / "raw" / "chennai-road-crashes-1998-2025.csv"
TN = DIR / "raw" / "tn-road-crashes-1993-2025.csv"
COLS = {
    "year": "YEAR",
    "fatal": "Fatal Accidents",
    "killed": "Fatal Killed",
    "grievous": "Grievous Injury - Accidents",
    "grievous_injured": "Grievous Injurty - Injured",  # sic: the file's own spelling
    "minor": "Minor Injury - Accidents",
    "minor_injured": "Minor Injury - Injured",
    "non_injury": "Non Injury",
    "total": "Total Accidents",
    "persons": "Total number of persons involved",
}


def lf(path: Path) -> bytes:
    """The file with Unix line endings: the same on every machine (Git stores it that way; the download had CRLF)."""
    return path.read_bytes().replace(b"\r\n", b"\n")


def read_chennai(path: Path = CHENNAI) -> list[dict[str, int]]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        rows = [{k: int(r[v]) for k, v in COLS.items()} for r in csv.DictReader(f)]
    return rows


def checks(rows: list[dict[str, int]]) -> dict:
    years = [r["year"] for r in rows]
    parts_ok = [r["year"] for r in rows if r["fatal"] + r["grievous"] + r["minor"] + r["non_injury"] == r["total"]]
    parts_bad = [r["year"] for r in rows if r["year"] not in parts_ok]
    return {
        "years": [years[0], years[-1]],
        "rows": len(rows),
        "years_consecutive": years == list(range(years[0], years[-1] + 1)),
        "years_where_the_four_severity_counts_add_up_to_the_total": len(parts_ok),
        "years_where_they_do_not": parts_bad,
        "killed_at_least_fatal_accidents_every_year": all(r["killed"] >= r["fatal"] for r in rows),
        "no_negative_values": all(v >= 0 for r in rows for v in r.values()),
    }


def main() -> int:
    rows = read_chennai()
    c = checks(rows)
    by_year = {r["year"]: r for r in rows}
    recent = {y: {k: by_year[y][k] for k in ("total", "fatal", "killed", "persons")} for y in range(2021, 2026) if y in by_year}
    # Severity classes: the grievous / minor split swings between years (for example grievous 87 in 1999, 1,832 in 1998, 2,949 in
    # 2015 with minor falling by about as much), which looks like a change in how injuries were classified, so the split is not
    # compared across years here. Totals are used.
    summary = {
        "task": "check and summarise the Greater Chennai Police yearly crash totals",
        "run_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "https://data.opencity.in/dataset/chennai-road-crashes-data (publisher: Greater Chennai Police; source given as tnsta.gov.in; licence: Other (Public Domain))",
        "files": {p.name: {"bytes_lf": len(lf(p)), "sha256_lf": hashlib.sha256(lf(p)).hexdigest()} for p in (CHENNAI, TN)},
        "scope": "yearly totals for the city; no location, no date within a year; says nothing about which road",
        "checks": c,
        "recent_years_as_in_the_file": recent,
        "change_in_total_accidents_2022_to_2025_percent": round(100 * (by_year[2025]["total"] - by_year[2022]["total"]) / by_year[2022]["total"], 1),
        "caution": "The grievous-injury and minor-injury columns swing by thousands between some neighbouring years (1998-1999, 2014-2017, 2024-2025), "
                   "which looks like a change in classification; compare totals, not the severity split.",
    }
    (DIR / "summary.json").write_text(json.dumps(summary, indent=1, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({k: summary[k] for k in ("checks", "recent_years_as_in_the_file", "change_in_total_accidents_2022_to_2025_percent")}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
