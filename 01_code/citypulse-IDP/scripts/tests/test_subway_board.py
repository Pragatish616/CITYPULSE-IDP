"""The internal subway board: newest observation and its age per subway, "No observation" kept apart from "Could not tell", no
safety words, no volunteer codes, no external requests. No network."""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import subway_board as board

NOW = datetime(2026, 10, 16, 9, 0, tzinfo=timezone.utc)
WATCH = json.loads(board.WATCHLIST.read_text(encoding="utf-8"))
HEADER = "protocol,entry_id,site_id,state,observed_at_utc,depth_band,lat,lon,volunteer,received_at_utc,lag_seconds,client\n"


def csv_text(rows: list[tuple]) -> str:
    out = HEADER
    for i, (site, state, when, depth, who, lag) in enumerate(rows):
        out += f"field-log-v1,{i:08d}-0000-4000-8000-000000000000,{site},{state},{when},{depth},,,{who},{when},{lag},web-1\n"
    return out


def run(tmp_path: Path, rows: list[tuple], **kw):
    p = tmp_path / "export.csv"
    p.write_text(csv_text(rows), encoding="utf-8")
    entries = board.load_entries(p)
    return board.summarise(entries, WATCH, NOW, kw.get("stale_hours", 6.0))


def by_id(b: dict) -> dict:
    return {s["id"]: s for s in b["subways"]}


def test_newest_observation_and_its_age_per_subway(tmp_path) -> None:
    b = run(tmp_path, [
        ("sub-gcc-rr-12", "not_passable", "2026-10-16T05:00:00+00:00", "knee", "v01", 40),
        ("sub-gcc-rr-12", "passable", "2026-10-16T08:20:00+00:00", "", "v02", 30),
        ("sub-gcc-rr-04", "unknown", "2026-10-16T08:50:00+00:00", "", "v01", 10),
    ])
    m = by_id(b)["sub-gcc-rr-12"]
    assert m["latest"]["state"] == "passable" and m["entries"] == 2 and m["observers"] == 2 and m["age_hours"] == 0.67
    assert m["stale"] is False
    assert by_id(b)["sub-gcc-rr-04"]["latest"]["state"] == "unknown"


def test_no_observation_is_not_the_same_as_could_not_tell(tmp_path) -> None:
    b = run(tmp_path, [("sub-gcc-rr-04", "unknown", "2026-10-16T08:50:00+00:00", "", "v01", 10)])
    assert by_id(b)["sub-gcc-rr-09"]["latest"] is None and by_id(b)["sub-gcc-rr-09"]["entries"] == 0
    page = board.render(b, WATCH)
    assert "No observation" in page and "Could not tell" in page
    assert b["summary"]["subways_with_no_observation"] == 30 and b["summary"]["subways_with_an_observation"] == 1


def test_old_observations_are_marked_stale_but_still_shown(tmp_path) -> None:
    b = run(tmp_path, [("sub-gcc-rr-12", "not_passable", "2026-10-16T01:00:00+00:00", "ankle", "v01", 5)])
    m = by_id(b)["sub-gcc-rr-12"]
    assert m["stale"] is True and m["latest"]["depth_band"] == "ankle"
    assert "older than 6 h" in board.render(b, WATCH)


def test_two_observers_who_disagree_within_half_an_hour_are_flagged(tmp_path) -> None:
    b = run(tmp_path, [
        ("sub-gcc-rr-12", "passable", "2026-10-16T08:00:00+00:00", "", "v01", 5),
        ("sub-gcc-rr-12", "not_passable", "2026-10-16T08:20:00+00:00", "knee", "v02", 5),
        ("sub-gcc-rr-04", "passable", "2026-10-16T08:00:00+00:00", "", "v01", 5),
        ("sub-gcc-rr-04", "not_passable", "2026-10-16T08:20:00+00:00", "knee", "v01", 5),  # same person changing their mind
        ("sub-gcc-rr-09", "passable", "2026-10-16T06:00:00+00:00", "", "v01", 5),
        ("sub-gcc-rr-09", "not_passable", "2026-10-16T08:20:00+00:00", "knee", "v02", 5),  # hours apart
    ])
    m = by_id(b)
    assert m["sub-gcc-rr-12"]["observers_disagree"] is True
    assert m["sub-gcc-rr-04"]["observers_disagree"] is False and m["sub-gcc-rr-09"]["observers_disagree"] is False


def test_other_sites_are_counted_but_not_shown_as_subways(tmp_path) -> None:
    b = run(tmp_path, [("tw1-0004", "not_passable", "2026-10-16T08:00:00+00:00", "knee", "v01", 5),
                       ("adhoc", "passable", "2026-10-16T08:00:00+00:00", "", "v01", 5)])
    assert b["summary"]["entries_on_other_sites"] == 2 and b["summary"]["subways_with_an_observation"] == 0


def test_the_page_has_no_safety_words_no_volunteer_codes_and_no_external_requests(tmp_path) -> None:
    b = run(tmp_path, [
        ("sub-gcc-rr-12", "not_passable", "2026-10-16T08:00:00+00:00", "knee", "SECRETCODE", 5),
        ("sub-gcc-rr-04", "passable", "2026-10-16T08:30:00+00:00", "", "SECRETCODE", 5),
    ])
    page = board.render(b, WATCH)
    text = re.sub(r"<style>.*?</style>", "", page, flags=re.DOTALL)
    assert not re.search(r"\b(safe|safely|dry|clear|cleared|open|fine|go ahead|all clear|good to go|risk-free)\b", text, re.IGNORECASE)
    assert "SECRETCODE" not in page
    assert not re.search(r"<script|src=|href=|https?://", page)
    assert "not for travellers" in page and "none is verified on the ground" in page


def test_names_with_markup_are_escaped(tmp_path) -> None:
    watch = json.loads(json.dumps(WATCH))
    watch["entries"][0]["name"] = "<b>x</b> & y"
    p = tmp_path / "e.csv"
    p.write_text(csv_text([]), encoding="utf-8")
    page = board.render(board.summarise(board.load_entries(p), watch, NOW, 6.0), watch)
    assert "&lt;b&gt;x&lt;/b&gt; &amp; y" in page and "<b>x</b>" not in page


def test_the_command_writes_a_page_and_a_summary(tmp_path, capsys) -> None:
    p = tmp_path / "e.csv"
    p.write_text(csv_text([("sub-gcc-rr-12", "passable", "2026-10-16T08:00:00+00:00", "", "v01", 7)]), encoding="utf-8")
    out = tmp_path / "board.html"
    assert board.main([str(p), "--out", str(out), "--now", "2026-10-16T09:00:00Z"]) == 0
    assert out.exists() and out.with_suffix(".json").exists()
    summary = json.loads(out.with_suffix(".json").read_text(encoding="utf-8"))["summary"]
    assert summary["entries_in_export"] == 1 and summary["lag_seconds"]["median"] == 7
    assert "1 of 31 subways have an observation" in capsys.readouterr().out


def test_human_ages() -> None:
    from datetime import timedelta

    assert board.human_age(timedelta(seconds=30)) == "just now"
    assert board.human_age(timedelta(minutes=40)) == "40 min ago"
    assert board.human_age(timedelta(hours=3)) == "3 h ago"
    assert board.human_age(timedelta(hours=5, minutes=30)) == "5.5 h ago"
    assert board.human_age(timedelta(days=4)) == "4 days ago"
