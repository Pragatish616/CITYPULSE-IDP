"""Merge field-log exports with phone CSVs, so entries the server lost can be restored (ADR-028, F-37; docs/PILOT_PLAN.md).

On a free host the server's log is lost by a restart, a redeploy and probably by sleeping. Every phone keeps its recent entries and
can save them ("Save my entries (CSV)" on the page). This tool combines:

  * one or more SERVER exports (`scripts/fieldlog_ops.py export`), and
  * PHONE files, each given as `CODE=path` where CODE is that volunteer's pseudonymous code (a phone file does not carry it),

matching entries by `entry_id`. It writes one CSV in the server's column layout plus a `source` column, and a JSON report beside it.

    python scripts/fieldlog_merge.py --server exports/a.csv --server exports/b.csv --phone v01=v01.csv --phone v02=v02.csv --out exports/merged.csv

`source` is `server`, `phone_only_synced` (the phone says the server acknowledged it, but no server export has it: the server lost it),
or `phone_only_queued` (it never reached the server). A phone row whose content differs from the server's row for the same id is a
CONFLICT: both are reported and the server's row is kept in the output. Rejected phone rows and invalid rows are left out and counted.
Nothing is edited or deleted; an existing output file is never overwritten.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

SERVER_COLUMNS = ["protocol", "entry_id", "site_id", "state", "observed_at_utc", "depth_band", "lat", "lon", "volunteer",
                  "received_at_utc", "lag_seconds", "client"]
OUT_COLUMNS = [*SERVER_COLUMNS, "source"]
STATES = {"passable", "not_passable", "unknown"}
DEPTHS = {"", "ankle", "knee", "above_knee", "unknown"}
SITE_ID = re.compile(r"^[a-z0-9][a-z0-9_-]{1,31}$")
CODE = re.compile(r"^[A-Za-z0-9_-]{2,24}$")


def unprotect(v: str) -> str:
    """The phone prefixes a quote to cells that start like a spreadsheet formula (= + - @); remove it again."""
    return v[1:] if len(v) > 1 and v[0] == "'" and v[1] in "=+-@\t\r" else v


def when(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)


def number(v: str) -> float | None:
    return round(float(v), 4) if v not in ("", None) else None


def content(row: dict) -> tuple:
    """What must agree for two rows to be the same entry."""
    return (row["site_id"], row["state"], when(row["observed_at_utc"]), row.get("depth_band") or "",
            number(row.get("lat", "")), number(row.get("lon", "")))


def invalid_reason(row: dict) -> str | None:
    try:
        uuid.UUID(row["entry_id"])
        when(row["observed_at_utc"])
        number(row.get("lat", ""))
        number(row.get("lon", ""))
    except (ValueError, KeyError, TypeError):
        return "unreadable id, time or position"
    if row["state"] not in STATES:
        return "unknown state"
    if (row.get("depth_band") or "") not in DEPTHS:
        return "unknown depth band"
    if row.get("depth_band") and row["state"] != "not_passable":
        return "depth given without not_passable"
    if not SITE_ID.match(row["site_id"]):
        return "bad site id"
    return None


def read_csv(path: Path) -> list[dict]:
    with path.open(encoding="utf-8", newline="") as f:
        return [{k: unprotect(v) if isinstance(v, str) else v for k, v in r.items()} for r in csv.DictReader(f)]


def merge(server_files: list[Path], phone_files: list[tuple[str, Path]]) -> tuple[list[dict], dict]:
    report = {"server_files": [p.name for p in server_files], "phone_files": [f"{c}={p.name}" for c, p in phone_files],
              "server_rows_read": 0, "server_unique": 0, "server_duplicates_identical": 0, "server_conflicts": [],
              "phone": {}, "in_both": 0, "phone_only_synced": 0, "phone_only_queued": 0, "phone_rejected_skipped": 0,
              "phone_invalid_skipped": [], "conflicts": []}
    out: dict[str, dict] = {}
    for path in server_files:
        for r in read_csv(path):
            report["server_rows_read"] += 1
            if r["entry_id"] in out:
                if content(out[r["entry_id"]]) == content(r):
                    report["server_duplicates_identical"] += 1
                else:
                    report["server_conflicts"].append(r["entry_id"])
                continue
            out[r["entry_id"]] = {**{c: r.get(c, "") for c in SERVER_COLUMNS}, "source": "server"}
    report["server_unique"] = len(out)
    server_ids = set(out)
    for code, path in phone_files:
        if not CODE.match(code):
            raise SystemExit(f"volunteer code {code!r}: 2 to 24 characters of letters, digits, _ or -")
        counts = {"rows": 0, "in_both": 0, "restored": 0, "rejected": 0, "invalid": 0}
        for r in read_csv(path):
            counts["rows"] += 1
            if r.get("sync_status") == "rejected":
                counts["rejected"] += 1
                report["phone_rejected_skipped"] += 1
                continue
            why = invalid_reason(r)
            if why:
                counts["invalid"] += 1
                report["phone_invalid_skipped"].append({"phone": code, "entry_id": r.get("entry_id"), "reason": why})
                continue
            eid = r["entry_id"]
            if eid in server_ids:
                if content(out[eid]) == content(r) and out[eid]["volunteer"] == code:
                    counts["in_both"] += 1
                    report["in_both"] += 1
                else:
                    report["conflicts"].append({"entry_id": eid, "phone": code, "note": "content or volunteer differs from the server's row"})
                continue
            if eid in out:  # the same entry on two phone files
                if content(out[eid]) != content(r):
                    report["conflicts"].append({"entry_id": eid, "phone": code, "note": "differs from the same id in another phone file"})
                continue
            synced = r.get("sync_status") == "synced"
            out[eid] = {
                "protocol": "field-log-v1", "entry_id": eid, "site_id": r["site_id"], "state": r["state"],
                "observed_at_utc": when(r["observed_at_utc"]).isoformat(), "depth_band": r.get("depth_band") or "",
                "lat": r.get("lat", ""), "lon": r.get("lon", ""), "volunteer": code, "received_at_utc": "", "lag_seconds": "",
                "client": "phone-csv", "source": "phone_only_synced" if synced else "phone_only_queued",
            }
            counts["restored"] += 1
            report["phone_only_synced" if synced else "phone_only_queued"] += 1
        report["phone"][code] = counts
    rows = sorted(out.values(), key=lambda r: (when(r["observed_at_utc"]), r["entry_id"]))
    report["rows_written"] = len(rows)
    return rows, report


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--server", action="append", default=[], type=Path, help="a server export (repeat for several)")
    ap.add_argument("--phone", action="append", default=[], help="CODE=path of a phone CSV (repeat for several)")
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args(argv)
    if not args.server and not args.phone:
        ap.error("give at least one --server or --phone file")
    if args.out.exists():
        print(f"{args.out} exists; this tool never overwrites. Choose another name.")
        return 2
    phones = []
    for spec in args.phone:
        code, sep, path = spec.partition("=")
        if not sep:
            ap.error(f"--phone needs CODE=path, got {spec!r}")
        phones.append((code, Path(path)))
    rows, report = merge(args.server, phones)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=OUT_COLUMNS, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    report["sha256"] = hashlib.sha256(args.out.read_bytes()).hexdigest()
    args.out.with_suffix(".report.json").write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"wrote {args.out} ({len(rows)} entries): {report['server_unique']} from the server, {report['phone_only_synced']} restored that "
          f"the server lost, {report['phone_only_queued']} that never reached it; in both {report['in_both']}; "
          f"conflicts {len(report['conflicts']) + len(report['server_conflicts'])}; rejected skipped {report['phone_rejected_skipped']}; "
          f"invalid skipped {len(report['phone_invalid_skipped'])}\nsha256 {report['sha256']}")
    return 1 if (report["conflicts"] or report["server_conflicts"]) else 0


if __name__ == "__main__":
    sys.exit(main())
