"""Operator tools for the field log: tokens are strong and distinct, status is honest, export is checked and keeps the admin token off the command line."""

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fieldlog_ops as ops

HEADER = "protocol,entry_id,site_id,state,observed_at_utc,depth_band,lat,lon,volunteer,received_at_utc,lag_seconds,client\n"
ROW = "field-log-v1,{i},tw1-0001,passable,2026-10-05T18:00:00+00:00,,,,alice,2026-10-05T18:01:00+00:00,60,web-1\n"


def server(entries_over_time, csv_rows=None):
    """A fake server. `entries_over_time` is the count the summary reports on each call; the CSV has `csv_rows` data rows (default: the first count)."""
    counts = iter(entries_over_time)
    last = {"n": entries_over_time[0]}

    def fetch(url, headers):
        if url.endswith("/fieldlog/health"):
            return 200, json.dumps({"enabled": True, "volunteers_configured": 2, "tokens_refused_as_too_weak_or_malformed": 0,
                                    "admin_token_configured": True, "sites": 433, "subway_sites": 31, "entries": last["n"], "corrupt_lines_skipped": 0,
                                    "durable": False, "durability_note": "NOT known to be persistent"}).encode()
        if headers.get("x-admin-token") != "admin-secret-0123456789":
            return 401, b"{}"
        if url.endswith("/fieldlog/summary"):
            last["n"] = next(counts, last["n"])
            return 200, json.dumps({"entries": last["n"]}).encode()
        if url.endswith("/fieldlog/export.csv"):
            n = entries_over_time[0] if csv_rows is None else csv_rows
            return 200, (HEADER + "".join(ROW.format(i=i) for i in range(n))).encode()
        return 404, b"{}"

    return fetch


def test_tokens_are_long_random_distinct_and_valid_for_the_server() -> None:
    pairs = ops.make_tokens(["alice", "bob", "v03"])
    tokens = [t for _, t in pairs]
    assert len(set(tokens)) == 3 and all(len(t) >= 30 for t in tokens)
    # the server refuses tokens shorter than 16 characters and codes outside [A-Za-z0-9_-]{2,24}
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "server"))
    from app.fieldlog.service import TokenBook

    book = TokenBook(",".join(f"{c}:{t}" for c, t in pairs))
    assert len(book) == 3 and book.refused == 0
    assert [book.identify(t) for t in tokens] == ["alice", "bob", "v03"]


@pytest.mark.parametrize("codes", [["a"], ["has space"], ["x" * 25], ["ok", "ok"], ["bad!"]])
def test_bad_or_repeated_codes_are_refused(codes) -> None:
    with pytest.raises(SystemExit):
        ops.make_tokens(codes)


def test_token_command_prints_each_line_once_and_stores_nothing(capsys, tmp_path, monkeypatch) -> None:
    monkeypatch.chdir(tmp_path)
    assert ops.main(["token", "alice", "bob"]) == 0
    out = capsys.readouterr().out
    assert out.count("FIELDLOG_TOKENS=") == 1 and "alice:" in out and "bob:" in out
    assert list(tmp_path.iterdir()) == [], "no file is written"


def test_status_prints_the_facts_and_warns_when_the_disk_is_not_durable(capsys) -> None:
    code = ops.cmd_status(argparse.Namespace(url="https://x/ingest"), fetch=server([3]))
    out = capsys.readouterr().out
    assert code == 0 and "entries stored            : 3" in out and "sites                     : 433 (31 subways)" in out
    assert "WARNING" in out and "NOT known to be persistent" in out


def test_status_fails_clearly_when_the_server_cannot_be_read(capsys) -> None:
    assert ops.cmd_status(argparse.Namespace(url="https://x"), fetch=lambda u, h: (502, b"")) == 1
    assert "could not read" in capsys.readouterr().out


def test_export_needs_the_admin_token_in_the_environment_not_on_the_command_line(capsys, monkeypatch, tmp_path) -> None:
    monkeypatch.delenv("FIELDLOG_ADMIN_TOKEN", raising=False)
    assert ops.cmd_export(argparse.Namespace(url="https://x", out=str(tmp_path)), fetch=server([2])) == 2
    assert "not accepted on the command line" in capsys.readouterr().out
    with pytest.raises(SystemExit):
        ops.main(["export", "https://x", "--admin-token", "secret"])  # no such option


def test_a_good_export_is_written_with_a_checksum(capsys, monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("FIELDLOG_ADMIN_TOKEN", "admin-secret-0123456789")
    fixed = datetime(2026, 10, 6, 1, 2, 3, tzinfo=timezone.utc)
    code = ops.cmd_export(argparse.Namespace(url="https://x/ingest", out=str(tmp_path / "ex")), fetch=server([2, 2]), now=lambda: fixed)
    assert code == 0
    (path,) = list((tmp_path / "ex").glob("*.csv"))
    assert path.name == "fieldlog-export-20261006T010203Z.csv"
    out = capsys.readouterr().out
    assert "(2 entries)" in out and hashlib.sha256(path.read_bytes()).hexdigest() in out


def test_a_wrong_admin_token_writes_nothing(monkeypatch, tmp_path, capsys) -> None:
    monkeypatch.setenv("FIELDLOG_ADMIN_TOKEN", "wrong-admin-0123456789")
    assert ops.cmd_export(argparse.Namespace(url="https://x", out=str(tmp_path)), fetch=server([2])) == 1
    assert list(tmp_path.glob("*.csv")) == []


def test_a_file_that_does_not_match_the_summary_is_not_written(monkeypatch, tmp_path, capsys) -> None:
    monkeypatch.setenv("FIELDLOG_ADMIN_TOKEN", "admin-secret-0123456789")
    # the summary says 3 but the CSV only has 2 rows, both times
    code = ops.cmd_export(argparse.Namespace(url="https://x", out=str(tmp_path)), fetch=server([3, 3, 3, 3], csv_rows=2))
    assert code == 1 and list(tmp_path.glob("*.csv")) == []
    assert "giving up, nothing was written" in capsys.readouterr().out


def test_an_entry_arriving_during_the_download_triggers_one_retry(monkeypatch, tmp_path, capsys) -> None:
    monkeypatch.setenv("FIELDLOG_ADMIN_TOKEN", "admin-secret-0123456789")
    # first pass: 2 before, 3 after (someone logged during the download); second pass: stable at 3
    calls = {"n": 0}
    base = server([2, 3, 3, 3], csv_rows=3)
    code = ops.cmd_export(argparse.Namespace(url="https://x", out=str(tmp_path)), fetch=lambda u, h: (calls.__setitem__("n", calls["n"] + 1), base(u, h))[1])
    out = capsys.readouterr().out
    assert code == 0 and "trying once more" in out and len(list(tmp_path.glob("*.csv"))) == 1
