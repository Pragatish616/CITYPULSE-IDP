"""Describe what is really in the downloaded training sources (no modelling).

Reads data/chennai_cfm/<date>/raw/ and data/nyc_floodnet/<date>/raw/ and writes profile.json next to
each fetch_log.json. Aggregates only, so the profiles are safe to commit even though the CFM raw files are
not. Every number quoted in DATA_SOURCES_ASSESSMENT.md comes from these files.

Usage: python scripts/profile_training_sources.py [--date YYYY-MM-DD]   (needs pandas and pyarrow)
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
EVENTS = {
    "2005_Oct_Nov": ("2005-10-15", "2005-12-11"),
    "2015_Nov_Dec": ("2015-11-09", "2015-12-11"),
    "2023_Michaung": ("2023-12-01", "2023-12-08"),
    "2025_NEM": ("2025-11-01", "2025-12-31"),
}


def day(series: pd.Series) -> pd.Series:
    return pd.to_datetime(series.astype("string").str.replace("Z", "", regex=False), errors="coerce")


def by_year(df: pd.DataFrame, date_col: str, station_col: str) -> dict:
    g = df.groupby(df[date_col].dt.year).agg(rows=(station_col, "size"), stations=(station_col, "nunique"))
    return {str(int(y)): {"rows": int(r.rows), "stations": int(r.stations)} for y, r in g.iterrows()}


def window(df: pd.DataFrame, date_col: str, station_col: str, a: str, b: str) -> dict:
    w = df[(df[date_col] >= a) & (df[date_col] <= b)]
    return {"rows": int(len(w)), "stations": int(w[station_col].nunique())}


def profile_cfm(base: Path, date: str) -> dict:
    raw = base / "raw"
    t = raw / "chennai-flood-monitor-transactions" / "data"
    srg = pd.read_parquet(t / "srg_rain.parquet")
    srg["d"] = day(srg["date"])
    arg = pd.read_parquet(t / "aws_arg_rain_met.parquet")
    arg["d"] = day(arg["date"])
    awlr = pd.read_parquet(t / "awlr_waterlevel.parquet")
    awlr["d"] = day(awlr["combined_datetime"])
    out = {
        "srg_daily_rain": {"by_year": by_year(srg, "d", "srgid"), "max_mm_in_a_row": float(srg["rainfall"].max())},
        "aws_arg": {"by_year": by_year(arg, "d", "awsid")},
        "awlr_water_level": {"by_year": by_year(awlr, "d", "awlrid")},
        "event_windows": {
            name: {
                "srg": window(srg, "d", "srgid", a, b),
                "aws_arg": window(arg, "d", "awsid", a, b),
                "awlr": window(awlr, "d", "awlrid", a, b),
            }
            for name, (a, b) in EVENTS.items()
        },
    }
    # Largest daily rainfall of the 2015 event, across stations, from the daily gauge network.
    w = srg[(srg["d"] >= "2015-11-09") & (srg["d"] <= "2015-12-11")]
    out["srg_2015_max_single_row_mm"] = float(w["rainfall"].max())

    h = raw / "chennai-flood-history"
    crowd = pd.read_parquet(h / "crowdsourced" / "reports_scrubbed.parquet")
    crowd["t"] = pd.to_datetime(crowd["imagetimestamp"])
    lat = crowd["pointgeom"].str.extract(r"POINT\(([-\d.]+) ([-\d.]+)\)").astype(float)
    in_chennai = (lat[1].between(12.75, 13.25)) & (lat[0].between(79.95, 80.35))
    out["crowd_reports"] = {
        "rows": int(len(crowd)),
        "first": str(crowd["t"].min()), "last": str(crowd["t"].max()),
        "level_counts": {str(k): int(v) for k, v in crowd["level"].value_counts().sort_index().items()},
        "inside_chennai_box": int(in_chennai.sum()),
        "level_2_or_more": int((crowd["level"] >= 2).sum()),
        "level_2_or_more_inside_chennai_box": int(((crowd["level"] >= 2) & in_chennai).sum()),
        "details_containing_test": int(crowd["details"].astype("string").str.contains("test", case=False, na=False).sum()),
    }
    counts = {}
    for p in sorted((h / "hotspots_2015").glob("*.parquet")) + sorted((h / "flood_extents").glob("*.parquet")):
        counts[p.stem] = int(len(pd.read_parquet(p)))
    out["history_layers_rows"] = counts
    ward = pd.read_parquet(h / "wards" / "ward_waterdepth_minmax.parquet")
    out["ward_water_depth_model"] = {"rows": int(len(ward)), "datetime_values": sorted({str(x) for x in ward["datetime"].unique()})[:3]}
    gis = raw / "chennaidss-gis-layers"
    out["gis_layers"] = {sub.name: len(list(sub.glob("*.parquet"))) for sub in sorted(gis.iterdir()) if sub.is_dir()}

    # How many IMD-reported Chennai events fall inside the years the daily gauges cover?
    cal = ROOT / "data" / "india_flood" / date / "tn_event_calendar.csv"
    if cal.exists():
        rows = [r for r in csv.DictReader(cal.open(encoding="utf-8")) if r["chennai_named"] == "True"]
        in_gauge_years = [r for r in rows if "1988" <= r["start"][:4] <= "2019"]
        days: set[dt.date] = set()
        for r in in_gauge_years:
            s, e = dt.date.fromisoformat(r["start"]), dt.date.fromisoformat(r["end"])
            if (e - s).days <= 60:
                days.update(s + dt.timedelta(n) for n in range((e - s).days + 1))
        out["imd_chennai_events"] = {
            "all_years": len(rows), "inside_1988_2019": len(in_gauge_years),
            "event_days_inside_1988_2019_for_events_up_to_60_days": len(days),
            "days_in_1988_2019": (dt.date(2019, 12, 31) - dt.date(1988, 1, 1)).days + 1,
        }
    return out


def profile_floodnet(base: Path) -> dict:
    d = pd.read_csv(base / "raw" / "floodnet_flood_events.csv")
    d["s"] = pd.to_datetime(d["flood_start_time"])
    per_sensor = d.groupby("sensor_id").size()
    return {
        "rows": int(len(d)), "sensors": int(d["sensor_id"].nunique()),
        "first": str(d["s"].min().date()), "last": str(d["s"].max().date()),
        "events_per_year": {str(int(k)): int(v) for k, v in d.groupby(d["s"].dt.year).size().items()},
        "max_depth_inches": {q: round(float(d["max_depth_inches"].quantile(p)), 2) for q, p in (("median", 0.5), ("p90", 0.9), ("p99", 0.99))},
        "share_max_depth_at_least_4in": round(float((d["max_depth_inches"] >= 4).mean()), 3),
        "share_max_depth_at_least_12in": round(float((d["max_depth_inches"] >= 12).mean()), 3),
        "events_per_sensor": {"median": float(per_sensor.median()), "max": int(per_sensor.max()), "sensors_with_at_least_10": int((per_sensor >= 10).sum())},
        "has_per_minute_depth_profile": "flood_profile_depth_inches" in d.columns,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default="2026-10-04")
    a = ap.parse_args()
    for folder, fn in (("chennai_cfm", lambda b: profile_cfm(b, a.date)), ("nyc_floodnet", profile_floodnet)):
        base = ROOT / "data" / folder / a.date
        res = fn(base)
        (base / "profile.json").write_text(json.dumps(res, indent=2, sort_keys=True), encoding="utf-8")
        print(folder, "profile written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
