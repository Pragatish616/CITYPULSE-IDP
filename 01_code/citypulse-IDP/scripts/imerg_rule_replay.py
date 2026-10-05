"""Replay the ADR-027 event-state rule over satellite rain for fixed past windows (the validation that ADR-027 committed to).

The windows, the times of day and the rule's numbers are the ones written in docs/DECISIONS.md ADR-027 on 5 October 2026, before this
script was run. Nothing here is tuned: a miss or a false alarm is reported as it is.

For each window and each of 00, 06, 12 and 18 UTC it reads the six NASA IMERG half-hour images ending at that time (the server's
three-hour window), computes the same two numbers the live service uses, and applies the rule WITHOUT holds. A rule with holds can
only raise the state above this, so "the instantaneous level reached watch or active at least once" is a necessary condition for the
live rule to leave `dry` in that window.

Run from 01_code/citypulse-IDP:  python scripts/imerg_rule_replay.py
Writes data/results/2026-10-05-imerg-event-rule-replay/result.json. Read-only against NASA GIBS; about 360 image requests, 3 at a time.
"""

from __future__ import annotations

import asyncio
import json
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from app.ingest import imerg  # noqa: E402

# Fixed in ADR-027 before the run. (label, kind, first day, last day)
WINDOWS = [
    ("2015-12 (the project's replay flood; 2 Dec 2015 is the proxy day)", "flood", "2015-12-01", "2015-12-03"),
    ("2023-12 Michaung (NOT independent: its values were seen before the rule was fixed)", "flood", "2023-12-03", "2023-12-05"),
    ("2025-11 north-east monsoon event", "flood", "2025-11-29", "2025-12-01"),
    ("2024-03 dry control", "control", "2024-03-05", "2024-03-07"),
    ("2025-04 dry control", "control", "2025-04-10", "2025-04-12"),
]
HOURS = (0, 6, 12, 18)
# The rule's numbers, copied from the ADR-027 table. The Dart service holds its own copy (services/router_api/lib/src/event_state.dart,
# class EventRule) and its tests pin the same values; if either changes, change both and write a new ADR.
ACTIVE_ACC, ACTIVE_PEAK, WATCH_ACC, WATCH_PEAK = 15.0, 25.0, 8.0, 7.6


def level(acc: float, peak: float) -> str:
    if acc >= ACTIVE_ACC or peak >= ACTIVE_PEAK:
        return "active"
    if acc >= WATCH_ACC or peak >= WATCH_PEAK:
        return "watch"
    return "dry"


async def one_time(client, legend, when, gate):
    times = [when - timedelta(minutes=30 * i) for i in range(imerg.ACCUMULATION_SLICES)]

    async def img(t):
        async with gate:
            for attempt in range(3):
                try:
                    return imerg.decode_slice(await imerg.fetch_slice_png(client, t), legend, t)
                except Exception:  # noqa: BLE001
                    await asyncio.sleep(1.5 * (attempt + 1))
            return None

    slices = await asyncio.gather(*(img(t) for t in times))
    ok = [s for s in slices if s is not None]
    if not ok:
        return {"time": when.isoformat(), "error": "no image could be read"}
    acc = sum(s.mean_mm_h for s in ok) * (imerg.SLICE_MINUTES / 60.0)
    peak = max(s.peak_mm_h for s in ok)
    return {
        "time": when.strftime("%Y-%m-%dT%H:%MZ"),
        "area_mean_accumulation_3h_mm": round(acc, 2),
        "peak_cell_rate_mm_h": round(peak, 2),
        "images_read": len(ok),
        "images_missing": len(slices) - len(ok),
        "unmatched_pixels": sum(s.unmatched_pixels for s in ok),
        "level": level(acc, peak),
    }


async def main() -> int:
    gate = asyncio.Semaphore(3)
    out_windows = []
    async with httpx.AsyncClient(timeout=imerg.HTTP_TIMEOUT, headers={"User-Agent": imerg.USER_AGENT}, follow_redirects=True) as client:
        legend = await imerg.fetch_colormap(client)
        for label, kind, first, last in WINDOWS:
            d0 = datetime.fromisoformat(first).replace(tzinfo=timezone.utc)
            d1 = datetime.fromisoformat(last).replace(tzinfo=timezone.utc)
            points = []
            day = d0
            while day <= d1:
                for h in HOURS:
                    points.append(await one_time(client, legend, day + timedelta(hours=h), gate))
                day += timedelta(days=1)
            levels = [p["level"] for p in points if "level" in p]
            order = {"dry": 0, "watch": 1, "active": 2}
            top = max(levels, key=order.get) if levels else None
            out_windows.append({
                "label": label, "kind": kind, "first_day": first, "last_day": last, "points": points,
                "highest_instantaneous_level": top,
                "times_at_watch_or_higher": sum(1 for lv in levels if lv != "dry"),
                "times_total": len(points),
                "expected": "watch or active at least once" if kind == "flood" else "dry at every time",
                "as_expected": (top in ("watch", "active")) if kind == "flood" else (top == "dry"),
            })
            print(f"{label}: highest {top}, {out_windows[-1]['times_at_watch_or_higher']}/{len(points)} times at watch or higher -> "
                  f"{'as expected' if out_windows[-1]['as_expected'] else 'NOT as expected'}", flush=True)
    adr_commit = subprocess.run(["git", "log", "--format=%H", "-1", "--", "docs/DECISIONS.md"], capture_output=True, text=True, cwd=ROOT).stdout.strip()
    result = {
        "task": "ADR-027 validation: the event-state rule replayed over NASA IMERG for fixed past windows",
        "run_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "rule": {"active": f"A>={ACTIVE_ACC} mm or P>={ACTIVE_PEAK} mm/h", "watch": f"A>={WATCH_ACC} mm or P>={WATCH_PEAK} mm/h",
                 "holds_applied": False, "note": "no holds: a necessary condition for the live rule to leave dry"},
        "decision_record_commit": adr_commit,
        "data": {"layer": imerg.LAYER, "bbox": imerg.CHENNAI_BBOX, "resolution_km": 10, "source": imerg.CREDIT},
        "windows": out_windows,
        "summary": {"flood_windows_as_expected": sum(1 for w in out_windows if w["kind"] == "flood" and w["as_expected"]),
                    "flood_windows": sum(1 for w in out_windows if w["kind"] == "flood"),
                    "control_windows_as_expected": sum(1 for w in out_windows if w["kind"] == "control" and w["as_expected"]),
                    "control_windows": sum(1 for w in out_windows if w["kind"] == "control")},
    }
    out = ROOT / "data" / "results" / "2026-10-05-imerg-event-rule-replay"
    out.mkdir(parents=True, exist_ok=True)
    (out / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("wrote", out / "result.json")
    print(json.dumps(result["summary"]))
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
