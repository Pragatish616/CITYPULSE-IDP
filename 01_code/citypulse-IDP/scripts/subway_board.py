"""Internal subway board (ADR-031): what volunteers last SAW at each listed subway, and how long ago, from a field-log export.

    python scripts/subway_board.py exports/fieldlog-export-20261016T040000Z.csv --out exports/board.html
    python scripts/subway_board.py EXPORT.csv --now 2026-10-16T09:00:00Z --stale-hours 6   # a fixed time, for a repeatable page

It reads the CSV that `scripts/fieldlog_ops.py export` writes and the committed watchlist, and writes one self-contained HTML page
(no script, no network request) plus a JSON summary next to it. Per subway it shows the newest observation (what was seen, depth if
not passable, time, age), how many observers have logged it, and whether the two newest observers disagree. A subway nobody has
logged says "No observation", which is different from "Could not tell" (someone looked and could not see).

What it is not. It records what people saw and when; it does not tell anyone whether to go, never says a road is safe or passable,
and is for the team (it is not a public or traveller-facing page: showing field data to travellers is a separate decision, ADR-028).
Volunteer codes are never printed; only counts. Observation times are phone clocks (see `lag_seconds` in the export).
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import statistics
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WATCHLIST = ROOT / "data" / "watchlist" / "2026-10-09" / "subways.json"
DISAGREE_WINDOW = timedelta(minutes=30)
SEEN = {"passable": "Seen passable", "not_passable": "Seen not passable", "unknown": "Could not tell"}
DEPTH = {"ankle": "ankle", "knee": "knee", "above_knee": "above the knee", "unknown": "depth not sure"}
QUALITY_TEXT = {
    "osm_named": "position from OpenStreetMap (named)", "osm_road_tunnel": "position: a tunnel on the named road",
    "osm_hint": "position is a hint", "none": "position not known",
}


def parse_time(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)


def human_age(delta: timedelta) -> str:
    s = max(0, int(delta.total_seconds()))
    if s < 90:
        return "just now"
    if s < 5400:
        return f"{round(s / 60)} min ago"
    if s < 172800:
        return f"{s / 3600:.1f} h ago".replace(".0 h", " h")
    return f"{s // 86400} days ago"


def load_entries(csv_path: Path) -> list[dict]:
    rows = []
    with csv_path.open(encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            rows.append({**r, "_t": parse_time(r["observed_at_utc"])})
    return rows


def summarise(entries: list[dict], watchlist: dict, now: datetime, stale_hours: float) -> dict:
    by_site: dict[str, list[dict]] = {}
    for e in entries:
        by_site.setdefault(e["site_id"], []).append(e)
    subways = []
    for w in watchlist["entries"]:
        rows = sorted(by_site.get(w["id"], []), key=lambda r: r["_t"])
        row = {"id": w["id"], "name": w["name"], "list": w["list"], "gcc_no": w["gcc_no"], "zone_ward": w["zone_ward"],
               "position_quality": w["position"]["quality"], "entries": len(rows),
               "observers": len({r["volunteer"] for r in rows}), "latest": None, "age_hours": None, "stale": None,
               "observers_disagree": False}
        if rows:
            last = rows[-1]
            age = now - last["_t"]
            row["latest"] = {"state": last["state"], "depth_band": last["depth_band"] or None,
                             "observed_at_utc": last["_t"].strftime("%Y-%m-%dT%H:%M:%SZ")}
            row["age_hours"] = round(age.total_seconds() / 3600, 2)
            row["stale"] = age > timedelta(hours=stale_hours)
            resolved = [r for r in rows if r["state"] in ("passable", "not_passable")]
            if len(resolved) >= 2:
                a, b = resolved[-1], resolved[-2]
                row["observers_disagree"] = (a["volunteer"] != b["volunteer"] and a["state"] != b["state"]
                                             and a["_t"] - b["_t"] <= DISAGREE_WINDOW)
        subways.append(row)
    lags = [int(e["lag_seconds"]) for e in entries if e.get("lag_seconds", "").lstrip("-").isdigit()]
    covered = [s for s in subways if s["entries"]]
    listed_ids = {w["id"] for w in watchlist["entries"]}
    summary = {
        "generated_at_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "stale_after_hours": stale_hours,
        "entries_in_export": len(entries), "observers_in_export": len({e["volunteer"] for e in entries}),
        "entries_on_listed_subways": sum(1 for e in entries if e["site_id"] in listed_ids),
        "entries_on_other_sites": sum(1 for e in entries if e["site_id"] not in listed_ids),
        "subways_in_list": len(subways), "subways_with_an_observation": len(covered),
        "subways_with_no_observation": len(subways) - len(covered),
        "gcc_road_rail_with_an_observation": sum(1 for s in covered if s["list"] == "gcc_road_rail"),
        "lag_seconds": ({"median": statistics.median(lags), "max": max(lags),
                         "p95": sorted(lags)[min(len(lags) - 1, int(0.95 * len(lags)))]} if lags else None),
    }
    return {"summary": summary, "subways": subways}


def render(board: dict, watchlist: dict) -> str:
    esc = html.escape
    s = board["summary"]
    cards = []
    for sub in board["subways"]:
        latest = sub["latest"]
        if latest is None:
            cls, head, detail = "none", "No observation", "Nobody has logged this subway in the export."
        else:
            when = datetime.fromisoformat(latest["observed_at_utc"].replace("Z", "+00:00"))
            head = SEEN[latest["state"]] + (f" ({DEPTH[latest['depth_band']]})" if latest["depth_band"] else "")
            age = human_age(parse_time(board["summary"]["generated_at_utc"]) - when)
            cls = {"not_passable": "blocked", "passable": "through", "unknown": "unsure"}[latest["state"]]
            detail = f"{age} · {when.astimezone(timezone(timedelta(hours=5, minutes=30))).strftime('%d %b %H:%M')} IST"
            if sub["stale"]:
                cls += " stale"
                detail += f" · older than {s['stale_after_hours']:g} h"
        flags = []
        if sub["observers_disagree"]:
            flags.append("The two newest observers disagree.")
        flags.append(f"{sub['entries']} entr{'y' if sub['entries'] == 1 else 'ies'} · {sub['observers']} observer"
                     f"{'' if sub['observers'] == 1 else 's'}")
        label = {"gcc_road_rail": f"GCC road/rail subway {sub['gcc_no']}", "gcc_pedestrian": f"GCC pedestrian subway {sub['gcc_no']}",
                 "news_only": "named in the news", "osm_only": "named in OpenStreetMap"}[sub["list"]]
        ward = f" · ward {sub['zone_ward']}" if sub["zone_ward"] else ""
        cards.append(
            f'<article class="card {cls}"><h3>{esc(sub["name"])}</h3><p class="meta">{esc(label)}{esc(ward)} · '
            f'{esc(QUALITY_TEXT[sub["position_quality"]])}</p><p class="head">{esc(head)}</p><p class="detail">{esc(detail)}</p>'
            f'<p class="meta">{esc(" · ".join(flags))}</p></article>'
        )
    lag = s["lag_seconds"]
    lag_text = f"median {lag['median']:g} s, 95th percentile {lag['p95']} s, longest {lag['max']} s" if lag else "no entries"
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>CityPulse subway board (internal)</title>
<style>
:root {{ --bg:#fafaf8; --fg:#1d1d1b; --muted:#5d5d58; --card:#fff; --line:#d9d9d2; --blocked:#c1440e; --through:#2f6690; --unsure:#b08900; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#161614; --fg:#ecece6; --muted:#a6a69e; --card:#1f1f1c; --line:#3a3a35; }} }}
body {{ margin:0; padding:16px; background:var(--bg); color:var(--fg); font:16px/1.45 system-ui, sans-serif; }}
main {{ max-width:1100px; margin:0 auto; }} h1 {{ margin:0 0 4px; font-size:1.4rem; }} h3 {{ margin:0 0 2px; font-size:1.05rem; }}
.note {{ color:var(--muted); max-width:70ch; }} .grid {{ display:grid; gap:12px; grid-template-columns:repeat(auto-fill, minmax(280px, 1fr)); margin-top:16px; }}
.card {{ background:var(--card); border:1px solid var(--line); border-left:6px solid var(--line); border-radius:10px; padding:12px; }}
.card p {{ margin:2px 0; }} .meta {{ color:var(--muted); font-size:.85rem; }} .head {{ font-weight:700; }}
.card.blocked {{ border-left-color:var(--blocked); }} .card.through {{ border-left-color:var(--through); }} .card.unsure {{ border-left-color:var(--unsure); }}
.card.stale {{ opacity:.65; }} .card.none {{ border-style:dashed; border-left-style:dashed; }}
.stats {{ display:flex; flex-wrap:wrap; gap:8px 24px; margin:12px 0; }} .stats div {{ min-width:120px; }} .stats b {{ display:block; font-size:1.3rem; }}
</style></head><body><main>
<h1>CityPulse subway board <span class="meta">(internal)</span></h1>
<p class="note">What volunteers last saw at each listed subway, and when, from the field-log export. It records what people saw; it does not tell anyone whether to go, and it is not for travellers. Times are phone clocks. Subways come from the Greater Chennai Corporation's table plus names from news and OpenStreetMap; none is verified on the ground.</p>
<div class="stats">
<div><b>{s['subways_with_an_observation']} of {s['subways_in_list']}</b>subways with an observation</div>
<div><b>{s['gcc_road_rail_with_an_observation']} of 16</b>GCC road/rail subways</div>
<div><b>{s['entries_in_export']}</b>entries</div>
<div><b>{s['observers_in_export']}</b>observers</div>
</div>
<p class="meta">Generated {esc(s['generated_at_utc'])}. Entry delay (phone to server): {esc(lag_text)}. Entries on other sites: {s['entries_on_other_sites']}.
Watchlist date {esc(watchlist['date'])}.</p>
<section class="grid">
{chr(10).join(cards)}
</section></main></body></html>
"""


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("export", type=Path, help="CSV from scripts/fieldlog_ops.py export")
    ap.add_argument("--out", type=Path, default=Path("exports/board.html"))
    ap.add_argument("--now", help="fixed time (UTC, ISO) instead of the clock, for a repeatable page")
    ap.add_argument("--stale-hours", type=float, default=6.0)
    ap.add_argument("--watchlist", type=Path, default=WATCHLIST)
    args = ap.parse_args(argv)
    watchlist = json.loads(args.watchlist.read_text(encoding="utf-8"))
    now = parse_time(args.now) if args.now else datetime.now(timezone.utc)
    board = summarise(load_entries(args.export), watchlist, now, args.stale_hours)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(board, watchlist), encoding="utf-8")
    args.out.with_suffix(".json").write_text(json.dumps(board, indent=1, ensure_ascii=False), encoding="utf-8")
    s = board["summary"]
    print(f"wrote {args.out} and {args.out.with_suffix('.json').name}: {s['subways_with_an_observation']} of {s['subways_in_list']} "
          f"subways have an observation ({s['entries_in_export']} entries, {s['observers_in_export']} observers)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
