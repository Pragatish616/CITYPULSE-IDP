"""Operator tools for the field log (ADR-028, docs/FIELD_PROTOCOL.md). Standard library only.

    python scripts/fieldlog_ops.py token alice bob carol          # make volunteer tokens
    python scripts/fieldlog_ops.py status https://SITE            # is it on, how many entries, is the disk durable
    FIELDLOG_ADMIN_TOKEN=... python scripts/fieldlog_ops.py export https://SITE --out exports/

Secrets: `token` prints new random tokens to the terminal once and stores nothing. `export` reads the admin token from the environment
variable FIELDLOG_ADMIN_TOKEN, never from the command line (a command line ends up in shell history and process lists).

Export is checked, not trusted: it asks the server for the entry count before and after, and refuses to call the file good unless the CSV
has exactly that many rows. It prints the SHA-256 of the file, so a copy can be compared later. A row count that changes between the two
asks (someone logged during the download) is reported, and the export is repeated once.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import re
import secrets
import sys
import urllib.error
import urllib.request
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path

CODE = re.compile(r"^[A-Za-z0-9_-]{2,24}$")
Fetch = Callable[[str, dict[str, str]], tuple[int, bytes]]


def http_fetch(url: str, headers: dict[str, str]) -> tuple[int, bytes]:
    req = urllib.request.Request(url, headers={"User-Agent": "citypulse-fieldlog-ops/1.0", **headers})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def make_tokens(codes: list[str]) -> list[tuple[str, str]]:
    bad = [c for c in codes if not CODE.match(c)]
    if bad:
        raise SystemExit(f"volunteer codes must be 2 to 24 characters of letters, digits, _ or -: {bad}")
    if len(set(codes)) != len(codes):
        raise SystemExit("volunteer codes must be different from each other")
    return [(c, secrets.token_urlsafe(24)) for c in codes]


def cmd_token(args: argparse.Namespace) -> int:
    pairs = make_tokens(args.codes)
    print("Give each volunteer ONLY their own line (token). Put the whole line below in the host's environment settings.\n")
    for code, token in pairs:
        print(f"  {code:<24} {token}")
    print("\nFIELDLOG_TOKENS=" + ",".join(f"{c}:{t}" for c, t in pairs))
    print("\nAlso set FIELDLOG_ADMIN_TOKEN to a different long random value (python -c \"import secrets; print(secrets.token_urlsafe(32))\").")
    return 0


def _get_json(fetch: Fetch, url: str, headers: dict[str, str] | None = None) -> tuple[int, dict]:
    status, body = fetch(url, headers or {})
    try:
        return status, json.loads(body)
    except ValueError:
        return status, {}


def cmd_status(args: argparse.Namespace, fetch: Fetch = http_fetch) -> int:
    base = args.url.rstrip("/")
    status, h = _get_json(fetch, f"{base}/fieldlog/health")
    if status != 200 or not h:
        print(f"could not read {base}/fieldlog/health (HTTP {status}). Is this the single-origin address, and is the server up?")
        return 1
    print(f"field logging switched on : {h['enabled']}  ({h['volunteers_configured']} volunteer tokens)")
    if h.get("tokens_refused_as_too_weak_or_malformed"):
        print(f"  WARNING: {h['tokens_refused_as_too_weak_or_malformed']} token entries were refused as too short or malformed")
    print(f"admin token configured    : {h['admin_token_configured']}")
    print(f"sites                     : {h['sites']}")
    print(f"entries stored            : {h['entries']}")
    print(f"log durable               : {h['durable']}")
    if not h["durable"]:
        print("  WARNING: " + h["durability_note"])
    if h.get("corrupt_lines_skipped"):
        print(f"  WARNING: {h['corrupt_lines_skipped']} damaged log lines were skipped at start-up")
    return 0


def cmd_export(args: argparse.Namespace, fetch: Fetch = http_fetch, now: Callable[[], datetime] | None = None) -> int:
    token = os.environ.get("FIELDLOG_ADMIN_TOKEN", "")
    if not token:
        print("set FIELDLOG_ADMIN_TOKEN in the environment first (it is not accepted on the command line).")
        return 2
    base = args.url.rstrip("/")
    headers = {"x-admin-token": token}
    for attempt in (1, 2):
        s1, before = _get_json(fetch, f"{base}/fieldlog/summary", headers)
        if s1 != 200:
            print(f"summary failed: HTTP {s1} (wrong admin token, or reading is switched off on the server)")
            return 1
        status, body = fetch(f"{base}/fieldlog/export.csv", headers)
        if status != 200:
            print(f"export failed: HTTP {status}")
            return 1
        _, after = _get_json(fetch, f"{base}/fieldlog/summary", headers)
        rows = list(csv.reader(io.StringIO(body.decode("utf-8"))))
        data_rows = len(rows) - 1
        if before.get("entries") == after.get("entries") == data_rows:
            break
        print(f"attempt {attempt}: the counts disagree (summary before {before.get('entries')}, file {data_rows}, summary after {after.get('entries')}); "
              + ("trying once more" if attempt == 1 else "giving up, nothing was written"))
        if attempt == 2:
            return 1
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    stamp = (now() if now else datetime.now(timezone.utc)).strftime("%Y%m%dT%H%M%SZ")
    path = out / f"fieldlog-export-{stamp}.csv"
    path.write_bytes(body)
    digest = hashlib.sha256(body).hexdigest()
    print(f"wrote {path}  ({data_rows} entries)\nsha256 {digest}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("token", help="make volunteer tokens")
    t.add_argument("codes", nargs="+", help="a short pseudonym per volunteer, for example v01 v02")
    s = sub.add_parser("status", help="read /fieldlog/health")
    s.add_argument("url", help="the site address, for example https://citypulse-idp.onrender.com/ingest")
    e = sub.add_parser("export", help="download the log as a checked CSV")
    e.add_argument("url", help="the site address including /ingest if there is one")
    e.add_argument("--out", default="exports", help="folder to write into (default ./exports)")
    args = ap.parse_args(argv)
    return {"token": cmd_token, "status": cmd_status, "export": cmd_export}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
