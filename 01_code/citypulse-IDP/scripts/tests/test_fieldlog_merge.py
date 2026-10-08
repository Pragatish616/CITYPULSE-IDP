"""Merging server exports with phone CSVs: entries the server lost come back labelled, conflicts are reported, nothing is overwritten."""

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import fieldlog_merge as fm

S_HEAD = ",".join(fm.SERVER_COLUMNS)
P_HEAD = "entry_id,site_id,site_label,state,observed_at_utc,depth_band,lat,lon,sync_status,synced_at_utc"
A, B, C, D, E = (f"0000000{i}-0000-4000-8000-000000000000" for i in range(1, 6))


def server_csv(tmp_path: Path, name: str, rows: list[str]) -> Path:
    p = tmp_path / name
    p.write_text(S_HEAD + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    return p


def phone_csv(tmp_path: Path, name: str, rows: list[str]) -> Path:
    p = tmp_path / name
    p.write_text(P_HEAD + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    return p


def srow(eid, site="sub-gcc-rr-12", state="passable", t="2026-10-16T08:00:00+00:00", depth="", who="v01", lag="5"):
    return f"field-log-v1,{eid},{site},{state},{t},{depth},,,{who},{t},{lag},web-1"


def prow(eid, site="sub-gcc-rr-12", state="passable", t="2026-10-16T08:00:00.000Z", depth="", status="synced"):
    return f"{eid},{site},label,{state},{t},{depth},,,{status},{t}"


def test_entries_the_server_lost_are_restored_and_labelled(tmp_path) -> None:
    server = server_csv(tmp_path, "s.csv", [srow(A)])
    phone = phone_csv(tmp_path, "p.csv", [prow(A), prow(B, state="not_passable", depth="knee", t="2026-10-16T09:00:00.000Z"),
                                          prow(C, status="queued", t="2026-10-16T10:00:00.000Z")])
    rows, rep = fm.merge([server], [("v01", phone)])
    by = {r["entry_id"]: r for r in rows}
    assert [r["source"] for r in rows] == ["server", "phone_only_synced", "phone_only_queued"]
    assert by[B]["volunteer"] == "v01" and by[B]["depth_band"] == "knee" and by[B]["received_at_utc"] == "" and by[B]["lag_seconds"] == ""
    assert (rep["in_both"], rep["phone_only_synced"], rep["phone_only_queued"]) == (1, 1, 1)
    assert rep["phone"]["v01"] == {"rows": 3, "in_both": 1, "restored": 2, "rejected": 0, "invalid": 0}


def test_a_phone_row_that_disagrees_with_the_server_is_a_conflict_and_the_servers_row_is_kept(tmp_path) -> None:
    server = server_csv(tmp_path, "s.csv", [srow(A, state="passable")])
    phone = phone_csv(tmp_path, "p.csv", [prow(A, state="not_passable", depth="knee")])
    rows, rep = fm.merge([server], [("v01", phone)])
    assert len(rows) == 1 and rows[0]["state"] == "passable" and len(rep["conflicts"]) == 1
    # the same entry attributed to a different volunteer is a conflict too
    rows, rep = fm.merge([server], [("v02", phone_csv(tmp_path, "p2.csv", [prow(A)]))])
    assert len(rep["conflicts"]) == 1


def test_times_in_different_notations_are_the_same_time(tmp_path) -> None:
    server = server_csv(tmp_path, "s.csv", [srow(A, t="2026-10-16T08:00:00.857000+00:00")])
    phone = phone_csv(tmp_path, "p.csv", [prow(A, t="2026-10-16T08:00:00.857Z")])
    assert fm.merge([server], [("v01", phone)])[1]["in_both"] == 1


def test_rejected_and_invalid_phone_rows_are_left_out_and_counted(tmp_path) -> None:
    phone = phone_csv(tmp_path, "p.csv", [
        prow(A, status="rejected"), prow(B, state="wet"), prow("not-a-uuid"), prow(C, site="Bad Site!"),
        prow(D, state="passable", depth="knee"), prow(E),
    ])
    rows, rep = fm.merge([], [("v01", phone)])
    assert [r["entry_id"] for r in rows] == [E]
    assert rep["phone_rejected_skipped"] == 1 and len(rep["phone_invalid_skipped"]) == 4
    assert {x["reason"] for x in rep["phone_invalid_skipped"]} == {"unknown state", "unreadable id, time or position", "bad site id",
                                                                    "depth given without not_passable"}


def test_duplicates_across_server_exports_are_dropped_and_conflicts_reported(tmp_path) -> None:
    s1 = server_csv(tmp_path, "s1.csv", [srow(A), srow(B)])
    s2 = server_csv(tmp_path, "s2.csv", [srow(A), srow(B, state="not_passable", depth="knee")])
    rows, rep = fm.merge([s1, s2], [])
    assert len(rows) == 2 and rep["server_duplicates_identical"] == 1 and rep["server_conflicts"] == [B]


def test_a_formula_prefix_added_by_the_phone_is_removed() -> None:
    assert fm.unprotect("'=SUM(1)") == "=SUM(1)" and fm.unprotect("'knee") == "'knee" and fm.unprotect("knee") == "knee"


def test_the_command_never_overwrites_and_writes_a_checked_report(tmp_path, capsys) -> None:
    server = server_csv(tmp_path, "s.csv", [srow(A)])
    phone = phone_csv(tmp_path, "p.csv", [prow(B)])
    out = tmp_path / "merged.csv"
    assert fm.main(["--server", str(server), "--phone", f"v01={phone}", "--out", str(out)]) == 0
    text = capsys.readouterr().out
    assert "1 restored that the server lost" in text and "sha256" in text
    rows = list(csv.DictReader(out.open(encoding="utf-8")))
    assert list(rows[0].keys()) == fm.OUT_COLUMNS and len(rows) == 2
    report = json.loads(out.with_suffix(".report.json").read_text(encoding="utf-8"))
    assert report["rows_written"] == 2 and len(report["sha256"]) == 64
    assert fm.main(["--server", str(server), "--out", str(out)]) == 2, "an existing file is never overwritten"


def test_a_conflict_makes_the_command_exit_nonzero(tmp_path) -> None:
    server = server_csv(tmp_path, "s.csv", [srow(A, state="passable")])
    phone = phone_csv(tmp_path, "p.csv", [prow(A, state="unknown")])
    assert fm.main(["--server", str(server), "--phone", f"v01={phone}", "--out", str(tmp_path / "m.csv")]) == 1


def test_the_merged_file_can_feed_the_board(tmp_path) -> None:
    import subway_board as board

    server = server_csv(tmp_path, "s.csv", [srow(A, t="2026-10-16T08:00:00+00:00")])
    phone = phone_csv(tmp_path, "p.csv", [prow(B, site="sub-gcc-rr-04", t="2026-10-16T08:30:00.000Z")])
    out = tmp_path / "m.csv"
    fm.main(["--server", str(server), "--phone", f"v02={phone}", "--out", str(out)])
    watch = json.loads(board.WATCHLIST.read_text(encoding="utf-8"))
    from datetime import datetime, timezone

    b = board.summarise(board.load_entries(out), watch, datetime(2026, 10, 16, 9, tzinfo=timezone.utc), 6.0)
    assert b["summary"]["subways_with_an_observation"] == 2 and b["summary"]["lag_seconds"]["median"] == 5
