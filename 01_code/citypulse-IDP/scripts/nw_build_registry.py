"""Step 1 of the nationwide flood-gating model (ADR-025): districts and district-event pairs from the IFI.

Reads data/india_flood/<date>/raw/India_Flood_Inventory_v3.csv (pinned, never edited) and writes, to
data/nationwide_flood/<date>/:
  districts.csv         one row per district: district_id (state|name), name, state
  district_events.csv   one row per (event, district) with start and end date, 1990-2023 only
  registry_report.json  how many rows and district mentions were kept, dropped, or ambiguous

A district is identified by (state, name). The LGD codes in the IFI cannot be used as keys: the same code
appears under different states (code 350 is "Cuttack" in a Madhya Pradesh row), so they are ignored.
A district named in a multi-state event is assigned to the one listed state whose single-state events also
name it; if that is zero or several states the mention is dropped and counted.

Why 1990: the rainfall source (ERA5 via Open-Meteo) is fetched for 1990-2023, and the IFI is thinner before.
"""

from __future__ import annotations

import csv
import datetime as dt
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATE = "2026-10-04"
FIRST_YEAR, LAST_YEAR = 1990, 2023
STATE_FIX = {"Madras": "Tamil Nadu"}  # the one old-name state value in the file


def split(s: str) -> list[str]:
    return [x.strip() for x in (s or "").split(",") if x.strip()]


def day(s: str) -> dt.date | None:
    try:
        return dt.datetime.strptime((s or "").strip(), "%d-%m-%Y %H:%M").date()
    except ValueError:
        return None


def clean_name(n: str) -> str:
    return " ".join(n.replace(".", " ").split())


def main() -> int:
    raw = ROOT / "data" / "india_flood" / DATE / "raw" / "India_Flood_Inventory_v3.csv"
    out = ROOT / "data" / "nationwide_flood" / DATE
    out.mkdir(parents=True, exist_ok=True)
    rows = list(csv.DictReader(raw.open(encoding="utf-8-sig")))

    # districts seen in single-state events
    state_of: dict[str, set[str]] = defaultdict(set)  # district name -> states
    for r in rows:
        st = [STATE_FIX.get(s, s) for s in split(r["State"])]
        if len(st) == 1:
            for d in split(r["Districts"]):
                state_of[clean_name(d)].add(st[0])

    pairs, report = set(), defaultdict(int)
    for r in rows:
        s = day(r["Start Date"])
        e = day(r["End Date"]) or s
        ds = [clean_name(d) for d in split(r["Districts"])]
        if not s or not ds:
            report["events_without_date_or_districts"] += 1
            continue
        if not (FIRST_YEAR <= s.year <= LAST_YEAR):
            continue
        report["events_in_period"] += 1
        sts = [STATE_FIX.get(x, x) for x in split(r["State"])]
        for d in ds:
            if len(sts) == 1:
                state = sts[0]
            else:
                cands = [x for x in sts if x in state_of.get(d, set())]
                if len(cands) != 1:
                    report["mentions_dropped_ambiguous_or_unknown_in_multi_state_events"] += 1
                    continue
                state = cands[0]
            pairs.add((r["UEI"].strip(), f"{state}|{d}", s.isoformat(), min(e, dt.date(LAST_YEAR, 12, 31)).isoformat()))
    ids = sorted({p[1] for p in pairs})
    with (out / "districts.csv").open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["district_id", "name", "state"])
        for i in ids:
            st, nm = i.split("|", 1)
            w.writerow([i, nm, st])
    with (out / "district_events.csv").open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["event_id", "district_id", "start", "end"])
        w.writerows(sorted(pairs))
    report.update({"districts": len(ids), "district_event_pairs": len(pairs), "states": len({i.split('|')[0] for i in ids})})
    (out / "registry_report.json").write_text(json.dumps(dict(report), indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(dict(report), indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
