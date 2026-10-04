"""Fetch the Global Flood Database maps for the India events in our Dartmouth list (ADR-026).

The database (Tellman et al. 2021, Cloud to Street / Dartmouth Flood Observatory) is a public Google Cloud Storage bucket,
gs://gfd_v3, one GeoTIFF per mapped flood event named DFO_<event id>_From_<date>_to_<date>.tif at 250 m with bands
flooded, duration, clear_views, clear_perc, jrc_perm_water. Events are chosen by matching the DFO event ids in
data/india_flood/<date>/raw/dfo_india_events.geojson (the 296 India events of ADR-023). Files are fetched SMALLEST FIRST
(this network reaches the bucket at only about 40 KB/s, so all 2 GB would take most of a day) and saved to
data/gfd_india/<date>/raw/ (git-ignored) through a temporary name so a partial file is never mistaken for a map. A file that exists
with the right size is not refetched. fetch_log.json (rewritten after every file) lists what has arrived, with Google's own MD5.
LICENCE: the database is CC BY-NC-ND 4.0 (HydroShare record); use is research-only, and the maps and anything that reproduces
them are never redistributed from this repository.
"""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
DATE = "2026-10-04"
BUCKET = "gfd_v3"


def listing() -> list[dict]:
    items, tok = [], None
    while True:
        u = f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o?maxResults=1000&fields=items(name,size,md5Hash),nextPageToken"
        if tok:
            u += "&pageToken=" + urllib.parse.quote(tok)
        j = json.load(urllib.request.urlopen(u, timeout=60))
        items += j.get("items", [])
        tok = j.get("nextPageToken")
        if not tok:
            return items


def main() -> int:
    ids = {int(f["properties"]["ID"]) for f in json.loads(
        (ROOT / "data/india_flood" / DATE / "raw/dfo_india_events.geojson").read_text(encoding="utf-8"))["features"]}
    chosen = [i for i in listing() if (m := re.match(r"DFO_(\d+)_", i["name"])) and int(m.group(1)) in ids]
    out = ROOT / "data" / "gfd_india" / DATE
    (out / "raw").mkdir(parents=True, exist_ok=True)
    log = {"bucket": BUCKET, "files": []}
    total = 0
    for k, it in enumerate(sorted(chosen, key=lambda x: (int(x["size"]), x["name"]))):
        dest = out / "raw" / it["name"]
        part = dest.with_suffix(".part")
        if not dest.exists() or dest.stat().st_size != int(it["size"]):
            for attempt in range(1, 7):
                try:
                    with requests.get(f"https://storage.googleapis.com/{BUCKET}/{urllib.parse.quote(it['name'])}", stream=True, timeout=180) as r:
                        r.raise_for_status()
                        with part.open("wb") as fh:
                            for chunk in r.iter_content(1 << 20):
                                fh.write(chunk)
                    part.replace(dest)
                    break
                except requests.RequestException as e:
                    print(f"  {it['name']}: {type(e).__name__}; retry {attempt}", file=sys.stderr, flush=True)
                    time.sleep(min(60, 5 * attempt))
            else:
                raise RuntimeError(f"could not fetch {it['name']}")
        log["files"].append({"name": it["name"], "bytes": int(it["size"]), "gcs_md5": it.get("md5Hash")})
        total += int(it["size"])
        log["count"], log["bytes"] = len(log["files"]), total
        (out / "fetch_log.json").write_text(json.dumps(log, indent=1, sort_keys=True), encoding="utf-8")
        if (k + 1) % 5 == 0:
            print(f"{k + 1}/{len(chosen)} files, {total / 1e6:.0f} MB", file=sys.stderr, flush=True)
    log["count"], log["bytes"] = len(chosen), total
    (out / "fetch_log.json").write_text(json.dumps(log, indent=1, sort_keys=True), encoding="utf-8")
    print(f"{len(chosen)} files, {total / 1e6:.0f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
