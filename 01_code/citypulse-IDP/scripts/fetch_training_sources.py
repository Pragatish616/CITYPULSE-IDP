"""Fetch the training-data sources approved on 2026-10-04 (data/DATA_SOURCES_ASSESSMENT.md).

  cfm       Chennai Flood Monitor (CFM-DSS) archive: three Hugging Face datasets, pinned by revision
  floodnet  NYC FloodNet street-flooding events from NYC Open Data (method sandbox, not Chennai data)

Raw files are written once to data/<source>/<date>/raw/ with their SHA-256 in a fetch_log.json. They are
never edited afterwards. The CFM archive states no licence, so it stays out of git (see .gitignore).

Usage: python scripts/fetch_training_sources.py cfm|floodnet [--date YYYY-MM-DD]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
HF = "https://huggingface.co"
CFM_DATASETS = [
    "CashlessConsumer/chennai-flood-monitor-transactions",
    "CashlessConsumer/chennaidss-gis-layers",
    "CashlessConsumer/chennai-flood-history",
]
FLOODNET_URL = "https://data.cityofnewyork.us/resource/aq7i-eu5q.csv"


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def get(url: str, dest: Path, tries: int = 5, **kw) -> int:
    """Download to [dest], retrying a dropped connection with growing waits."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(1, tries + 1):
        try:
            with requests.get(url, stream=True, timeout=120, **kw) as r:
                r.raise_for_status()
                with dest.open("wb") as fh:
                    for chunk in r.iter_content(1 << 20):
                        fh.write(chunk)
            return dest.stat().st_size
        except requests.RequestException as e:
            if attempt == tries:
                raise
            wait = 2**attempt
            print(f"  retry {attempt}/{tries - 1} after {type(e).__name__}; waiting {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise AssertionError("unreachable")


def fetch_cfm(base: Path) -> dict:
    log = {"source": "Chennai Flood Monitor archive via Hugging Face", "datasets": {}}
    for name in CFM_DATASETS:
        meta = requests.get(f"{HF}/api/datasets/{name}", timeout=60).json()
        rev = meta["sha"]
        files = []
        for s in meta["siblings"]:
            path = s["rfilename"]
            if path in (".gitattributes",):
                continue
            dest = base / "raw" / name.split("/")[1] / path
            n = get(f"{HF}/datasets/{name}/resolve/{rev}/{path}", dest)
            files.append({"path": path, "bytes": n, "sha256": sha256(dest)})
            time.sleep(0.2)  # be polite to the host
        log["datasets"][name] = {"revision": rev, "license_tag": [t for t in meta.get("tags", []) if t.startswith("license")], "files": files}
        print(f"{name}: {len(files)} files, {sum(f['bytes'] for f in files)/1e6:.1f} MB (revision {rev[:10]})")
    return log


def fetch_floodnet(base: Path) -> dict:
    dest = base / "raw" / "floodnet_flood_events.csv"
    n = get(FLOODNET_URL, dest, params={"$limit": 50000})
    rows = sum(1 for _ in dest.open(encoding="utf-8")) - 1
    print(f"floodnet: {n/1e6:.1f} MB, about {rows} lines")
    return {
        "source": "NYC Open Data, FloodNet: Street Flooding Events Measured by FloodNet Sensors (aq7i-eu5q)",
        "url": FLOODNET_URL,
        "files": [{"path": "raw/floodnet_flood_events.csv", "bytes": n, "sha256": sha256(dest)}],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", choices=["cfm", "floodnet"])
    ap.add_argument("--date", default="2026-10-04")
    a = ap.parse_args()
    folder = {"cfm": "chennai_cfm", "floodnet": "nyc_floodnet"}[a.source]
    base = ROOT / "data" / folder / a.date
    if (base / "fetch_log.json").exists():
        print("already fetched; raw files are never refetched or edited", file=sys.stderr)
        return 1
    log = fetch_cfm(base) if a.source == "cfm" else fetch_floodnet(base)
    log["fetched_on"] = a.date
    log["script"] = "scripts/fetch_training_sources.py"
    (base / "fetch_log.json").write_text(json.dumps(log, indent=2, sort_keys=True), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
