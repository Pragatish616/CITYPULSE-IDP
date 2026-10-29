"""Build the prototype Chennai Street Flood Evidence dataset (CSFE v0.2) from sources already on this machine.

Run from 01_code/citypulse-IDP:  python scripts/build_csfe_proto.py
Writes data/csfe/2026-10-30/ (v0.2; the v0 build of 2026-10-29 is kept). The tables mix in CFM-DSS data whose publisher states no licence (MANIFEST.md), so the generated tables
are git-ignored like data/chennai_cfm/*/raw; only summary.json, README.md and the hand-entered news facts are committed.

Rules fixed before the first build (documented in data/csfe/README.md):
- A rain day: the median daily total over CFM self-recording gauges inside the Chennai box is at least 30 mm, with at least 5 gauges
  reporting. Consecutive rain days form one event.
- Points are snapped to the nearest road edge within 50 m, and to its reverse twin when the street is two-way.
- Rain is attached for observations whose time is known to the day or better: same-day total at the nearest gauge within 10 km that
  reported that day, plus the city median that day and the two days before.
"""

from __future__ import annotations

import csv
import json
import math
import re
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pyarrow.parquet as pq
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
RAW = DATA / "chennai_cfm" / "2026-10-04" / "raw"
OUT = DATA / "csfe" / "2026-10-30"
NEWS = DATA / "csfe" / "news_facts_2026-10-30.csv"
COUNTS = DATA / "csfe" / "news_counts_2026-10-30.csv"
WINDOW = "B"  # gauge-day convention, see obs_day
BOX = (12.75, 13.25, 79.95, 80.35)  # Chennai box (cities.yaml)
IST = timezone(timedelta(hours=5, minutes=30))
CFM_LICENCE = "CFM-DSS via Hugging Face mirror; publisher states no licence; research use, do not republish"


def in_box(lat: float, lon: float) -> bool:
    return BOX[0] <= lat <= BOX[1] and BOX[2] <= lon <= BOX[3]


def table(rel: str) -> list[dict]:
    return pq.read_table(RAW / rel).to_pylist()


# ---------------------------------------------------------------- road graph (for snapping)

class Snapper:
    def __init__(self) -> None:
        g = DATA / "graph" / "2026-09-14"
        nodes = json.loads((g / "chennai_prior_ell0.json").read_text(encoding="utf-8"))["nodes"]
        edges = json.loads((g / "chennai_graph_cli.json").read_text(encoding="utf-8"))["edges"]
        lat = np.array([n["lat"] for n in nodes])
        lon = np.array([n["lon"] for n in nodes])
        self.frm = np.array([e["from"] for e in edges])
        self.to = np.array([e["to"] for e in edges])
        self.ids = np.array([e["edge_id"] for e in edges])
        mid_lat = (lat[self.frm] + lat[self.to]) / 2
        mid_lon = (lon[self.frm] + lon[self.to]) / 2
        self.k = 111_320 * math.cos(math.radians(13.05))
        self.tree = cKDTree(np.column_stack([mid_lat * 111_320, mid_lon * self.k]))
        self.twin = {}
        pair = {(int(a), int(b)): int(i) for a, b, i in zip(self.frm, self.to, self.ids, strict=True)}
        for (a, b), i in pair.items():
            j = pair.get((b, a))
            if j is not None:
                self.twin[i] = j

    def snap(self, lat: float, lon: float, max_m: float = 50.0) -> tuple[str, float | None]:
        d, i = self.tree.query([lat * 111_320, lon * self.k])
        if d > max_m:
            return "", None
        e = int(self.ids[i])
        both = [e] + ([self.twin[e]] if e in self.twin else [])
        return ";".join(str(x) for x in both), round(float(d), 1)


# ---------------------------------------------------------------- rain gauges

def gauges() -> dict[str, tuple[float, float]]:
    """srgid -> (lat, lon), matched by id or name against the station registries; unmatched gauges are left out."""
    import shapely.wkb as wkb

    pos: dict[str, tuple[float, float]] = {}

    def norm(s) -> str:
        return re.sub(r"[^a-z0-9]", "", str(s).lower().replace("srg_", ""))

    for r in table("chennai-flood-monitor-transactions/stations/srg_registry.parquet"):
        if r.get("geometry"):
            p = wkb.loads(r["geometry"])
            for key in (r.get("stationid"), r.get("srd_id"), r.get("stationname")):
                if key:
                    pos.setdefault(norm(key), (p.y, p.x))
    for r in table("chennai-flood-monitor-transactions/stations/arg_registry_328.parquet"):
        if r.get("latitude") and r.get("longitude"):
            for key in (r.get("stationid"), r.get("stationname")):
                if key:
                    pos.setdefault(norm(key), (float(r["latitude"]), float(r["longitude"])))
    for r in table("chennai-flood-monitor-transactions/stations/raingauge_stations_63.parquet"):
        if r.get("latitude") and r.get("longitude") and r.get("station_name"):
            pos.setdefault(norm(r["station_name"]), (float(r["latitude"]), float(r["longitude"])))
    ids = {r["srgid"] for r in pq.read_table(RAW / "chennai-flood-monitor-transactions/data/srg_rain.parquet", columns=["srgid"]).to_pylist()}
    return {i: pos[norm(i)] for i in ids if norm(i) in pos}


def rain_daily() -> dict[tuple[str, date], float]:
    t = pq.read_table(RAW / "chennai-flood-monitor-transactions/data/srg_rain.parquet", columns=["srgid", "date", "rainfall"]).to_pylist()
    out: dict[tuple[str, date], float] = {}
    for r in t:
        if r["rainfall"] is None or r["rainfall"] < 0:
            continue
        d = date.fromisoformat(r["date"][:10])
        key = (r["srgid"], d)
        out[key] = max(out.get(key, 0.0), float(r["rainfall"]))  # one reading a day; 7 duplicates keep the larger
    return out


# ---------------------------------------------------------------- observations

FIELDS = [
    "obs_id", "event_id", "t_observed", "t_precision", "lat", "lon", "place_id", "place_name", "edge_ids", "snap_m", "kind",
    "value", "value_unit", "level_raw", "source_type", "source", "source_ref", "licence", "extraction",
    "rain_day_mm_nearest", "rain_gauge", "rain_gauge_km", "rain_day_mm_city_median", "rain_prev2d_mm_city_median",
    "rain_reading_date",
]

DEPTH_FT = {"<2ft": (0, 61), "<2": (0, 61), "2 to 3 ft": (61, 91), "3 to 5 ft": (91, 152), ">5ft": (152, None)}


def depth_range(text: str | None) -> tuple[int | None, int | None]:
    if not text:
        return None, None
    t = str(text).strip().lower().replace(" ", "")
    for k, v in DEPTH_FT.items():
        if t == k.replace(" ", ""):
            return v
    m = re.match(r"^(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)$", t)
    if m:
        return round(float(m.group(1)) * 30.48), round(float(m.group(2)) * 30.48)
    return None, None


def build() -> dict:
    snap = Snapper()
    obs: list[dict] = []

    def add(**kw) -> None:
        row = {f: "" for f in FIELDS}
        row.update({k: ("" if v is None else v) for k, v in kw.items()})
        if row["lat"] != "" and row["edge_ids"] == "":
            row["edge_ids"], row["snap_m"] = snap.snap(float(row["lat"]), float(row["lon"]))
            row["snap_m"] = "" if row["snap_m"] is None else row["snap_m"]
        row["obs_id"] = f"csfe-{len(obs) + 1:06d}"
        obs.append(row)

    # 1. CFM citizen app reports (time-stamped photos). Free text is dropped (privacy); only what it says about water is kept.
    for r in table("chennai-flood-history/crowdsourced/reports_scrubbed.parquet"):
        details = (r.get("details") or "").lower()
        if "test" in details or r.get("level") is None:
            continue
        lon, lat = map(float, re.findall(r"[-\d.]+", r["pointgeom"])[:2])
        if not in_box(lat, lon):
            continue
        dry = bool(re.search(r"no water|no stagnation|not water", details))
        cm = re.search(r"(\d+(?:\.\d+)?)\s*cm", details)
        ts = r["imagetimestamp"]
        add(event_id="", t_observed=ts.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"), t_precision="minute",
            lat=round(lat, 6), lon=round(lon, 6), kind="not_waterlogged" if dry else ("depth" if cm else "report_unclear"),
            value=cm.group(1) if cm else "", value_unit="cm" if cm else "", level_raw=r["level"], source_type="crowd",
            source="CFM-DSS citizen app (photo time)", source_ref=f"cfm:{r['id']}", licence=CFM_LICENCE, extraction="automatic")

    # 2. GCC 2015 hotspots with depth classes.
    for r in table("chennai-flood-history/hotspots_2015/hotspots_gcc_2015.parquet"):
        if not r.get("latitude") or not in_box(r["latitude"], r["longitude"]):
            continue
        lo, hi = depth_range(r.get("inundation_ft"))
        add(event_id="2015-12", t_observed="2015-12", t_precision="event", lat=r["latitude"], lon=r["longitude"],
            place_name=r.get("location") or "", kind="depth_range", value=f"{lo}-{'' if hi is None else hi}" if lo is not None else "",
            value_unit="cm", level_raw=r.get("inundation_ft") or "", source_type="official", source="GCC flood hotspots 2015 (CFM-DSS)",
            source_ref=f"cfm:hotspots_gcc_2015:{r['id']}", licence=CFM_LICENCE, extraction="automatic")

    # 3. Flood spot heights (event not documented).
    for r in table("chennaidss-gis-layers/flood_history/flood_spot_heights.parquet"):
        if not r.get("latitude") or not in_box(r["latitude"], r["longitude"]):
            continue
        lo, hi = depth_range(r.get("inundation_height_ft"))
        add(event_id="unknown", t_observed="", t_precision="unknown", lat=r["latitude"], lon=r["longitude"],
            place_name=r.get("area_details") or "", kind="depth_range",
            value=f"{lo}-{'' if hi is None else hi}" if lo is not None else "", value_unit="cm", level_raw=r.get("inundation_height_ft") or "",
            source_type="official", source="Flood spot heights (CFM-DSS)", source_ref=f"cfm:flood_spot_heights:{r['id']}",
            licence=CFM_LICENCE, extraction="automatic")

    # 4. GCC hotspots, northeast monsoon 2020.
    for r in table("chennai-flood-history/hotspots_2015/hotspots_gcc_nem2020.parquet"):
        if not r.get("latitude") or not in_box(r["latitude"], r["longitude"]):
            continue
        add(event_id="2020-nem", t_observed="2020-10/2020-12", t_precision="season", lat=r["latitude"], lon=r["longitude"],
            place_name=r.get("name") or "", kind="waterlogged", source_type="official", source="GCC flood hotspots NEM 2020 (CFM-DSS)",
            source_ref=f"cfm:hotspots_gcc_nem2020:{r['id']}", licence=CFM_LICENCE, extraction="automatic")

    # 5. The 2015 replay corpus (OpenCity KMLs), already edge-snapped in its own index; points re-snapped here for one method.
    for line in (DATA / "corpus" / "2026-09-17" / "observations.ndjson").open(encoding="utf-8"):
        o = json.loads(line)
        lon, lat = o["geometry"]["coordinates"]
        add(event_id="2015-12", t_observed="2015-12", t_precision="event", lat=round(lat, 6), lon=round(lon, 6), kind="waterlogged",
            source_type="official" if o["source_class"] == "official_feed" else "crowd", source=f"OpenCity 2015 ({o['source_id']})",
            source_ref=f"corpus:{o['id']}", licence="OpenCity (see data/MANIFEST.md)", extraction="automatic")

    # 6. News facts about subways and roads (hand-entered from the articles, with links).
    subs = json.loads((DATA / "watchlist" / "2026-10-09" / "subways.json").read_text(encoding="utf-8"))["entries"]
    alias = subway_aliases(subs)
    unmatched = []
    with NEWS.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            key = norm_name(r["place_name"])
            s = alias.get(key)
            kind = {"closed": "closed", "not_waterlogged": "not_waterlogged", "partly_open": "partly_open",
                    "waterlogged_open": "waterlogged_open", "reopened": "open"}[r["status"]]
            if s is None:
                unmatched.append(r["place_name"])
            has_pos = bool(s and s.get("lat") is not None)
            add(event_id=r["event_id"], t_observed=f"{r['reported_date']}T{r['reported_time_local']}+05:30",
                t_precision="reported_by", lat=s["lat"] if has_pos else "", lon=s["lon"] if has_pos else "", place_id=s["id"] if s else "",
                place_name=r["place_name"], kind=kind, source_type="news", source=r["source"] + (f" citing {r['attribution']}" if r["attribution"] != "not stated" else ""),
                source_ref=r["url"], licence="facts extracted; article not stored", extraction="manual")

    # ---------------------------------------------------------------- rain and events
    pos = gauges()
    daily = rain_daily()
    by_day: dict[date, list[tuple[str, float]]] = defaultdict(list)
    for (g, d), v in daily.items():
        if g in pos and in_box(*pos[g]):
            by_day[d].append((g, v))
    med = {d: float(np.median([v for _, v in xs])) for d, xs in by_day.items() if len(xs) >= 5}
    rain_days = sorted(d for d, m in med.items() if m >= 30.0)
    events, cur = [], []
    for d in rain_days:
        if cur and (d - cur[-1]).days > 1:
            events.append(cur)
            cur = []
        cur.append(d)
    if cur:
        events.append(cur)
    ev_rows = [
        {"event_id": f"rain-{e[0].isoformat()}", "first_day": e[0].isoformat(), "last_day": e[-1].isoformat(), "days": len(e),
         "max_city_median_mm": round(max(med[d] for d in e), 1), "sum_city_median_mm": round(sum(med[d] for d in e), 1),
         "gauges_reporting": max(len(by_day[d]) for d in e)}
        for e in events
    ]

    def obs_day(row) -> date | None:
        """The gauge reading whose 24 hours contain the observation.

        Convention B (from 30 Oct 2026): a reading dated D covers about 08:30 IST on D to 08:30 IST on D+1, so an observation before
        08:30 belongs to the reading dated D-1. Inferred from the gauge series itself: every storm checked (Dec 2015, Michaung Dec 2023,
        15 Oct 2024, Fengal Nov 2024) has its heavy totals on the readings dated the days of heavy rain and near zero on the reading
        dated the day after it stopped (for Michaung, 0.0 mm dated 5 Dec). Convention A (the reading dated D ends at 08:30 on D), used
        until then and by the first B1 run, is kept as WINDOW = "A" for reproducibility. Still [UNVERIFIED] against gauge metadata.
        """
        t = row["t_observed"]
        if row["t_precision"] in ("minute", "reported_by") and len(t) >= 10:
            local = datetime.fromisoformat(t.replace("Z", "+00:00")).astimezone(IST)
            after = (local.hour, local.minute) >= (8, 30)
            if WINDOW == "A":
                return local.date() + timedelta(days=1 if after else 0)
            return local.date() - timedelta(days=0 if after else 1)
        return None

    for row in obs:
        d = obs_day(row)
        if d is None:
            continue
        # The city median needs no position; the nearest gauge does (fixed 30 Oct 2026: rows without a position used to get no
        # rain at all).
        best = None
        if row["lat"] != "":
            lat, lon = float(row["lat"]), float(row["lon"])
            for g, v in by_day.get(d, []):
                km = math.hypot((pos[g][0] - lat) * 111.32, (pos[g][1] - lon) * 108.4)
                if km <= 10 and (best is None or km < best[2]):
                    best = (g, v, km)
        row["rain_reading_date"] = d.isoformat()
        if best:
            row["rain_day_mm_nearest"], row["rain_gauge"], row["rain_gauge_km"] = best[1], best[0], round(best[2], 2)
        if d in med:
            row["rain_day_mm_city_median"] = round(med[d], 1)
        prev = [med.get(d - timedelta(days=k)) for k in (1, 2)]
        if all(p is not None for p in prev):
            row["rain_prev2d_mm_city_median"] = round(sum(prev), 1)
        if row["event_id"] == "":
            hit = next((e for e in ev_rows if e["first_day"] <= d.isoformat() <= e["last_day"]), None)
            row["event_id"] = hit["event_id"] if hit else f"day-{d.isoformat()}"

    # ---------------------------------------------------------------- write
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "observations.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(obs)
    with (OUT / "events.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(ev_rows[0]))
        w.writeheader()
        w.writerows(ev_rows)
    with (OUT / "gauges.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["gauge_id", "lat", "lon", "in_chennai_box"])
        for g, (la, lo) in sorted(pos.items()):
            w.writerow([g, round(la, 6), round(lo, 6), in_box(la, lo)])
    with (OUT / "rain_daily.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["gauge_id", "date", "rain_mm"])
        for (g, d), v in sorted(daily.items()):
            if g in pos:
                w.writerow([g, d.isoformat(), v])

    extra = write_context_tables(obs, subs)

    kinds = defaultdict(int)
    for r in obs:
        kinds[r["kind"]] += 1
    summary = {
        "built": "2026-10-29",
        "observations": len(obs),
        "by_kind": dict(sorted(kinds.items())),
        "by_source_type": dict(sorted({s: sum(1 for r in obs if r["source_type"] == s) for s in {r["source_type"] for r in obs}}.items())),
        "with_time_to_the_day_or_better": sum(1 for r in obs if r["t_precision"] in ("minute", "reported_by")),
        "snapped_to_an_edge": sum(1 for r in obs if r["edge_ids"]),
        "with_rain_attached": sum(1 for r in obs if r["rain_day_mm_nearest"] != ""),
        "with_city_median_rain": sum(1 for r in obs if r["rain_day_mm_city_median"] != ""),
        "gauges_with_position": len(pos),
        "gauges_in_box": sum(1 for p in pos.values() if in_box(*p)),
        "rain_days_rule": "city median >= 30 mm over >= 5 in-box gauges",
        "rain_window_convention": WINDOW,
        "rain_events": len(ev_rows),
        "news_places_unmatched_to_watchlist": sorted(set(unmatched)),
        "news_rows_linked_to_a_subway_without_position": sum(1 for r in obs if r["source_type"] == "news" and r["place_id"] and r["lat"] == ""),
        "rain_daily_rows": sum(1 for (g, _d) in daily if g in pos),
        "news_facts": sum(1 for r in obs if r["source_type"] == "news"),
        "news_events": len({r["event_id"] for r in obs if r["source_type"] == "news"}),
        **extra,
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return summary


# ---------------------------------------------------------------- context tables (v0.2)

def write_context_tables(obs: list[dict], subs: list[dict]) -> dict:
    """Water levels (daily max per station), ward model depths, the city-level news counts, and a per-subway status timeline."""
    import shutil

    # Water levels: CFM automatic water level recorders, daily maximum, with positions from the registry.
    reg = {r["awlrid"]: (r.get("latitude"), r.get("longitude"), r.get("location")) for r in
           table("chennai-flood-monitor-transactions/stations/awlr_44.parquet") if r.get("awlrid")}
    daily: dict[tuple[str, str], float] = {}
    for r in pq.read_table(RAW / "chennai-flood-monitor-transactions/data/awlr_waterlevel.parquet",
                           columns=["awlrid", "date", "waterlevel", "combined_datetime"]).to_pylist():
        day = (r["date"] or r["combined_datetime"] or "")[:10]
        if r["waterlevel"] is None or r["awlrid"] is None or not day:
            continue
        key = (r["awlrid"], day)
        daily[key] = max(daily.get(key, float("-inf")), float(r["waterlevel"]))
    with (OUT / "water_level_daily.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["station_id", "date", "max_level", "lat", "lon", "location"])
        for (s, d), v in sorted(daily.items()):
            la, lo, loc = reg.get(s, (None, None, None))
            w.writerow([s, d, v, "" if la is None else la, "" if lo is None else lo, loc or ""])
    # Ward model depths (modelled, not observed): context only.
    with (OUT / "ward_model_depth.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["ward", "model_depth_min_m", "model_depth_max_m", "model_time", "note"])
        for r in table("chennai-flood-history/wards/ward_waterdepth_minmax.parquet"):
            w.writerow([r["ward"], r["min"], r["max"], r["datetime"].isoformat() if r.get("datetime") else "",
                        "modelled by CFM-DSS; not an observation"])
    shutil.copyfile(COUNTS, OUT / "news_counts.csv")
    # Per-subway status timeline from the news rows.
    names = {s["id"]: s["name"] for s in subs}
    tl = sorted((r for r in obs if r["source_type"] == "news" and r["place_id"]), key=lambda r: (r["place_id"], r["t_observed"]))
    with (OUT / "subway_timeline.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["subway_id", "subway_name", "event_id", "reported_at", "status", "rain_day_mm_city_median", "source_ref"])
        for r in tl:
            w.writerow([r["place_id"], names.get(r["place_id"], ""), r["event_id"], r["t_observed"], r["kind"],
                        r["rain_day_mm_city_median"], r["source_ref"]])
    return {
        "water_level_stations": len({s for s, _ in daily}),
        "water_level_station_days": len(daily),
        "water_level_stations_with_position": len({s for s, _ in daily if reg.get(s, (None,))[0] is not None}),
        "subway_timeline_rows": len(tl),
        "subways_in_timeline": len({r["place_id"] for r in tl}),
    }


# ---------------------------------------------------------------- subway names

def norm_name(s: str) -> str:
    s = s.lower().replace("subway", "")
    s = re.sub(r"\((2-wheeler|pedestrian and two-wheeler)\)", "", s)  # vehicle notes are not part of the name
    s = s.replace("2-wheeler", "wheeler")
    return re.sub(r"[^a-z]", "", s)


# News spellings -> watchlist ids. Ambiguous ones are left out on purpose (Pazhavanthangal is not in the watchlist; "C.P. Road",
# "CB Road" and "Mount" could each be more than one subway).
NEWS_TO_ID_HINTS = {
    "ganesapuram": "Ganesapuram", "ganeshapuram": "Ganesapuram",
    "sembiumperambur": "Perambur subway", "villivakkam": "Villivakkam", "duraisamy": "Doraisamy",
    "rangarajapuram": "Rangarajapuram", "vyasarpadi": "Vyasarpadi", "manickamnagar": "Manickam Nagar",
    "choolaimeduloyola": "Choolaimedu", "aranganathan": "Aranganathan", "saidapetaranganathan": "Aranganathan",
    "kathirvedu": "Kathirvedu", "gengureddy": "Gengu Reddy", "gangureddy": "Gengu Reddy", "madley": "Madley",
    "thillaiganganagar": "Thillaiganga", "rbi": "Reserve Bank", "mcroadstanleyhospital": "Monegar Choultry",
    "stanleynagar": "Stanley Nagar", "harington": "Harrington", "jonesroad": "Jones Road",
    # v0.2 spellings
    "perambur": "Perambur subway", "perambur railway": "Perambur subway", "peramburrailway": "Perambur subway",
    "peramburhighroad": "Perambur subway", "duraisami": "Doraisamy", "duralsamy": "Doraisamy", "gunguruddy": "Gengu Reddy",
    "gengureddy": "Gengu Reddy", "nungambakkam": "Nungambakkam", "rangarajapuramwheeler": "Rangarajapuram",
    "jones": "Jones Road", "rangarajapuramwheelersubway": "Rangarajapuram",
}


def subway_aliases(entries: list[dict]) -> dict[str, dict]:
    out = {}
    for key, hint in NEWS_TO_ID_HINTS.items():
        hit = [e for e in entries if hint.lower() in e["name"].lower()]
        if len(hit) == 1:
            out[key] = hit[0]  # linked by id even when the watchlist has no position yet (lat/lon then stay empty)
    return out


if __name__ == "__main__":
    s = build()
    print(json.dumps(s, indent=1, ensure_ascii=False))
    sys.exit(0)
