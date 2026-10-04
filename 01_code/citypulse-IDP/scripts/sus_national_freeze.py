"""Part B (ADR-026): freeze the list of Global Flood Database maps used, before any is joined to features.

Lists the complete maps (no .part files) in data/gfd_india/<date>/raw/ at this moment, with the DFO event id, the year taken from the
file name, the size and the MD5 recorded by the bucket, and writes data/susceptibility/<date>/national_events.json. The list is committed
together with PREREGISTRATION_B.md; maps that arrive later are not used by Part B.
"""

from __future__ import annotations

import datetime as dt
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "gfd_india" / "2026-10-04" / "raw"
OUT = ROOT / "data" / "susceptibility" / "2026-10-04" / "national_events.json"


def main() -> int:
    log = {f["name"]: f for f in json.loads((RAW.parent / "fetch_log.json").read_text(encoding="utf-8"))["files"]}
    events = []
    for p in sorted(RAW.glob("DFO_*.tif"), key=lambda q: (q.stat().st_size, q.name)):
        m = re.match(r"DFO_(\d+)_From_(\d{4})(\d{2})(\d{2})_to_", p.name)
        if not m or p.name not in log or log[p.name]["bytes"] != p.stat().st_size:
            continue
        events.append({"name": p.name, "dfo_id": int(m.group(1)), "year": int(m.group(2)), "bytes": p.stat().st_size, "gcs_md5": log[p.name]["gcs_md5"]})
    OUT.write_text(json.dumps({"frozen_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"), "count": len(events), "events": events}, indent=1), encoding="utf-8")
    print(f"{len(events)} maps frozen, {sum(e['bytes'] for e in events) / 1e6:.0f} MB; years {min(e['year'] for e in events)}-{max(e['year'] for e in events)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
