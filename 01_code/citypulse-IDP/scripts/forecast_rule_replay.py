"""Replay the ADR-029 forecast rule against NASA IMERG over two north-east monsoons and a dry season (the validation ADR-029
committed to on 8 October 2026, before any forecast value for these periods was read).

Everything below (periods, times, points, model, threshold, horizon, measures, adoption criteria, bootstrap seed) is copied from
ADR-029. Nothing here is tuned; a miss or a false alarm is reported as it is.

    python scripts/forecast_rule_replay.py            # from 01_code/citypulse-IDP

Network: Open-Meteo's Previous Runs archive (a few requests) and NASA GIBS (about 5,900 small images, 3 at a time). Both are
read-only. The IMERG answers are cached in raw/imerg_truth.json as they arrive, so an interrupted run resumes where it stopped.
Writes data/results/2026-10-08-forecast-rule-replay/ (result.json, raw/).
"""

from __future__ import annotations

import asyncio
import json
import random
import subprocess
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from app.ingest import forecast, imerg

OUT = ROOT / "data" / "results" / "2026-10-08-forecast-rule-replay"
RAW = OUT / "raw"
PRE_REGISTRATION_COMMIT = "0c9c6d0"  # docs: pre-register the rain forecast rule and its replay (ADR-029, M3.7)

# ---- fixed in ADR-029
PERIODS = [
    ("P1", "monsoon", "2024-10-01", "2024-12-31"),
    ("P2", "monsoon", "2025-10-01", "2025-12-31"),
    ("P3", "dry", "2025-03-01", "2025-04-30"),
]
HOURS = (0, 6, 12, 18)
PRIMARY_MODEL, SECONDARY_MODEL = "ecmwf_ifs025", "gfs_seamless"
PRIMARY_VAR, SECONDARY_VAR = "precipitation_previous_day1", "precipitation"
THRESHOLD = forecast.WATCH_ACCUMULATION_MM  # 8.0 mm, ADR-027's own watch accumulation
# ADR-027's rule for the truth (copied, as in imerg_rule_replay.py)
ACTIVE_ACC, ACTIVE_PEAK, WATCH_ACC, WATCH_PEAK = 15.0, 25.0, 8.0, 7.6
BOOTSTRAP, SEED = 10_000, 20260918
PREVIOUS_RUNS_URL = "https://previous-runs-api.open-meteo.com/v1/forecast"


def imerg_level(acc: float, peak: float) -> str:
    if acc >= ACTIVE_ACC or peak >= ACTIVE_PEAK:
        return "active"
    if acc >= WATCH_ACC or peak >= WATCH_PEAK:
        return "watch"
    return "dry"


def times_of(first: str, last: str) -> list[datetime]:
    d0, d1 = date.fromisoformat(first), date.fromisoformat(last)
    out = []
    d = d0
    while d <= d1:
        for h in HOURS:
            out.append(datetime(d.year, d.month, d.day, h, tzinfo=timezone.utc))
        d += timedelta(days=1)
    return out


# ---------------------------------------------------------------------------------------------- forecasts


def fetch_previous_runs(model: str, first: str, last: str) -> list[dict]:
    """The archive for one model and period, one day either side so every window at the edges is complete."""
    start = (date.fromisoformat(first) - timedelta(days=1)).isoformat()
    end = (date.fromisoformat(last) + timedelta(days=1)).isoformat()
    path = RAW / f"open_meteo_{model}_{start}_{end}.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    q = {
        "latitude": ",".join(str(a) for a, _ in forecast.POINTS),
        "longitude": ",".join(str(o) for _, o in forecast.POINTS),
        "hourly": f"{SECONDARY_VAR},{PRIMARY_VAR}",
        "models": model,
        "start_date": start,
        "end_date": end,
        "timezone": "UTC",
    }
    r = httpx.get(PREVIOUS_RUNS_URL, params=q, timeout=120, headers={"User-Agent": imerg.USER_AGENT})
    r.raise_for_status()
    data = r.json()
    data = data if isinstance(data, list) else [data]
    path.write_text(json.dumps(data), encoding="utf-8")
    return data


def series_for(locations: list[dict], variable: str) -> list[tuple[datetime, float]]:
    return forecast.area_mean_series(locations, variable)


def same_time(series: dict[datetime, float], t: datetime) -> float | None:
    """F(T): the three-hour forecast over the stamps T-2h, T-1h, T."""
    parts = [series.get(t - timedelta(hours=k)) for k in (2, 1, 0)]
    return None if any(p is None for p in parts) else parts[0] + parts[1] + parts[2]


# ---------------------------------------------------------------------------------------------- IMERG truth


async def imerg_truth(all_times: list[datetime]) -> dict[str, dict]:
    path = RAW / "imerg_truth.json"
    done: dict[str, dict] = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    todo = [t for t in all_times if t.strftime("%Y-%m-%dT%H:%MZ") not in done]
    print(f"IMERG: {len(done)} cached, {len(todo)} to fetch", flush=True)
    if not todo:
        return done
    gate = asyncio.Semaphore(3)
    async with httpx.AsyncClient(
        timeout=imerg.HTTP_TIMEOUT, headers={"User-Agent": imerg.USER_AGENT}, follow_redirects=True
    ) as client:
        legend = await imerg.fetch_colormap(client)

        async def img(t: datetime):
            async with gate:
                for attempt in range(3):
                    try:
                        return imerg.decode_slice(await imerg.fetch_slice_png(client, t), legend, t)
                    except Exception:  # noqa: BLE001
                        await asyncio.sleep(1.5 * (attempt + 1))
                return None

        async def one(t: datetime) -> tuple[str, dict]:
            stamps = [t - timedelta(minutes=30 * i) for i in range(imerg.ACCUMULATION_SLICES)]
            slices = await asyncio.gather(*(img(s) for s in stamps))
            ok = [s for s in slices if s is not None]
            key = t.strftime("%Y-%m-%dT%H:%MZ")
            if not ok:
                return key, {"error": "no image could be read"}
            acc = sum(s.mean_mm_h for s in ok) * (imerg.SLICE_MINUTES / 60.0)
            peak = max(s.peak_mm_h for s in ok)
            return key, {
                "acc_3h_mm": round(acc, 3),
                "peak_mm_h": round(peak, 3),
                "images_read": len(ok),
                "images_missing": len(slices) - len(ok),
                "level": imerg_level(acc, peak),
            }

        started = time.monotonic()
        for i in range(0, len(todo), 24):
            batch = todo[i : i + 24]
            for key, value in await asyncio.gather(*(one(t) for t in batch)):
                done[key] = value
            path.write_text(json.dumps(done, indent=0, sort_keys=True), encoding="utf-8")
            n = i + len(batch)
            print(f"IMERG {n}/{len(todo)} ({time.monotonic() - started:.0f} s)", flush=True)
    return done


# ---------------------------------------------------------------------------------------------- measures


def contingency(rows: list[dict], fkey: str, wkey: str) -> dict:
    c = {"hits": 0, "misses": 0, "false_alarms": 0, "correct_negatives": 0, "excluded": 0}
    for r in rows:
        f, w = r.get(fkey), r.get(wkey)
        if f is None or w is None:
            c["excluded"] += 1
        elif f and w:
            c["hits"] += 1
        elif w:
            c["misses"] += 1
        elif f:
            c["false_alarms"] += 1
        else:
            c["correct_negatives"] += 1
    return c


def pod_far(c: dict) -> tuple[float | None, float | None]:
    wet = c["hits"] + c["misses"]
    fwet = c["hits"] + c["false_alarms"]
    return (c["hits"] / wet if wet else None, c["false_alarms"] / fwet if fwet else None)


def bootstrap_pod_far(rows: list[dict], fkey: str, wkey: str) -> dict:
    """95% percentile intervals by resampling calendar days (consecutive times on a day are not independent)."""
    by_day: dict[str, list[dict]] = {}
    for r in rows:
        by_day.setdefault(r["time"][:10], []).append(r)
    days = sorted(by_day)
    per_day = [contingency(by_day[d], fkey, wkey) for d in days]
    rng = random.Random(SEED)
    pods, fars = [], []
    undefined_pod = undefined_far = 0
    for _ in range(BOOTSTRAP):
        tot = {"hits": 0, "misses": 0, "false_alarms": 0}
        for _ in days:
            c = per_day[rng.randrange(len(days))]
            for k in tot:
                tot[k] += c[k]
        p, f = pod_far({**tot, "correct_negatives": 0})
        if p is None:
            undefined_pod += 1
        else:
            pods.append(p)
        if f is None:
            undefined_far += 1
        else:
            fars.append(f)

    def ci(xs: list[float]) -> list[float] | None:
        if not xs:
            return None
        xs = sorted(xs)
        return [round(xs[int(0.025 * (len(xs) - 1))], 4), round(xs[int(0.975 * (len(xs) - 1))], 4)]

    return {
        "days": len(days),
        "resamples": BOOTSTRAP,
        "seed": SEED,
        "pod_95ci": ci(pods),
        "far_95ci": ci(fars),
        "resamples_with_pod_undefined": undefined_pod,
        "resamples_with_far_undefined": undefined_far,
    }


def episodes(rows: list[dict], wkey: str) -> list[list[dict]]:
    """Maximal runs of consecutive wet times within one period. A time with no truth ends a run."""
    out, run = [], []
    for r in rows:
        if r.get(wkey):
            run.append(r)
        else:
            if run:
                out.append(run)
            run = []
    if run:
        out.append(run)
    return out


def measures(rows_by_period: dict[str, list[dict]], fvar: str, wkey: str) -> dict:
    monsoon = rows_by_period["P1"] + rows_by_period["P2"]
    fkey, lkey = f"F_{fvar}", f"L_{fvar}"
    c = contingency(monsoon, fkey, wkey)
    pod, far = pod_far(c)
    # M2: episodes in each monsoon period, warned ahead if the live rule at T0 - 6 h gave watch
    eps = episodes(rows_by_period["P1"], wkey) + episodes(rows_by_period["P2"], wkey)
    index = {r["time"]: r for r in monsoon}
    warned = no_answer = 0
    ep_rows = []
    for ep in eps:
        t0 = datetime.fromisoformat(ep[0]["time"].replace("Z", "+00:00"))
        before = (t0 - timedelta(hours=6)).strftime("%Y-%m-%dT%H:%MZ")
        lv = ep[0][f"{lkey}_minus6h"]
        if lv is None:
            no_answer += 1
        elif lv == "watch":
            warned += 1
        ep_rows.append({"first_wet": ep[0]["time"], "length_times": len(ep), "live_rule_at_minus_6h": lv, "minus_6h_time": before,
                        "minus_6h_in_period": before in index})
    # M3: false switching
    p3 = rows_by_period["P3"]
    p3_known = [r for r in p3 if r[lkey] is not None]
    p3_on = sum(1 for r in p3_known if r[lkey] == "watch")
    on_times = [r for r in monsoon if r[lkey] == "watch"]
    unconfirmed = judged = 0
    for r in on_times:
        t = datetime.fromisoformat(r["time"].replace("Z", "+00:00"))
        later = [index.get((t + timedelta(hours=h)).strftime("%Y-%m-%dT%H:%MZ")) for h in (6, 12)]
        later_w = [x.get(wkey) for x in later if x is not None and x.get(wkey) is not None]
        if not later_w:
            continue
        judged += 1
        if not any(later_w):
            unconfirmed += 1
    return {
        "M1_same_time": {**c, "pod": pod, "far": far, **bootstrap_pod_far(monsoon, fkey, wkey)},
        "M2_warning_ahead": {
            "episodes": len(eps),
            "warned_ahead": warned,
            "live_rule_gave_no_answer": no_answer,
            "share_warned": (warned / len(eps)) if eps else None,
            "episode_list": ep_rows,
        },
        "M3_false_switching": {
            "P3_times_with_an_answer": len(p3_known),
            "P3_times_without_an_answer": len(p3) - len(p3_known),
            "P3_times_at_watch": p3_on,
            "P3_share_at_watch": (p3_on / len(p3_known)) if p3_known else None,
            "monsoon_watch_times": len(on_times),
            "monsoon_watch_times_judged": judged,
            "monsoon_watch_times_not_followed_by_wet": unconfirmed,
            "monsoon_share_not_followed_by_wet": (unconfirmed / judged) if judged else None,
        },
    }


def criteria(m: dict) -> dict:
    m1, m2, m3 = m["M1_same_time"], m["M2_warning_ahead"], m["M3_false_switching"]
    c1 = m1["pod"] is not None and m1["far"] is not None and m1["pod"] >= 0.5 and m1["far"] <= 0.5
    if m2["episodes"] < 10:
        c2: bool | str = "not testable (fewer than 10 wet episodes)"
    else:
        c2 = m2["share_warned"] is not None and m2["share_warned"] >= 0.5
    c3 = m3["P3_share_at_watch"] is not None and m3["P3_share_at_watch"] <= 0.05
    all_met = c1 is True and c2 is True and c3 is True
    return {
        "1_pod_at_least_0.5_and_far_at_most_0.5": c1,
        "2_half_of_wet_episodes_warned_ahead": c2,
        "3_dry_season_false_switching_at_most_5pct": c3,
        "all_met": all_met,
        "recommendation": "turn the forecast on by default (the owner decides)" if all_met
        else "keep the forecast off by default; report as negative",
    }


# ---------------------------------------------------------------------------------------------- main


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)
    rows_by_period: dict[str, list[dict]] = {}
    all_times = [t for _, _, a, b in PERIODS for t in times_of(a, b)]
    print(f"{len(all_times)} times", flush=True)

    # forecasts: {model: {var: {time: area mean}}}
    fc: dict[str, dict[str, dict[datetime, float]]] = {}
    for model in (PRIMARY_MODEL, SECONDARY_MODEL):
        fc[model] = {PRIMARY_VAR: {}, SECONDARY_VAR: {}}
        for _, _, a, b in PERIODS:
            locs = fetch_previous_runs(model, a, b)
            for var in (PRIMARY_VAR, SECONDARY_VAR):
                fc[model][var].update(dict(series_for(locs, var)))
        print(f"forecast {model}: {len(fc[model][PRIMARY_VAR])} hours ({PRIMARY_VAR})", flush=True)

    truth = asyncio.run(imerg_truth(all_times))

    ordered = {(m, v): sorted(fc[m][v].items()) for m in fc for v in fc[m]}
    for pid, _, a, b in PERIODS:
        rows = []
        for t in times_of(a, b):
            key = t.strftime("%Y-%m-%dT%H:%MZ")
            tr = truth.get(key, {})
            ok = "level" in tr
            row = {
                "time": key,
                "imerg_acc_3h_mm": tr.get("acc_3h_mm"),
                "imerg_peak_mm_h": tr.get("peak_mm_h"),
                "imerg_level": tr.get("level"),
                "imerg_images_missing": tr.get("images_missing"),
                "wet": (tr["level"] != "dry") if ok else None,
                "wet_acc_only": (tr["acc_3h_mm"] >= WATCH_ACC) if ok else None,
            }
            for model in (PRIMARY_MODEL, SECONDARY_MODEL):
                for var in (PRIMARY_VAR, SECONDARY_VAR):
                    s = fc[model][var]
                    series = ordered[(model, var)]
                    tag = f"{model}.{var}"
                    acc = same_time(s, t)
                    row[f"forecast_3h_mm_{tag}"] = None if acc is None else round(acc, 3)
                    row[f"F_{tag}"] = None if acc is None else acc >= THRESHOLD
                    row[f"L_{tag}"] = forecast.level_ahead(series, t)
                    row[f"L_{tag}_minus6h"] = forecast.level_ahead(series, t - timedelta(hours=6))
            rows.append(row)
        rows_by_period[pid] = rows

    results = {}
    for model in (PRIMARY_MODEL, SECONDARY_MODEL):
        for var in (PRIMARY_VAR, SECONDARY_VAR):
            for wkey in ("wet", "wet_acc_only"):
                results[f"{model}|{var}|truth={wkey}"] = measures(rows_by_period, f"{model}.{var}", wkey)
    primary_key = f"{PRIMARY_MODEL}|{PRIMARY_VAR}|truth=wet"
    verdict = criteria(results[primary_key])

    truth_missing = sum(1 for r in rows_by_period["P1"] + rows_by_period["P2"] + rows_by_period["P3"] if r["wet"] is None)
    result = {
        "task": "ADR-029 validation: the rain forecast rule replayed against NASA IMERG (M3.7)",
        "run_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pre_registration_commit": PRE_REGISTRATION_COMMIT,
        "code_commit": subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, cwd=ROOT, check=False).stdout.strip(),
        "rule": {
            "model": PRIMARY_MODEL, "points": forecast.POINTS, "threshold_mm_3h_area_mean": THRESHOLD,
            "horizon_hours": forecast.HORIZON_HOURS, "min_future_stamps": 9, "max_level": "watch",
        },
        "truth": {"source": imerg.CREDIT, "layer": imerg.LAYER, "bbox": imerg.CHENNAI_BBOX,
                  "rule": f"ADR-027 instantaneous level: active if A>={ACTIVE_ACC} or P>={ACTIVE_PEAK}; watch if A>={WATCH_ACC} or P>={WATCH_PEAK}",
                  "times_without_truth": truth_missing},
        "forecast_source": {"archive": PREVIOUS_RUNS_URL, "primary": f"{PRIMARY_MODEL} {PRIMARY_VAR}",
                            "secondary": [f"{PRIMARY_MODEL} {SECONDARY_VAR}", f"{SECONDARY_MODEL} (context only)"],
                            "credit": forecast.CREDIT},
        "periods": [{"id": p, "kind": k, "first": a, "last": b, "times": len(rows_by_period[p])} for p, k, a, b in PERIODS],
        "primary": {"key": primary_key, **results[primary_key]},
        "adoption_criteria": verdict,
        "all_combinations": results,
        "rows": rows_by_period,
    }
    (OUT / "result.json").write_text(json.dumps(result, indent=1, default=str), encoding="utf-8")
    m = results[primary_key]
    print(json.dumps({
        "M1": {k: m["M1_same_time"][k] for k in ("hits", "misses", "false_alarms", "correct_negatives", "excluded", "pod", "far", "pod_95ci", "far_95ci")},
        "M2": {k: m["M2_warning_ahead"][k] for k in ("episodes", "warned_ahead", "live_rule_gave_no_answer", "share_warned")},
        "M3": {k: v for k, v in m["M3_false_switching"].items()},
        "criteria": verdict,
    }, indent=1, default=str))
    print("wrote", OUT / "result.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
